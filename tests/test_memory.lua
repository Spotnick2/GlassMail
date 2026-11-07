-- Core/Memory.lua: each character's mailbox as last seen (PLAN.md, "The window
-- PR in detail", "Taking a snapshot").
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.today = "2026-11-06"
local GM = loadAddon()
local db = GlassMailDB
local ME = WoW.playerGUID
local MAILBOX = 17

-- Memory's saves (other modules scan the inbox on each update too).
local scans = 0
local setSnapshot = GM.Store.SetSnapshot
GM.Store.SetSnapshot = function(...) scans = scans + 1; return setSnapshot(...) end

local function mail(over)
    local m = { sender = "Kaleid Sumner", subject = "ore", money = 0, daysLeft = 3, canReply = true,
        items = { [1] = { id = 2589, count = 5 } } }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

local function open() WoW.fire("MAIL_SHOW") end
local function close() WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", MAILBOX) end
local function update() WoW.fire("MAIL_INBOX_UPDATE") end
local function frame() WoW.advance(0.01) end
local function snap() return db.snapshots[ME] end
local function fresh(mails)
    close()
    db.snapshots = {}
    WoW.inbox, WoW.inboxTotal = mails, nil
    scans = 0
end

-- Outside a visit, nothing.
fresh({ mail() })
update()
frame()
eq(snap(), nil, "an update with no mailbox open saves nothing")
eq(scans, 0, "  nor tries to")

-- A visit: the first update's scan, a frame later.
fresh({ mail({ money = 150, cod = 20, daysLeft = 2.5, wasReturned = true,
    items = { [1] = { id = 2589, count = 5 }, [2] = { id = 1, count = 3, currency = true } } }),
    mail({ sender = "Horde Auction House", subject = "Auction won: Linen", canReply = false }) })
open()
frame()
eq(snap(), nil, "no snapshot before the visit's first update")
update()
eq(snap(), nil, "  nor in the update's own frame")
frame()
local s = snap()
check(s ~= nil, "the first update's scan, a frame later, is saved")
eq(s.at, WoW.clock, "  stamped now")
eq(s.loaded, 2, "  with the loaded count")
eq(s.complete, true, "  complete when all are loaded")
local m = s.mails[1]
eq(m.sender, "Kaleid Sumner", "  each mail's sender")
eq(m.money, 150, "  money")
eq(m.cod, 20, "  COD")
eq(m.wasReturned, true, "  returned")
eq(m.type, "player", "  type")
eq(s.mails[2].type, "ah", "  (an AH mail by its subject)")
eq(m.expires, math.floor((WoW.clock + 2.5 * 86400) / 60) * 60, "  expiry, rounded down to the minute")
eq(#m.items, 1, "  a currency attachment is left out")
eq(m.items[1].id, 2589, "  items by itemID")
eq(m.items[1].count, 5, "  with counts")

-- Several updates in one frame: one scan.
scans = 0
update()
update()
update()
frame()
eq(scans, 1, "three updates in one frame scan (and save) once")

-- After the close: nothing.
WoW.inbox = {}
close()
update()
frame()
eq(#snap().mails, 2, "an update after the close changes nothing")

-- update, close, reopen: the old visit's callback does nothing.
open()
update()
frame()
eq(#snap().mails, 0, "an empty inbox is a snapshot too")
WoW.inbox = { mail() }
update()
close()
open()
frame()
eq(#snap().mails, 0, "update, close, reopen: the old visit's scan saves nothing")
update()
frame()
eq(#snap().mails, 1, "  the new visit's own update does")

-- What keeps the old snapshot: anything not read whole.
local function keeps(mails, label, total)
    WoW.inbox, WoW.inboxTotal = mails, total
    local before = snap()
    update()
    frame()
    check(snap() == before, label)
end
open()
keeps({ mail(), mail({ items = { [1] = { id = 2589, count = 5, link = false } } }) },
    "an attachment without a link keeps the old snapshot")
keeps({ mail(), mail({ sender = WoW.Secret("sender") }) }, "  a secret field")
keeps({ mail(), { missing = true } }, "  a header not there yet")
keeps({ mail(), mail({ daysLeft = false }) }, "  a mail with no days left")
keeps({ mail(), mail({ itemCount = 2 }) }, "  fewer attachments than the header says")
eq(GM.failures["memory scan"], nil, "  each refused cleanly, not by an error")

-- Money only, a plain letter and a mail with items: taken.
WoW.inbox, WoW.inboxTotal = { mail({ items = {}, money = 300 }), mail({ items = {}, subject = "hello" }), mail() }, nil
update()
frame()
eq(#snap().mails, 3, "money only, a plain letter and items: taken (no items is a nil count)")
eq(#snap().mails[2].items, 0, "  a letter has no items")

-- A partial inbox (over 100): taken, marked incomplete.
WoW.inbox, WoW.inboxTotal = { mail() }, 140
update()
frame()
eq(snap().complete, false, "a loaded subset is taken, incomplete")
eq(snap().total, 140, "  with the total")
eq(snap().loaded, 1, "  and the loaded count")

-- No GUID we can keep: nothing.
close()
db.snapshots = {}
WoW.playerGUID = WoW.Secret("guid")
WoW.inbox, WoW.inboxTotal = { mail() }, nil
open()
update()
frame()
eq(next(db.snapshots), nil, "a secret GUID saves nothing")
WoW.playerGUID = ME

-- The debug line names the visit and what was read.
GM.API.debug = true
newChat()
update()
frame()
check(chatHas("mailbox scan, visit"), "the debug line logs each scan")
GM.API.debug = false

done("test_memory")
