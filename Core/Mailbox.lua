-- Core/Mailbox.lua: GlassMail's Scan, Summary and Names, over the embedded
-- LibMailbox-1.0 (M3, docs/PLAN.md; the library's docs/DESIGN.md is the
-- contract). The names and signatures the rest of the addon calls stay as they
-- were; the logic lives in the library.
--
-- Every call looks the library's function up when it runs (a newer embedded
-- copy, another addon's, replaces them on the same table), and first asks
-- LM.Ready(): a newer copy that failed half-way leaves it false, and then
-- nothing is read. An unreadable scan, an empty count, no summary, no name:
-- the callers already handle each (a secret did the same).

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local LM = LibStub and LibStub("LibMailbox-1.0", true)
if not LM then API.Fail("LibMailbox", "LibMailbox-1.0 isn't loaded") end

local Scan, Summary, Names = {}, {}, {}
GM.Scan, GM.Summary, GM.Names = Scan, Summary, Names

local function ready() return LM ~= nil and LM.Ready() end

-- The scan when the library can't be used: unknown, never "empty".
local function unreadable() return { loaded = 0, total = 0, mails = {}, resolved = false, headers = false } end

-- The loaded inbox: { loaded, total, mails, resolved, headers } (LM.ScanInbox).
function Scan.Inbox()
    if not ready() then return unreadable() end
    return LM.ScanInbox()
end

-- { [fp] = n } over the resolved mails.
function Scan.Count(snap)
    if not ready() then return {} end
    return LM.Count(snap)
end

-- The fingerprint a take should leave, and whether it may empty the mail out.
function Scan.Residual(m, kind, slot)
    if not ready() then return nil, false end
    return LM.Residual(m, kind, slot)
end

function Scan.Fingerprint(m)
    if not ready() then return nil end
    return LM.Fingerprint(m)
end

-- { count, money, soonest } over a snapshot's mails at `now` (Core/Memory.lua
-- saves `expires`: the library's saved shape), or nil when none counts.
function Summary.Of(snapshot, now)
    if type(snapshot) ~= "table" or type(snapshot.mails) ~= "table" then return nil end
    if not ready() then return nil end
    return LM.Summary(snapshot.mails, now)
end

-- The comparison key and the display form of a mail address; nil when secret,
-- not a string, blank, or the library can't be used.
function Names.Key(name)
    if not ready() then return nil end
    return LM.NameKey(name)
end

function Names.Display(name)
    if not ready() then return nil end
    return LM.NameDisplay(name)
end
