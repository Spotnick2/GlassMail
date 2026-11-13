-- harness.lua: the addon loader and GlassMail's test helpers. dofile it after
-- wow_stubs.lua. check / eq / done are WowTestKit's (tests/kit.lua).
-- GlassChat's harness, trimmed: no plugins; two embedded libraries.

TOC = "GlassMail.toc"

-- Every file line of the TOC, in load order (our .lua files and the embedded
-- library's .xml).
function tocLines() return Kit.tocLines(TOC) end

-- Lua files listed in the TOC, in load order.
function tocFiles() return Kit.tocFiles(TOC) end

-- The embedded libraries come from checkouts, not from Libs\ (gitignored,
-- filled by the packager): $LIBGLASS, else ..\LibGlass; $LIBMAILBOX, else ..\LibMailbox. No checkout fails the
-- run loudly; a silently skipped library would test nothing.
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
LIBMAILBOX_XML = "Libs\\LibMailbox-1.0\\LibMailbox-1.0.xml"
LIBS = {
    [LIBGLASS_XML] = { env = "LIBGLASS", dir = "../LibGlass", xml = "LibGlass-1.0.xml" },
    [LIBMAILBOX_XML] = { env = "LIBMAILBOX", dir = "../LibMailbox", xml = "LibMailbox-1.0.xml" },
}

function libRoot(line)
    local L = LIBS[line]
    local root = (os.getenv(L.env) or L.dir):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/" .. L.xml, "rb")
    if not f then
        error(L.xml .. " checkout not found at " .. root .. ": clone it there or set " .. L.env, 0)
    end
    f:close()
    return root
end
function libGlassRoot() return libRoot(LIBGLASS_XML) end

-- The Lua files a library's XML loads, as paths, in order.
function libScripts(line)
    local L, root = LIBS[line], libRoot(line)
    local f = assert(io.open(root .. "/" .. L.xml, "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error(L.xml .. " at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error(L.xml .. " at " .. root .. " lists no Script files", 0) end
    return files
end

-- Load the addon the way the client does: every TOC file with (name, ns), the
-- library's XML expanded in place, then ADDON_LOADED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD (initial login).
function loadAddon(opts)
    opts = opts or {}
    local ns = {}
    for _, line in ipairs(tocLines()) do
        local files = { line }
        if LIBS[line] then
            files = libScripts(line)
        elseif not line:match("%.lua$") then
            error("the harness can't load TOC line " .. line, 0)
        end
        for _, file in ipairs(files) do
            assert(loadfile((file:gsub("\\", "/"))))("GlassMail", ns)
        end
    end
    if opts.db then GlassMailDB = opts.db end
    if opts.charDB then GlassMailCharDB = opts.charDB end
    WoW.fire("ADDON_LOADED", "GlassMail")
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", opts.initialLogin ~= false, false)
    WoW.tick()
    return GlassMail
end

-- ForeverProbe, the probe host (..\ForeverProbe, or $FOREVERPROBE), loaded
-- into these stubs the way the client does: every TOC file with (name, ns),
-- then its ADDON_LOADED. GlassChat's loader. It is private and local, so CI
-- sets FOREVERPROBE_OPTIONAL=1 and a probe test exits as SKIPPED there;
-- locally a missing checkout is an error, never a silent skip.
function loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
end

-- Chat lines printed since the last call.
local seenChat = 0
function newChat()
    local lines = {}
    for i = seenChat + 1, #WoW.chat do lines[#lines + 1] = WoW.chat[i] end
    seenChat = #WoW.chat
    return lines
end

function chatHas(pattern)
    for _, line in ipairs(WoW.chat) do
        if line:find(pattern) then return true end
    end
    return false
end

-- LibMailbox.lua's source from its checkout, for tests that load another
-- copy of it (a failed upgrade).
function readLibMailbox()
    local f = assert(io.open(libRoot(LIBMAILBOX_XML) .. "/LibMailbox.lua", "rb"))
    local s = f:read("*a")
    f:close()
    return s
end
