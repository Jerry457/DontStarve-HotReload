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

local change_file_name = "client.lua"
if TheNet:GetIsMasterSimulation() then  -- ismastersim
    local TheShard = rawget(_G, "TheShard")
    if not TheShard or not TheShard:IsSecondary() then
        change_file_name = "master.lua"
    else
        change_file_name = "cave.lua"
    end
end
local change_file_path = "change_file/".. change_file_name

local function PushFileChange(file_path)
    for i, mod in ipairs(ModManager.mods) do

        local path = resolvefilepath_soft(MODS_ROOT .. mod.modname .. "/" .. change_file_path)
        if path then
            local result = kleiloadlua(mod.MODROOT .. change_file_path)
            if not result or type(result) == "string" then
                print("change_file error:", result)
            else
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
