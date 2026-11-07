-- Core/Store.lua: the saved memory's shape, the play-day clock, expiry, and
-- the two settings that drive it (PLAN.md, "The core PR in detail").
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.today = "2026-11-06"
local GM = loadAddon()
local Store = GM.Store

-- Load a saved table the way a login does.
local function reload(saved)
    GlassMailDB = saved
    GM.db = GM._test.ensureDefaults()
    Store.loaded = false
    Store.Load()
    return GlassMailDB
end

local function sentRec(over)
    local r = { kind = "send", day = 1, at = 1000, from = "Player-1-AAA", to = "Kaleid Sumner", state = "sent",
        subject = "ore", money = 0, cod = 0, items = { { id = 2589, count = 5 } } }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end
local function trashRec(over)
    local r = { at = 1000, from = "Player-1-AAA", expires = WoW.clock + 86400, sender = "Kaleid Sumner" }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end

-- A fresh DB ---------------------------------------------------------------
local db = GlassMailDB
eq(db.version, 1, "a fresh DB gets the version")
eq(db.playDay, 1, "the play-day counter starts at 1")
eq(db.lastDate, "2026-11-06", "  on today's date")
eq(type(db.sent), "table", "the subtrees exist")
eq(#db.sent + #db.trash, 0, "  empty")

-- v0.1.0's settings-only DB keeps every setting ---------------------------
db = reload({ skin = "smoked", keepFree = 5, openAH = false, tradeBlock = false })
eq(GM.db.skin, "smoked", "v0.1.0's look survives")
eq(GM.db.keepFree, 5, "  and its Open All reserve")
eq(GM.db.openAH, false, "  and its filters")
eq(GM.db.tradeBlock, false, "  and its comforts")
eq(db.version, 1, "  and the memory starts at version 1")

-- An unknown version drops the subtrees, never the settings ----------------
db = reload({ version = 2, skin = "smoked", playDay = 9, lastDate = "2026-11-01", sent = { sentRec() },
    trash = { trashRec() } })
eq(#db.sent, 0, "an unknown version drops Sent")
eq(#db.trash, 0, "  and Trash")
eq(db.playDay, 1, "  and restarts the clock")
eq(GM.db.skin, "smoked", "  but keeps the settings")

-- One malformed subtree is dropped alone ------------------------------------
local good = { version = 1, playDay = 5, lastDate = "2026-11-06" }
local function with(fields)
    local t = {}
    for k, v in pairs(good) do t[k] = v end
    for k, v in pairs(fields) do t[k] = v end
    return t
end
db = reload(with({ sent = { sentRec(), { kind = "send", day = 1 } }, trash = { trashRec() } }))
eq(#db.sent, 0, "a record missing a required field drops its subtree")
eq(#db.trash, 1, "  and only that one")
eq(db.playDay, 5, "  the clock is kept")
db = reload(with({ sent = { sentRec({ state = "failed" }) } }))
eq(#db.sent, 0, "a state the plan doesn't have is invalid")
db = reload(with({ sent = { [1] = sentRec(), [3] = sentRec() } }))
eq(#db.sent, 0, "a list with a hole is unreadable")
db = reload(with({ chars = { ["Player-1-BBB"] = { name = "Kaleid Sumner" } } }))
eq(next(db.chars), nil, "a character without lastPlayDay is invalid")
db = reload(with({ sent = { sentRec({ subject = false }), sentRec({ subject = nil, items = nil }) } }))
eq(#db.sent, 2, "records with a bad or missing optional field are kept")
eq(db.sent[1].subject, nil, "  the bad field is left out")
eq(db.sent[1].to, "Kaleid Sumner", "  the rest is there")
db = reload(with({ sent = { sentRec({ extra = "x" }) } }))
eq(db.sent[1].extra, nil, "a field the shape doesn't list isn't kept")

-- Insertion: secrets, caps ---------------------------------------------------
db = reload(with({}))
check(Store.AddSent(sentRec({ subject = WoW.Secret("subject"), money = WoW.Secret("money") })),
    "a record with a secret optional field is saved")
eq(db.sent[1].subject, nil, "  without the secret subject")
eq(db.sent[1].money, nil, "  or the secret money")
check(not Store.AddSent(sentRec({ to = WoW.Secret("to") })), "a secret recipient drops the record")
check(not Store.AddSent(sentRec({ from = WoW.Secret("guid") })), "  and so does a secret GUID")
eq(#db.sent, 1, "  neither was saved")
check(not Store.AddSent(sentRec({ items = { { id = WoW.Secret("id"), count = 1 } } })) == false,
    "a secret inside items only drops the items")
eq(db.sent[2].items, nil, "  the field is left out")

local SENT_MAX, TRASH_MAX = Store.SENT_MAX, Store.TRASH_MAX
Store.SENT_MAX, Store.TRASH_MAX = 3, 2
db = reload(with({}))
for i = 1, 4 do Store.AddSent(sentRec({ at = i })) end
eq(#db.sent, 3, "Sent is capped on insertion")
eq(db.sent[1].at, 2, "  the oldest goes")
for i = 1, 3 do Store.AddTrash(trashRec({ at = i })) end
eq(#db.trash, 2, "Trash is capped on insertion")
eq(db.trash[1].at, 2, "  the oldest goes")
Store.SENT_MAX, Store.TRASH_MAX = SENT_MAX, TRASH_MAX

-- The clock ---------------------------------------------------------------------
db = reload(with({ playDay = 5, lastDate = "2026-11-06" }))
Store.Tick()
Store.Tick()
eq(db.playDay, 5, "the same date counts once")
WoW.today = "2026-11-07"
WoW.advance(600)   -- the 10-minute ticker, over midnight within one session
eq(db.playDay, 6, "midnight in a session counts the new date (the ticker)")
eq(db.lastDate, "2026-11-07", "  and moves lastDate")
WoW.today = "2026-11-08"
Store.Tick()
eq(db.playDay, 7, "the next date counts")
WoW.today = "2026-11-02"
Store.Tick()
eq(db.playDay, 7, "a clock set back counts nothing")
eq(db.lastDate, "2026-11-08", "  lastDate is a high-water mark")
WoW.today = "2026-11-08"
Store.Tick()
eq(db.playDay, 7, "back to the original date: not counted again")
WoW.today = "2026-11-09"
Store.Tick()
eq(db.playDay, 8, "the date after counts once")

-- An invalid header restarts the clock and drops what it stamped ---------------
WoW.today = "2026-11-06"
for _, bad in ipairs({ { playDay = "x" }, { playDay = 0 }, { playDay = 2.5 }, { lastDate = "11/06/2026" } }) do
    local t = with({ chars = { ["Player-1-BBB"] = { name = "Kaleid Sumner", lastPlayDay = 200 } },
        recents = { ["kaleid sumner"] = { name = "Kaleid Sumner", day = 200 } },
        sent = { sentRec({ day = 200 }) }, trash = { trashRec() } })
    for k, v in pairs(bad) do t[k] = v end
    db = reload(t)
    local which = tostring(bad.playDay or bad.lastDate)
    eq(db.playDay, 1, "an invalid header (" .. which .. ") restarts the counter")
    eq(db.lastDate, "2026-11-06", "  on today")
    eq(next(db.chars), nil, "  chars go (their days belong to the lost counter)")
    eq(next(db.recents), nil, "  recents go")
    eq(#db.sent, 0, "  Sent goes")
    eq(#db.trash, 1, "  Trash ages in real time and stays")
end

-- Pruning ------------------------------------------------------------------------
db = reload(with({ playDay = 40,
    chars = { ["Player-1-BBB"] = { name = "Old Alt", lastPlayDay = 10 }, ["Player-1-CCC"] = { name = "New Alt", lastPlayDay = 11 },
        [WoW.playerGUID] = { name = "Karuzo Morphisto", lastPlayDay = 1 } },
    recents = { ["old"] = { name = "Old", day = 10 }, ["new"] = { name = "New", day = 11 } },
    sent = { sentRec({ day = 10 }), sentRec({ day = 11 }) },
    trash = { trashRec({ expires = WoW.clock - 1 }), trashRec({ expires = WoW.clock + 60 }) } }))
Store.Prune()
eq(db.chars["Player-1-BBB"], nil, "a character 30 play days unplayed goes (expiryDays 30)")
check(db.chars["Player-1-CCC"] ~= nil, "  one 29 days old stays")
check(db.chars[WoW.playerGUID] ~= nil, "  the current character never goes")
eq(db.recents.old, nil, "a recent recipient 30 play days old goes")
check(db.recents.new ~= nil, "  a younger one stays")
eq(#db.sent, 1, "a Sent record 30 play days old goes")
eq(db.sent[1].day, 11, "  the younger stays")
eq(#db.trash, 1, "a Trash entry past its mail's expiry goes (real time)")

db = reload(with({}))
for i = 1, 12 do Store.Recents()["n" .. string.format("%02d", i)] = { name = "N" .. i, day = i } end
GM.Settings.SetRecentMax(10)
local n = 0
for _ in pairs(db.recents) do n = n + 1 end
eq(n, 10, "recentMax keeps that many recent recipients")
eq(db.recents.n01, nil, "  the oldest go")
eq(db.recents.n02, nil, "  both of them")
check(db.recents.n12 ~= nil, "  the newest stays")
check(Store.AddRecent("  Kaleid Sumner "), "a recipient is added")
eq(db.recents["kaleid sumner"].name, "Kaleid Sumner", "  keyed by Names.Key, shown trimmed")
eq(db.recents["kaleid sumner"].day, db.playDay, "  stamped today")
check(not Store.AddRecent(WoW.Secret("name")), "a secret recipient isn't added")

-- The settings ----------------------------------------------------------------------
db = reload({ expiryDays = "30", recentMax = 25 })
eq(rawget(db, "expiryDays"), nil, "a saved expiryDays that isn't a choice is removed (a string)")
eq(rawget(db, "recentMax"), nil, "  and a recentMax that isn't one (25)")
eq(GM.db.expiryDays, 30, "  the defaults apply")
eq(GM.db.recentMax, 20, "  both")
db = reload({ expiryDays = 45 })
eq(rawget(db, "expiryDays"), nil, "an unoffered number of days is removed")
db = reload({ expiryDays = 60, recentMax = 50 })
eq(GM.db.expiryDays, 60, "a valid non-default expiry is kept")
eq(GM.db.recentMax, 50, "  and a valid recentMax")
check(not GM.Settings.SetExpiryDays(45), "the setter refuses an unoffered value")
eq(GM.db.expiryDays, 60, "  and leaves the setting")
db = reload(with({ playDay = 20, sent = { sentRec({ day = 10 }) } }))
check(GM.Settings.SetExpiryDays(7), "the setter takes an offered value")
eq(#db.sent, 0, "  and prunes at once")

-- Snapshots (the window PR) ---------------------------------------------------------
local function snapMail(over)
    local m = { expires = WoW.clock + 86400, type = "player", sender = "Kaleid Sumner", subject = "ore",
        money = 0, cod = 0, wasReturned = false, items = { { id = 2589, count = 5 } } }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end
local function snapRec(over)
    local s = { at = 1000, loaded = 1, total = 1, complete = true, mails = { snapMail() } }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end
local ALT = "Player-1-BBB"
local alive = { [ALT] = { name = "Kaleid Sumner", lastPlayDay = 5 } }

db = reload(with({ chars = alive, snapshots = { [ALT] = snapRec({ complete = false, total = 140 }) } }))
local s = db.snapshots[ALT]
check(s ~= nil, "a valid snapshot loads")
eq(s.complete, false, "  complete = false is kept, not taken for missing")
eq(s.mails[1].wasReturned, false, "  and a mail's wasReturned = false")
eq(s.mails[1].items[1].id, 2589, "  its items")
db = reload(with({ chars = alive, snapshots = { [ALT] = snapRec({ mails = { snapMail(), snapMail({ type = "letter" }) } }) } }))
eq(next(db.snapshots), nil, "a mail of an unknown type drops the subtree")
db = reload(with({ chars = alive, snapshots = { [ALT] = snapRec({ mails = { snapMail({ expires = "soon" }) } }) } }))
eq(next(db.snapshots), nil, "  and one without a numeric expiry")
db = reload(with({ chars = alive, snapshots = { [ALT] = snapRec({ complete = "yes" }) } }))
eq(next(db.snapshots), nil, "a complete that isn't a boolean drops it")
local many = {}
for i = 1, Store.MAILS_MAX + 1 do many[i] = snapMail() end
db = reload(with({ chars = alive, snapshots = { [ALT] = snapRec({ mails = many }) } }))
eq(next(db.snapshots), nil, "over 100 mails is invalid")
many[Store.MAILS_MAX + 1] = nil
db = reload(with({ chars = alive, snapshots = { [ALT] = snapRec({ mails = many }) } }))
eq(#db.snapshots[ALT].mails, 100, "  100 is fine")
db = reload(with({ chars = alive, snapshots = { [ALT] = snapRec({ mails = { snapMail({ wasReturned = 1 }) } }) } }))
eq(db.snapshots[ALT].mails[1].wasReturned, nil, "a bad optional field is left out of a mail")
db = reload(with({ chars = alive, sent = { sentRec() } }))
eq(type(db.snapshots), "table", "an older save with no snapshots loads an empty table")
eq(#db.sent, 1, "  and keeps its other subtrees")

-- A restarted clock drops snapshots with their characters, through a login.
db = reload(with({ playDay = "x", chars = alive, snapshots = { [ALT] = snapRec() } }))
eq(next(db.snapshots), nil, "a restarted clock drops snapshots at load")
Store.Tick()
eq(next(db.snapshots), nil, "a restarted clock drops snapshots (Load, Tick, Prune)")

-- Prune: a snapshot goes with its character; expired mails go; an emptied one stays.
db = reload(with({ playDay = 40, chars = { [ALT] = { name = "Kaleid Sumner", lastPlayDay = 39 },
    ["Player-1-CCC"] = { name = "Old Alt", lastPlayDay = 1 } },
    snapshots = { [ALT] = snapRec({ loaded = 2, total = 2,
        mails = { snapMail({ expires = WoW.clock - 1 }), snapMail({ expires = WoW.clock + 60 }) } }),
        ["Player-1-CCC"] = snapRec(), ["Player-1-DDD"] = snapRec() } }))
Store.Prune()
eq(db.snapshots["Player-1-CCC"], nil, "a snapshot goes when its character ages out")
eq(db.snapshots["Player-1-DDD"], nil, "  and one whose character isn't known")
eq(#db.snapshots[ALT].mails, 1, "an expired mail goes from its snapshot")
eq(db.snapshots[ALT].loaded, 2, "  the visit's coverage is kept")
WoW.clock = WoW.clock + 120
Store.Prune()
check(db.snapshots[ALT] ~= nil, "a snapshot whose mails all expired stays")
eq(#db.snapshots[ALT].mails, 0, "  empty")
WoW.clock = WoW.clock - 120

-- Writes and forgets, and the change notice.
db = reload(with({ chars = alive }))
local notices = 0
Store.OnChange(function() notices = notices + 1 end)
check(Store.SetSnapshot(ALT, snapRec()), "SetSnapshot takes a valid snapshot")
eq(notices, 1, "  and says so")
check(not Store.SetSnapshot(WoW.Secret("guid"), snapRec()), "a secret GUID isn't kept")
check(not Store.SetSnapshot(ALT, snapRec({ mails = "x" })), "nor an invalid snapshot")
local m = db.snapshots[ALT].mails[1]
check(Store.ForgetMail(ALT, m), "a mail can be forgotten")
eq(#db.snapshots[ALT].mails, 0, "  it's gone from the snapshot")
check(Store.ForgetSnapshot(ALT), "a snapshot can be forgotten")
eq(db.snapshots[ALT], nil, "  it's gone")
check(not Store.ForgetSnapshot(ALT), "  forgetting it again does nothing")
Store.AddSent(sentRec())
Store.AddTrash(trashRec())
local before = notices
check(Store.ForgetSent(db.sent[1]), "a Sent record can be forgotten")
check(Store.ForgetTrash(db.trash[1]), "a Trash entry can be forgotten")
eq(#db.sent + #db.trash, 0, "  both gone")
eq(notices, before + 2, "  each says so")
check(not Store.ForgetSent(sentRec()), "a record that isn't in the list isn't forgotten")
before = notices
Store.Prune()
eq(notices, before, "a prune that removes nothing says nothing")

-- /gmail expiry, /gmail recents
newChat()
SlashCmdList.GLASSMAIL("expiry 14")
eq(GM.db.expiryDays, 14, "/gmail expiry 14 sets it")
SlashCmdList.GLASSMAIL("expiry 15")
check(chatHas("/gmail expiry 7/14/30/60/90"), "/gmail expiry with a bad value lists the choices")
SlashCmdList.GLASSMAIL("recents 50")
eq(GM.db.recentMax, 50, "/gmail recents 50 sets it")

done("test_store")
