-- Core/Names.lua: how a mail address is compared and shown.
--
-- Forever names are "First Surname" with no realm (FOREVER-PROBE session 6:
-- the guild roster carries no suffix). A "-Realm" suffix, if one ever comes,
-- is kept as part of the key: other realms are unmeasured, so such a name is
-- never merged with a plain one. A secret name is never keyed or stored.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Names = {}
GM.Names = Names

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The name as the player would type it (trimmed), or nil: secret, not a
-- string, or blank.
function Names.Display(name)
    if API.IsSecret(name) or type(name) ~= "string" then return nil end
    local s = trim(name)
    if s == "" then return nil end
    return s
end

-- The comparison key: trimmed, inner spaces collapsed, lower-cased; nil as
-- for Display.
function Names.Key(name)
    local s = Names.Display(name)
    if not s then return nil end
    return (s:gsub("%s+", " ")):lower()
end
