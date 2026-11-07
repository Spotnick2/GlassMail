-- Core/Trash.lua: X2's Trash folder (deleted mail, kept until it would have
-- expired), and the returns Sent records ("returned to").
--
-- Every DeleteInboxItem / ReturnInboxItem, ours or anyone's (the letter's
-- buttons, the delete popup, our row icons), is captured at its post-hook from
-- a fresh scan of that index: session 6 found the mail still there 5 of 5,
-- and the update that removes it 0.12-0.37 s later. A capture is kept only
-- when the inbox proves it:
-- - not when an inbox update came in the same frame (it may have come inside
--   the call, and the index may already hold the next mail);
-- - not while an earlier inbox call is unsettled: every inbox-changing call
--   marks the inbox unsettled, and only a MAIL_INBOX_UPDATE with no command
--   pending (C_Mail.IsCommandPending) settles it. No timeout does;
-- - one capture at a time; any later inbox-changing call drops one still
--   outstanding (a take that empties a mail can't pass for its return);
-- - confirmed when an update within 5 s shows its fingerprint's count and the
--   loaded count each one fewer, committed a frame later so a call in between
--   can still void it. Otherwise dropped.
-- Removals left out are left out: Trash holds what Glass Mail saw. Takes by
-- hand aren't recorded.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Store, Scan, Registry, Sent = GM.Store, GM.Scan, GM.Registry, GM.Sent
local Trash = {}
GM.Trash = Trash

Trash.TIMEOUT = 5
local DAY = 86400

local unsettled = false      -- an inbox call is in flight
local lastUpdate             -- GetTime() of the last MAIL_INBOX_UPDATE
local capture                -- the outstanding removal, or nil

local function items(m)
    local out = {}
    for _, it in ipairs(m.items) do out[#out + 1] = { id = it.itemID, count = it.count } end
    return out
end

local function take(kind, index)
    local t = GetTime()
    local can = not unsettled and lastUpdate ~= t and Store.Ready()
    capture = nil            -- any later call voids an outstanding capture
    unsettled = true
    if not can or (kind ~= "delete" and kind ~= "return") then return end
    if API.IsSecret(index) or type(index) ~= "number" then return end
    local snap = Scan.Inbox()
    local m
    for _, mail in ipairs(snap.mails) do if mail.index == index then m = mail end end
    if not (m and m.fp and m.resolved) then return end
    local c = { kind = kind, mail = m, fp = m.fp, before = Scan.Count(snap)[m.fp], loaded = snap.loaded,
        deadline = t + Trash.TIMEOUT, from = Registry.CurrentGUID(), at = time(),
        expires = time() + math.floor((tonumber(m.daysLeft) or 0) * DAY) }
    capture = c
    C_Timer.After(Trash.TIMEOUT, function()
        if capture == c then capture = nil end
    end)
end

local function commit(c)
    local m = c.mail
    if c.kind == "delete" then
        Store.AddTrash({ at = c.at, from = c.from, sender = m.sender, subject = m.subject, money = m.money,
            cod = m.cod, items = items(m), expires = c.expires })
    else
        Sent.AddReturn(m, items(m))
    end
end

local function onUpdate()
    local t = GetTime()
    lastUpdate = t
    local c = capture
    if c and t <= c.deadline then
        local snap = Scan.Inbox()
        if snap.resolved and (Scan.Count(snap)[c.fp] or 0) == c.before - 1 and snap.loaded == c.loaded - 1 then
            -- A frame later: a call's post-hook in between still voids it.
            C_Timer.After(0, function()
                if capture ~= c then return end
                capture = nil
                commit(c)
            end)
        end
    end
    local pending = C_Mail.IsCommandPending()
    API.Debug("inbox update, command pending: " .. tostring(pending))
    if not API.IsSecret(pending) and pending == false then unsettled = false end
end

local KINDS = { TakeInboxItem = "take", TakeInboxMoney = "take", AutoLootMailItem = "take",
    ReturnInboxItem = "return", DeleteInboxItem = "delete" }
for fn, kind in pairs(KINDS) do
    if type(rawget(_G, fn)) == "function" then
        hooksecurefunc(fn, function(index)
            local ok, err = pcall(take, kind, index)
            if not ok then API.Fail("trash " .. fn, err) end
        end)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    local ok, err = pcall(onUpdate)
    if not ok then API.Fail("trash update", err) end
end)
API.RegisterEvents(events, { "MAIL_INBOX_UPDATE" })

-- The last n Trash entries, oldest first, one line each.
function Trash.Lines(n)
    local trash, lines, now = Store.Trash(), {}, time()
    for i = math.max(1, #trash - n + 1), #trash do
        local e = trash[i]
        local days = math.max(0, math.ceil((e.expires - now) / DAY))
        lines[#lines + 1] = date("%m-%d %H:%M", e.at) .. " " .. Sent.CharName(e.from) .. " deleted mail from "
            .. (e.sender or "?") .. Sent.Contents(e) .. ", gone in " .. days .. (days == 1 and " day" or " days")
    end
    return lines
end

GM._test = GM._test or {}
GM._test.trash = {
    state = function() return { unsettled = unsettled, lastUpdate = lastUpdate, capture = capture } end,
}
