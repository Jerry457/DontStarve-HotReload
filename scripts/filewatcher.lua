local ffi = require("ffi")

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

DWORD GetLastError();

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
]]

local CP_UTF8 = 65001

local function buffer(type)
    return function(size)
        return ffi.new(type, size)
    end
end

local wcsbuf = buffer('WCHAR[?]')
local mbsbuf = buffer('char[?]')

local function string_to_wchar(s, msz, wbuf) -- string -> WCHAR[?]
    msz = msz and msz + 1 or #s + 1
    wbuf = wbuf or wcsbuf
    local wsz = ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, msz, nil, 0)
    assert(wsz > 0) -- should never happen otherwise
    local buf = wbuf(wsz)
    local sz = ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, msz, buf, wsz)
    assert(sz == wsz) -- should never happen otherwise
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

local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
local DirectoryWatchers = {}

local function GetAbsolutePath(path)
    local buffer = ffi.new("WCHAR[260]")  -- MAX_PATH is 260
    local length = ffi.C.GetFullPathNameW(string_to_wchar(path), 260, buffer, nil)
    if length == 0 then
        local err_code = ffi.C.GetLastError()
        error("Failed to get full path name. Error code: " .. err_code)
    end
    return wchar_to_string(buffer, length)
end

local function AddDirectoryWatcher(directory)
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

local function RemoveAllDirectoryWatcher()
    print("Remove all directory watcher")
    for directory, watcher in pairs(DirectoryWatchers) do
        ffi.C.CloseHandle(watcher.handle)
        ffi.C.CloseHandle(watcher.overlapped.hEvent)
    end
    DirectoryWatchers = {}
end

local function WatchFileChange(filepath, OnFileChange, ...)
    filepath = GetAbsolutePath(filepath)
    local directory = filepath:match("^(.*)\\[^\\]*$")

    local watcher = AddDirectoryWatcher(directory)
    if not watcher.watchfiles[filepath] then
        watcher.watchfiles[filepath] = {}
    end

    table.insert(watcher.watchfiles[filepath], {fn = OnFileChange, params = {...}})
end

local function PushDirectoryChange()
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
            local filename_length = info.FileNameLength / 2  -- WCHAR is 2 bytes
            local filename_wide = ffi.string(info.FileName, filename_length * ffi.sizeof("WCHAR"))

            local info_filename = ""
            for i = 0, filename_length - 1 do
                local char = ffi.cast("WCHAR*", filename_wide)[i]
                info_filename = info_filename .. string.char(char)
            end

            local found = false
            for filepath, filewatchers in pairs(watcher.watchfiles) do
                if info_filename == filepath:match("[^\\]+$") then
                    print(filepath .. " has changed")
                    for k, filewatcher in ipairs(filewatchers) do
                        filewatcher.fn(unpack(filewatcher.params))
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

local DirectoryChangeWatcher = staticScheduler:ExecutePeriodic(1, PushDirectoryChange)

local _SimReset = SimReset
function SimReset(...)
    RemoveAllDirectoryWatcher()
    return _SimReset(...)
end

return {
    GetAbsolutePath = GetAbsolutePath,
    WatchFileChange = WatchFileChange,
    AddDirectoryWatcher = AddDirectoryWatcher,
    RemoveAllDirectoryWatcher = RemoveAllDirectoryWatcher,
}
