local FileChangeWatchers = {
    --[[
    [file_path] = {
        {fn = fn, params = { ... } },
        {fn = fn, params = { ... } }
    }
    --]]
}

local function GetFileWatchers(path)
    return FileChangeWatchers[path]
end

local function WatchFileChange(path, fn, ...)
    local wathcers = GetFileWatchers(path)
    if not wathcers then
        wathcers = {}
        FileChangeWatchers[path] = wathcers
    end

    table.insert(wathcers, { fn = fn, params = { ... } })
end

local function RemoveAllWatcher()
    FileChangeWatchers = {}
end

local function PushFileChange(file_path)
    for i, mod in ipairs(ModManager.mods) do
        local path = resolvefilepath_soft(MODS_ROOT .. mod.modname .. "/change_file.lua")
        if path then
            local result = kleiloadlua(mod.MODROOT .. "change_file.lua")
            if result and type(result) ~= "string" then
                setfenv(result, mod)
                result()
                if mod.change_file then
                    local change_path = resolvefilepath_soft(MODS_ROOT .. mod.modname .. "/".. mod.change_file)
                    if change_path then
                        local watchers = GetFileWatchers(change_path)
                        if watchers then
                            print(mod.change_file .. " has changed", change_path)
                            for i, watcher in ipairs(watchers) do
                                watcher.fn(watcher, unpack(watcher.params))
                            end
                        end
                    end
                end
            end

            -- clear file
            mod.change_file = nil
            local file = io.open(path, "w")
            file:close()
        end
    end
end

return {
    WatchFileChange = WatchFileChange,
    GetFileWatchers = GetFileWatchers,
    PushFileChange = PushFileChange,
    RemoveAllWatcher = RemoveAllWatcher,
}
