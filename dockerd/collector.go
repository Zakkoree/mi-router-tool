package stats

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"runtime"
	"strconv"
	"sync"
	"time"

	containertypes "github.com/moby/moby/api/types/container"
	"github.com/moby/moby/v2/daemon/container"
	"github.com/moby/pubsub"
	"golang.org/x/sys/unix"
)

type cpuSample struct {
	totalUsage  uint64
	systemUsage uint64
	readTime    time.Time
}

var (
	cpuCacheMu sync.Mutex
	cpuCache   = make(map[string]cpuSample, 64)

	systemMemOnce sync.Once
	cachedSysMem  uint64

	bufPool = sync.Pool{
		New: func() any {
			b := make([]byte, 8192)
			return &b
		},
	}
)

type Collector struct {
	m          sync.Mutex
	cond       *sync.Cond
	supervisor supervisor
	interval   time.Duration
	publishers map[*container.Container]*pubsub.Publisher
}

func NewCollector(supervisor supervisor, interval time.Duration) *Collector {
	s := &Collector{
		interval:   interval,
		supervisor: supervisor,
		publishers: make(map[*container.Container]*pubsub.Publisher),
	}
	s.cond = sync.NewCond(&s.m)
	return s
}

type supervisor interface {
	GetContainerStats(container *container.Container) (*containertypes.StatsResponse, error)
}

func (s *Collector) Collect(c *container.Container) chan any {
	s.cond.L.Lock()
	defer s.cond.L.Unlock()

	publisher, exists := s.publishers[c]
	if !exists {
		publisher = pubsub.NewPublisher(100*time.Millisecond, 1024)
		s.publishers[c] = publisher
	}

	s.cond.Broadcast()
	return publisher.Subscribe()
}

func (s *Collector) StopCollection(c *container.Container) {
	s.m.Lock()
	if publisher, exists := s.publishers[c]; exists {
		publisher.Close()
		delete(s.publishers, c)

		cpuCacheMu.Lock()
		delete(cpuCache, c.ID)
		cpuCacheMu.Unlock()
	}
	s.m.Unlock()
}

func (s *Collector) Unsubscribe(c *container.Container, ch chan any) {
	s.m.Lock()
	publisher := s.publishers[c]
	if publisher != nil {
		publisher.Evict(ch)
		if publisher.Len() == 0 {
			delete(s.publishers, c)

			cpuCacheMu.Lock()
			delete(cpuCache, c.ID)
			cpuCacheMu.Unlock()
		}
	}
	s.m.Unlock()
}

func (s *Collector) Run() {
	type publishersPair struct {
		container *container.Container
		publisher *pubsub.Publisher
	}

	var pairs []publishersPair

	for {
		s.cond.L.Lock()
		for len(s.publishers) == 0 {
			s.cond.Wait()
		}

		pairs = pairs[:0]
		for ctr, publisher := range s.publishers {
			pairs = append(pairs, publishersPair{
				container: ctr,
				publisher: publisher,
			})
		}
		s.cond.L.Unlock()

		var wg sync.WaitGroup
		for _, pair := range pairs {
			wg.Add(1)
			go func(p publishersPair) {
				defer wg.Done()
				stats, err := ReadDirectCgroupStats(p.container)
				if err != nil || stats == nil {
					stats = &containertypes.StatsResponse{
						ID:     p.container.ID,
						Name:   p.container.Name,
						OSType: runtime.GOOS,
					}
				}
				p.publisher.Publish(*stats)
			}(pair)
		}
		wg.Wait()

		time.Sleep(s.interval)
	}
}

