local hidefn = require("fnhider")
local FileWatcher = require("file_api/file_watcher")

-- hot reload prefab file
local _LoadPrefabFile = LoadPrefabFile

local function UpdatePrefabFile(watcher, ...)
    _LoadPrefabFile(...)
end

function LoadPrefabFile(file_name, ...)
    local ret = _LoadPrefabFile(file_name, ...)
    if ret then
        for i, val in ipairs(ret) do
            if type(val) == "table" and val.is_a and val:is_a(Prefab) then
                local path = resolvefilepath("scripts/" .. file_name .. ".lua")
                FileWatcher.WatchFileChange(path, UpdatePrefabFile, file_name, ...)
            end
        end
    end
    return ret
end
hidefn(LoadPrefabFile, _LoadPrefabFile)

local function OnHotReload()
    LoadPrefabFile = _LoadPrefabFile
end

return {
    OnHotReload = OnHotReload,
    UpdatePrefabFile = UpdatePrefabFile,
}
