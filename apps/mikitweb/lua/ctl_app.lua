local M = {}

local cjson = require "cjson"
local Res = require("response")
local Env = require("env")

local function get_apps()
    local cmd = string.format("uci -c %s -q get mikit_db.mikit.apps", Env.ROOT_DIR .. "/data")
    local result = Env.exec_cmd(cmd)

    if not result or result == "" then
        return {}
    end

    -- 把空格隔开的多个项拆分并放入一个 Lua 数组中
    local apps = {}
    for app_id in string.gmatch(result, "%S+") do
        local manifest_path = Env.DATA_DIR .. "/apps/" .. app_id .. "/manifest.json"

        -- 初始化一个基础表，并把 id 放进去
        local app_info = { id = app_id }

        local file = io.open(manifest_path, "r")
        if file then
            local content = file:read("*a")
            file:close()

            local ok, json_data = pcall(cjson.decode, content)
            -- 如果 json 解析成功，并且是个表，就把里面的字段平铺合并到 app_info 中
            if ok and type(json_data) == "table" then
                for k, v in pairs(json_data) do
                    app_info[k] = v
                end
            end
        end

        table.insert(apps, app_info)
    end
    return apps
end

function M.list()
    local list = get_apps()
    return list
end

function M.status(params)
    local app_id = params.app_id or params.id or "all"
    local root_dir = Env.ROOT_DIR or "/"
    local script_path = Env.DATA_DIR .. "/apps/" .. app_id .. "/" .. app_id

    -- 补载环境并执行 status
    local cmd = string.format(
        "[ -f /etc/profile ] && . /etc/profile; cd %s && %s status 2>&1",
        root_dir,
        script_path
    )

    local result = Env.exec_cmd(cmd)

    -- 直接根据脚本输出的内容判断：包含 status=running 即为运行中
    local is_running = false
    if string.find(result, "status=running") then
        is_running = true
    end

    return {
        id = app_id,
        status = is_running and "running" or "stopped"
    }
end


function M.toggle(params)
    local app_id = params.id
    local target_status = params.status -- "running" 或 "stopped"

    if not app_id or app_id == "" then
        return Res.bad_request("应用 ID 不能为空")
    end

    if target_status ~= "running" and target_status ~= "stopped" then
        return Res.bad_request("无效的目标状态")
    end

    if not app_id:match("^[a-zA-Z0-9_-]+$") then
        return Res.bad_request("非法的应用 ID 格式")
    end

    local action = (target_status == "running") and "start" or "stop"
    local script_path = Env.DATA_DIR .. "/apps/" .. app_id .. "/" .. app_id

    -- 检查服务脚本是否存在
    local check_file = io.open(script_path, "r")
    if not check_file then
        return Res.error("未找到该应用的管理服务")
    end
    check_file:close()

    local cmd = string.format(
        "[ -f /etc/profile ] && . /etc/profile; (cd %s && %s %s < /dev/null > /dev/null 2>&1 &)",
        Env.ROOT_DIR,
        script_path,
        action
    )

    local result = Env.exec_cmd(cmd)

    return {
        code = 0,
        msg = "success",
        data = {
            id = app_id,
            status = target_status
        }
    }
end


return M