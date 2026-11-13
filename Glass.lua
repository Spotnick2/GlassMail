-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Material changes are LibGlass PRs, not
-- edits here.
--
-- An instance, not the library itself: the tuning and the font registry are
-- GlassMail's own and never touch another glass addon's surfaces. Call
-- sites keep the dot-call shape (Glass.Apply, Glass.Font, Glass.MEDIA, ...).
--
-- Built once, when we know which material (docs/PLAN.md, "Following Glass
-- UI's suite"): at our ADDON_LOADED, after the settings, Suite.Start asks
-- Glass UI and calls Build with its preset, or Pearl, our own (owner,
-- 2026-11-12). GlassMail.Glass is a stable table that forwards to the
-- instance, so the files that captured it at load keep working; nothing
-- reads it before the build (every surface is built at PLAYER_LOGIN or
-- later). The body (tint, wash) is never pushed into STYLE: Skin paints it on
-- each surface after building, against the material's own wash (BaseWash).

GlassMail = GlassMail or {}
local GM = GlassMail

local instance
local build        -- { wanted, preset, failed, minor }
local Glass = setmetatable({}, { __index = function(_, k)
    if not instance then error("GlassMail.Glass was used before it was built", 2) end
    return instance[k]
end })
GM.Glass = Glass

-- Build the instance: `wanted` (a LibGlass preset name), else clean, else the
-- library's defaults. Once per session; later calls return the first result.
-- { wanted, preset = what was built ("classic" for the defaults), failed =
-- why `wanted` wasn't built ("library-too-old" for Pearl under MINOR 11, else
-- "build-failed"), minor = the winning LibGlass's MINOR at the attempt }.
function GM.BuildGlass(wanted)
    if build then return build end
    local lib, minor = LibStub("LibGlass-1.0")
    build = { wanted = wanted, minor = minor }
    local tries, seen = {}, {}
    for _, name in ipairs({ wanted, "clean" }) do
        if type(name) == "string" and not seen[name] then
            seen[name] = true
            tries[#tries + 1] = name
        end
    end
    tries[#tries + 1] = false   -- the defaults: no preset (an older copy has no "classic" name)
    for _, name in ipairs(tries) do
        local ok, inst = pcall(lib.New, lib, name and { preset = name } or nil)
        if ok then
            instance, build.preset = inst, name or "classic"
            break
        end
        if name == wanted then
            build.failed = (wanted == "pearl" and type(minor) == "number" and minor < 11)
                and "library-too-old" or "build-failed"
        end
    end
    if not instance then error("no glass material could be built", 0) end
    return build
end

function GM.GlassBuild() return build end
function GM.GlassBuilt() return instance ~= nil end

-- The material's own wash, as New made it: every body's wash is a factor of it.
function GM.BaseWash() return instance and instance.STYLE.wash or 0 end
