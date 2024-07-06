local FileWatcher = require("file_api/file_watcher")

local ModsModuleData = {
    --[[
        [modname] = {
            [modulename] = {
                postinitfns = {}
                postinitdata = {}
            }
        }
    ]]
}

local function UpdateModModule(watcher, mod, modulename, reloadfn)
    if reloadfn then
        reloadfn()
    end

    local module_data = ModsModuleData[mod.modname][modulename]

    local _modimport = mod.modimport
    mod.modimport = function() end  -- only load this modmodule

    mod.postinitfns = deepcopy(module_data.postinitfns)
    mod.postinitdata = deepcopy(module_data.postinitdata)

    HotReloading = true
    mod.HotReloading = HotReloading
    _modimport(modulename)
    HotReloading = false
    mod.HotReloading = HotReloading

    mod.modimport = _modimport

    watcher.params[3] = rawget(_G, "OnHotReload")  -- update reloadfn
    if watcher.params[3] then
        _G.OnHotReload = nil
    end
end

for i, mod in ipairs(ModManager.mods) do
    if not ModsModuleData[mod.modname] then
        ModsModuleData[mod.modname] = {}
    end

    local _modimport = mod.modimport
    mod._modimport = _modimport
    mod.modimport = function(modulename, ...)
        if string.sub(modulename, #modulename - 3, #modulename) ~= ".lua" then
            modulename = modulename .. ".lua"
        end

        if not ModsModuleData[mod.modname][modulename] then  -- first load only
            ModsModuleData[mod.modname][modulename] = {
                postinitfns = deepcopy(mod.postinitfns),
                postinitdata = deepcopy(mod.postinitdata)
            }
        end

        local result = {_modimport(modulename, ...)}

        local path = mod.MODROOT .. modulename
        local OnHotReload = rawget(_G, "OnHotReload")
        if not FileWatcher.GetFileWatchers(path) then  -- first load only
            FileWatcher.WatchFileChange(path, UpdateModModule, mod, modulename, mod.OnHotReload or OnHotReload)
        end

        mod.OnHotReload = nil
        if OnHotReload then
            _G.OnHotReload = nil
        end
        return unpack(result)
    end

    -- FileWatcher.WatchFileChange(path, UpdateModModule, mod, "modmian", mod.OnHotReload or OnHotReload)
end

local function OnHotReload()
    for i, mod in ipairs(ModManager.mods) do
        mod.modimport = mod._modimport
    end
end

return {
    OnHotReload = OnHotReload,
    ModsModuleData = ModsModuleData,
}
