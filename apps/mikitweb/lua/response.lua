local M = {}

function M.json(code, msg, data)
    return {
        code = code,
        msg = msg or "",
        data = data or nil
    }
end

function M.success(data, msg)
    return M.json(0, msg or "获取成功", data)
end

function M.bad_request(msg)
    return M.json(400, msg or "请求参数错误")
end

function M.unauthorized(msg)
    return M.json(401, msg or "未授权，请先登录")
end

function M.forbidden(msg)
    return M.json(403, msg or "拒绝访问，权限不足")
end

function M.error(msg)
    return M.json(500, msg or "服务器内部错误")
end

return M