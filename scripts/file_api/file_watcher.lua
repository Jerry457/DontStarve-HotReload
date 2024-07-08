local FileWatcher
if rawget(_G, "jit") then
    FileWatcher = require("file_api/file_watcher_jit")
else
    FileWatcher = require("file_api/file_watcher_normal")
end

local FileChangeWatcher = staticScheduler:ExecutePeriodic(1, FileWatcher.PushFileChange)

local _SimReset = SimReset
function SimReset(...)
    FileChangeWatcher:Cancel()
    FileWatcher.RemoveAllWatcher()
    return _SimReset(...)
end

local function OnHotReload()
    SimReset = _SimReset
    FileChangeWatcher:Cancel()
end

return {
    GetFileWatchers = FileWatcher.GetFileWatchers,
    WatchFileChange = FileWatcher.WatchFileChange,
    RemoveAllWatcher = FileWatcher.RemoveAllWatcher,
    PushFileChange = FileWatcher.PushFileChange,
    OnHotReload = OnHotReload,
}
