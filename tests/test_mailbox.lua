-- Core/Mailbox.lua: GlassMail's Scan, Summary and Names over LibMailbox-1.0.
-- The logic is tested in the library (its tests/); here, that the adapters
-- pass through, and that a newer embedded copy which failed half-way (Ready()
-- false) leaves every caller reading nothing, without an error (PLAN.md, M3).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ORE = { id = 2770, count = 5 }
WoW.inbox = {
    { sender = "Cowruzo Kashmere", subject = "ore", money = 100, items = { [1] = ORE } },
    { sender = "Horde Auction House", subject = "Outbid on Copper Ore", money = 500, canReply = false },
}
local GM = loadAddon()
local Scan, Summary, Names = GM.Scan, GM.Summary, GM.Names
local LM = LibStub("LibMailbox-1.0")
eq(GM.failures.LibMailbox, nil, "the library is loaded")
check(LM.Ready(), "  and ready")

-- Passing through.
local snap = Scan.Inbox()
eq(#snap.mails, 2, "Scan.Inbox: the library's scan")
check(snap.headers and snap.resolved, "  whole")
eq(snap.mails[2].type, "ah", "  classified")
eq(Scan.Count(snap)[snap.mails[1].fp], 1, "Scan.Count")
eq(Scan.Fingerprint(snap.mails[1]), snap.mails[1].fp, "Scan.Fingerprint")
local fp, gone = Scan.Residual(snap.mails[1], "item", 1)
check(type(fp) == "string" and gone == false, "Scan.Residual: a mail still holding money stays")
local NOW = time()
local s = Summary.Of({ mails = { { expires = NOW + 60, money = 5, items = {} }, { expires = NOW + 120, money = 0,
    items = { { itemID = 1, count = 1 } } } } }, NOW)
check(s and s.count == 2 and s.money == 5 and s.soonest == NOW + 60, "Summary.Of: the saved shape")
eq(Summary.Of(nil, NOW), nil, "  no snapshot: nil")
eq(Summary.Of({}, NOW), nil, "  a snapshot without mails: nil")
eq(Names.Key("  Kaleid  Sumner "), "kaleid sumner", "Names.Key")
eq(Names.Display("  Kaleid Sumner "), "Kaleid Sumner", "Names.Display")

-- A newer copy (another addon's) that errors after claiming its minor.
local src = readLibMailbox()
local half = src:gsub('local MAJOR, MINOR = "LibMailbox%-1%.0", (%d+)', function(n)
    return 'local MAJOR, MINOR = "LibMailbox-1.0", ' .. (tonumber(n) + 1)
end):gsub("\nlib%.ready = MINOR", '\nerror("half-loaded")\nlib.ready = MINOR')
check(not pcall(assert(loadstring(half, "=half"))), "a newer copy fails half-way")
check(not LM.Ready(), "  Ready is false")
local u = Scan.Inbox()
check(u.loaded == 0 and #u.mails == 0 and u.resolved == false and u.headers == false,
    "Scan.Inbox: an unreadable scan, never an empty inbox")
eq(next(Scan.Count(u)), nil, "Scan.Count: empty")
local rfp, rgone = Scan.Residual(snap.mails[1], "money")
check(rfp == nil and rgone == false, "Scan.Residual: nothing")
eq(Scan.Fingerprint(snap.mails[1]), nil, "Scan.Fingerprint: nothing")
eq(Summary.Of({ mails = { { expires = NOW + 60, money = 5, items = {} } } }, NOW), nil, "Summary.Of: nil")
eq(Names.Key("Kaleid Sumner"), nil, "Names.Key: nil")
eq(Names.Display("Kaleid Sumner"), nil, "Names.Display: nil")
-- The callers: Inbox.lua's refresh (Scan.Inbox then Scan.Count), the grid, Open All's count, a snapshot.
GM.failures = GM.failures or {}
local before = 0
for _ in pairs(GM.failures) do before = before + 1 end
MailFrame:Show()
WoW.fire("MAIL_SHOW")
WoW.fire("MAIL_INBOX_UPDATE")
local ok, err = pcall(InboxFrame.Update, InboxFrame)
check(ok, "the inbox's refresh goes through without an error: " .. tostring(err))
WoW.tick()
local after = 0
for _ in pairs(GM.failures) do after = after + 1 end
eq(after, before, "  and records no failure")
eq(GM.Store.Snapshots()[WoW.playerGUID], nil, "  no snapshot from an unreadable inbox")

done("test_mailbox")