func ReadDirectCgroupStats(c *container.Container) (*containertypes.StatsResponse, error) {
	if c == nil {
		return nil, fmt.Errorf("nil container")
	}

	now := time.Now()
	basePath := "/sys/fs/cgroup/docker/" + c.ID

	dirFD, err := unix.Open(basePath, unix.O_RDONLY|unix.O_DIRECTORY, 0)
	if err != nil {
		return nil, err
	}
	defer unix.Close(dirFD)

	// ------------------------------------------------------------------------
	// 1. CPU STATS
	// ------------------------------------------------------------------------
	cpuTotal, _ := readUint64At(dirFD, "cpuacct.usage")
	systemUsage := getSystemCPUUsage()
	userMode, sysMode := readCPUStatsAt(dirFD, "cpuacct.stat")
	perCPU := readPercpuUsageAt(dirFD, "cpuacct.usage_percpu")

	throttlingData := readCPUThrottlingAt(dirFD)

	var preCPUTotal, preSystemUsage uint64
	var preRead time.Time

	cpuCacheMu.Lock()
	if prev, ok := cpuCache[c.ID]; ok {
		preCPUTotal = prev.totalUsage
		preSystemUsage = prev.systemUsage
		preRead = prev.readTime
	}
	cpuCache[c.ID] = cpuSample{
		totalUsage:  cpuTotal,
		systemUsage: systemUsage,
		readTime:    now,
	}
	cpuCacheMu.Unlock()

	stats := &containertypes.StatsResponse{
		ID:      c.ID,
		Name:    c.Name,
		OSType:  runtime.GOOS,
		Read:    now,
		PreRead: preRead,
	}

	stats.CPUStats.CPUUsage.TotalUsage = cpuTotal
	stats.CPUStats.CPUUsage.PercpuUsage = perCPU
	stats.CPUStats.CPUUsage.UsageInUsermode = userMode
	stats.CPUStats.CPUUsage.UsageInKernelmode = sysMode
	stats.CPUStats.SystemUsage = systemUsage
	stats.CPUStats.OnlineCPUs = uint32(runtime.NumCPU())
    stats.CPUStats.ThrottlingData = throttlingData

	stats.PreCPUStats.CPUUsage.TotalUsage = preCPUTotal
	stats.PreCPUStats.SystemUsage = preSystemUsage

	// ------------------------------------------------------------------------
	// 2. MEMORY USAGE / LIMIT
	// ------------------------------------------------------------------------
	rawMemUsage, _ := readUint64At(dirFD, "memory.usage_in_bytes")
	memLimit, _ := readUint64At(dirFD, "memory.limit_in_bytes")
	maxUsage, _ := readUint64At(dirFD, "memory.max_usage_in_bytes")
	failcnt, _ := readUint64At(dirFD, "memory.failcnt")

	memStatsMap := readAndSanitizeMemoryStats(dirFD, rawMemUsage)

	sysMemTotal := getCachedSystemTotalMemory()
	if memLimit == 0 || memLimit > sysMemTotal || memLimit > (1<<62) {
		memLimit = sysMemTotal
	}

	stats.MemoryStats.Usage = rawMemUsage
	stats.MemoryStats.MaxUsage = maxUsage
	stats.MemoryStats.Limit = memLimit
	stats.MemoryStats.Failcnt = failcnt
	stats.MemoryStats.Stats = memStatsMap

	// ------------------------------------------------------------------------
	// 3. BLKIO STATS
	// ------------------------------------------------------------------------
	stats.BlkioStats.IoServiceBytesRecursive = readBlkioEntriesAt(dirFD, []string{
		"blkio.throttle.io_service_bytes",
		"blkio.io_service_bytes",
	})
	stats.BlkioStats.IoServicedRecursive = readBlkioEntriesAt(dirFD, []string{
		"blkio.throttle.io_serviced",
		"blkio.io_serviced",
	})

	// ------------------------------------------------------------------------
	// 4. PIDs & NET I/O
	// ------------------------------------------------------------------------
	pidsCurrent, _ := readUint64At(dirFD, "pids.current")
	stats.PidsStats.Current = pidsCurrent

	if c.State != nil && c.State.Pid > 0 {
		if c.HostConfig != nil && (c.HostConfig.NetworkMode.IsHost() || c.HostConfig.NetworkMode.IsContainer() || c.HostConfig.NetworkMode.IsNone()) {
			stats.Networks = nil
		} else {
			stats.Networks = readNetworkStats(c.State.Pid)
		}
	}

	return stats, nil
}

func readAllAt(dirFD int, fileName string) ([]byte, func()) {
	fd, err := unix.Openat(dirFD, fileName, unix.O_RDONLY, 0)
	if err != nil {
		return nil, func() {}
	}
	defer unix.Close(fd)

	bufPtr := bufPool.Get().(*[]byte)
	buf := *bufPtr

	totalRead := 0
	for {
		if totalRead == len(buf) {
			newBuf := make([]byte, len(buf)*2)
			copy(newBuf, buf)
			buf = newBuf
		}

		n, readErr := unix.Read(fd, buf[totalRead:])
		if n > 0 {
			totalRead += n
		}
		if readErr != nil || n == 0 {
			break
		}
	}

	if totalRead == 0 {
		bufPool.Put(bufPtr)
		return nil, func() {}
	}

	cleanup := func() {
		bufPool.Put(bufPtr)
	}

	return buf[:totalRead], cleanup
}

func readUint64At(dirFD int, fileName string) (uint64, error) {
	data, cleanup := readAllAt(dirFD, fileName)
	defer cleanup()
	if len(data) == 0 {
		return 0, fmt.Errorf("empty file")
	}
	return parseFirstUint64(data), nil
}

