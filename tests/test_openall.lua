-- I1 Open All: Core/Ops.lua driven through OpenAll.lua's button, against the
-- scripted mail server (WoW.serve answers each recorded call when the test
-- says so).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local FOOD, ORE, ARROW = 6290, 2770, 2512
WoW.itemInfo = { [FOOD] = { maxStack = 20, family = 0 }, [ORE] = { maxStack = 20, family = 0 },
    [ARROW] = { maxStack = 200, family = 1 } }
WoW.bags = { [0] = { size = 16, family = 0, items = {} } }
WoW.now = 100
local function inbox()
    WoW.inbox = {
        { sender = "Cowruzo Kashmere", subject = "supplies", money = 250,
          items = { [1] = { id = FOOD, count = 2 }, [2] = { id = ORE, count = 5 } } },
        { sender = "Horde Auction House", subject = "Auction won: Copper Ore", canReply = false,
          items = { [1] = { id = ORE, count = 3 } } },
    }
end
inbox()
local GM = loadAddon()
local O = GM._test.openAll
local button = O.button()
local function step(dt) WoW.now = WoW.now + (dt or 0.2); WoW.tick(dt or 0.2) end
local function last() return WoW.mailCalls[#WoW.mailCalls] end
local function callText(c) return c and (c[1] .. "(" .. tostring(c[2]) .. (c[3] and (", " .. c[3]) or "") .. ")") end
local function click(b, mouse) b._scripts.OnClick(b, mouse or "LeftButton") end
local function running() return GM.Ops.Running() end

-- The stock button: hidden in mouse mode on every show; ours in its place.
WoW.fire("MAIL_SHOW")
check(not InboxFrame.OpenAllMail:IsShown(), "the stock Open All is hidden at the mailbox")
InboxFrame.OpenAllMail:Show()
check(not InboxFrame.OpenAllMail:IsShown(), "  and again whenever it's shown")
check(button:IsShown(), "ours is shown")
eq(button:GetParent(), InboxFrame, "  in the inbox")
eq(button:GetText(), "Open All", "  labelled Open All")
eq(O.count():GetText(), "2 messages", "the message count")
WoW.inboxTotal = 130
WoW.fire("MAIL_INBOX_UPDATE")
eq(O.count():GetText(), "2 of 130 messages", "  past the loaded window, the server's total too")
WoW.inboxTotal = nil

-- A run: SetOpeningAll(true) after the stock button is hidden; money first.
WoW.openingAll = nil
click(button)
check(running(), "a click starts the run")
eq(WoW.openingAll, true, "  opening-all is on")
check(button:GetText():find("^Stop") ~= nil, "  the button reads Stop (n)")
step()
eq(callText(last()), "TakeInboxMoney(1)", "money first")
step(); step()
eq(#WoW.mailCalls, 1, "one attempt at a time: nothing more until it's confirmed")
WoW.fire("MAIL_INBOX_UPDATE")
step()
eq(#WoW.mailCalls, 1, "an inbox update that changed nothing confirms nothing")

-- The server answers: money 0, the residual the attempt expected.
WoW.serve(last())
eq(GM.Ops.Stats().money, 250, "confirmed: the money counts")
WoW.commandPending = true
step()
eq(#WoW.mailCalls, 1, "a pending mail command holds the next one")
WoW.commandPending = false
step(0.05)
eq(callText(last()), "TakeInboxItem(1, 1)", "then slot 1")

-- Slot 1 taken: slots keep their numbers. The next item waits for the bags.
WoW.serve(last())
eq(GM.Ops.Stats().items, 1, "an item confirmed")
step()
eq(#WoW.mailCalls, 2, "after an item, the next waits for the bags to update")
WoW.fire("BAG_UPDATE_DELAYED")
step()
eq(callText(last()), "TakeInboxItem(1, 2)", "  then slot 2, still slot 2")

-- The last item of a mail without money: the mail may be removed. That is
-- proof only if the loaded count fell: a mail arriving in the same update
-- hides it.
table.remove(WoW.inbox, 1)
table.insert(WoW.inbox, { sender = "New", subject = "arrival" })
WoW.fire("MAIL_INBOX_UPDATE")
step(1.5)
eq(GM.Ops.Stats().items, 1, "the mail gone but another arrived: not confirmed")
eq(#WoW.mailCalls, 3, "  and nothing more dispatched")
table.remove(WoW.inbox)
WoW.fire("MAIL_INBOX_UPDATE")
eq(GM.Ops.Stats().items, 2, "  the loaded count fell: confirmed")

-- A mail whose attachment isn't linked yet confirms nothing.
WoW.inbox[2] = { sender = "X", subject = "late", items = { [1] = { id = FOOD, count = 1, link = false } } }
step(1.1)
eq(callText(last()), "TakeInboxItem(1, 1)", "the AH mail next (the unlinked one is skipped)")
table.remove(WoW.inbox, 1)
WoW.fire("MAIL_INBOX_UPDATE")
eq(GM.Ops.Stats().items, 2, "an unlinked attachment in the inbox: nothing is confirmed")
WoW.inbox[1].items[1].link = nil
WoW.fire("MAIL_INBOX_UPDATE")
eq(GM.Ops.Stats().items, 3, "  once it's linked, the take is")
step(1.1)
eq(callText(last()), "TakeInboxItem(1, 1)", "  and that mail is taken next")
WoW.serve(last())
eq(GM.Ops.Stats().items, 4, "  confirmed")

-- Nothing left: the run ends, opening-all off, one summary line.
newChat()
step(1.1)
check(not running(), "nothing left: the run ends")
eq(WoW.openingAll, false, "  opening-all off")
check(chatHas("took 4 items and 250c"), "  a summary of what was taken")
eq(button:GetText(), "Open All", "  the button reads Open All again")

-- MAIL_FAILED(itemID): that item is skipped, the run goes on.
inbox()
WoW.inbox[1].money = 0
WoW.mailCalls = {}
click(button)
step()
eq(callText(last()), "TakeInboxItem(1, 1)", "a new run")
WoW.fire("MAIL_FAILED", FOOD)
step()
eq(callText(last()), "TakeInboxItem(1, 2)", "a failed item is skipped for the run, the next one taken")
-- A failure with no itemID: uncertain, stop.
WoW.fire("MAIL_FAILED", nil)
check(not running(), "a failure with no item ID stops the run")
check(chatHas("stopped: uncertain"), "  as uncertain")

-- A money failure stops the run.
inbox()
WoW.mailCalls = {}
click(button)
step()
WoW.fire("MAIL_FAILED", nil)
check(not running() and chatHas("stopped: money failed"), "a failed money take stops the run")

-- No answer within 5 s: uncertain, never retried.
inbox()
WoW.mailCalls = {}
click(button)
step()
for _ = 1, 30 do step() end
check(not running(), "an attempt unconfirmed after 5 s stops the run")
eq(#WoW.mailCalls, 1, "  with no retry")

-- Another mail action while we run: ours stops.
inbox()
WoW.mailCalls = {}
click(button)
step()
TakeInboxItem(2, 1)
check(not running() and chatHas("another mail action ran"), "a take that isn't ours stops the run")

-- The mailbox closing, combat, a click on Stop.
for _, case in ipairs({
    { "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17, "mailbox closed" },
    { "PLAYER_REGEN_DISABLED", nil, "combat" },
}) do
    inbox()
    click(button)
    WoW.fire(case[1], case[2])
    check(not running() and chatHas("stopped: " .. case[3]), "the run stops: " .. case[3])
end
WoW.fire("PLAYER_REGEN_ENABLED")
inbox()
click(button)
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
check(running(), "another interaction's HIDE doesn't stop it")
click(button)
check(not running(), "Stop stops it")
WoW.fire("PLAYER_REGEN_DISABLED")   -- InCombatLockdown() is still false here, as on the client
check(not button:IsEnabled(), "the button is disabled in combat")
WoW.combat = true
click(button)
check(not running(), "  and can't start a run")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(button:IsEnabled(), "  enabled again after")

-- Twins (identical mails, session 2): Open All takes both.
WoW.inbox = {
    { sender = "Alt", subject = "arrows", items = { [1] = { id = ORE, count = 2 } } },
    { sender = "Alt", subject = "arrows", items = { [1] = { id = ORE, count = 2 } } },
}
WoW.mailCalls = {}
click(button)
step(); WoW.serve(last()); WoW.fire("BAG_UPDATE_DELAYED")
step(); WoW.serve(last())
step(1.1); step()
eq(#WoW.mailCalls, 2, "both twins taken")
eq(#WoW.inbox, 0, "  the inbox empty")

-- A mail with letter text can stay, empty, after its last item (Blizzard
-- deletes such a mail itself when the letter closes): that's confirmed too,
-- and the run goes on.
WoW.inbox = { { sender = "A", subject = "letter", text = true, items = { [1] = { id = ORE, count = 1 } } },
    { sender = "B", subject = "more", money = 5 } }
WoW.mailCalls = {}
click(button)
step()
WoW.serve(last())
eq(#WoW.inbox, 2, "the emptied letter stays listed")
eq(GM.Ops.Stats().items, 1, "  and its take is confirmed")
step(1.1)
eq(callText(last()), "TakeInboxMoney(2)", "  the run goes on to the next mail")
click(button)

-- Pacing: 0.15 s between two commands, counted from the last dispatch.
WoW.inbox = { { sender = "A", subject = "m1", money = 10 }, { sender = "A", subject = "m2", money = 20 } }
WoW.mailCalls = {}
click(button)
step()
WoW.serve(last())
step(0.05)
eq(#WoW.mailCalls, 1, "a confirmed take still waits 0.15 s before the next")
step(0.15)
eq(callText(last()), "TakeInboxMoney(2)", "  then the next")
click(button)

-- Confirmation needs the acted-on mail gone from its fingerprint AND its
-- residual appearing: either alone is not the take.
WoW.inbox = { { sender = "A", subject = "m1", money = 10 }, { sender = "B", subject = "other" } }
WoW.mailCalls = {}
click(button)
step()
WoW.inbox[3] = { sender = "A", subject = "m1", money = 0 }
WoW.fire("MAIL_INBOX_UPDATE")
eq(GM.Ops.Stats().money, 0, "the residual appearing while the mail is unchanged: not confirmed")
table.remove(WoW.inbox, 3)
table.remove(WoW.inbox, 1)
WoW.fire("MAIL_INBOX_UPDATE")
eq(GM.Ops.Stats().money, 0, "the mail vanishing without its residual: not confirmed")
click(button)

-- Any input-mode transition stops a run, even one that keeps mouse mode.
inbox()
click(button)
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 0)
check(not running() and chatHas("stopped: input mode changed"), "an input-mode transition stops the run")
WoW.gamepad = true
check(not GM.Ops.OpenAll({ types = {}, keepFree = 0 }), "Ops won't start a run in gamepad mode")
WoW.gamepad = false

-- Filters and keepFree from the right-click menu.
click(button, "RightButton")
local items = WoW.menu.items
local function item(text) for _, it in ipairs(items) do if it.text == text then return it end end end
check(item("Auction House") and item("System mail") and item("Player mail"), "the menu lists the three mail types")
check(item("Auction House").isSelected(), "  checked by default")
item("Auction House").setSelected()
eq(GM.db.openAH, false, "  a click unchecks one")
item("5").setSelected(5)
eq(GM.db.keepFree, 5, "keep 5 free, from the menu")
check(item("5").isSelected(5), "  shown selected")
inbox()
WoW.inbox[1].money = 0
WoW.mailCalls = {}
WoW.bags = { [0] = { size = 6, family = 0, items = {} } }   -- 6 free, 5 kept: room for one
click(button)
step()
eq(callText(last()), "TakeInboxItem(1, 1)", "the player's mail")
WoW.serve(last()); WoW.fire("BAG_UPDATE_DELAYED")
WoW.bags[0].items[1] = { id = FOOD, count = 2 }
step()
check(not running(), "  then the reserve is reached and the AH mail is filtered out: done")
check(chatHas("left 1 with no bag room"), "the summary says what was left for lack of room")
GM.Settings.SetOpenFilter("openAH", true)
GM.Settings.SetKeepFree(0)
check(not GM.Settings.SetKeepFree(3), "a reserve that isn't offered is refused")
check(not GM.Settings.SetOpenFilter("openEverything", true), "  and an unknown filter")

-- More mail on the server than loaded: said at the end (no refill in v0.1.0).
WoW.inbox = {}
WoW.inboxTotal = 140
newChat()
click(button)
step()
check(chatHas("More mail waits on the server"), "more mail on the server is mentioned")
WoW.inboxTotal = nil

-- Gamepad UI mode: Blizzard's own Open All, ours hidden; a mode change stops a run.
inbox()
click(button)
check(running(), "a run")
WoW.gamepad = true
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
check(not running(), "an input mode change stops it")
check(not button:IsShown(), "in gamepad mode ours is hidden")
InboxFrame.OpenAllMail:Show()
check(InboxFrame.OpenAllMail:IsShown(), "  and Blizzard's is left alone")
click(button)
check(not running(), "  no run starts in gamepad mode")
WoW.gamepad = false
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
check(button:IsShown() and not InboxFrame.OpenAllMail:IsShown(), "back to mouse mode: ours shown, Blizzard's hidden")
InboxFrame.OpenAllMail:Show()
check(not InboxFrame.OpenAllMail:IsShown(), "  and re-hidden if Blizzard shows it after our handler")

eq(next(GM.failures), nil, "no failures recorded")
done("test_openall")
