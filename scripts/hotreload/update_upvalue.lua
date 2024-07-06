
local function UpdateUpvalue(fn1, fn2)
    assert(type(fn1) == "function")
    assert(type(fn2) == "function")

    local upvalue_map = {}
    for i = 1, math.huge do
        local name, value = debug.getupvalue(fn2, i)
        if not name then break end
        upvalue_map[name] = value
    end

    -- update new upvalues to target
    for i = 1, math.huge do
        local name, value = debug.getupvalue(fn1, i)
        if not name then break end
        if type(upvalue_map[name]) ~= "function" and type(value) ~= "function" then
            debug.setupvalue(fn1, i, upvalue_map[name])
        end
    end
end

return UpdateUpvalue
