-- Core/Recall.lua and its two faces, the inbox (Inbox.lua) and the Sent
-- folder (Window.lua): N2, return assistance (PLAN.md, "N2: recall").
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.today = "2026-11-12"
local ORE, CLOTH, FOOD = 2770, 2589, 6290
WoW.itemInfo = { [ORE] = { maxStack = 20, family = 0 }, [CLOTH] = { maxStack = 20, family = 0 },
    [FOOD] = { maxStack = 20, family = 0 } }
WoW.bags = { [0] = { size = 16, family = 0, items = {} } }
local GM = loadAddon()
local Store, Recall, Scan = GM.Store, GM.Recall, GM.Scan
local I = GM._test.inbox
local db = GlassMailDB
local ME, ALT = WoW.playerGUID, "Player-1-BBB"
local MY_NAME, ALT_NAME = "Karuzo Morphisto", "Kaleid Sumner"
local NOW = WoW.clock

local function click(b) b._scripts.OnClick(b, "LeftButton") end
local function step(dt) WoW.tick(dt or 0.2); WoW.advance(0) end   -- OnUpdate, then the due timers
local function has(s, part) return type(s) == "string" and s:find(part, 1, true) ~= nil end
local function last() return WoW.mailCalls[#WoW.mailCalls] end

eq(Store.Chars()[ME].name, MY_NAME, "the playing character is in chars (Registry.Touch at login)")
Store.SetChar(ALT, { name = ALT_NAME, realm = "Doomhowl", faction = "Horde", lastPlayDay = Store.PlayDay() })
Store.SetChar("Player-1-ALY", { name = "Ally Person", realm = "Doomhowl", faction = "Alliance", lastPlayDay = 1 })
Store.SetChar("Player-1-PVP", { name = "Pvp Person", realm = "Sunfire PvP", faction = "Horde", lastPlayDay = 1 })
Store.SetChar("Player-1-NOR", { name = "Norealm Person", faction = "Horde", lastPlayDay = 1 })

-- A send saved in Sent, returned as the saved record itself.
local function sent(over)
    local r = { kind = "send", day = Store.PlayDay(), at = NOW, from = ME, to = ALT_NAME, state = "sent",
        subject = "ore", money = 500, cod = 0, items = { { id = CLOTH, count = 5 }, { id = ORE, count = 3 } } }
    for k, v in pairs(over or {}) do
        if v == false then r[k] = nil else r[k] = v end
    end
    check(Store.AddSent(r), "  (a send saved)")
    local list = Store.Sent()
    return list[#list]
end
-- The mail that send makes, in the inbox stub's shape (slots on purpose not in order).
local function arrived(over)
    local m = { sender = MY_NAME, subject = "ore", money = 500,
        items = { [1] = { id = ORE, count = 3 }, [4] = { id = CLOTH, count = 5 } } }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end
-- The live shape: one mail scanned from the stub.
local function live(m)
    WoW.inbox = { m }
    return Scan.Inbox().mails[1]
end
local REC = { fromName = MY_NAME, subject = "ore", money = 500, cod = 0,
    items = { { id = CLOTH, count = 5 }, { id = ORE, count = 3 } } }
local function rec(over)
    local r = {}
    for k, v in pairs(REC) do r[k] = v end
    for k, v in pairs(over or {}) do
        if v == false then r[k] = nil else r[k] = v end
    end
    return r
end

--------------------------------------------------------------------------------
-- Matches
--------------------------------------------------------------------------------

check(Recall.Matches(rec(), live(arrived())), "the mail a send made matches it (slots in another order)")
check(not Recall.Matches(rec(), live(arrived({ sender = "Bank Alt" }))), "  another sender doesn't")
check(not Recall.Matches(rec(), live(arrived({ subject = "Ore" }))), "  another subject doesn't")
check(not Recall.Matches(rec(), live(arrived({ money = 499 }))), "  other money doesn't")
check(not Recall.Matches(rec(), live(arrived({ cod = 10 }))), "  a COD doesn't")
check(not Recall.Matches(rec(), live(arrived({ items = { [1] = { id = ORE, count = 2 }, [4] = { id = CLOTH, count = 5 } } }))),
    "  another count doesn't")
check(not Recall.Matches(rec(), live(arrived({ items = { [1] = { id = ORE, count = 3 }, [2] = { id = FOOD, count = 1 },
    [4] = { id = CLOTH, count = 5 } } }))), "  an extra item doesn't")
check(not Recall.Matches(rec(), live(arrived({ items = { [1] = { id = ORE, count = 3 } } }))), "  a missing item doesn't")
check(not Recall.Matches(rec(), live(arrived({ wasReturned = true }))), "  a returned mail doesn't")
check(Recall.Matches(rec({ subject = " Ore  " }), live(arrived({ subject = " Ore  " }))), "the subject is compared as it is")

local twice = rec({ items = { { id = ORE, count = 3 }, { id = ORE, count = 3 } } })
check(Recall.Matches(twice, live(arrived({ items = { [2] = { id = ORE, count = 3 }, [7] = { id = ORE, count = 3 } } }))),
    "a repeated item: both stacks match")
check(not Recall.Matches(twice, live(arrived({ items = { [2] = { id = ORE, count = 3 } } }))), "  one of them doesn't")

local auctionShaped = rec({ subject = "Auction won: Copper Ore" })
local m = live(arrived({ subject = "Auction won: Copper Ore" }))
eq(m.type, "ah", "an alt's mail titled like an AH one is classified ah by LibMailbox")
check(Recall.Matches(auctionShaped, m), "  and still matches (no test of the type)")
check(not Recall.Matches(auctionShaped, live(arrived({ sender = "Horde Auction House", subject = "Auction won: Copper Ore",
    canReply = false }))), "a real AH mail doesn't: its sender")

check(not Recall.Matches(rec(), live(arrived({ itemCount = 3 }))), "fewer attachments read than the header's count: no match")
check(Recall.Matches(rec(), live(arrived({ items = { [1] = { id = ORE, count = 3 }, [4] = { id = CLOTH, count = 5 },
    [5] = { id = 1, count = 1, currency = true } } }))), "a currency attachment is counted whole, then left out")
check(Recall.Matches(rec(), live(arrived({ items = { [1] = { id = ORE, count = 3, link = false }, [4] = { id = CLOTH, count = 5 } } }))),
    "a mail still loading a link can match")

local saved = { sender = MY_NAME, subject = "ore", money = 500, cod = 0, type = "player",
    items = { { id = ORE, count = 3 }, { id = CLOTH, count = 5 } } }
check(Recall.Matches(rec(), saved), "a snapshot's mail (the saved shape) matches")
check(not Recall.Matches(rec({ fromName = false }), saved), "a record without fromName matches nothing")
check(not Recall.Matches(rec({ items = false }), saved), "  without items")
check(not Recall.Matches(rec({ money = false }), saved), "  without money (unknown, not 0)")
check(not Recall.Matches(rec({ cod = false }), saved), "  without cod")
-- A snapshot mail whose money (or COD) the Store dropped: two unknowns don't agree.
local function without(field)
    local t = {}
    for k, v in pairs(saved) do t[k] = v end
    t[field] = nil
    return t
end
check(not Recall.Matches(rec({ money = false }), without("money")), "  two unknown moneys don't agree")
check(not Recall.Matches(rec({ cod = false }), without("cod")), "  nor two unknown CODs")
check(not Recall.Matches(rec({ subject = false }), without("subject")), "  nor two unknown subjects")
check(not Recall.Matches(rec({ subject = false }), saved), "  without a subject")
check(not Recall.Matches(rec({ fromName = "" }), saved), "  with a blank sender")
check(not Recall.Matches(rec(), nil), "no mail: no match (never an error)")

--------------------------------------------------------------------------------
-- CanMark
--------------------------------------------------------------------------------

local function why(r) return select(2, Recall.CanMark(r)) end
local ok, name = Recall.CanMark(sent())
check(ok, "a send of items and gold to my alt can be marked")
eq(name, MY_NAME, "  with the sender's name")
eq(select(2, Recall.CanMark(sent({ kind = "return" }))), nil, "a return: no reason (it gets no toggle)")
check(not Recall.CanMark(sent({ kind = "return" })), "  and can't be marked")
eq(why(sent({ subject = false })), Recall.WHY_UNREAD, "a subject that was secret: unreadable")
eq(why(sent({ items = false })), Recall.WHY_UNREAD, "  items")
eq(why(sent({ money = false })), Recall.WHY_UNREAD, "  money")
eq(why(sent({ cod = false })), Recall.WHY_UNREAD, "  cod")
eq(why(sent({ money = 0, items = {} })), Recall.WHY_EMPTY, "a letter alone: nothing attached")
check(Recall.CanMark(sent({ items = {} })), "  money alone can be")
eq(why(sent({ from = "Player-1-ZZZ" })), Recall.WHY_SENDER, "a sender Glass Mail no longer knows")
eq(why(sent({ to = "A Stranger" })), Recall.WHY_RECIPIENT, "a stranger")
eq(why(sent({ to = MY_NAME })), Recall.WHY_RECIPIENT, "  the sender itself")
eq(why(sent({ to = "Ally Person" })), Recall.WHY_REACH:format("Ally Person", MY_NAME), "another faction")
Store.SetChar("Player-1-NO2", { name = "Norealm Two", faction = "Horde", lastPlayDay = 1 })
eq(why(sent({ from = "Player-1-NOR", to = "Norealm Two" })), Recall.WHY_REACH:format("Norealm Two", "Norealm Person"),
    "two unknown realms don't agree")
eq(why(sent({ to = "Pvp Person" })), Recall.WHY_REACH:format("Pvp Person", MY_NAME), "another ruleset")
eq(why(sent({ to = "Norealm Person" })), Recall.WHY_REACH:format("Norealm Person", MY_NAME), "a realm unknown: no agreement")
check(Recall.CanMark(sent({ to = "  kaleid   sumner " })), "the recipient by Names.Key")
ok, name = Recall.CanMark(sent({ from = ALT, to = MY_NAME }))
check(ok, "judged from the record's sender, not the character browsing")
eq(name, ALT_NAME, "  whose name it takes")

rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true },
    GetCharacters = function()
        return { { guid = "Player-1-AST", name = "Stable Alt", realm = "Doomhowl", faction = "Horde", provenance = "self" } }
    end })
