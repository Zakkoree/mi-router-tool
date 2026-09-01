local M = {}

local function get_profile_env(key)
    local file = io.open("/etc/profile", "r")
    if not file then return nil end

    for line in file:lines() do
        local val = line:match("^%s*export%s+" .. key .. '%s*=%s*["\']?(.-)["\']?$')
        if val then
            file:close()
            return val
        end
    end
    file:close()
    return nil
end
M.ROOT_DIR = os.getenv("MIKIT_DIR") or get_profile_env("MIKIT_DIR") or "/data/mikit/"
M.DATA_DIR = os.getenv("MIKIT_DATA_DIR") or get_profile_env("MIKIT_DATA_DIR")


function M.exec_cmd(cmd)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result:match("^%s*(.-)%s*$")
end

function M.detect_arch()
    -- 1. 执行 uname -m 获取架构信息
    local handle = io.popen("uname -m")
    if not handle then return "unknown" end

    local raw_arch = handle:read("*a")
    handle:close()

    -- 清除首尾空白字符及换行符
    raw_arch = raw_arch and raw_arch:gsub("%s+", "") or ""

    -- 2. 匹配架构逻辑 (模式匹配)
    if raw_arch:find("^aarch64") or raw_arch:find("^arm64") then
        return "arm64"

    elseif raw_arch:find("^armv7") then
        return "armv7"

    elseif raw_arch:find("^armv5") or raw_arch:find("^armv6") or raw_arch == "arm" then
        return "armv5"

    elseif raw_arch == "x86_64" or raw_arch == "amd64" then
        return "amd64"

    elseif raw_arch == "i386" or raw_arch == "i686" or raw_arch == "x86" then
        return "386"

    elseif raw_arch:find("^mips") then
        -- 读取 /proc/cpuinfo 内容
        local cpu_info = ""
        local f = io.open("/proc/cpuinfo", "r")
        if f then
            cpu_info = f:read("*a") or ""
            f:close()
        end

        -- 判断小端序 (mipsle)
        if raw_arch == "mipsel" or raw_arch == "mips64el" or
           cpu_info:find("MT7621") or
           cpu_info:find("MediaTek") or
           cpu_info:lower():find("little endian") then
            return "mipsle"
        else
            return "mips"
        end

    else
        return raw_arch
    end
end

return M