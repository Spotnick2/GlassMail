-- Core/Mailbox.lua without LibMailbox-1.0 loaded (a broken package): the
-- failure is recorded, and every adapter reads nothing instead of erroring.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local lines = tocLines
tocLines = function()
    local out = {}
    for _, line in ipairs(lines()) do
        if line ~= LIBMAILBOX_XML then out[#out + 1] = line end
    end
    return out
end
WoW.inbox = { { sender = "A", subject = "s", money = 5 } }
local GM = loadAddon()
check(GM.failures.LibMailbox ~= nil, "LibMailbox missing: the failure is recorded")
local s = GM.Scan.Inbox()
check(s.headers == false and #s.mails == 0, "  Scan.Inbox: unreadable")
eq(next(GM.Scan.Count(s)), nil, "  Scan.Count: empty")
eq(GM.Summary.Of({ mails = {} }, 0), nil, "  Summary.Of: nil")
eq(GM.Names.Key("A B"), nil, "  Names.Key: nil")
done("test_mailbox_missing")
