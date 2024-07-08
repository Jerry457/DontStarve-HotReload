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

local function UpdateModModule(watcher, mod, modulename, reloadfn_key, reloadfn)
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

    watcher.params[4] = mod[reloadfn_key]  -- update reloadfn
    mod[reloadfn_key] = nil

    print("replaced mod module success")
end

local mainfiles = {
    modmain = "OnHotReloadModmain",
    modworldgenmain = "OnHotReloadModWorldgenmain"
}

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
        if not FileWatcher.GetFileWatchers(path) then  -- first load only
            FileWatcher.WatchFileChange(path, UpdateModModule, mod, modulename, "OnHotReload", mod.OnHotReload)
        end

        mod.OnHotReload = nil
        return unpack(result)
    end

    for file_name, reloadfn_key in pairs(mainfiles) do
        if not ModsModuleData[mod.modname][file_name] then  -- first load only
            ModsModuleData[mod.modname][file_name] = {
                postinitfns = deepcopy(mod.postinitfns),
                postinitdata = deepcopy(mod.postinitdata)
            }
        end

        local main_file_path = resolvefilepath_soft(mod.MODROOT .. file_name .. ".lua")
        if main_file_path and not FileWatcher.GetFileWatchers(main_file_path) then
            FileWatcher.WatchFileChange(main_file_path, UpdateModModule, mod, file_name, reloadfn_key, mod[reloadfn_key])
        end
    end
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
