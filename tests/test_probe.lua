-- MailProbe smoke test: it loads, registers only real events, installs its
-- hooks, and its read-only commands run against a small fake inbox. What it
-- measures needs the live client; this only keeps it from breaking there.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A fake inbox: two identical mails and one with money. GetInboxHeaderInfo's
-- 15 returns, in Blizzard's order (MailFrame.lua).
local inbox = {
    { sender = "Karuzo Morphisto", subject = "ore", money = 0, items = { { "Copper Ore", 2770, 20 } } },
    { sender = "Karuzo Morphisto", subject = "ore", money = 0, items = { { "Copper Ore", 2770, 20 } } },
    { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 1500, items = {} },
}
local calls = {}
rawset(_G, "GetInboxNumItems", function() return #inbox, #inbox end)
rawset(_G, "GetInboxHeaderInfo", function(i)
    local m = inbox[i]
    if m then return nil, nil, m.sender, m.subject, m.money, 0, 29.5, #m.items, false, false, false, true, false,
        nil, nil end
end)
rawset(_G, "GetInboxItem", function(i, a)
    local it = inbox[i] and inbox[i].items[a]
    if it then return it[1], it[2], 134, it[3], 1, true, false end
end)
rawset(_G, "GetInboxInvoiceInfo", function() return nil end)
rawset(_G, "GetInboxText", function() end)
rawset(_G, "TakeInboxItem", function(i, a) table.insert(calls, "take " .. i .. ":" .. a) end)
rawset(_G, "HasNewMail", function() return false end)
rawset(_G, "GetLatestThreeSenders", function() end)
rawset(_G, "GetMoney", function() return WoW.Secret("money") end)
rawset(_G, "C_Mail", { CanCheckInbox = function() return true, 0 end, IsCommandPending = function() return false end,
    SetOpeningAll = function() end })
rawset(_G, "C_Container", { CalculateTotalNumberOfFreeBagSlots = function() return 12 end,
    GetContainerNumSlots = function(bag) return bag <= 4 and 16 or 0 end,
    GetContainerNumFreeSlots = function() return 3, 0 end })
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
check(chatHas("/mprobe state"), "help lists the commands")

-- The mailbox lifecycle is logged, filtered to the mailbox interaction.
newChat()
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17)
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
WoW.fire("MAIL_SHOW")
local lines = newChat()
eq(#lines, 2, "the mailbox interaction and MAIL_SHOW are logged, another interaction isn't")
check(#MailProbeDB.log > 0, "every line is kept in the log")

done("test_probe")
