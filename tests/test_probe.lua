-- MailProbe smoke test: it loads, registers only real events, installs its
-- hooks, and its read-only commands run against a small fake inbox. What it
-- measures needs the live client; this only keeps it from breaking there.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A fake inbox: two identical mails and one with money. GetInboxHeaderInfo's
-- 15 returns, in Blizzard's order (MailFrame.lua).
local ORE = { "Copper Ore", 2770, 20, "|Hitem:2770|h[Copper Ore]|h" }
local inbox = {
    { sender = "Karuzo Morphisto", subject = "ore", money = 0, items = { ORE } },
    { sender = "Karuzo Morphisto", subject = "ore", money = 0, items = { ORE } },
    { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 1500, items = {} },
}
local calls = {}
local total   -- the server's count, when more than the loaded window
rawset(_G, "GetInboxNumItems", function() return #inbox, total or #inbox end)
rawset(_G, "GetInboxHeaderInfo", function(i)
    local m = inbox[i]
    if m then return nil, nil, m.sender, m.subject, m.money, 0, 29.5, #m.items > 0 and #m.items or nil, false,
        false, false, m.canReply ~= false, false, nil, nil end
end)
rawset(_G, "GetInboxItem", function(i, a)
    local it = inbox[i] and inbox[i].items[a]
    if it then return it[1], it[2], 134, it[3], 1, true, false end
end)
rawset(_G, "GetInboxItemLink", function(i, a)
    local it = inbox[i] and inbox[i].items[a]
    return it and it[4]
end)
rawset(_G, "GetInboxInvoiceInfo", function() return nil end)
rawset(_G, "GetInboxText", function() end)
rawset(_G, "TakeInboxItem", function(i, a) table.insert(calls, "take " .. i .. ":" .. a) end)
rawset(_G, "HasNewMail", function() return false end)
rawset(_G, "GetLatestThreeSenders", function() end)
rawset(_G, "GetMoney", function() return WoW.Secret("money") end)
rawset(_G, "C_Mail", { CanCheckInbox = function() return true, 0 end, IsCommandPending = function() return false end,
    SetOpeningAll = function() end })
-- Bags 0-3 general, bag 4 a quiver (family 1); 15 ore in bag 0 slot 1.
rawset(_G, "C_Container", { CalculateTotalNumberOfFreeBagSlots = function() return 12 end,
    GetContainerNumSlots = function(bag) return bag <= 4 and 16 or 0 end,
    GetContainerNumFreeSlots = function(bag) if bag == 4 then return 5, 1 end return 3, 0 end,
    GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 1 then return { itemID = 2770, stackCount = 15 } end
    end })
rawset(_G, "C_Item", { GetItemMaxStackSizeByID = function(id) return id == 2512 and 200 or 20 end,
    GetItemFamily = function(id) return id == 2512 and 1 or 0 end,
    GetItemCount = function(id) return id == 2770 and 15 or 0 end,
    GetItemInfo = function(id) if id == 2770 then return "Copper Ore" end end })
rawset(_G, "AUCTION_SOLD_MAIL_SUBJECT", "Auction successful: %s")
rawset(_G, "AUCTION_OUTBID_MAIL_SUBJECT", "Outbid on %s.")
local indicatorFrame = CreateFrame("Frame")
indicatorFrame:Hide()
rawset(_G, "MinimapCluster", { IndicatorFrame = { MailFrame = indicatorFrame } })
rawset(_G, "Enum", { PlayerInteractionType = { MailInfo = 17 } })
rawset(_G, "MailProbeDB", nil)

assert(loadfile("Tools/MailProbe/MailProbe.lua"))("MailProbe", {})
WoW.fire("ADDON_LOADED", "MailProbe")
WoW.fire("PLAYER_LOGIN")
eq(type(MailProbeDB), "table", "the probe's log table exists")
eq(MailProbeDB.loads, 1, "it counts sessions")
check(chatHas("C ReturnInboxItem: MISSING"), "a mail call the client lacks is reported")
newChat()
TakeInboxItem(3, 2)
check(chatHas("C TakeInboxItem%(3, 2%)"), "a call to a hooked mail function is logged, whoever makes it")
eq(calls[1], "take 3:2", "and still happens")
table.remove(calls, 1)

newChat()
SlashCmdList.MAILPROBE("state")
check(chatHas("money secret=true"), "state reports a secret GetMoney without touching it")
SlashCmdList.MAILPROBE("inbox")
check(chatHas('sender="Karuzo Morphisto"'), "inbox lists senders as the client gives them")
check(chatHas("slot 1: \"Copper Ore\" id=2770 count=20"), "inbox lists attachments")
SlashCmdList.MAILPROBE("dupes")
check(chatHas("mail 2 looks identical to mail 1"), "dupes finds two identical mails")
check(chatHas("1 identical pair"), "and only those")
SlashCmdList.MAILPROBE("bags")
check(chatHas("total free 12"), "bags reports free space")
SlashCmdList.MAILPROBE("taketimer 1")
eq(calls[1], "take 1:1", "taketimer takes the first attachment from the key press")
SlashCmdList.MAILPROBE("")
check(chatHas("/mailprobe state"), "help lists the commands")
-- Not /mprobe: MagelyProbe owns that one (Magely/Tools/MagelyProbe).
eq(SLASH_MAILPROBE1, "/mailprobe", "the probe's command is /mailprobe")

-- The mailbox lifecycle is logged, filtered to the mailbox interaction.
newChat()
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17)
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
WoW.fire("MAIL_SHOW")
local lines = newChat()
eq(#lines, 2, "the mailbox interaction and MAIL_SHOW are logged, another interaction isn't")
check(#MailProbeDB.log > 0, "every line is kept in the log")

-- The open time is logged on the interaction HIDE (MAIL_CLOSED never fires),
-- once even when HIDE fires twice, as it does at logout.
local function durations()
    local n = 0
    for _, l in ipairs(newChat()) do if l:find("mailbox was open") then n = n + 1 end end
    return n
end
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
eq(durations(), 1, "the open time is logged once on HIDE, not again on a second HIDE")
-- Without the enum, the measured type 17 still counts as the mailbox.
rawset(_G, "Enum", {})
WoW.fire("MAIL_SHOW")
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
eq(durations(), 1, "with no MailInfo enum, HIDE 17 still closes the mailbox")

-- Session 5 (M1). The AH subject templates, and which one a subject matches.
newChat()
SlashCmdList.MAILPROBE("strings")
check(chatHas('AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %%s"'), "strings lists the client's templates")
check(chatHas("2 AUCTION_%*_MAIL_SUBJECT"), "  all of them")
SlashCmdList.MAILPROBE("inbox")
check(chatHas('AH template="AUCTION_SOLD_MAIL_SUBJECT"'), "inbox names the template an AH subject matches")
check(chatHas('link="|Hitem:2770|h%[Copper Ore%]|h"'), "inbox logs each attachment's link")
inbox[4] = { sender = "Auction House", subject = "Outbid on Linen Cloth", money = 0, items = {} }
newChat()
SlashCmdList.MAILPROBE("inbox")
check(chatHas("AH template=nil"), "a template's punctuation is literal: no final '.', no match")
inbox[4] = nil

-- New mail: HasNewMail and the minimap indicator, passively.
newChat()
WoW.fire("UPDATE_PENDING_MAIL")
check(chatHas("hasNewMail=false .* minimap indicator shown=false"), "UPDATE_PENDING_MAIL logs new mail and the indicator")

-- watch: every mail once, then only what an update changed.
WoW.fire("MAIL_INBOX_UPDATE")   -- settle the I line
newChat()
SlashCmdList.MAILPROBE("watch on")
check(chatHas('W 1: "Karuzo Morphisto" "ore" .* %[1:|Hitem:2770'), "watch logs each mail with its slots")
newChat()
inbox[3].money = 0
WoW.fire("MAIL_INBOX_UPDATE")
local w = newChat()
eq(#w, 1, "an update logs only the mail it changed")
check(w[1] and w[1]:find("W 3: .*money=0"), "  with its new state")
table.remove(inbox, 3)
newChat()
WoW.fire("MAIL_INBOX_UPDATE")
check(chatHas("W 3: %(none%)"), "a mail that went is logged as gone")
SlashCmdList.MAILPROBE("watch off")
inbox[3] = { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 1500, items = {} }

-- fit: what I1's per-item fit rule would see.
inbox[4] = { sender = "Cowruzo Test", subject = "arrows", money = 0,
    items = { { "Sharp Arrow", 2512, 200, "|Hitem:2512|h[Sharp Arrow]|h" } } }
newChat()
SlashCmdList.MAILPROBE("fit 1")
check(chatHas("fit 1 slot 1: id=2770 x20 maxStack=20 family=0 held=15 cached=true room in partial stacks=5 "
    .. "specialty free=0"), "fit: room in a partial stack, no specialty bag for ore")
SlashCmdList.MAILPROBE("fit 4")
check(chatHas("fit 4 slot 1: .* family=1 .* cached=false .* specialty free=5"), "fit: a quiver's free slots for arrows")

-- refill: CheckInbox when allowed, and the time to the next update.
local checked = 0
rawset(_G, "CheckInbox", function() checked = checked + 1 end)
total = 140
newChat()
SlashCmdList.MAILPROBE("refill")
eq(checked, 1, "refill calls CheckInbox when allowed")
WoW.fire("MAIL_INBOX_UPDATE")
check(chatHas("refill: MAIL_INBOX_UPDATE .* after CheckInbox, loaded=4 total=140"), "  and logs the next update")
newChat()
WoW.fire("MAIL_INBOX_UPDATE")
eq(#newChat(), 0, "  once")
WoW.flushTimers()
C_Mail.CanCheckInbox = function() return false, 42 end
SlashCmdList.MAILPROBE("refill")
eq(checked, 1, "refill waits while the client says not yet")
check(chatHas("again in 42 s"), "  and says how long")
total = nil

-- returnmany: each found again by fingerprint, the rest from timers.
local returned = {}
rawset(_G, "ReturnInboxItem", function(i)
    returned[#returned + 1] = inbox[i].subject
    table.remove(inbox, i)
end)
inbox[5] = { sender = "Cowruzo Test", subject = "a", money = 0, items = {} }
inbox[6] = { sender = "Cowruzo Test", subject = "b", money = 0, items = {} }
newChat()
SlashCmdList.MAILPROBE("returnmany 1 5")
eq(#returned, 0, "returnmany refuses a mail with an identical twin")
check(chatHas("mail 1 has an identical twin"), "  and says so")
inbox[6].items = { { "Mystery", 99999, 1, nil } }
SlashCmdList.MAILPROBE("returnmany 5 6")
eq(#returned, 0, "returnmany refuses a mail with an unloaded attachment link")
inbox[6].items = {}
newChat()
SlashCmdList.MAILPROBE("returnmany 5 6")
eq(returned[1], "a", "the first return is made from the key press")
check(chatHas("returning from the key press"), "  and logged as such")
for _ = 1, 6 do WoW.flushTimers(0.5) end
eq(returned[2], "b", "the next mail is found again after the index shift and returned from a timer")
check(chatHas("mail %(was 6%) is now 5.*from a timer"), "  at its new index")
check(chatHas("done, 2 mail"), "returnmany finishes")
eq(#returned, 2, "  with nothing else returned")

-- rows: T / R / D on each row, children of InboxFrame, in and out of combat.
rawset(_G, "TakeInboxMoney", function(i) calls[#calls + 1] = "money " .. i end)
rawset(_G, "DeleteInboxItem", function(i) calls[#calls + 1] = "delete " .. i end)
rawset(_G, "InboxItemCanDelete", function() return true end)
inbox = {
    { sender = "Karuzo Morphisto", subject = "ore", money = 0, items = { ORE } },
    { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 1500, items = {} },
}
newChat()
SlashCmdList.MAILPROBE("rows on")
local function button(text, row)
    for _, f in ipairs(WoW.frames) do
        if f:GetParent() == InboxFrame and f.GetText and f:GetText() == text then
            local _, rel = f:GetPoint(1)
            if rel == _G["MailItem" .. row] then return f end
        end
    end
end
check(button("T", 2) and button("R", 2) and button("D", 2), "rows: three buttons per row, children of InboxFrame")
check(button("T", 2):GetFrameLevel() > MailItem2:GetFrameLevel(), "  above the row")
calls = {}
WoW.combat = true
button("T", 2)._scripts.OnClick(button("T", 2))
eq(calls[1], "money 2", "T takes the row's money")
check(chatHas("combat=true"), "  and logs whether in combat")
WoW.combat = false
button("D", 1)._scripts.OnClick(button("D", 1))
eq(calls[2], nil, "D never deletes a mail with items")
inbox[2].money = 0
button("D", 2)._scripts.OnClick(button("D", 2))
eq(calls[2], "delete 2", "D deletes an empty mail")
inbox[2].canReply = false
returned = {}
button("R", 2)._scripts.OnClick(button("R", 2))
eq(#returned, 0, "R never returns a mail that can't be replied to")
SlashCmdList.MAILPROBE("rows off")
check(not button("T", 1):IsShown(), "rows off hides them")

done("test_probe")
