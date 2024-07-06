local UpdateTable = require("hotreload/update_table")
local FileWatcher = require("file_api/file_watcher")

local _require = require

local function UpdateModule(watcher, module_name, reloadfn)
    if reloadfn then
        reloadfn()
    end

    local _module = package.loaded[module_name]

    if type(_module) == "table" and _module.OnHotReload and _module.OnHotReload ~= reloadfn then
        _module.OnHotReload()
    end

    package.loaded[module_name] = nil

    HotReloading = true
    local ok, err = pcall(_require, module_name)
    HotReloading = false
    if not ok then
        package.loaded[module_name] = _module
        print("reload lua file failed.", err)
        return
    end

    watcher.params[2] = rawget(_G, "OnHotReload")  -- update reloadfn
    if watcher.params[2] then
        _G.OnHotReload = nil
    end

    local module = package.loaded[module_name]

    if type(module) == "table" and type(_module) == "table" then
        UpdateTable.UpdateTable(_module, module)
        package.loaded[module_name] = _module
    end
    print("replaced succeed")
end

function require(module_name, ...)
    local ret = {_require(module_name)}

    local OnHotReload = rawget(_G, "OnHotReload")
    local path = resolvefilepath_soft("scripts/" .. module_name .. ".lua")
    if path and not FileWatcher.GetFileWatchers(path) then  -- first load only
        FileWatcher.WatchFileChange(path, UpdateModule, module_name, OnHotReload)
    end
    if OnHotReload then
        _G.OnHotReload = nil
    end

    return unpack(ret)
end

local function OnHotReload()
    require = _require
end

return {
    OnHotReload = OnHotReload
}
