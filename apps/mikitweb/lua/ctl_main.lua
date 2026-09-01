local M = {}

local Env = require("env")
local Res = require("response")

M.ROOT_DIR = Env and Env.ROOT_DIR or "./"

-- 1. 获取 MIKIT 版本号
local function get_ver_via_sh()
    local env_file = M.ROOT_DIR .. "/core/env.sh"
    local file = io.open(env_file, "r")
        if not file then return nil end

        for line in file:lines() do
            -- 匹配: MIKIT_VER="2.4.0" 或 export MIKIT_VER = '2.4.0' 等各种规范/不规范写法
            local ver = line:match("MIKIT_VER%s*=%s*[\"']?(.-)[\"']?%s*$")
            if ver and ver ~= "" then
                file:close()
                return ver
            end
        end
        file:close()
        return nil
end

local function get_app_sum()
    local root = Env and Env.ROOT_DIR or "./"
    if root:sub(-1) ~= "/" then
        root = root .. "/"
    end
    local config_dir = root .. "data"

    local cmd = string.format("uci -c %s -q get mikit_db.mikit.apps 2>/dev/null", config_dir)
    local result = Env.exec_cmd(cmd)
    if not result or result == "" then
        return {}, 0
    end
    local app_list = {}
    local count = 0

    for app in result:gmatch("%S+") do
        table.insert(app_list, app)
        count = count + 1
    end

    -- 返回包含两个元素的元组：(应用列表Table, 应用总个数)
    return count
end

local function get_memory_usage()
    local meminfo = Env.exec_cmd("cat /proc/meminfo 2>/dev/null")
    if meminfo then
        local total_kb = tonumber(meminfo:match("MemTotal:%s+(%d+)%s+kB") or 0)
        local avail_kb = tonumber(meminfo:match("MemAvailable:%s+(%d+)%s+kB") or 0)

        if avail_kb == 0 then
            local free_kb    = tonumber(meminfo:match("MemFree:%s+(%d+)%s+kB") or 0)
            local buffers_kb = tonumber(meminfo:match("Buffers:%s+(%d+)%s+kB") or 0)
            local cached_kb  = tonumber(meminfo:match("^Cached:%s+(%d+)%s+kB") or 0)
            avail_kb = free_kb + buffers_kb + cached_kb
        end

        if total_kb > 0 then
            local used_kb = math.max(0, total_kb - avail_kb)
            local used_mb = math.floor(used_kb / 1024)
            local percent = math.floor((used_kb / total_kb) * 100)
            return used_mb .. " MB", percent .. "%"
        end
    end
    return "500 MB", "0%"
end

local function get_cpu_temp()
    local shell_cmd = [[
        if [ -f /sys/devices/virtual/thermal/thermal_zone0/temp ]; then
            echo "$(cat /sys/devices/virtual/thermal/thermal_zone0/temp 2>/dev/null)"
        elif [ -f /proc/dmu/temperature ]; then
            cat /proc/dmu/temperature 2>/dev/null | awk '{print $4}' | cut -b 1-2
        else
            echo "N/A"
        fi
    ]]

    local res = Env.exec_cmd(shell_cmd)

    if res then
        res = res:gsub("%s+", "")
    end

    if res and tonumber(res) then
        local val = tonumber(res)
        if val > 1000 then
            val = math.floor(val / 1000)
        end
        return tostring(val) .. "°C"
    end

    if res and res ~= "" then
        return res:find("°C") and res or (res .. "°C")
    end

    return "N/A"
end

local function get_system_uptime()
    local uptime_str = Env.exec_cmd("cat /proc/uptime 2>/dev/null | awk '{print $1}'")
    if uptime_str and tonumber(uptime_str) then
        local total_seconds = math.floor(tonumber(uptime_str))
        local days = math.floor(total_seconds / 86400)
        local hours = math.floor((total_seconds % 86400) / 3600)
        local mins = math.floor((total_seconds % 3600) / 60)

        if days > 0 then
            -- 超过 1 天：精简展示为 "X天Y小时" 或 "X天"
            if hours > 0 then
                return string.format("%d天%d时", days, hours)
            else
                return string.format("%d天", days)
            end
        elseif hours > 0 then
            -- 1天以内：展示为 "X时Y分"
            return string.format("%d时%d分", hours, mins)
        else
            -- 1小时以内：展示为 "X分"
            return string.format("%d分", math.max(1, mins))
        end
    end
    return "2天5时" -- 保底精简格式
end

function M.info()
    local mem_mb, mem_pct = get_memory_usage()
    local data = {
        version      = get_ver_via_sh() or "0.0.0",
        appSum = get_app_sum(),
        memory      = mem_mb,
        mem_percent = mem_pct,
        temp         = get_cpu_temp(),
        uptime       = get_system_uptime()
    }

    return {
        code = 0,
        msg = "success",
        data = data
    }
end

return M