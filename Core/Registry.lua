-- Core/Registry.lua: the player's own characters (S1, X1).
--
-- Two sources:
-- 1. Our own account-wide record, keyed by GUID: { name, realm, ruleset,
--    faction, lastPlayDay }, written for the current character on every clock tick
--    (Store.Tick: at login and every 10 minutes), aged out by expiryDays.
-- 2. AltStable, when loaded with PUBLIC_API_VERSION 1 and its `provenance`
--    feature: read live, never saved (AltStable/docs/PUBLIC-API.md). Its sheet
--    holds other players' characters too, so only the ones it proves the
--    player's own ("self", "own-account") are taken; an AltStable that can't
--    say whose a character is isn't used. Its "forget" isn't mirrored: absence
--    from GetCharacters() can't be told from "never known".
-- A character is reachable by mail when its faction tag and ruleset match the
-- current character's (session 6: the other faction fails). On Forever a
-- realm is part of its ruleset, not a world of its own (owner, 2026-11-12: mail
-- reached a character from another realm of the same ruleset); another
-- ruleset is unmeasured, so it stays out. Since the 2026-11-20 hotfix the
-- client hides the realm, so the ruleset is read from the game's rules and
-- saved per character (only the one playing can be read).

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

local KNOWN_RULESET = { Normal = true, PvP = true, RP = true, RPPvP = true, Hardcore = true }

