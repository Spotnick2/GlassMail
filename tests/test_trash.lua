-- Core/Trash.lua: deletes into Trash, returns into Sent, kept only when the
-- inbox proves them (PLAN.md, "Trash (Core/Trash.lua)" and "Trash, in code").
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.today = "2026-11-06"
local GM = loadAddon()
local state = GM._test.trash.state
local db = GlassMailDB

local function mail(over)
    local m = { sender = "Kaleid Sumner", subject = "ore", money = 0, daysLeft = 3, canReply = false,
        items = { [1] = { id = 2589, count = 5 } } }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

-- A fresh, settled inbox; each scenario starts a frame after the last update.
local function setup(mails)
    WoW.inbox, WoW.mailCalls, WoW.commandPending = mails, {}, false
    WoW.advance(1)
    WoW.fire("MAIL_INBOX_UPDATE")
    WoW.advance(6)   -- past any earlier capture's 5 s
    db.trash, db.sent = {}, {}
end
local function lastCall() return WoW.mailCalls[#WoW.mailCalls] end
local function serve() WoW.serve(lastCall()) end

-- A delete: captured at the hook, confirmed by the next update, committed a frame later.
setup({ mail({ subject = "first" }), mail({ subject = "second" }) })
DeleteInboxItem(1)
check(state().capture ~= nil, "a delete is captured at its post-hook")
WoW.advance(0.2)
serve()
eq(#db.trash, 0, "confirmed by the update, not yet committed")
WoW.advance(0.02)
eq(#db.trash, 1, "committed a frame later")
local e = db.trash[1]
eq(e.subject, "first", "  the mail that was at that index")
eq(e.sender, "Kaleid Sumner", "  its sender")
eq(e.items[1].id, 2589, "  its items by itemID")
eq(e.items[1].count, 5, "  with counts")
eq(e.from, WoW.playerGUID, "  from this character's mailbox")
eq(e.expires, WoW.clock + 3 * 86400, "  kept until the mail would have expired")

-- An update in the same frame as the call: not captured.
setup({ mail() })
WoW.fire("MAIL_INBOX_UPDATE")
DeleteInboxItem(1)
eq(state().capture, nil, "an update in the call's frame: not captured (the index may have moved)")

-- A take before the confirmation drops the capture.
setup({ mail({ subject = "a" }), mail({ subject = "b" }) })
DeleteInboxItem(1)
local del = lastCall()
WoW.advance(0.1)
TakeInboxItem(2, 1)
eq(state().capture, nil, "a later call drops an outstanding capture")
WoW.serve(del)
WoW.advance(0.1)
eq(#db.trash, 0, "  nothing is committed")

-- Take, then Return before the take's update: the return isn't captured.
setup({ mail({ canReply = true, subject = "x" }) })
TakeInboxItem(1, 1)
WoW.advance(0.1)
ReturnInboxItem(1)
eq(state().capture, nil, "take, then return before the take's update: the return isn't captured")

-- Removal A, then removal B before A's update: neither.
setup({ mail({ subject = "a" }), mail({ subject = "b" }) })
DeleteInboxItem(1)
local a = lastCall()
WoW.advance(0.05)
DeleteInboxItem(2)
eq(state().capture, nil, "A then B before A's update: B isn't captured (unsettled), A is dropped")
WoW.serve(a)
WoW.advance(0.1)
eq(#db.trash, 0, "  neither is committed")
-- With twins, and a second call the server rejects (no update for it).
setup({ mail(), mail() })
DeleteInboxItem(1)
a = lastCall()
WoW.advance(0.05)
DeleteInboxItem(1)
table.remove(WoW.mailCalls)   -- rejected: never served
WoW.serve(a)
WoW.advance(0.1)
eq(#db.trash, 0, "twins, A then a rejected B: nothing committed")

-- A take, an unrelated update while a command is still pending, then a Return.
setup({ mail({ canReply = true }), mail({ canReply = true, subject = "other" }) })
TakeInboxItem(1, 1)
WoW.advance(0.1)
WoW.commandPending = true
WoW.fire("MAIL_INBOX_UPDATE")
check(state().unsettled, "an update with a command pending doesn't settle the inbox")
WoW.advance(0.1)
ReturnInboxItem(2)
eq(state().capture, nil, "  so a Return then isn't captured")

-- A take that produces no update: the next removal is left out, and its own
-- update settles the inbox again.
setup({ mail({ subject = "a" }), mail({ subject = "b" }), mail({ subject = "c" }) })
TakeInboxItem(1, 9)   -- an empty slot: no event at all (session 5)
WoW.advance(1)
DeleteInboxItem(1)
eq(state().capture, nil, "after a take with no update, the next removal is left out")
WoW.advance(0.2)
serve()
check(not state().unsettled, "  its own update settles the inbox")
WoW.advance(0.1)
DeleteInboxItem(1)
check(state().capture ~= nil, "  and the next removal is captured again")

-- Twins: the fingerprint's count falls by one.
setup({ mail(), mail() })
DeleteInboxItem(2)
eq(state().capture.before, 2, "a twin is captured with its fingerprint's count")
WoW.advance(0.2)
serve()
WoW.advance(0.02)
eq(#db.trash, 1, "  confirmed when it falls by one and the inbox shrinks by one")

-- The inbox shrinks by one, but another mail left: not confirmed.
setup({ mail({ subject = "a" }), mail({ subject = "b" }) })
DeleteInboxItem(1)
WoW.advance(0.2)
table.remove(WoW.inbox, 2)   -- "b" goes (expired, say); "a" is still there
WoW.fire("MAIL_INBOX_UPDATE")
WoW.advance(0.02)
eq(#db.trash, 0, "one mail fewer, but not the captured one: not confirmed")

-- The captured mail goes, but a new one arrives in the same update: the
-- loaded count didn't fall, so nothing proves the removal.
setup({ mail({ subject = "a" }), mail({ subject = "b" }) })
DeleteInboxItem(1)
WoW.advance(0.2)
WoW.inbox[1] = mail({ subject = "new" })
WoW.fire("MAIL_INBOX_UPDATE")
WoW.advance(0.02)
eq(#db.trash, 0, "the mail left but another arrived: the inbox didn't shrink, not confirmed")

-- A return goes to Sent as "return".
setup({ mail({ canReply = true, money = 500, subject = "loan" }) })
ReturnInboxItem(1)
WoW.advance(0.2)
serve()
WoW.advance(0.02)
eq(#db.trash, 0, "a return isn't Trash")
local r = db.sent[#db.sent]
eq(r and r.kind, "return", "  it goes to Sent as a return")
eq(r and r.to, "Kaleid Sumner", "  to its sender")
eq(r and r.state, "sent", "  confirmed")
eq(r and r.money, 500, "  with what it carried")
eq(next(db.recents), nil, "  its sender doesn't become a recent recipient")

-- An unresolved mail isn't captured.
setup({ mail({ items = { [1] = { id = 2589, count = 5, link = false } } }) })
DeleteInboxItem(1)
eq(state().capture, nil, "a mail with an attachment not yet linked isn't captured")
setup({ mail({ sender = WoW.Secret("sender") }) })
DeleteInboxItem(1)
eq(state().capture, nil, "nor one with a secret field")

-- The 5 s end drops it.
setup({ mail() })
DeleteInboxItem(1)
WoW.advance(5.1)
eq(state().capture, nil, "unconfirmed after 5 s: dropped")
serve()
WoW.advance(0.1)
eq(#db.trash, 0, "  a late update commits nothing")

-- The deferred commit checks the capture is still the same one.
setup({ mail({ subject = "a" }), mail({ subject = "b" }) })
DeleteInboxItem(1)
WoW.advance(0.2)
serve()
TakeInboxItem(1, 1)   -- in the same frame, before the commit
WoW.advance(0.02)
eq(#db.trash, 0, "a call between the confirmation and the commit voids it")

-- /gmail trash
setup({ mail({ subject = "junk" }) })
DeleteInboxItem(1)
WoW.advance(0.2)
serve()
WoW.advance(0.02)
newChat()
SlashCmdList.GLASSMAIL("trash")
local lines = newChat()
eq(#lines, 1, "/gmail trash: one line per entry")
check(lines[1]:find("deleted mail from Kaleid Sumner", 1, true) ~= nil, "  the sender")
check(lines[1]:find('"junk"', 1, true) ~= nil, "  the subject")
check(lines[1]:find("gone in 3 days", 1, true) ~= nil, "  when it goes")

done("test_trash")
