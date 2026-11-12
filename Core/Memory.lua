-- Core/Memory.lua: X1, each character's mailbox as last seen (the window's
-- Inbox folder). PLAN.md, "The window PR in detail".
--
-- A visit runs from MAIL_SHOW to the mailbox's close (interaction type 17).
-- Each MAIL_INBOX_UPDATE in it, the first included, schedules one scan a frame
-- later, for that visit only (update, close, reopen: the old callback does
-- nothing). Assumed, checked in game before v0.2.0: the first update carries
-- this visit's inbox; the debug line logs each scan for that check.
-- A scan replaces the character's snapshot only when it read every loaded mail
-- whole; else the previous one stays. A readable loaded subset (over 100
-- mails) is the newest truth and is taken, marked incomplete. No letter text,
-- ever (GetInboxText marks mail read).

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Scan, Store, Registry, Names = GM.Scan, GM.Store, GM.Registry, GM.Names
local Memory = {}
GM.Memory = Memory

local MAILBOX = 17           -- Enum.PlayerInteractionType.MailInfo
local DAY = 86400

local visits = 0             -- a number per visit
local visit                  -- the open visit's number, or nil
local queued                 -- the visit a scan is already queued for

-- Every loaded mail read whole: resolved (no secret, every attachment linked),
-- one mail per loaded index, a number of days left, and as many attachments
-- as its header says (nil there means none).
local function whole(snap)
    if not snap.resolved or #snap.mails ~= snap.loaded then return false end
    for _, m in ipairs(snap.mails) do
        if type(m.daysLeft) ~= "number" then return false end
        if #m.items ~= (m.itemCount or 0) then return false end
    end
    return true
end

local function items(m)
    local out = {}
    for _, it in ipairs(m.items) do
        -- A currency's ID isn't an itemID: left out.
        if not it.isCurrency then out[#out + 1] = { id = it.itemID, count = it.count } end
    end
    return out
end

local function take()
    local guid = Registry.CurrentGUID()
    if not guid or not Store.Ready() then return end
    local snap = Scan.Inbox()
    API.Debug(("mailbox scan, visit %d: %d of %d loaded, first from %s%s"):format(visit, snap.loaded, snap.total,
        snap.mails[1] and snap.mails[1].sender or "-", whole(snap) and "" or ", not whole: kept the old one"))
    if not whole(snap) then return end
    local now = time()
    local mails = {}
    for _, m in ipairs(snap.mails) do
        mails[#mails + 1] = { sender = Names.Display(m.sender), subject = m.subject, money = m.money, cod = m.cod,
            expires = math.floor((now + m.daysLeft * DAY) / 60) * 60, type = m.type,
            wasReturned = m.wasReturned, items = items(m) }
    end
    Store.SetSnapshot(guid, { at = now, loaded = snap.loaded, total = snap.total,
        complete = snap.loaded == snap.total, mails = mails })
end

local function onUpdate()
    local v = visit
    if not v or queued == v then return end
    queued = v
    C_Timer.After(0, function()
        if queued == v then queued = nil end
        if visit ~= v then return end
        local ok, err = pcall(take)
        if not ok then API.Fail("memory scan", err) end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "MAIL_SHOW" then
        visits = visits + 1
        visit = visits
    elseif event == "MAIL_INBOX_UPDATE" then
        onUpdate()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if arg1 == MAILBOX then visit = nil end
    end
end)
API.RegisterEvents(events, { "MAIL_SHOW", "MAIL_INBOX_UPDATE", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" })

GM._test = GM._test or {}
GM._test.memory = { whole = whole, visit = function() return visit end }
