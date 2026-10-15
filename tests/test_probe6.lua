-- MailProbe, session 6 (M2): sendwatch, capture and names, against the shared
-- fake inbox, with the probe loaded as a ForeverProbe module (runs locally
-- only: ForeverProbe is private, CI skips it). What they measure needs the live client; this keeps the probe's
-- bookkeeping honest: an event inside SendMail is told from one in the click's
-- setup, a send without an answer shows as an overlap, a delete is confirmed
-- only by an update that shows it gone.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The send side: Blizzard's button runs SetSendMailCOD(0), SetSendMailMoney(0)
-- and then SendMail (MailFrame.lua:1250-1273). Each Set fires its event inside it.
local draft = { money = 0, cod = 0, items = {} }
local failInside = false   -- SendMail fires MAIL_FAILED before it returns
CreateFrame("Button", "SendMailMailButton", SendMailFrame)
rawset(_G, "SetSendMailCOD", function(c) draft.cod = c; WoW.fire("SEND_MAIL_COD_CHANGED") end)
rawset(_G, "SetSendMailMoney", function(c) draft.money = c; WoW.fire("SEND_MAIL_MONEY_CHANGED") end)
rawset(_G, "GetSendMailMoney", function() return draft.money end)
rawset(_G, "GetSendMailCOD", function() return draft.cod end)
rawset(_G, "GetSendMailPrice", function() return 30 end)
rawset(_G, "GetSendMailItem", function(a)
    local it = draft.items[a]
    if it then return it.name, it.id, 134, it.count end
end)
rawset(_G, "SendMail", function() if failInside then WoW.fire("MAIL_FAILED") end end)
local function click(money)
    local b = SendMailMailButton
    if b._scripts.PreClick then b._scripts.PreClick(b, "LeftButton") end
    SetSendMailCOD(0)
    SetSendMailMoney(0)
    if money then SetSendMailMoney(money) end
    SendMail("Cowruzo Test", "hi", "")
end

-- Names: a friend with a realm suffix, a secret one; a guild of three.
local friends = { { name = "Cowruzo Test", connected = true }, { name = "Tobi Far-Otherrealm", connected = false },
    { name = WoW.Secret("friend") } }
local guild = { "Karuzo Morphisto", "Anna Smith-Otherrealm", WoW.Secret("member") }
local inGuild, rosterAsked = true, 0
rawset(_G, "C_FriendList", { GetNumFriends = function() return #friends end,
    GetFriendInfoByIndex = function(i) return friends[i] end })
