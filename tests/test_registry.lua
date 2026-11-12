-- Core/Registry.lua: the own-character record, and AltStable read live.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.today = "2026-11-06"
local GM = loadAddon()
local Store, Registry = GM.Store, GM.Registry
local db = GlassMailDB
local ME = WoW.playerGUID

-- Written at login.
local me = db.chars[ME]
check(me ~= nil, "the current character is written at login")
eq(me.name, "Karuzo Morphisto", "  with its full name")
eq(me.realm, "Doomhowl", "  its realm")
eq(me.faction, "Horde", "  its faction tag")
eq(me.lastPlayDay, 1, "  played today")

-- A tick over midnight refreshes it; then a character switch.
WoW.today = "2026-11-07"
WoW.advance(600)
eq(db.chars[ME].lastPlayDay, 2, "a tick over midnight refreshes the current character's play day")
WoW.playerGUID, WoW.playerName = "Player-1-BBB", "Kaleid"
Store.Tick()
eq(db.chars["Player-1-BBB"].lastPlayDay, 2, "after a switch the new character is played today")
eq(db.chars[ME].lastPlayDay, 2, "  the first ages from the later day")

-- Aged out by play days, never the current one.
GM.Settings.SetExpiryDays(7)
db.playDay = 9   -- the current (BBB) and AAA both last played on day 2: 7 days old
Store.Prune()
eq(db.chars[ME], nil, "a character expiryDays play days unplayed is forgotten")
check(db.chars["Player-1-BBB"] ~= nil, "  never the current one")
GM.Settings.SetExpiryDays(30)
WoW.playerGUID, WoW.playerName = ME, nil
Store.Tick()

-- Characters(): ours without AltStable.
Store.SetChar("Player-1-CCC", { name = "Alt Other", realm = "Doomhowl", faction = "Alliance", lastPlayDay = 9 })
local list, source = Registry.Characters()
eq(source, "own", "without AltStable, our own record")
local byGuid = {}
for _, c in ipairs(list) do byGuid[c.guid] = c end
check(byGuid[ME] and byGuid[ME].current, "  the current character is flagged")
eq(byGuid["Player-1-BBB"] and byGuid["Player-1-BBB"].name, "Kaleid Morphisto", "  the other is listed")

-- Reachability: same ruleset and faction, not the current one.
check(Registry.Reachable(byGuid["Player-1-BBB"]), "same realm and faction: reachable")
check(not Registry.Reachable(byGuid[ME]), "the current character isn't a recipient")
check(not Registry.Reachable(byGuid["Player-1-CCC"]), "the other faction isn't reachable")
check(Registry.Reachable({ name = "X Y", realm = "Elsewhere", faction = "Horde" }),
    "another realm of the same ruleset is reachable (a realm is part of its ruleset)")
check(not Registry.Reachable({ name = "X Y", realm = "Elsewhere PvP", faction = "Horde" }), "another ruleset isn't")
check(not Registry.Reachable({ name = "X Y", faction = "Horde" }), "nor one with no realm known")
local realm = WoW.realm
WoW.realm = nil
check(not Registry.Reachable(byGuid["Player-1-BBB"]), "  nor anyone while this character's realm is unknown")
check(not Registry.Reachable({ name = "X Y", faction = "Horde" }), "  not even one whose realm is unknown too")
WoW.realm = realm

-- Rulesets, from the realm's name (AltStable's rule).
local R = Registry.RulesetOf
eq(R("CAMWOW US2 Realm 1 PvE"), "Normal", "a PvE realm is Normal")
eq(R("CAMWOW US2 Realm 7 PvE"), R("CAMWOW US2 Realm 1 PvE"), "  realms 1 and 7: the same ruleset")
eq(R("Classic Beta PvP 2"), "PvP", "a PvP realm, numbered")
eq(R("Some RP Realm"), "RP", "RP, as a word")
eq(R("Sharp Realm"), "Normal", "  not inside another word")
eq(R("Roleplay PvP"), "RPPvP", "RP and PvP together: RP-PvP")
eq(R("RPPvP One"), "RPPvP", "  written as one word")
eq(R("Hardcore Realm"), "Hardcore", "Hardcore")
eq(R("HC One"), "Hardcore", "  HC as a word")
eq(R(""), "Unknown", "an empty name is Unknown")
eq(R(nil), "Unknown", "  so is none")
eq(R(WoW.Secret("realm")), "Unknown", "  and a secret one")

-- AltStable with an unknown API version: ignored.
local calls = 0
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 2, GetCharacters = function() calls = calls + 1; return {} end })
local _, src = Registry.Characters()
eq(src, "own", "an AltStable of another API version is ignored")
eq(calls, 0, "  and never called")

-- AltStable v1 without the provenance feature: it can't say whose a
-- character is, so it isn't used.
calls = 0
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, GetCharacters = function()
    calls = calls + 1
    return { { guid = "Player-9-FRI", name = "A Friend", realm = "Doomhowl", faction = "Horde" } }
end })
_, src = Registry.Characters()
eq(src, "own", "an AltStable v1 without provenance is ignored")
eq(calls, 0, "  and never called")

-- AltStable v1 with provenance: its own characters, live, nothing saved.
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true },
    GetCharacters = function()
    return {
        { guid = "Player-2-ZZZ", name = "Bank Alt", realm = "Doomhowl", faction = "Horde", hidden = true,
            current = false, provenance = "own-account" },
        { guid = "Player-9-FRI", name = "A Friend", realm = "Doomhowl", faction = "Horde", hidden = false,
            current = false, provenance = "third-party" },
        { guid = "Player-9-NOP", name = "No Provenance", realm = "Doomhowl", faction = "Horde" },
        { guid = ME, name = "Karuzo Morphisto", realm = "Doomhowl", faction = "Horde", hidden = false, current = true,
            provenance = "self" },
        { guid = WoW.Secret("guid"), name = "Secret Guid", provenance = "self" },
    }
end })
list, src = Registry.Characters()
eq(src, "altstable", "with AltStable v1 loaded, its list")
eq(#list, 2, "  a third-party character, one with no provenance and a secret GUID are skipped")
for _, c in ipairs(list) do
    check(c.name ~= "A Friend", "  a friend's same-realm character is never one of ours")
end
eq(list[1].name, "Bank Alt", "  in its order")
check(list[1].hidden, "  hidden is passed on")
eq(list[1].provenance, "own-account", "  and provenance")
check(list[2].current, "  the current character is flagged")
eq(db.chars["Player-2-ZZZ"], nil, "nothing from AltStable is saved")

-- An AltStable that throws: our list, and the failure recorded.
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true },
    GetCharacters = function() error("boom") end })
_, src = Registry.Characters()
eq(src, "own", "an AltStable that throws falls back to our record")
check(GM.failures.altstable ~= nil, "  and the failure is recorded")
rawset(_G, "AltStable", nil)

done("test_registry")