-- The ruleset the game says the current character is on, from its rules:
-- Hardcore, RP and/or PvP, else Normal (porting guide, "The realm is hidden
-- since the 2026-11-20 server hotfix"; AltStable's LiveRuleset). nil when the
-- client can't say: the rule names aren't in the API dump, so each is checked,
-- and a query that throws or answers anything but a boolean is no reading at
-- all (reading it as "off" would make a PvP character Normal).
function Registry.LiveRuleset()
    local rules = rawget(_G, "C_GameRules")
    local enum = rawget(_G, "Enum")
    local E = type(enum) == "table" and rawget(enum, "GameRule")
    if type(rules) ~= "table" or type(rules.IsGameRuleActive) ~= "function" or type(E) ~= "table"
        or not (E.HardcoreRuleset and E.RPRuleset and E.PvPRuleset) then
        return nil
    end
    local function on(rule)
        local ok, v = pcall(rules.IsGameRuleActive, rule)
        if ok and not API.IsSecret(v) and type(v) == "boolean" then return v end
        return nil
    end
    local hc, rp, pvp = on(E.HardcoreRuleset), on(E.RPRuleset), on(E.PvPRuleset)
    if hc == nil or rp == nil or pvp == nil then return nil end
    if hc then return "Hardcore" end
    if rp and pvp then return "RPPvP" end
    if rp then return "RP" end
    if pvp then return "PvP" end
    return "Normal"
end

-- The current character as { guid, name, realm, faction, class, ruleset };
-- any field nil when the client won't say. class is the file token
-- ("PRIEST"). The realm is "" since the 2026-11-20 hotfix, so the ruleset
-- comes from the game's rules, else the realm's name, else what this
-- character's own record kept.
function Registry.Current()
    local me = { guid = Registry.CurrentGUID(), name = API.PlayerFullName(), realm = str(GetRealmName()),
        faction = str((UnitFactionGroup("player"))), class = str(select(2, UnitClass("player"))) }
    local ruleset = Registry.LiveRuleset() or Registry.RulesetOf(me.realm)
    if not KNOWN_RULESET[ruleset] then
        local old = me.guid and Store.Ready() and Store.Chars()[me.guid]
        ruleset = old and Registry.RulesetOf(old)
    end
    me.ruleset = KNOWN_RULESET[ruleset] and ruleset or nil
    return me
end

-- Store.Tick's hook: the current character is played today.
function Registry.Touch()
    local me = Registry.Current()
    if not me.guid then return end
    local old = Store.Chars()[me.guid]
    local name = me.name or (old and old.name)
    if not name then return end
    Store.SetChar(me.guid, { name = name, realm = me.realm or (old and old.realm), ruleset = me.ruleset,
        faction = me.faction or (old and old.faction), class = me.class or (old and old.class),
        lastPlayDay = Store.PlayDay(), lastTo = old and old.lastTo })
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

-- Every own character known, as fresh copies: { guid, name, realm, ruleset,
-- faction, hidden, current, provenance }. AltStable's proven own characters
-- when it is loaded, else ours. Nothing from AltStable is saved.
function Registry.Characters()
    local current = Registry.CurrentGUID()
    local out = {}
    local A = altStable()
    if A then
        local ok, list = pcall(A.GetCharacters)
        if ok and type(list) == "table" then
            local saved = Store.Ready() and Store.Chars() or {}
            for _, c in ipairs(list) do
                if type(c) == "table" and str(c.guid) and str(c.name) and OWN[str(c.provenance) or ""] then
                    -- ruleset: AltStable's `ruleset` feature (#405), its own
                    -- client's reading; RulesetOf checks the value. An AltStable
                    -- without it (v1.10.0) and a realm hidden since the hotfix
                    -- say nothing, so our own record of that GUID does (#75).
                    local e = { guid = c.guid, name = c.name, realm = str(c.realm), ruleset = str(c.ruleset),
                        faction = str(c.faction),
                        class = str(c.class), hidden = c.hidden == true, current = c.guid == current,
                        provenance = str(c.provenance) }
                    local mine = saved[c.guid]
                    if Registry.RulesetOf(e) == "Unknown" and type(mine) == "table" then
                        local r = Registry.RulesetOf(mine)
                        e.ruleset = r ~= "Unknown" and r or nil
                    end
                    out[#out + 1] = e
                end
            end
            return out, "altstable"
        end
        API.Fail("altstable", ok and "GetCharacters returned no list" or list)
    end
    for guid, c in pairs(Store.Ready() and Store.Chars() or {}) do
        out[#out + 1] = { guid = guid, name = c.name, realm = c.realm, ruleset = c.ruleset, faction = c.faction,
            class = c.class,
            hidden = false, current = guid == current }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out, "own"
end

-- A character's ruleset ("Normal", "PvP", "RP", "RPPvP", "Hardcore"), or
-- "Unknown", which matches nothing. `realm` is a character ({ ruleset, realm })
-- or a realm name. A character's own client's reading of the game's rules
-- (`ruleset`) wins; else its realm's name (AltStable's rule, AltStable/Config.lua
-- RulesetOf): whole words, so an "rp" inside another word isn't RP, and RP and
-- PvP together are RP-PvP. A character first seen after the 2026-11-20 hotfix
-- has no realm name, only its ruleset.
function Registry.RulesetOf(realm)
    if type(realm) == "table" then
        if KNOWN_RULESET[realm.ruleset] then return realm.ruleset end
        realm = realm.realm
    end
    if type(realm) ~= "string" or API.IsSecret(realm) or not realm:find("%S") then return "Unknown" end
    local words = " " .. (realm:lower():gsub("[^%w]", " ")) .. " "
    if words:find(" hardcore ", 1, true) or words:find(" hc ", 1, true) then return "Hardcore" end
    if words:find(" rppvp ", 1, true) then return "RPPvP" end
    local pvp = words:find("pvp", 1, true) ~= nil
    if words:find(" rp ", 1, true) or words:find(" roleplay ", 1, true) then
        return pvp and "RPPvP" or "RP"
    end
    if pvp then return "PvP" end
    return "Normal"
end

-- True when mail from the current character can reach c: same faction, same
-- ruleset (any of its realms), not the current character.
function Registry.Reachable(c)
    local me = Registry.Current()
    local ruleset = Registry.RulesetOf(me)
    return not c.current and me.faction ~= nil and c.faction == me.faction and ruleset ~= "Unknown"
        and Registry.RulesetOf(c) == ruleset
end