rawset(_G, "IsInGuild", function() return inGuild end)
rawset(_G, "C_GuildInfo", { GuildRoster = function() rosterAsked = rosterAsked + 1 end })
rawset(_G, "GetNumGuildMembers", function() return #guild end)
rawset(_G, "GetGuildRosterInfo", function(i) return guild[i] end)
rawset(_G, "UnitFullName", function() return "Karuzo", "Doomhowl" end)
rawset(_G, "GetNormalizedRealmName", function() return "Doomhowl" end)
rawset(_G, "IsInInstance", function() return false, "none" end)
rawset(_G, "Ambiguate", function(n) return (n:gsub("%-.*$", "")) end)
rawset(_G, "MailProbeDB", nil)
-- A delete the server can answer inside the call: the mail goes and
-- MAIL_INBOX_UPDATE fires before the probe's post-hook runs.
local serveInside = false
local recordDelete = DeleteInboxItem
rawset(_G, "DeleteInboxItem", function(i)
    recordDelete(i)
    if serveInside then table.remove(WoW.inbox, i); WoW.fire("MAIL_INBOX_UPDATE") end
end)

-- A take the server answers inside the call: the slot empties (the mail goes
-- with its last item) and MAIL_INBOX_UPDATE fires before the post-hook.
local takeInside = false
local recordTake = TakeInboxItem
rawset(_G, "TakeInboxItem", function(i, a)
    recordTake(i, a)
    if takeInside then WoW.serve({ "TakeInboxItem", i, a }) end
end)
-- The open letter's Delete / Return button (MailFrame.xml:1316).
CreateFrame("Button", "OpenMailDeleteButton", OpenMailFrame)

-- The probe's lines are in its saved log (never chat); only the lines since
-- the last mark() count.
local from = 0
local function mark() from = #MailProbeDB.log end
-- A removal clicked in a later frame than the last update (GetTime() is the
-- frame's time; an update in the same frame makes the baseline ambiguous).
local function delete(i)
    WoW.now = (WoW.now or 0) + 1
    DeleteInboxItem(i)
end
local function saw(pattern)
    for i = from + 1, #MailProbeDB.log do if MailProbeDB.log[i]:find(pattern) then return true end end
    return false
end

loadForeverProbe()
assert(loadfile("Tools/MailProbe/MailProbe.lua"))("MailProbe", {})
WoW.fire("ADDON_LOADED", "MailProbe")
WoW.fire("PLAYER_LOGIN")

-- sendwatch off: nothing extra.
mark()
click()
check(not saw("#%d+ S "), "sendwatch off: a send logs no S line")

-- sendwatch on: the draft at the click and at the post-hook; nothing inside SendMail.
SlashCmdList.FOREVERPROBE("mail sendwatch on")
draft.items[1] = { name = "Copper Ore", id = 2770, count = 20 }
mark()
WoW.now = 100
click(500)
check(saw("S Send clicked: to=nil money=0 cod=0 items=1:2770x20 postage=30"), "the draft is logged at the click")
check(saw("S send #1 to \"Cowruzo Test\": draft at the post%-hook money=500 cod=0 items=1:2770x20"),
    "  and at SendMail's post-hook, numbered")
check(saw("inside SendMail: no event"), "the setup calls' own events are not inside SendMail")
check(saw("SEND_MAIL_MONEY_CHANGED.*during the Send click"), "  they are during the click")
WoW.now = 104.3
mark()
WoW.fire("MAIL_SEND_SUCCESS")
check(saw("MAIL_SEND_SUCCESS %(%) %[%+4%.30 s after send #1%]"), "a result is timed from the send")
check(saw("Send button enabled=true"), "  with the Send button's state")
check(saw("draft now: to=nil money=500 items=1"), "  and the draft as it is then")
WoW.flushTimers()
check(not saw("never reached"), "a click that reached SendMail is not reported as lost")

-- An event SendMail fires before it returns is inside it.
failInside = true
mark()
click()
check(saw("inside SendMail: MAIL_FAILED"), "an event fired by SendMail itself is listed at the post-hook")
failInside = false
WoW.flushTimers()

-- A second send while the first has no success is an overlap.
mark()
click()
check(saw("OVERLAP: send #2 had no MAIL_SEND_SUCCESS yet"), "a send before the last one succeeded is an overlap")
WoW.fire("MAIL_SEND_SUCCESS")
mark()
click()
check(not saw("OVERLAP"), "  not after a success")
WoW.flushTimers()

-- SendMail from elsewhere (no click), and a click that never reached SendMail.
mark()
SendMail("Cowruzo Test", "x", "")
check(saw("not from the Send button"), "a SendMail without a click is said")
mark()
SendMailMailButton._scripts.PreClick(SendMailMailButton, "LeftButton")
WoW.flushTimers()
check(saw("the Send click never reached SendMail"), "a click without SendMail is said")
mark()
WoW.fire("MAIL_SEND_SUCCESS")
check(not saw("during the Send click"), "  and its phase ended")
SlashCmdList.FOREVERPROBE("mail sendwatch off")

-- capture: a delete whose mail is still at its index, confirmed by the update.
WoW.inbox = {
    { sender = "Cowruzo Test", subject = "a" },
    { sender = "Cowruzo Test", subject = "b", items = { { id = 2770, count = 5 } } },
    { sender = "Cowruzo Test", subject = "c" },
}
mark()
SlashCmdList.FOREVERPROBE("mail capture on")
WoW.mailCalls = {}
mark()
WoW.now = 199   -- delete() clicks at 200
delete(2)
check(saw("X DeleteInboxItem%(2%) post%-hook: loaded 3 before the call %(the last update%), 3 now"),
    "capture logs the counts at the hook, against the last update when none came this frame")
check(saw("before: 2: \"Cowruzo Test\" \"b\""), "  the mail at that index before")
check(saw("SAME mail at its index"), "  and that it is still there")
WoW.now = 200.4
mark()
WoW.serve(WoW.mailCalls[1])
check(saw("X update %+0%.40 s after DeleteInboxItem of mail 2: loaded 3 %-> 2, its fingerprint 1 %-> 0"),
    "the next update is logged against it")
check(not saw("confirmed"), "  not confirmed in the same frame (a later call's post-hook may still void it)")
WoW.flushTimers(0)
check(saw("confirmed: one fewer of it, one mail fewer"), "  confirmed a frame later")
WoW.flushTimers()
check(not saw("no update showed"), "  so its 5 s timer says nothing")

-- The inbox shrank before the hook (no update yet): not the same mail at the index.
local realDelete = rawget(_G, "DeleteInboxItem")
WoW.mailCalls = {}
WoW.inbox[#WoW.inbox + 1] = { sender = "Cowruzo Test", subject = "d" }
WoW.inbox[#WoW.inbox + 1] = { sender = "Cowruzo Test", subject = "e" }
WoW.fire("MAIL_INBOX_UPDATE")
mark()
table.remove(WoW.inbox, 1)   -- as if the server answered inside the call, without an update
delete(1)
check(saw("loaded 4 before the call %(the last update%), 3 now"), "a shrink before the hook shows in the counts")
check(saw("NOT the same"), "  and the mail at the index is another one")
WoW.flushTimers(0)
check(saw("confirmed"), "  the counts at the hook confirm it, a frame later")

-- Not confirmed: another mail went (its own still there), or its fingerprint
-- changed with no mail fewer (money taken).
WoW.fire("MAIL_INBOX_UPDATE")
mark()
delete(1)
table.remove(WoW.inbox, 2)
WoW.fire("MAIL_INBOX_UPDATE")
WoW.flushTimers(0)
check(saw("its fingerprint 1 %-> 1") and not saw("confirmed"), "another mail going doesn't confirm it")
WoW.flushTimers()
mark()
delete(1)
WoW.inbox[1].money = 5
WoW.fire("MAIL_INBOX_UPDATE")
WoW.flushTimers(0)
check(saw("loaded (%d+) %-> %1, its fingerprint 1 %-> 0") and not saw("confirmed"), "  nor its mail changing in place")
WoW.inbox[1].money = 0
WoW.flushTimers()

-- A take after a removal voids it: a take that empties the mail must not
-- confirm the delete (PLAN.md, Trash), whether its update comes after the
-- take returns or inside it.
WoW.inbox = { { sender = "Cowruzo Test", subject = "t", items = { { id = 2770, count = 5 } } },
    { sender = "Cowruzo Test", subject = "u" } }
WoW.fire("MAIL_INBOX_UPDATE")
WoW.mailCalls = {}
mark()
delete(1)   -- unanswered
TakeInboxItem(1, 1)
check(saw("capture %(DeleteInboxItem of mail 1%) dropped: TakeInboxItem ran"), "a take drops the waiting capture")
WoW.serve(WoW.mailCalls[2])   -- the take empties the mail: it goes
WoW.flushTimers(0)
check(not saw("confirmed"), "  so the take emptying the mail confirms nothing")
WoW.flushTimers()
check(not saw("no update showed"), "  and the dropped capture's timer says nothing")
WoW.inbox = { { sender = "Cowruzo Test", subject = "t", items = { { id = 2770, count = 5 } } },
    { sender = "Cowruzo Test", subject = "u" } }
WoW.fire("MAIL_INBOX_UPDATE")
mark()
delete(1)   -- unanswered
takeInside = true
TakeInboxItem(1, 1)   -- empties the mail; its update fires inside the take
takeInside = false
WoW.flushTimers(0)
check(saw("dropped: TakeInboxItem ran"), "a take whose update fires inside it still drops the capture")
check(not saw("confirmed"), "  before that update can confirm the delete")
WoW.flushTimers()

-- The letter's button marks the inbox before its call: an update inside the
-- call is then told apart, and the removed mail (A) is compared, not B.
WoW.inbox = { { sender = "Cowruzo Test", subject = "A" }, { sender = "Cowruzo Test", subject = "B" } }
WoW.now = 300
WoW.fire("MAIL_INBOX_UPDATE")
WoW.now = 301
mark()
OpenMailDeleteButton._scripts.PreClick(OpenMailDeleteButton, "LeftButton")
serveInside = true
DeleteInboxItem(1)   -- as the button's OnClick does
serveInside = false
check(saw("loaded 2 before the call %(the button's PreClick%), 1 now"), "the button's pre-call point is the baseline")
check(saw('before: 1: "Cowruzo Test" "A"'), "  the mail before the call (A)")
check(saw("NOT the same"), "  so B at index 1 is not taken for A")
WoW.flushTimers(0)
check(saw("confirmed"), "  and A's removal is confirmed")
WoW.flushTimers()

-- An update in the same frame with no pre-call point: inside the call or
-- before it can't be told, so nothing is captured. Here the update came
-- before the call, and B, the delete's target, is still there.
WoW.inbox = { { sender = "Cowruzo Test", subject = "A" }, { sender = "Cowruzo Test", subject = "B" } }
WoW.now = 310
WoW.fire("MAIL_INBOX_UPDATE")
WoW.now = 310.5
DeleteInboxItem(2)   -- an earlier removal, still waiting
WoW.now = 311
table.remove(WoW.inbox, 1)
WoW.fire("MAIL_INBOX_UPDATE")   -- an unrelated update: A goes
mark()
DeleteInboxItem(1)   -- same frame, targets B, the server hasn't answered
check(saw("AMBIGUOUS, not captured"), "an update this frame without a pre-call point is ambiguous")
check(saw('before the update: 1: "Cowruzo Test" "A"') and saw('after it: +1: "Cowruzo Test" "B"'),
    "  both candidates are logged")
WoW.flushTimers()
check(saw("previous capture %(DeleteInboxItem of mail 2%) dropped"), "  and the removal still waiting is dropped")
check(not saw("confirmed") and not saw("no update showed"), "  nothing is confirmed or timed")
OpenMailDeleteButton._scripts.PreClick(OpenMailDeleteButton, "LeftButton")   -- a click that never called
WoW.now = 312
mark()
DeleteInboxItem(1)   -- a later frame: the PreClick of an earlier frame doesn't count
check(saw("before the call %(the last update%)"), "an old pre-call point is not reused")
WoW.flushTimers()

-- A delete with no update: dropped after 5 s; one replaced by the next.
WoW.inbox = { { sender = "Cowruzo Test", subject = "v" }, { sender = "Cowruzo Test", subject = "w" } }
WoW.fire("MAIL_INBOX_UPDATE")
mark()
delete(1)
delete(2)
check(saw("previous capture %(DeleteInboxItem of mail 1%) dropped"), "a second removal drops the first capture")
WoW.flushTimers(5)
check(saw("no update showed mail 2 gone within 5 s"), "an unanswered capture ends after 5 s")
check(not saw("no update showed mail 1"), "  the dropped one says nothing more")
mark()
SlashCmdList.FOREVERPROBE("mail capture off")
delete(1)
check(not saw("#%d+ X "), "capture off: a delete logs no X line")
check(realDelete == rawget(_G, "DeleteInboxItem"), "the delete function was hooked, not replaced")

-- names: realm suffixes, secrets, Ambiguate, the roster asked for.
mark()
SlashCmdList.FOREVERPROBE("mail names")
check(saw('names: you "Karuzo", "Doomhowl" realm="Doomhowl" normalized="Doomhowl" instance=false, "none"'),
    "names logs your name and realm")
check(saw('friend 1 "Cowruzo Test" suffix=false Ambiguate%(none%)="Cowruzo Test" connected=true'), "  a friend")
check(saw('friend 2 "Tobi Far%-Otherrealm" suffix=true Ambiguate%(none%)="Tobi Far"'), "  a realm suffix")
check(saw("friend 3 <secret>"), "  a secret name, untouched")
eq(rosterAsked, 1, "the guild roster is requested")
check(saw("guild 2 \"Anna Smith%-Otherrealm\" suffix=true"), "  each member's name")
check(saw("guild: 1 with a realm suffix, 1 secret, of 3"), "  and the totals")
inGuild = false
mark()
SlashCmdList.FOREVERPROBE("mail names")
check(saw("not in a guild"), "no guild is said")
eq(rosterAsked, 1, "  and no roster requested")

done("test_probe6")