eq(#GM.Registry.Characters(), 1, "(AltStable lists its character)")
eq(why(sent({ to = "Stable Alt" })), Recall.WHY_RECIPIENT, "AltStable's characters don't count: it must have run Glass Mail here")
rawset(_G, "AltStable", nil)

--------------------------------------------------------------------------------
-- The Store
--------------------------------------------------------------------------------

db.sent = {}
local r1 = sent()
local seen
Store.OnChange(function()
    if seen == false then seen = { r1.recall, r1.fromName } end
end)
seen = false
check(Recall.Toggle(r1), "Toggle marks a send")
eq(seen and seen[1], true, "  recall set before the watchers run")
eq(seen and seen[2], MY_NAME, "  fromName too")
seen = false
check(Recall.Toggle(r1), "Toggle again unmarks it")
eq(r1.recall, nil, "  recall cleared")
eq(r1.fromName, nil, "  fromName too")
check(seen and seen[1] == nil and seen[2] == nil, "  both before the watchers run")
seen = nil
check(not Store.SetRecall({ kind = "send" }, true, MY_NAME), "SetRecall refuses a record not in Sent")
check(not Store.SetRecall(r1, true, 5), "  and a name that isn't a string")
check(not Recall.Toggle(sent({ to = "A Stranger" })), "Toggle won't mark what CanMark refuses")

db.sent = {
    { kind = "send", day = 1, at = NOW, from = ME, to = ALT_NAME, state = "sent", subject = "ore", money = 500, cod = 0,
      items = { { id = ORE, count = 3 } }, recall = true, fromName = MY_NAME },
    { kind = "send", day = 1, at = NOW, from = ME, to = ALT_NAME, state = "sent", subject = "ore", money = 500, cod = 0,
      items = { { id = ORE, count = 3 } }, recall = true, fromName = 5 },
}
Store.Load()
eq(#Store.Sent(), 2, "a saved recall loads (the record kept)")
eq(Store.Sent()[1].recall, true, "  its mark")
eq(Store.Sent()[1].fromName, MY_NAME, "  and the sender's name")
eq(Store.Sent()[2].fromName, nil, "a junk fromName is dropped alone")
eq(Store.Sent()[2].recall, true, "  the mark survives it")
check(not Recall.Matches(Store.Sent()[2], live(arrived({ items = { [1] = { id = ORE, count = 3 } } }))),
    "  and then matches nothing")
check(Recall.Toggle(Store.Sent()[2]), "  but can still be unmarked")
eq(Store.Sent()[2].recall, nil, "  (unmarked)")

--------------------------------------------------------------------------------
-- The inbox, on the alt
--------------------------------------------------------------------------------

db.sent = {}
local target = sent()
check(Recall.Toggle(target), "marked on the sender")
WoW.playerName = ALT_NAME   -- now the alt plays, with the same account-wide memory
eq(#Recall.Mine(), 1, "the alt sees the recall")
local other = sent({ to = "Bank Alt", subject = "for the bank" })
other.recall, other.fromName = true, MY_NAME
eq(#Recall.Mine(), 1, "  not one for another character")

local notice = I.notice()
local rows = I.rows
local function update() InboxFrame:Update() end
local function hello() return { sender = "Cowruzo Kashmere", subject = "hello" } end

WoW.inbox = { hello(), arrived() }
WoW.fire("MAIL_SHOW")
update()
check(rows[2].tint:IsShown(), "the matching row is tinted")
check(not rows[1].tint:IsShown(), "  the other isn't")
eq(rows[2].tint:GetParent(), InboxFrame, "  our frame")
check(not rows[2].tint:IsMouseEnabled(), "  never taking a click")
local accent = GM.Suite.AccentColor()
local c = rows[2].tint.tex._color
check(c and c[1] == accent[1] and c[2] == accent[2], "  in the accent: sure")
check(notice.frame:IsShown(), "the notice shows")
check(has(notice.text:GetText(), '"ore"') and has(notice.text:GetText(), MY_NAME), "  naming the mail and its sender")
check(notice.ret:IsShown() and notice.ret:IsEnabled(), "  with an enabled Return button")
-- Its place: a strip under the mail window, never inside it, where the footer's
-- Prev / Open All / Next are (PR #51's review: a Return over Next took its click).
local function anchoredBelow(f)
    local top = {}
    for _, p in ipairs(f._points) do top[p[1]] = p end
    local l, r = top.TOPLEFT, top.TOPRIGHT
    return l and r and l[2] == MailFrame and l[3] == "BOTTOMLEFT" and r[2] == MailFrame and r[3] == "BOTTOMRIGHT"
        and l[5] < 0 and r[5] < 0 and #f._points == 2
end
check(anchoredBelow(notice.frame), "the notice hangs under the mail window, its top below the window's bottom")
eq(notice.frame:GetParent(), InboxFrame, "  InboxFrame's child: it goes with the inbox tab")
check(notice.frame:IsMouseEnabled(), "  it takes its own clicks (none fall through)")
local inside = notice.ret
while inside and inside ~= notice.frame do inside = inside:GetParent() end
eq(inside, notice.frame, "  the Return button is inside it")
for _, p in ipairs(notice.ret._points) do
    check(p[2] ~= InboxFrame and p[2] ~= MailFrame, "  and anchored to the strip, not the inbox")
end

-- The tooltip: a recall line even with no attachment lines or truncated subject.
WoW.inbox = { hello(), arrived({ items = { [1] = { id = ORE, count = 3 } } }) }
target.items = { { id = ORE, count = 3 } }
update()
GameTooltip._lines = {}
MailItem2Button.index = 2   -- InboxMixin:Update sets it in the client
InboxFrameItem_OnEnter(MailItem2Button)
check(has(table.concat(GameTooltip._lines or {}, "|"), GM.Inbox.RECALL_SURE), "a recall-only tooltip shows its line")
target.items = { { id = CLOTH, count = 5 }, { id = ORE, count = 3 } }
WoW.inbox = { hello(), arrived() }
update()

-- Disabled while anything else is going on.
WoW.fire("PLAYER_REGEN_DISABLED")
update()
check(not notice.ret:IsEnabled(), "combat: Return disabled")
click(notice.ret)
step()
eq(#WoW.mailCalls, 0, "  a click does nothing")
WoW.fire("PLAYER_REGEN_ENABLED")
OpenMailFrame:Show()
check(not notice.ret:IsEnabled(), "a letter open: disabled")
OpenMailFrame:Hide()
update()
check(notice.ret:IsEnabled(), "  enabled again")

-- Unmarked with the mailbox open: repainted at once.
Recall.Toggle(target)
check(not notice.frame:IsShown(), "unmarked from the window: the notice goes at once")
check(not rows[2].tint:IsShown(), "  and the tint")
Recall.Toggle(target)
check(notice.frame:IsShown() and notice.ret:IsEnabled(), "marked again: back")

-- Nothing acts by itself.
step(1)
WoW.fire("MAIL_INBOX_UPDATE")
step(1)
eq(#WoW.mailCalls, 0, "nothing returns without the click")

-- The click: one return, of that mail; its confirmation ends the recall.
newChat()
click(notice.ret)
step()
eq(#WoW.mailCalls, 1, "Return: one call")
eq(last()[1], "ReturnInboxItem", "  a return")
eq(last()[2], 2, "  of the matching mail")
step(0.2)
WoW.serve(last())
step(0.05)
eq(target.recall, nil, "the confirmed return ends the recall")
local said = table.concat(newChat(), "|")
check(has(said, "sent back to " .. MY_NAME) and has(said, '"ore"'), "  and chat says so")
check(not notice.frame:IsShown(), "  the notice goes")
local back = Store.Sent()[#Store.Sent()]
eq(back.kind, "return", "  Sent records the return")

-- Possible: two mails could be it; twins; a mail still loading; one Blizzard won't return.
db.sent = {}
target = sent()
Recall.Toggle(target)
WoW.mailCalls = {}
WoW.inbox = { arrived(), hello(), arrived({ items = { [1] = { id = ORE, count = 3, link = "|Hitem:2770:1|h[x]|h" },
    [4] = { id = CLOTH, count = 5 } } }) }
step(1)
update()
check(rows[1].tint:IsShown() and rows[3].tint:IsShown(), "two candidates: both tinted")
c = rows[1].tint.tex._color
check(c and c[1] == 1 and c[2] == 0.7, "  amber: possible")
check(not notice.ret:IsShown(), "  no Return button")
check(has(notice.text:GetText(), "2 mails could be"), "  the notice says to check them")
WoW.inbox = { arrived(), arrived() }
update()
check(has(notice.text:GetText(), "identical"), "twins: open one and use its Return button")
check(not notice.ret:IsShown(), "  no button")
WoW.inbox = { arrived({ items = { [1] = { id = ORE, count = 3, link = false }, [4] = { id = CLOTH, count = 5 } } }) }
update()
check(rows[1].tint:IsShown() and not notice.ret:IsShown(), "a mail still loading: possible, no button")
WoW.inbox = { arrived({ canDelete = true }) }
update()
check(rows[1].tint:IsShown() and not notice.ret:IsShown(), "a mail Blizzard won't return: possible, no button")
GameTooltip._lines = {}
MailItem1Button.index = 1
InboxFrameItem_OnEnter(MailItem1Button)
check(has(table.concat(GameTooltip._lines or {}, "|"), GM.Inbox.RECALL_POSSIBLE), "  its tooltip says to check it")

-- Two identical recalls share their one mail: sure, and the return ends the oldest.
db.sent = {}
local first, second = sent(), sent()
Recall.Toggle(first)
Recall.Toggle(second)
WoW.mailCalls = {}
WoW.inbox = { arrived() }
step(1)
update()
check(notice.ret:IsShown() and notice.ret:IsEnabled(), "two identical recalls, one mail: sure")
check(has(notice.text:GetText(), "+1 more"), "  the notice counts the other")
click(notice.ret)
step()
step(0.2)
WoW.serve(last())
step(0.05)
eq(first.recall, nil, "the return ends the oldest")
eq(second.recall, true, "  not the other")

-- A return by hand (Blizzard's letter button) ends it too, through Trash.
WoW.mailCalls = {}
WoW.inbox = { arrived() }
step(1)
WoW.fire("MAIL_INBOX_UPDATE")
step(1)
ReturnInboxItem(1)
step(0.2)
WoW.serve(last())
step(0.05)
eq(second.recall, nil, "a return by hand ends the recall too")

-- A return Trash can't confirm ends nothing.
db.sent = {}
target = sent()
Recall.Toggle(target)
WoW.mailCalls = {}
WoW.inbox = { arrived() }
step(1)
WoW.fire("MAIL_INBOX_UPDATE")
step(1)
ReturnInboxItem(1)
step(6)   -- no answer within Trash's 5 s
eq(target.recall, true, "an unconfirmed return leaves the recall")
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)

--------------------------------------------------------------------------------
-- The Sent folder
--------------------------------------------------------------------------------

WoW.playerName = nil   -- the sender plays again
db.sent, db.snapshots = {}, {}
local T = GM._test.window
local toStranger = sent({ to = "A Stranger", at = NOW - 10 })
local plain = sent({ at = NOW - 5 })
local marked = sent()
Recall.Toggle(marked)
local ret = sent({ kind = "return", to = "Cowruzo Kashmere" })
SlashCmdList.GLASSMAIL("mail")
WoW.advance(0.01)
local ui = T.ui()
-- Newest first: ret, marked, plain, toStranger.
local function row(i) return ui.rows[i] end
check(not row(1).recall:IsShown(), "a return: no toggle")
check(row(2).recall:IsShown() and row(2).recall:IsEnabled(), "a marked send: the toggle, enabled")
check(has(row(2).top:GetText(), "recall"), "  its top line says recall")
eq(row(2).right:GetText(), "not seen yet", "  and where it is: not seen yet")
check(row(3).recall:IsShown() and row(3).recall:IsEnabled(), "a send that can be marked: enabled")
check(not has(row(3).top:GetText(), "recall"), "  not tagged")
check(row(4).recall:IsShown() and not row(4).recall:IsEnabled(), "a send to a stranger: shown, disabled")
row(4).recall._scripts.OnEnter(row(4).recall)
check(has(table.concat(GameTooltip._lines or {}, "|"), Recall.WHY_RECIPIENT), "  its tooltip says why")
eq(row(4).recall:GetMotionScriptsWhileDisabled(), true, "  its motion scripts run while disabled (so that tooltip shows)")
click(row(3).recall)
WoW.advance(0.01)
eq(plain.recall, true, "a click marks it")
check(has(row(3).top:GetText(), "recall"), "  the row repaints")
click(row(3).recall)
WoW.advance(0.01)
eq(plain.recall, nil, "  a second click unmarks it")

-- Seen, from the alt's snapshot.
local function snapshot(mails, complete, at)
    db.snapshots[ALT] = { at = at or NOW + 60, loaded = #mails, total = complete == false and #mails + 5 or #mails,
        complete = complete ~= false, mails = mails }
end
local function savedMail(over)
    local s = { sender = MY_NAME, subject = "ore", money = 500, cod = 0, type = "player", expires = NOW + 30 * 86400,
        items = { { id = ORE, count = 3 }, { id = CLOTH, count = 5 } } }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end
snapshot({ savedMail() })
eq((Recall.Seen(marked)), "in " .. ALT_NAME .. "'s mailbox", "a match in the alt's snapshot: in its mailbox")
snapshot({ savedMail() }, false)
eq((Recall.Seen(marked)), "in " .. ALT_NAME .. "'s mailbox", "  a match in a partial snapshot counts too")
snapshot({ savedMail({ subject = "else" }) }, false)
eq((Recall.Seen(marked)), "not read whole", "no match in a partial one: not read whole")
snapshot({ savedMail({ subject = "else" }) })
local short, long = Recall.Seen(marked)
eq(short, "not found", "no match in a complete one: not found")
check(has(long, "what Glass Mail saved"), "  said of Glass Mail's memory, never of the mailbox")
snapshot({ savedMail() }, true, NOW - 60)
eq((Recall.Seen(marked)), "not seen yet", "a snapshot older than the send: not seen yet")
snapshot({ savedMail(), savedMail({ subject = "else" }) })
Store.ForgetMail(ALT, db.snapshots[ALT].mails[1])
short, long = Recall.Seen(marked)
check(short == "not found" and has(long, "what Glass Mail saved") and not has(long, "not in"),
    "a matching mail forgotten in the window: the memory's wording")
row(2).recall._scripts.OnEnter(row(2).recall)
check(has(table.concat(GameTooltip._lines or {}, "|"), "Click to stop"), "a marked toggle's tooltip offers to stop")

done("test_recall")
