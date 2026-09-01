# 🛠️ 自行编译适配版 Dockerd

专为小米路由器官方固件设计的 Docker 优化补丁。完美解决 Docker `stats` 及第三方监控工具（如 Portainer、Beszel、Dpanel 等）失灵问题（CPU、内存、网络流量统计全部显示为 0 的问题）。

> 💡 **测试设备**：已在 **Xiaomi BE7000** 上完整验证。其他型号请自行测试。*(注：由于系统内核缺失 BLKIO 统计模块，所以还是不支持磁盘 I/O 统计)*

如果你需要修改代码或升级到其他版本，请参考以下编译流程：

### 1. 克隆 Moby 源码并切换分支

```bash
git clone -b docker-29.x https://github.com/moby/moby.git
cd moby
```

### 2. 应用适配补丁

将本项目 `dockerd/` 目录下的补丁文件覆盖到 Moby 对应的源码路径：
* 本项目 `dockerd/collector.go` ➡️ 覆盖 Moby 的 `daemon/stats/collector.go`
* 本项目 `dockerd/stats.go` ➡️ 覆盖 Moby 的 `daemon/stats/stats.go`

### 3. Docker 容器内交叉编译 (ARM64)

```bash
docker run --rm \
  -e CGO_ENABLED=0 \
  -e GOOS=linux \
  -e GOARCH=arm64 \
  -e VER='29.7.1-xiaomi' \
  -e PKG='github.com/moby/moby/v2/dockerversion' \
  -e COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo custom)" \
  -e BUILDTIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -v "$PWD":/go/src/github.com/moby/moby \
  -w /go/src/github.com/moby/moby \
  golang:1.26-alpine \
  sh -c 'go build -mod=vendor \
    -ldflags="-s -w \
      -X ${PKG}.Version=${VER} \
      -X ${PKG}.GitCommit=${COMMIT} \
      -X ${PKG}.BuildTime=${BUILDTIME}" \
    -v -o dockerd ./cmd/dockerd'
```

### 4. 手动替换部署

1. 编译完成后，将生成的 `dockerd` 传输至路由器。
2. 备份并替换官方二进制文件：
   ```bash
   cp /mnt/usb-*/mi_docker/docker-binaries/dockerd /mnt/usb-*/mi_docker/docker-binaries/dockerd_bak
   cp dockerd /mnt/usb-*/mi_docker/docker-binaries/dockerd
   chmod +x /mnt/usb-*/mi_docker/docker-binaries/dockerd
   ```
3. 重启 Docker 服务：
   ```bash
   /etc/init.d/dockerd restart
   ```
4. 验证版本：
   运行 `dockerd --version`，应输出 `Docker version 29.7.1-xiaomi, build <commit-id>`。

---


## 📊 性能对比报告：重构采集器 vs Docker 原生

`评估数据来自 Google Gemini`

针对小米路由器的定制补丁使用了 **直读 Cgroup (`openat` + `dirFD`)** 与 **Zero-Alloc** 极致优化，性能相比 Docker 原生实现得到了数量级提升：


### 核心性能对比摘要

| 评估维度 | Docker 原生实现 | 重构采集器                  | 优化提升                        |
| :--- | :--- |:----------------------------|:--------------------------------|
| **单次采集耗时** | ~1.5 ms - 3.0 ms | **~15 μs - 40 μs**          | **🚀 速度提升 50~100 倍**       |
| **内存分配 (Allocs/op)** | 高 (频繁触发堆分配) | **接近 0 (Zero-Alloc)**     | **📉 内存分配降低 90%+**        |
| **GC (垃圾回收) 压力** | 明显 (产生大量临时对象) | **极低 (无 STW 风险)**      | 🛡️ 极大缓解高频采集下的 GC 停顿 |
| **系统调用 Overhead** | 高 (逐级解析 VFS 绝对路径) | **低 (`dirFD` + `openat`)** | **⚡ Syscall 速度提升 30%~50%** |
| **生态兼容性** | 标准逻辑 | **完全兼容**                | 💯 完美兼容 DPanel / Beszel 等  |

> 总结: 稳定能用

---