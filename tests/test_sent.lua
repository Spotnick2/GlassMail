-- Core/Sent.lua: send capture and attribution, as timelines (PLAN.md, "Sent's
-- window, in code"). WoW.now is GetTime(); WoW.advance runs the timers due.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.today = "2026-11-06"
local GM = loadAddon()
local Store, Sent = GM.Store, GM.Sent
local open = GM._test.sent.open
local db = GlassMailDB

local function reset()
    for i = #open(), 1, -1 do table.remove(open(), i) end
    db.sent, db.recents = {}, {}
    WoW.draft, WoW.sends = {}, {}
end

-- A send through Blizzard's button: SendMail(to, subject, body).
local function send(to, opts)
    opts = opts or {}
    WoW.draft = opts.draft or {}
    WoW.confirmNext = opts.stranger
    SendMail(to, opts.subject or "hi", "")
end
local function success() WoW.fire("MAIL_SEND_SUCCESS") end
local function last() return db.sent[#db.sent] end

-- The draft, captured at the post-hook -----------------------------------------
reset()
send("Kaleid Sumner", { subject = "ore", draft = { money = 150, cod = 7,
    items = { [1] = { id = 2589, count = 5 }, [4] = { id = 2770, count = 20 } } } })
local r = open()[1]
check(r ~= nil, "a send is captured at the post-hook")
eq(r.to, "Kaleid Sumner", "  its recipient")
eq(r.subject, "ore", "  its subject")
eq(r.money, 150, "  its money")
eq(r.cod, 7, "  its COD")
eq(#r.items, 2, "  each attachment")
eq(r.items[2].id, 2770, "  by itemID")
eq(r.items[2].count, 20, "  with its count")
eq(r.items[1].link, nil, "  no links")
eq(r.from, WoW.playerGUID, "  from this character")
eq(#db.sent, 0, "nothing is saved while it is pending")

-- One open window and a success: sent, and a recent -------------------------
WoW.advance(0.5)
success()
eq(#open(), 0, "the success closes its window")
eq(last().state, "sent", "one open window and a success: sent")
eq(last().to, "Kaleid Sumner", "  to its recipient")
eq(last().items[1].id, 2589, "  with its items saved")
eq(last().day, db.playDay, "  stamped today")
eq(db.recents["kaleid sumner"].name, "Kaleid Sumner", "  and the recipient becomes a recent")
WoW.advance(130)
eq(#db.sent, 1, "  its window's end changes nothing")

-- Two open: a success confirms neither -------------------------------------------
reset()
send("Kaleid Sumner")
WoW.advance(1)
send("Cowruzo Kashmere")
WoW.advance(0.5)
success()
eq(#db.sent, 0, "two open windows: the success confirms neither")
eq(#open(), 2, "  both stay candidates")
WoW.advance(120)
eq(#db.sent, 2, "  and each ends with its window")
eq(db.sent[1].state, "unconfirmed", "  unconfirmed")
eq(db.sent[2].state, "unconfirmed", "  both")
eq(next(db.recents), nil, "  no recent from an unconfirmed send")

-- The 120 s end ------------------------------------------------------------------
reset()
send("Kaleid Sumner")
WoW.advance(119)
eq(#db.sent, 0, "still open at 119 s")
WoW.advance(2)
eq(last() and last().state, "unconfirmed", "a window that ends without a result: unconfirmed")
eq(#open(), 0, "  and it is no longer a candidate")
success()
eq(#db.sent, 1, "a late success confirms nothing")

-- The client's refusal (error 457) ------------------------------------------------
reset()
send("Kaleid")
WoW.fire("UI_ERROR_MESSAGE", 457, "Please enter a full character name.")
eq(#open(), 0, "error 457 in the send's frame drops the record")
WoW.advance(121)
eq(#db.sent, 0, "  it is never saved")

reset()
send("Kaleid Sumner")
WoW.fire("UI_ERROR_MESSAGE", 321, "Target is unfriendly.")
eq(#open(), 1, "another error in that frame leaves the record")
WoW.advance(0.02)
WoW.fire("UI_ERROR_MESSAGE", 457, "Please enter a full character name.")
eq(#open(), 1, "457 a frame later leaves it too")
WoW.advance(121)
eq(last().state, "unconfirmed", "  it ends with its window")

reset()
send("Kaleid")
send("Cowruzo")
WoW.fire("UI_ERROR_MESSAGE", 457, "Please enter a full character name.")
eq(#open(), 2, "457 with two sends in that frame drops neither (whose was it?)")

reset()
send("Kaleid Sumner")
WoW.fire("UI_ERROR_MESSAGE", WoW.Secret("type"), "x")
eq(#open(), 1, "a secret error type is left alone")

-- Logout -------------------------------------------------------------------------------
reset()
send("Kaleid Sumner")
WoW.advance(1)
WoW.fire("PLAYER_LOGOUT")
eq(last() and last().state, "unconfirmed", "at logout an open send is saved unconfirmed")
eq(#open(), 0, "  and closed")

-- The stranger confirmation --------------------------------------------------------------
-- A at t=0 raises the dialog; accepted at t=130 (its window starts), B sent at
-- 130.3, a success at 130.6: two candidates, neither.
reset()
send("Stranger One", { stranger = true })
check(open()[1].awaiting, "a send that raised the confirmation awaits it")
WoW.advance(130)
eq(#db.sent, 0, "  with no time limit")
SendMailFrame_EnableSendMailButton()   -- the dialog closes (accepted)
check(not open()[1].awaiting, "the dialog's close starts its window")
WoW.advance(0.3)
send("Kaleid Sumner")
WoW.advance(0.3)
success()
eq(#db.sent, 0, "accepted at 130 s, B at 130.3, a success at 130.6: neither")

reset()
send("Stranger One", { stranger = true })
WoW.advance(11)
SendMailFrame_EnableSendMailButton()
WoW.advance(0.4)
success()
eq(last() and last().state, "sent", "a stranger accepted at 11 s, alone: sent")
eq(last().to, "Stranger One", "  to the stranger")

reset()
send("Stranger One", { stranger = true })
WoW.advance(5)
SendMailFrame_EnableSendMailButton()   -- cancelled: nothing else fires
WoW.advance(119)
eq(#db.sent, 0, "a cancelled stranger's window starts at the close")
WoW.advance(2)
eq(last() and last().state, "unconfirmed", "  and ends unconfirmed 120 s later")

-- The close hook never firing: the record stays a candidate until logout.
reset()
send("Stranger One", { stranger = true })
WoW.advance(300)
send("Kaleid Sumner")
WoW.advance(0.5)
success()
eq(#db.sent, 0, "a dialog never closed keeps its send a candidate: the next success is ambiguous")
WoW.fire("PLAYER_LOGOUT")
eq(#db.sent, 2, "  logout saves both")
eq(db.sent[1].state, "unconfirmed", "  unconfirmed")

-- A secret recipient: a candidate, never saved ---------------------------------------
reset()
send(WoW.Secret("to"))
send("Kaleid Sumner")
WoW.advance(0.5)
success()
eq(#db.sent, 0, "a send to a secret name still counts as a candidate")
WoW.advance(121)
eq(#db.sent, 1, "  and is never saved")
eq(db.sent[1].to, "Kaleid Sumner", "  only the other is")

-- /gmail sent -------------------------------------------------------------------------
reset()
send("Kaleid Sumner", { subject = "ore", draft = { money = 150, items = { [1] = { id = 2589, count = 5 } } } })
WoW.advance(0.5)
success()
newChat()
SlashCmdList.GLASSMAIL("sent")
local lines = newChat()
eq(#lines, 1, "/gmail sent: one line per record")
check(lines[1]:find("Karuzo Morphisto sent to Kaleid Sumner", 1, true) ~= nil, "  from whom, to whom")
check(lines[1]:find('"ore"', 1, true) ~= nil, "  the subject")
check(lines[1]:find("150c", 1, true) ~= nil, "  the money")
check(lines[1]:find("2589 x5", 1, true) ~= nil, "  the items")
reset()
SlashCmdList.GLASSMAIL("sent")
check(chatHas("nothing sent or returned yet"), "/gmail sent with nothing says so")

-- A send stops an Ops run (one mail action at a time).
WoW.inbox = { { sender = "Kaleid Sumner", subject = "gold", money = 100 } }
check(GM.Ops.OpenAll({ types = { ah = true, system = true, player = true }, keepFree = 0 }), "an Open All run starts")
send("Kaleid Sumner")
check(not GM.Ops.Running(), "a send stops it")

done("test_sent")
