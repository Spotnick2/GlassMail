-- Core/Registry.lua: the player's own characters (S1, X1).
--
-- Two sources:
-- 1. Our own account-wide record, keyed by GUID: { name, realm, faction,
--    lastPlayDay }, written for the current character on every clock tick
--    (Store.Tick: at login and every 10 minutes), aged out by expiryDays.
-- 2. AltStable, when loaded with PUBLIC_API_VERSION 1 and its `provenance`
--    feature: read live, never saved (AltStable/docs/PUBLIC-API.md). Its sheet
--    holds other players' characters too, so only the ones it proves the
--    player's own ("self", "own-account") are taken; an AltStable that can't
--    say whose a character is isn't used. Its "forget" isn't mirrored: absence
--    from GetCharacters() can't be told from "never known".
-- A character is reachable by mail when its faction tag and realm match the
-- current character's (session 6: the other faction fails; other realms and
-- rulesets are unmeasured, so they stay out).

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Store = GM.Store
local Registry = {}
GM.Registry = Registry

local function str(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

function Registry.CurrentGUID() return str(UnitGUID("player")) end

-- The current character as { guid, name, realm, faction }; any field nil
-- when the client won't say.
function Registry.Current()
    return { guid = Registry.CurrentGUID(), name = API.PlayerFullName(), realm = str(GetRealmName()),
        faction = str((UnitFactionGroup("player"))) }
end

-- Store.Tick's hook: the current character is played today.
function Registry.Touch()
    local me = Registry.Current()
    if not me.guid then return end
    local old = Store.Chars()[me.guid]
    local name = me.name or (old and old.name)
    if not name then return end
    Store.SetChar(me.guid, { name = name, realm = me.realm or (old and old.realm),
        faction = me.faction or (old and old.faction), lastPlayDay = Store.PlayDay(),
        lastTo = old and old.lastTo })
end

-- AltStable's public API, when it is the version we know and says whose each
-- character is; else nil.
local function altStable()
    local A = rawget(_G, "AltStable")
    if type(A) ~= "table" or A.PUBLIC_API_VERSION ~= 1 or type(A.GetCharacters) ~= "function" then return nil end
    local F = A.PUBLIC_API_FEATURES
    if type(F) ~= "table" or F.provenance ~= true then return nil end
    return A
end

local OWN = { self = true, ["own-account"] = true }

-- Every own character known, as fresh copies: { guid, name, realm, faction,
-- hidden, current, provenance }. AltStable's proven own characters when it is
-- loaded, else ours. Nothing from AltStable is saved.
function Registry.Characters()
    local current = Registry.CurrentGUID()
    local out = {}
    local A = altStable()
    if A then
        local ok, list = pcall(A.GetCharacters)
        if ok and type(list) == "table" then
            for _, c in ipairs(list) do
                if type(c) == "table" and str(c.guid) and str(c.name) and OWN[str(c.provenance) or ""] then
                    out[#out + 1] = { guid = c.guid, name = c.name, realm = str(c.realm), faction = str(c.faction),
                        hidden = c.hidden == true, current = c.guid == current, provenance = str(c.provenance) }
                end
            end
            return out, "altstable"
        end
        API.Fail("altstable", ok and "GetCharacters returned no list" or list)
    end
    for guid, c in pairs(Store.Ready() and Store.Chars() or {}) do
        out[#out + 1] = { guid = guid, name = c.name, realm = c.realm, faction = c.faction, hidden = false,
            current = guid == current }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out, "own"
end

-- True when mail from the current character can reach c.
function Registry.Reachable(c)
    local me = Registry.Current()
    return not c.current and me.realm ~= nil and me.faction ~= nil and c.realm == me.realm
        and c.faction == me.faction
end
