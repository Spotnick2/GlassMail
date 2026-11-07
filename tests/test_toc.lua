-- The manifest, the pinned build and the embedded material.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Interface 16001, the version token, every listed .lua file exists and every
-- line is listed once (the library's XML line too).
Kit.checkToc(TOC)
local toc = io.open(TOC):read("*a")
check(toc:find("## SavedVariables: GlassMailDB", 1, true), "saved variables declared")
check(toc:find("## SavedVariablesPerCharacter: GlassMailCharDB", 1, true), "per-character saved variables declared")
-- The publishers read these from the packaged TOC: CurseForge's webhook, and
-- the `wago` job (RELEASING.md section 1). A wrong ID uploads to another project.
check(toc:find("\n## X%-Curse%-Project%-ID: 1743548\r?\n"), "the CurseForge project ID")
check(toc:find("\n## X%-Wago%-ID: b6XybbKp\r?\n"), "the Wago project ID")
-- The embedded material loads before any of our files: Glass.lua calls
-- LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
eq(tocFiles()[#tocFiles()], "GlassMail.lua", "the bootstrap loads last")

-- Two places that must agree, never derived from each other (porting guide section 0).
loadAddon()
eq(GlassMail.MEASURED_ON_BUILD, "1.60.1.70291", "MEASURED_ON_BUILD")

-- Every texture the material names ships with the library.
local root = libGlassRoot()
for size, S in pairs(GlassMail.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
-- Glass.MEDIA points into the embedded copy, where the packager puts it.
eq(GlassMail.Glass.STYLE.thinRim, true, "the clean material (LibGlass r6+): thin rims")
eq(GlassMail.Glass.STYLE.grain, 0, "  no grain")
eq(GlassMail.Glass.MEDIA, "Interface\\AddOns\\GlassMail\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")
for _, k in ipairs({ "Apply", "MEDIA", "SIZES" }) do
    check(GlassMail.Glass[k] ~= nil, "the instance has Glass." .. k)
end

done("test_toc")
