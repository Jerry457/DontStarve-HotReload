GLOBAL.setfenv(1, GLOBAL)

if not IsWin32() then
    print("Hot Reload only support window")
    return
end

global("HotReloading")

require("hotreload/update_module")
require("hotreload/update_module")  -- call again for watch

require("hotreload/update_modmodule")
require("hotreload/update_translate")
require("hotreload/update_prefab")
