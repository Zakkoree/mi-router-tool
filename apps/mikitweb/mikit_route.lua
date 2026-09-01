local cjson = require "cjson"

-- 核心统一输出函数（直接内嵌在当前脚本中）
local function output(code, msg, data, status_code)
    status_code = status_code or (code == 0 and 200 or code)

    io.write("Status: " .. status_code .. " OK\r\n")
    io.write("Content-Type: application/json; charset=utf-8\r\n")
    io.write("Access-Control-Allow-Origin: *\r\n")
    io.write("Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n")
    io.write("Access-Control-Allow-Headers: Content-Type\r\n\r\n")

    io.write(cjson.encode({
        code = code,
        msg = msg,
        data = data
    }))
    os.exit(0)
end

local current_dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local extra_path = ";" .. current_dir .. "lua/?.lua"
if not string.find(package.path, extra_path, 1, true) then
    package.path = package.path .. extra_path
end

local function parse_query_string(query_str)
    local params = {}
    if not query_str or query_str == "" then return params end

    for key, value in string.gmatch(query_str, "([^&=]+)=([^&]*)") do
        key = string.gsub(key, "+", " ")
        key = string.gsub(key, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)

        value = string.gsub(value, "+", " ")
        value = string.gsub(value, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)

        params[key] = value
    end
    return params
end

local function parse_post_data()
    local method = os.getenv("REQUEST_METHOD") or "GET"
    if method ~= "POST" and method ~= "PUT" then return {} end

    local content_length = tonumber(os.getenv("CONTENT_LENGTH") or 0)
    if not content_length or content_length <= 0 then return {} end

    local body = io.read(content_length)
    if not body or body == "" then return {} end

    local ok, data = pcall(cjson.decode, body)
    if ok and type(data) == "table" then
        return data
    end

    return parse_query_string(body)
end

local function get_request_params()
    local params = {}

    local query_string = os.getenv("QUERY_STRING")
    local get_params = parse_query_string(query_string)
    for k, v in pairs(get_params) do params[k] = v end

    local post_params = parse_post_data()
    for k, v in pairs(post_params) do params[k] = v end

    return params
end

local uri = os.getenv("REQUEST_URI") or ""
local path_info = os.getenv("PATH_INFO") or ""

if not string.find(uri, "mikit") then return end

if os.getenv("REQUEST_METHOD") == "OPTIONS" then
    io.write("Status: 204 No Content\r\n")
    io.write("Access-Control-Allow-Origin: *\r\n")
    io.write("Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n")
    io.write("Access-Control-Allow-Headers: Content-Type\r\n\r\n")
    os.exit(0)
end

local req_params = get_request_params()

local inner_controllers = {
    default = {
        index = function(params)
            return { code = 0, msg = "API 服务运行中", data = { received_params = params } }
        end
    }
}

local c_name, a_name = string.match(path_info, "/mikit/([%w_]+)/?([%w_]*)")

c_name = c_name or "default"
a_name = (a_name and a_name ~= "") and a_name or "index"

local controller = nil
local load_ok, ext_controller = pcall(require, "ctl_" .. c_name)

if load_ok and type(ext_controller) == "table" then
    controller = ext_controller
elseif inner_controllers[c_name] then
    controller = inner_controllers[c_name]
end

if controller and type(controller[a_name]) == "function" then
    local ok, result = pcall(controller[a_name], req_params)
    if ok then
        if type(result) == "table" and result.code ~= nil then
            output(result.code, result.msg, result.data, result.code == 0 and 200 or 400)
        else
            output(0, "success", result, 200)
        end
    else
        output(500, "error" .. tostring(result), nil, 500)
    end
else
    output(404, "not found: " .. tostring(c_name) .. "/" .. tostring(a_name), nil, 404)
end