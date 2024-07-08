local hidefn = require("fnhider")
local UpdateUpvalue = require("hotreload/update_upvalue")

local ProxyFnMap = {}
local FnProxyMap = {}

local function can_stringified(value)
    local value_type = type(value)
    return value_type ~= "nil" and value_type ~= "function" and value_type ~= "table" and value_type ~= "thread" and value_type ~= "userdata"
end

local function HasProxy(key)
    return ProxyFnMap[key] ~= nil
end

local function ProxyFuctinon(key, fn)
    local function proxy(...)
        return ProxyFnMap[key](...)
    end

    ProxyFnMap[key] = fn
    FnProxyMap[fn] = proxy
    hidefn(proxy, fn)

    return proxy
end

local function UpdateProxyFunction(key, fn)
    local _fn = ProxyFnMap[key]
    if _fn then
        local proxy = FnProxyMap[_fn]
        ProxyFnMap[key] = fn
        FnProxyMap[fn] = proxy
        hidefn(proxy, fn)
        UpdateUpvalue(fn, _fn)
    else
        return ProxyFuctinon(key, fn)
    end
end

local function ProxyTableFuctinon(prefix, t, visited)
    visited = visited or setmetatable({}, {__mode = "k"})
    if visited[t] then
        return
    end
    visited[t] = true

    for k, v in pairs(t) do
        if can_stringified(k) then
            local k_prefix = prefix .. "." .. tostring(k)
            if type(v) == "function" and not HasProxy(k) then
                t[k] = ProxyFuctinon(k_prefix, v)
            elseif type(v) == "table" then
                ProxyTableFuctinon(k_prefix, v, visited)
            end
        end
    end
end

local function UpdateProxyFuctinonTable(prefix, t1, t2)
    for k, v in pairs(t2) do
        if can_stringified(k) then
            local k_prefix = prefix .. ".".. tostring(k)
            if type(v) == "table" and type(t1[k]) == "table" then
                UpdateProxyFuctinonTable(k_prefix, t1[k], v)
            else if type(v) == "function" and type(t1[k]) == "function" then
                local proxy = UpdateProxyFunction(k_prefix, v)
                if proxy then
                    t1[k] = proxy
                end
            end
                t1[k] = v
            end
        end
    end
end

return {
    HasProxy = HasProxy,
    ProxyFuctinon = ProxyFuctinon,
    UpdateProxyFunction = UpdateProxyFunction,
    ProxyTableFuctinon = ProxyTableFuctinon,
    UpdateProxyFuctinonTable = UpdateProxyFuctinonTable,
}
