local ffi = require("ffi")

if not rawget(_G, "HotReloading") then
    ffi.cdef[[
        typedef char*               LPSTR;
        typedef const char*         LPCSTR;
        typedef void*               HANDLE;
        typedef void*               PVOID;
        typedef void*               LPVOID;
        typedef int                 BOOL;
        typedef BOOL                *LPBOOL;
        typedef unsigned int        UINT;
        typedef unsigned short      WCHAR;
        typedef unsigned long       DWORD, *ULONG_PTR;
        typedef WCHAR*              LPWSTR;
        typedef const WCHAR*        LPCWSTR;
        typedef DWORD*              LPDWORD;

        static const DWORD WAIT_OBJECT_0 = 0;
        static const DWORD INFINITE = 0xFFFFFFFF;
        static const DWORD FILE_NOTIFY_CHANGE_LAST_WRITE = 0x00000010;
        static const DWORD FILE_LIST_DIRECTORY = 0x0001;

        typedef struct _OVERLAPPED {
            ULONG_PTR Internal;
            ULONG_PTR InternalHigh;
            union {
                struct {
                    DWORD Offset;
                    DWORD OffsetHigh;
                } DUMMYSTRUCTNAME;
                PVOID Pointer;
            } DUMMYUNIONNAME;
            HANDLE    hEvent;
        } OVERLAPPED, *LPOVERLAPPED;

        typedef struct _FILE_NOTIFY_INFORMATION {
            DWORD NextEntryOffset;
            DWORD Action;
            DWORD FileNameLength;
            WCHAR FileName[1];
        } FILE_NOTIFY_INFORMATION, *PFILE_NOTIFY_INFORMATION;

        typedef void (LPOVERLAPPED_COMPLETION_ROUTINE)(
            DWORD dwErrorCode,
            DWORD dwNumberOfBytesTransfered,
            LPOVERLAPPED lpOverlapped
        );

        int MultiByteToWideChar(
            UINT     CodePage,
            DWORD    dwFlags,
            LPCSTR   lpMultiByteStr,
            int      cbMultiByte,
            LPWSTR   lpWideCharStr,
            int      cchWideChar
        );

        int WideCharToMultiByte(
            UINT     CodePage,
            DWORD    dwFlags,
            LPCWSTR  lpWideCharStr,
            int      cchWideChar,
            LPSTR    lpMultiByteStr,
            int      cbMultiByte,
            LPCSTR   lpDefaultChar,
            LPBOOL   lpUsedDefaultChar
        );

        HANDLE CreateFileW(
            LPCWSTR lpFileName,
            DWORD dwDesiredAccess,
            DWORD dwShareMode,
            LPVOID lpSecurityAttributes,
            DWORD dwCreationDisposition,
            DWORD dwFlagsAndAttributes,
            HANDLE hTemplateFile
        );

        HANDLE CreateEventW(
            LPVOID lpEventAttributes,
            BOOL bManualReset,
            BOOL bInitialState,
            LPCWSTR lpName
        );

        BOOL ReadDirectoryChangesW(
            HANDLE hDirectory,
            LPVOID lpBuffer,
            DWORD nBufferLength,
            BOOL bWatchSubtree,
            DWORD dwNotifyFilter,
            LPDWORD lpBytesReturned,
            LPOVERLAPPED lpOverlapped,
            LPOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine
        );

        BOOL CloseHandle(
            HANDLE hObject
        );

        BOOL ResetEvent(
            HANDLE hEvent
        );

        DWORD GetFullPathNameW(
            LPCWSTR lpFileName,
            DWORD nBufferLength,
            LPWSTR lpBuffer,
            LPWSTR* lpFilePart
        );

        DWORD GetFileAttributesW(LPCWSTR lpFileName);

        DWORD GetLastError();
        ]]
end

local function buffer(type)
    return function(size)
        return ffi.new(type, size)
    end
end

local wcsbuf = buffer("WCHAR[?]")
local mbsbuf = buffer("char[?]")
local kernel32 = ffi.load("kernel32")

local CP_UTF8 = 65001
local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF

local DirectoryWatchers = {
    --[[
    [directory_path] = {
        watchfiles = {
            {fn = fn, params = { ... } },
            {fn = fn, params = { ... } }
        }
    }
    --]]
}

local function string_to_wchar(s, msz, wbuf) -- string -> WCHAR[?]
    msz = msz and msz + 1 or #s + 1
    wbuf = wbuf or wcsbuf
    local wsz = ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, msz, nil, 0)
    assert(wsz > 0)  -- should never happen otherwise
    local buf = wbuf(wsz)
    local sz = ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, msz, buf, wsz)
    assert(sz == wsz)  -- should never happen otherwise
    return buf
end

local function wchar_to_string(ws, wsz, mbuf) -- WCHAR* -> string
    wsz = wsz and wsz + 1 or -1
    mbuf = mbuf or mbsbuf
    local msz = ffi.C.WideCharToMultiByte(
        CP_UTF8, 0, ws, wsz, nil, 0, nil, nil)
    assert(msz > 0) -- should never happen otherwise
    local buf = mbuf(msz)
    local sz = ffi.C.WideCharToMultiByte(
        CP_UTF8, 0, ws, wsz, buf, msz, nil, nil)
    assert(sz == msz) -- should never happen otherwise
    return ffi.string(buf, sz - 1)
end

