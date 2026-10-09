-- The manifest, the pinned build, the event fixture and the embedded material.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open(TOC):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassMailboxDB", 1, true), "saved variables declared")
check(toc:find("## SavedVariablesPerCharacter: GlassMailboxCharDB", 1, true), "per-character saved variables declared")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
-- The embedded material loads before any of our files: Glass.lua calls
-- LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
eq(tocFiles()[#tocFiles()], "GlassMailbox.lua", "the bootstrap loads last")
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

-- Two places that must agree, never derived from each other (porting guide section 0).
loadAddon()
eq(GlassMailbox.MEASURED_ON_BUILD, "1.60.1.70291", "MEASURED_ON_BUILD")

-- The checked-in event list matches the dump, when the dump is here.
if WoW.dumpAvailable then
    local fixture = {}
    for line in io.lines("tests/events-70291.txt") do
        local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
        if name then fixture[name] = true end
    end
    local missing, extra = 0, 0
    for e in pairs(WoW.KNOWN_EVENTS) do if not fixture[e] then missing = missing + 1 end end
    for e in pairs(fixture) do if not WoW.KNOWN_EVENTS[e] then extra = extra + 1 end end
    eq(missing + extra, 0, "tests/events-70291.txt matches the dump (regenerate it)")
end

-- Every texture the material names ships with the library.
local root = libGlassRoot()
for size, S in pairs(GlassMailbox.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
-- Glass.MEDIA points into the embedded copy, where the packager puts it.
eq(GlassMailbox.Glass.MEDIA, "Interface\\AddOns\\GlassMailbox\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")
for _, k in ipairs({ "Apply", "MEDIA", "SIZES" }) do
    check(GlassMailbox.Glass[k] ~= nil, "the instance has Glass." .. k)
end

done("test_toc")
