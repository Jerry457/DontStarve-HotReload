local FileWatcher = require("file_api/file_watcher")

local _LoadPOFile = LanguageTranslator.LoadPOFile
local function UpdatePOFile(watcher, ...)
    _LoadPOFile(...)
    TranslateStringTable(STRINGS)
    for guid, ent in pairs(Ents) do  -- update ent name
        if ent.prefab then
            ent.name = STRINGS.NAMES[string.upper(ent.prefab)] or "MISSING NAME"
        end
    end
end

function Translator:LoadPOFile(file_name, ...)
    local path = resolvefilepath(file_name)
    FileWatcher.WatchFileChange(path, UpdatePOFile, self, file_name, ...)

    return _LoadPOFile(self, file_name, ...)
end

local function OnHotReload()
    LanguageTranslator.LoadPOFile = _LoadPOFile
end

return {
    OnHotReload = OnHotReload
}
