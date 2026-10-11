-- Core/Scan.lua: the inbox as plain values, fingerprints and residuals.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ARROW = { id = 2512, count = 20 }
local ORE = { id = 2770, count = 5 }
WoW.inbox = {
    { sender = "Cowruzo Kashmere", subject = "arrows", money = 100, items = { [1] = ARROW, [2] = ORE } },
    { sender = "Horde Auction House", subject = "Auction canceled: Scroll of Spirit (3)", canReply = false,
      items = { [1] = { id = 1180, count = 3 } } },
    { sender = "Horde Auction House", subject = "Outbid on Copper Ore", money = 500, canReply = false },
    { sender = "The Postmaster", subject = "Recovered Item", canReply = false, items = { [1] = ORE } },
    { sender = "Cowruzo Kashmere", subject = "returned", wasReturned = true, items = { [1] = ORE } },
    { sender = "Gamemaster", subject = "hello", isGM = true },
}
local GM = loadAddon()
local Scan = GM.Scan
local snap = Scan.Inbox()
eq(snap.loaded, 6, "the loaded count")
eq(#snap.mails, 6, "one entry per mail")
local m1 = snap.mails[1]
eq(m1.index, 1, "each mail knows its index")
eq(m1.money, 100, "  its money")
eq(#m1.items, 2, "  its attachments")
eq(m1.items[2].slot, 2, "  each with its slot number")
eq(m1.items[2].itemID, 2770, "  its item ID")
check(m1.resolved and m1.fp ~= nil, "a mail whose links all came back has a fingerprint")
eq(m1.type, "player", "a player's mail")
eq(snap.mails[2].type, "ah", "an AH subject, by template, is AH mail (the count suffix inside %s)")
eq(snap.mails[3].type, "ah", "  an outbid notice too (no trailing period)")
eq(snap.mails[4].type, "system", "not AH and can't be replied to: system mail")
eq(snap.mails[5].type, "player", "a returned mail can be replied to: player mail")
eq(snap.mails[6].type, "system", "a GM's mail is system mail")
eq(snap.mails[6].money, 0, "no money reads as 0")
eq(#snap.mails[6].items, 0, "  no items as an empty list")

-- Slots keep their numbers after a take (session 5).
WoW.inbox[1].items[1] = nil
local after = Scan.Inbox().mails[1]
eq(after.items[1].slot, 2, "slot 2 stays slot 2 when slot 1 empties")

-- An uncached attachment (name "") is still there: occupied by its item ID.
WoW.inbox[1].items[1] = { id = 9999, count = 1, name = "" }
eq(#Scan.Inbox().mails[1].items, 2, "an uncached item still counts as an attachment")

-- A missing link: the mail is unresolved, and so is the scan.
WoW.inbox[1].items[1].link = false
local s2 = Scan.Inbox()
check(not s2.mails[1].resolved and s2.mails[1].fp == nil, "an attachment without a link leaves the mail unresolved")
check(not s2.resolved, "  and the scan with it")
local counted = 0
for _, n in pairs(Scan.Count(s2)) do counted = counted + n end
eq(counted, 5, "  an unresolved mail isn't counted (5 of 6)")
WoW.inbox[1].items[1] = ARROW

-- A secret field: unresolved, and never touched.
WoW.inbox[3].subject = WoW.Secret("subject")
local s3 = Scan.Inbox()
check(not s3.mails[3].resolved, "a secret subject leaves the mail unresolved")
eq(s3.mails[3].type, nil, "  and unclassified")
WoW.inbox[3].subject = "Outbid on Copper Ore"

-- Fingerprints: what identifies a mail, and what doesn't.
local fp = Scan.Inbox().mails[1].fp
WoW.inbox[1].daysLeft = 3.2
WoW.inbox[1].wasRead = true
eq(Scan.Inbox().mails[1].fp, fp, "expiry and read state don't change a fingerprint")
WoW.inbox[1].items[2] = { id = 2770, count = 4 }
check(Scan.Inbox().mails[1].fp ~= fp, "an attachment's count does")
WoW.inbox[1].items[2] = ORE
WoW.inbox[1].wasReturned = true
check(Scan.Inbox().mails[1].fp ~= fp, "  and being returned")
WoW.inbox[1].wasReturned = nil

-- Length-prefixed fields: a delimiter inside a field can't merge two mails.
local a = Scan.Fingerprint({ sender = "A", subject = "1:B", money = 0, cod = 0, items = {} })
local b = Scan.Fingerprint({ sender = "A1:", subject = "B", money = 0, cod = 0, items = {} })
check(a ~= b, "fields can't run into each other")

-- Two identical mails share a fingerprint (session 2): counted, not merged.
WoW.inbox[7] = { sender = "Cowruzo Kashmere", subject = "returned", wasReturned = true, items = { [1] = ORE } }
local s4 = Scan.Inbox()
eq(Scan.Count(s4)[s4.mails[5].fp], 2, "twins are counted twice")
table.remove(WoW.inbox, 7)

-- Residuals: the fingerprint each action should leave behind.
local s5 = Scan.Inbox()
local mail = s5.mails[1]
local afterMoney = Scan.Residual(mail, "money")
WoW.inbox[1].money = 0
eq(Scan.Inbox().mails[1].fp, afterMoney, "after its money: the same mail with money 0")
local afterSlot1 = Scan.Residual(Scan.Inbox().mails[1], "item", 1)
WoW.inbox[1].items[1] = nil
eq(Scan.Inbox().mails[1].fp, afterSlot1, "after slot 1: the same mail without slot 1, slot 2 unmoved")
eq(Scan.Residual(Scan.Inbox().mails[1], "item", 2), Scan.GONE, "taking the last item of a mail without money: gone")
local moneyOnly = Scan.Inbox().mails[3]
check(Scan.Residual(moneyOnly, "money") ~= Scan.GONE, "a money-only mail stays, at money 0 (session 3)")
local withMoney = { sender = "x", subject = "y", money = 5, cod = 0, items = { { slot = 1, link = "l", count = 1 } } }
check(Scan.Residual(withMoney, "item", 1) ~= Scan.GONE, "an item mail still holding money stays")

-- The template patterns: magic characters, positional specifiers, %%.
local T = GM._test.scan
check(("Gewonnen (100%): Ore"):find(T.templatePattern("Gewonnen (100%%): %1$s")) ~= nil,
    "a positional %1$s and a literal %% match")
check(("Outbid on Ore."):find(T.templatePattern("Outbid on %s")) ~= nil, "  a %s takes the rest")
check(("xOutbid on Ore"):find(T.templatePattern("Outbid on %s")) == nil, "  anchored at the start")

-- A missing template global is skipped, not an error.
rawset(_G, "AUCTION_WON_MAIL_SUBJECT", nil)
T.resetPatterns()
eq(Scan.Inbox().mails[2].type, "ah", "a missing template global is skipped")

done("test_scan")