local function GetFullPathName(path)
    local buffer = ffi.new("WCHAR[260]")  -- MAX_PATH is 260
    local length = ffi.C.GetFullPathNameW(string_to_wchar(path), 260, buffer, nil)
    if length == 0 then
        local err_code = ffi.C.GetLastError()
        error("Failed to get full path name. Error code: " .. err_code)
    end
    return wchar_to_string(buffer, length)
end

local function FileExists(file_path)
    local w_file_path = string_to_wchar(file_path)
    local attributes = kernel32.GetFileAttributesW(w_file_path)
    return attributes ~= INVALID_FILE_ATTRIBUTES
end

local function GetAbsolutePath(path)
    local absolute_path = GetFullPathName(path)

    if path:find("../mods/workshop") and not FileExists(absolute_path) then
        local workshop_path = string.gsub(path, "%.%.%/mods/workshop%-", "../../../workshop/content/322330/")
        absolute_path = GetFullPathName(workshop_path)
    end

    return FileExists(absolute_path) and absolute_path or nil
end

local function WatchDirectoryChange(directory)
    local watcher = DirectoryWatchers[directory]
    if not watcher then
        DirectoryWatchers[directory] = { watchfiles = {} }
        watcher = DirectoryWatchers[directory]

        watcher.handle = ffi.C.CreateFileW(
            string_to_wchar(directory),
            ffi.C.FILE_LIST_DIRECTORY,
            0x00000007, -- FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
            nil,
            0x00000003, -- OPEN_EXISTING
            0x02000000 + 0x40000000, -- FILE_FLAG_BACKUP_SEMANTICS + FILE_FLAG_OVERLAPPED
            nil
        )

        if watcher.handle == INVALID_HANDLE_VALUE then
            local err_code = ffi.C.GetLastError()
            error("Failed to open " .. directory .. " for monitoring. Error code: " .. err_code)
        end

        watcher.buffer = ffi.new("char[1024]")
        watcher.bytesReturned = ffi.new("DWORD[1]")
        watcher.overlapped = ffi.new("OVERLAPPED")
        watcher.overlapped.hEvent = ffi.C.CreateEventW(nil, true, false, nil)
    end

    return watcher
end

local function GetDirectoryWatcher(directory)
    return DirectoryWatchers[directory]
end

local function RemoveAllWatcher()
    print("Remove all directory watcher")
    for directory, watcher in pairs(DirectoryWatchers) do
        ffi.C.CloseHandle(watcher.handle)
        ffi.C.CloseHandle(watcher.overlapped.hEvent)
    end
    DirectoryWatchers = {}
end

local function WatchFileChange(file_path, fn, ...)
    local absolute_path = GetAbsolutePath(file_path)
    if not absolute_path then
        -- print("could not get: \"" ..file_path .. "\" absolute path")
        return
    end

    local directory = absolute_path:match("^(.*)\\[^\\]*$")

    local watcher = WatchDirectoryChange(directory)
    if not watcher.watchfiles[absolute_path] then
        watcher.watchfiles[absolute_path] = {}
    end

    table.insert(watcher.watchfiles[absolute_path], {fn = fn, params = {...}})
end

local function GetFileWatchers(file_path)
    local absolute_path = GetAbsolutePath(file_path)
    if not absolute_path then
        return
    end

    local directory = absolute_path:match("^(.*)\\[^\\]*$")
    local directory_watcher = GetDirectoryWatcher(directory)

    return directory_watcher and directory_watcher.watchfiles[absolute_path] or nil
end

local function PushFileChange()
    for directory, watcher in pairs(DirectoryWatchers) do
        local success = ffi.C.ReadDirectoryChangesW(
            watcher.handle,
            watcher.buffer,
            1024,
            true,
            ffi.C.FILE_NOTIFY_CHANGE_LAST_WRITE,
            watcher.bytesReturned,
            watcher.overlapped,
            nil
        )

        if success == 0 then
            local err_code = ffi.C.GetLastError()
            error("ReadDirectoryChangesW failed. Error code: " .. err_code)
        end
        local offset = 0
        repeat
            local info = ffi.cast("PFILE_NOTIFY_INFORMATION", watcher.buffer + offset)
            local file_name_length = info.FileNameLength / 2  -- WCHAR is 2 bytes
            local file_name_wide = ffi.string(info.FileName, file_name_length * ffi.sizeof("WCHAR"))

            local info_file_name = ""
            for i = 0, file_name_length - 1 do
                local char = ffi.cast("WCHAR*", file_name_wide)[i]
                info_file_name = info_file_name .. string.char(char)
            end

            local found = false
            for filepath, filewatchers in pairs(watcher.watchfiles) do
                if info_file_name == filepath:match("[^\\]+$") then
                    print(filepath .. " has changed")
                    for k, filewatcher in ipairs(filewatchers) do
                        filewatcher.fn(filewatcher, unpack(filewatcher.params))
                    end
                    found = true
                    break
                end
            end

            offset = offset + info.NextEntryOffset
        until (info.NextEntryOffset == 0) or found
        ffi.fill(watcher.buffer, 1024)

        ffi.C.ResetEvent(watcher.overlapped.hEvent)
    end
end

return {
    FileExists = FileExists,
    GetFullPathName = GetFullPathName,
    GetAbsolutePath = GetAbsolutePath,
    WatchFileChange = WatchFileChange,
    GetFileWatchers = GetFileWatchers,
    PushFileChange = PushFileChange,
    WatchDirectoryChange = WatchDirectoryChange,
    GetDirectoryWatcher = GetDirectoryWatcher,
    RemoveAllWatcher = RemoveAllWatcher,
}