func readAndSanitizeMemoryStats(dirFD int, rawMemUsage uint64) map[string]uint64 {
	data, cleanup := readAllAt(dirFD, "memory.stat")
	defer cleanup()

	statMap := make(map[string]uint64, 32)

	if len(data) > 0 {
		for len(data) > 0 {
			var line []byte
			idx := bytes.IndexByte(data, '\n')
			if idx != -1 {
				line = data[:idx]
				data = data[idx+1:]
			} else {
				line = data
				data = nil
			}

			spaceIdx := bytes.IndexByte(line, ' ')
			if spaceIdx == -1 {
				continue
			}

			k := string(line[:spaceIdx])
			v := parseFirstUint64(line[spaceIdx+1:])
			statMap[k] = v
		}
	}

	ensureStatPair := func(k1, k2 string) {
		v1, has1 := statMap[k1]
		v2, has2 := statMap[k2]
		if has1 && !has2 {
			statMap[k2] = v1
		} else if has2 && !has1 {
			statMap[k1] = v2
		} else if !has1 && !has2 {
			statMap[k1] = 0
			statMap[k2] = 0
		}
	}

	ensureStatPair("inactive_file", "total_inactive_file")
	ensureStatPair("active_file", "total_active_file")
	ensureStatPair("inactive_anon", "total_inactive_anon")
	ensureStatPair("active_anon", "total_active_anon")
	ensureStatPair("cache", "total_cache")
	ensureStatPair("rss", "total_rss")
	ensureStatPair("pgpgin", "total_pgpgin")
	ensureStatPair("pgpgout", "total_pgpgout")

	sanitizeKey := func(key string) {
		if val, exists := statMap[key]; exists && val > rawMemUsage {
			statMap[key] = rawMemUsage
		}
	}

	sanitizeKey("inactive_file")
	sanitizeKey("total_inactive_file")
	sanitizeKey("active_file")
	sanitizeKey("total_active_file")
	sanitizeKey("cache")
	sanitizeKey("total_cache")

	statMap["working_set"] = statMap["active_anon"] + statMap["inactive_anon"] + statMap["active_file"]
	if statMap["working_set"] > rawMemUsage {
		statMap["working_set"] = rawMemUsage
	}

	return statMap
}

func readBlkioEntriesAt(dirFD int, fileCandidates []string) []containertypes.BlkioStatEntry {
	var data []byte
	var cleanup func()

	for _, fileName := range fileCandidates {
		data, cleanup = readAllAt(dirFD, fileName)
		if len(data) > 0 {
			break
		}
	}
	defer cleanup()

	entries := make([]containertypes.BlkioStatEntry, 0)
	if len(data) == 0 {
		return entries
	}

	for len(data) > 0 {
		var line []byte
		idx := bytes.IndexByte(data, '\n')
		if idx != -1 {
			line = data[:idx]
			data = data[idx+1:]
		} else {
			line = data
			data = nil
		}

		fields := bytes.Fields(line)
		if len(fields) < 3 {
			continue
		}

		opType := string(fields[1])
		val := parseFirstUint64(fields[2])
		major, minor := parseMajorMinor(fields[0])

		entries = append(entries, containertypes.BlkioStatEntry{
			Major: major,
			Minor: minor,
			Op:    opType,
			Value: val,
		})
	}

	return entries
}

func parseMajorMinor(b []byte) (uint64, uint64) {
	colonIdx := bytes.IndexByte(b, ':')
	if colonIdx == -1 {
		return 0, 0
	}
	major := parseFirstUint64(b[:colonIdx])
	minor := parseFirstUint64(b[colonIdx+1:])
	return major, minor
}

func readCPUStatsAt(dirFD int, fileName string) (uint64, uint64) {
	data, cleanup := readAllAt(dirFD, fileName)
	defer cleanup()

	if len(data) == 0 {
		return 0, 0
	}

	var user, system uint64

	uIdx := bytes.Index(data, []byte("user "))
	if uIdx != -1 && uIdx+5 < len(data) {
		user = parseFirstUint64(data[uIdx+5:]) * 10000000
	}

	sIdx := bytes.Index(data, []byte("system "))
	if sIdx != -1 && sIdx+7 < len(data) {
		system = parseFirstUint64(data[sIdx+7:]) * 10000000
	}

	return user, system
}

func readCPUThrottlingAt(dirFD int) containertypes.ThrottlingData {
	data, cleanup := readAllAt(dirFD, "cpu.stat")
	defer cleanup()

	var t containertypes.ThrottlingData
	if len(data) == 0 {
		return t
	}

	for len(data) > 0 {
		var line []byte
		idx := bytes.IndexByte(data, '\n')
		if idx != -1 {
			line = data[:idx]
			data = data[idx+1:]
		} else {
			line = data
			data = nil
		}

		if bytes.HasPrefix(line, []byte("nr_periods ")) {
			t.Periods = parseFirstUint64(line[11:])
		} else if bytes.HasPrefix(line, []byte("nr_throttled ")) {
			t.ThrottledPeriods = parseFirstUint64(line[13:])
		} else if bytes.HasPrefix(line, []byte("throttled_time ")) {
			t.ThrottledTime = parseFirstUint64(line[15:])
		}
	}

	return t
}

