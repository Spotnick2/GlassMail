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

-- Reachability: same realm and faction, not the current one.
check(Registry.Reachable(byGuid["Player-1-BBB"]), "same realm and faction: reachable")
check(not Registry.Reachable(byGuid[ME]), "the current character isn't a recipient")
check(not Registry.Reachable(byGuid["Player-1-CCC"]), "the other faction isn't reachable")
check(not Registry.Reachable({ name = "X Y", realm = "Elsewhere", faction = "Horde" }), "nor another realm")
check(not Registry.Reachable({ name = "X Y", faction = "Horde" }), "nor one with no realm known")

-- AltStable with an unknown API version: ignored.
local calls = 0
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 2, GetCharacters = function() calls = calls + 1; return {} end })
local _, src = Registry.Characters()
eq(src, "own", "an AltStable of another API version is ignored")
eq(calls, 0, "  and never called")

-- AltStable v1: its list, live, nothing saved.
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, GetCharacters = function()
    return {
        { guid = "Player-2-ZZZ", name = "Bank Alt", realm = "Doomhowl", faction = "Horde", hidden = true,
            current = false, provenance = "own-account" },
        { guid = ME, name = "Karuzo Morphisto", realm = "Doomhowl", faction = "Horde", hidden = false, current = true },
        { guid = WoW.Secret("guid"), name = "Secret Guid" },
    }
end })
list, src = Registry.Characters()
eq(src, "altstable", "with AltStable v1 loaded, its list")
eq(#list, 2, "  an entry with a secret GUID is skipped")
eq(list[1].name, "Bank Alt", "  in its order")
check(list[1].hidden, "  hidden is passed on")
eq(list[1].provenance, "own-account", "  and provenance")
check(list[2].current, "  the current character is flagged")
eq(db.chars["Player-2-ZZZ"], nil, "nothing from AltStable is saved")

-- An AltStable that throws: our list, and the failure recorded.
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, GetCharacters = function() error("boom") end })
_, src = Registry.Characters()
eq(src, "own", "an AltStable that throws falls back to our record")
check(GM.failures.altstable ~= nil, "  and the failure is recorded")
rawset(_G, "AltStable", nil)

done("test_registry")
