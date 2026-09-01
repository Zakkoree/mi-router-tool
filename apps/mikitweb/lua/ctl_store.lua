local M = {}

local json = require("cjson")
local Res = require("response")
local Env = require("env")

-- 辅助函数：版本号对比 (v1 > v2 返回 1，v1 < v2 返回 -1，相等返回 0)
local function version_gt(v1, v2)
    if not v1 or v1 == "" then return 0 end
    if not v2 or v2 == "" then return 1 end

    local a, b = {}, {}
    for num in string.gmatch(v1:gsub("[^0-9.]", ""), "%d+") do table.insert(a, tonumber(num)) end
    for num in string.gmatch(v2:gsub("[^0-9.]", ""), "%d+") do table.insert(b, tonumber(num)) end

    local max_len = math.max(#a, #b)
    for i = 1, max_len do
        local num1 = a[i] or 0
        local num2 = b[i] or 0
        if num1 > num2 then return 1 end
        if num1 < num2 then return -1 end
    end
    return 0
end

-- 辅助函数：判断架构兼容性
local function check_arch_compat(app_arch, sys_arch)
    if app_arch == "all" then
        return true
    elseif app_arch and sys_arch and string.find("|" .. app_arch .. "|", "|" .. sys_arch .. "|", 1, true) then
        return true
    else
        return false
    end
end

-- 服务函数：获取商店应用数据列表（静默运行，无终端输出）
function M.apps()
    local store_apps_list = {}

    -- 1. 获取已安装列表与版本映射
    local cmd = string.format("uci -c %s -q get mikit_db.mikit.apps", Env.ROOT_DIR .. "/data")
    local raw_installed = Env.exec_cmd(cmd)
    local installed_apps_map = {}
    local installed_ver_map = {}

    for app_id in string.gmatch(raw_installed, "%S+") do
        installed_apps_map[app_id] = true
        cmd = string.format("uci -c %s -q get mikit_db.%s.version", Env.ROOT_DIR .. "/data", app_id)
        local ver = Env.exec_cmd(cmd)
        installed_ver_map[app_id] = (ver and ver ~= "") and ver or "0.0.0"
    end

    local store_dir = Env.ROOT_DIR .. "/data/store"

    -- 2. 遍历商店 JSON 文件
    local p = io.popen('ls "' .. store_dir .. '"/*.json 2>/dev/null')
    if p then
        for json_path in p:lines() do
            local file = io.open(json_path, "r")
            if file then
                local content = file:read("*a")
                file:close()

                local ok, store_data = pcall(json.decode, content)
                if ok and store_data then
                    local sid = store_data.source_id or ""
                    local surl = store_data.source_url or ""
                    local apps = store_data.apps or { store_data }

                    for _, app in ipairs(apps) do
                        if app.id and app.id ~= "" then
                            local is_installed = "uninstalled"
                            local local_v = ""

                            -- 判断安装/更新状态
                            if installed_apps_map[app.id] then
                                local_v = installed_ver_map[app.id] or "0.0.0"
                                if version_gt(app.version, local_v) == 1 then
                                    is_installed = "upgradable"
                                else
                                    is_installed = "installed"
                                end
                            end

                            local is_compatible = check_arch_compat(app.arch, Env.detect_arch())

                            -- 组合数据结构
                            table.insert(store_apps_list, {
                                id = app.id,
                                name = (app.name and app.name ~= "") and app.name or app.id,
                                version = app.version or "",
                                author = app.author or "",
                                arch = app.arch or "",
                                is_compatible = is_compatible,
                                url = app.url or "",
                                icon = app.icon or "",
                                desc = app.desc or "",
                                status = is_installed,
                                local_version = local_v,
                                source_id = sid,
                                source_url = surl
                            })
                        end
                    end
                end
            end
        end
        p:close()
    end

    return store_apps_list
end

return M