func readPercpuUsageAt(dirFD int, fileName string) []uint64 {
	data, cleanup := readAllAt(dirFD, fileName)
	defer cleanup()

	if len(data) == 0 {
		return nil
	}

	fields := bytes.Fields(data)
	perCPU := make([]uint64, 0, len(fields))

	for _, field := range fields {
		perCPU = append(perCPU, parseFirstUint64(field))
	}

	return perCPU
}

func getCachedSystemTotalMemory() uint64 {
	systemMemOnce.Do(func() {
		bufPtr := bufPool.Get().(*[]byte)
		defer bufPool.Put(bufPtr)

		file, err := os.Open("/proc/meminfo")
		if err != nil {
			return
		}
		defer file.Close()

		n, _ := file.Read(*bufPtr)
		data := (*bufPtr)[:n]

		idx := bytes.Index(data, []byte("MemTotal:"))
		if idx != -1 && idx+9 < len(data) {
			cachedSysMem = parseFirstUint64(data[idx+9:]) * 1024
		}
	})
	return cachedSysMem
}

func getSystemCPUUsage() uint64 {
	file, err := os.Open("/proc/stat")
	if err != nil {
		return 0
	}
	defer file.Close()

	bufPtr := bufPool.Get().(*[]byte)
	defer bufPool.Put(bufPtr)

	n, err := file.Read(*bufPtr)
	if err != nil && err != io.EOF {
		return 0
	}

	line := (*bufPtr)[:n]
	idx := bytes.IndexByte(line, '\n')
	if idx != -1 {
		line = line[:idx]
	}

	if !bytes.HasPrefix(line, []byte("cpu ")) {
		return 0
	}

	var totalJiffies uint64
	cursor := 4
	for cursor < len(line) {
		for cursor < len(line) && line[cursor] == ' ' {
			cursor++
		}
		if cursor >= len(line) {
			break
		}
		start := cursor
		for cursor < len(line) && line[cursor] >= '0' && line[cursor] <= '9' {
			cursor++
		}
		if start < cursor {
			totalJiffies += parseFirstUint64(line[start:cursor])
		}
	}

	return totalJiffies * 10000000
}

func readNetworkStats(pid int) map[string]containertypes.NetworkStats {
	netDevPath := "/proc/" + strconv.Itoa(pid) + "/net/dev"
	file, err := os.Open(netDevPath)
	if err != nil {
		return nil
	}
	defer file.Close()

	bufPtr := bufPool.Get().(*[]byte)
	defer bufPool.Put(bufPtr)

	n, err := file.Read(*bufPtr)
	if err != nil && err != io.EOF {
		return nil
	}

	data := (*bufPtr)[:n]
	networks := make(map[string]containertypes.NetworkStats, 2)

	for len(data) > 0 {
		var line []byte
		idx := bytes.IndexByte(data, '\n')
		if idx != -1 {
			line = data[:idx]
			data = data[idx+1:]
		} else {
			line = data
			data = nil
		}

		colonIdx := bytes.IndexByte(line, ':')
		if colonIdx == -1 {
			continue
		}

		ifaceBytes := bytes.TrimSpace(line[:colonIdx])

		if bytes.Equal(ifaceBytes, []byte("lo")) {
			continue
		}

		rxBytes, txBytes := parseNetDevBytes(line[colonIdx+1:])
		networks[string(ifaceBytes)] = containertypes.NetworkStats{
			RxBytes: rxBytes,
			TxBytes: txBytes,
		}
	}

	return networks
}

func parseFirstUint64(b []byte) uint64 {
	var val uint64
	i := 0
	// 遇到 minus 负号时容错：Linux 某些 cgroup 异常可能会输出 -1
	for i < len(b) && (b[i] < '0' || b[i] > '9') {
		if b[i] == '-' {
			return 0
		}
		i++
	}
	for i < len(b) && b[i] >= '0' && b[i] <= '9' {
		val = val*10 + uint64(b[i]-'0')
		i++
	}
	return val
}

func parseNetDevBytes(b []byte) (uint64, uint64) {
	var rx, tx uint64
	fieldIndex := 0
	i := 0

	for i < len(b) && fieldIndex < 9 {
		for i < len(b) && b[i] == ' ' {
			i++
		}
		if i >= len(b) {
			break
		}

		start := i
		for i < len(b) && b[i] != ' ' {
			i++
		}

		if fieldIndex == 0 {
			rx = parseFirstUint64(b[start:i])
		} else if fieldIndex == 8 {
			tx = parseFirstUint64(b[start:i])
			break
		}
		fieldIndex++
	}

	return rx, tx
}


