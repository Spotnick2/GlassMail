-- Core/Sent.lua: X2's Sent folder, the record of every send and every return
-- Glass Mail could identify. Recent recipients come from here.
--
-- Capture at the SendMail post-hook (the only caller is Blizzard's Send, the
-- gamepad footer included; the draft is still filled there, session 6). A
-- record is a candidate until its outcome is known; nothing in the client
-- says which send a result belongs to, so attribution is by time:
-- - each SendMail opens a 120 s window for its record (the slowest result
--   ever seen took 99 s, sessions 2-3; session 6: under 1 s, 11 s for a
--   stranger confirmed by hand);
-- - MAIL_SEND_SUCCESS confirms a record only when it is the one candidate:
--   `sent`. Two candidates: neither (never the wrong one);
-- - a window that ends unconfirmed saves the record `unconfirmed`: "where did
--   I send that?" needs it too;
-- - a stranger's confirmation (SECURE_TRANSFER_CONFIRM_SEND_MAIL, inside
--   SendMail) has no timeout: such a record is a candidate with no limit
--   until the dialog closes, which calls SendMailFrame_EnableSendMailButton
--   (Blizzard_SecureTransferUIOutbound.lua:8-10); its window starts then;
-- - the client's refusal of a name (UI_ERROR_MESSAGE 457, in SendMail's
--   frame) drops the record unsaved: the mail never left;
-- - MAIL_FAILED says nothing about whose action failed, and
--   SECURE_TRANSFER_CANCEL fires on every close and reload: neither is used.
-- At logout, every candidate is saved `unconfirmed`; a /reload starts empty.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Store, Names, Registry = GM.Store, GM.Names, GM.Registry
local Sent = {}
GM.Sent = Sent

Sent.WINDOW = 120
-- Address.lua's fill: called with the recipient's key once an attributed send
-- has set lastTo (Sent.onConfirmed = fn).
Sent.onConfirmed = nil
local REFUSED = 457          -- "Please enter a full character name." (session 6)

local open = {}              -- the candidates, oldest first
local confirmAt              -- GetTime() of the last stranger confirmation

local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

-- The attachments as { id, count }; nil (the field left out) if any is secret.
local function draftItems()
    local out = {}
    for i = 1, rawget(_G, "ATTACHMENTS_MAX_SEND") or 12 do
        local _, itemID, _, count = GetSendMailItem(i)
        if API.IsSecret(itemID) or API.IsSecret(count) then return nil end
        if itemID ~= nil then out[#out + 1] = { id = itemID, count = count or 1 } end
    end
    return out
end

local function remove(rec)
    for i, r in ipairs(open) do
        if r == rec then return table.remove(open, i) end
    end
end

-- Saved in its final state; a record that can't be (a secret name or GUID)
-- is just dropped.
local function save(rec, state)
    remove(rec)
    rec.state = state
    Store.AddSent(rec)
    if state == "sent" then
        Store.AddRecent(rec.to)
        -- S1's fill: this character's last recipient (a return never comes here).
        local key = Names.Key(rec.to)
        if rec.from and key and Store.SetLastTo(rec.from, key) and Sent.onConfirmed then
            Sent.onConfirmed(key)
        end
    end
end

-- The record's window opens now (once: at SendMail, or at the stranger
-- dialog's close); at its end, still a candidate, it is saved unconfirmed.
local function openWindow(rec)
    rec.opened = GetTime()
    C_Timer.After(Sent.WINDOW, function()
        for _, r in ipairs(open) do
            if r == rec then return save(r, "unconfirmed") end
        end
    end)
end

local function capture(to, subject)
    if not Store.Ready() then return end
    local t = GetTime()
    -- A record that can't be saved (a secret name) still counts as a
    -- candidate, so no other send takes its result.
    local rec = { kind = "send", day = Store.PlayDay(), at = time(), from = Registry.CurrentGUID(),
        to = Names.Display(to), subject = plainString(subject), money = GetSendMailMoney(), cod = GetSendMailCOD(),
        items = draftItems(), state = "pending", called = t }
    open[#open + 1] = rec
    if confirmAt == t then rec.awaiting = true else openWindow(rec) end
end

hooksecurefunc("SendMail", function(to, subject)
    local ok, err = pcall(capture, to, subject)
    if not ok then API.Fail("sent capture", err) end
end)

local function onSuccess()
    -- A send succeeded: whatever lastTo held is no longer the last one, before
    -- anything below can fail (PLAN.md, "S1: the last recipient"). Only an
    -- attributed send sets it again.
    local me = Registry.CurrentGUID()
    if me then Store.SetLastTo(me, nil) end
    local t, candidates = GetTime(), {}
    for _, r in ipairs(open) do
        if r.awaiting or t - r.opened <= Sent.WINDOW then candidates[#candidates + 1] = r end
    end
    API.Debug("send success, " .. #candidates .. " candidate(s)")
    if #candidates == 1 then save(candidates[1], "sent") end
end

local function onError(errType)
    if API.IsSecret(errType) or errType ~= REFUSED then return end
    local t, same = GetTime(), {}
    for _, r in ipairs(open) do
        if r.called == t then same[#same + 1] = r end
    end
    if #same == 1 then remove(same[1]) end
end

-- The stranger dialog closed (accepted or cancelled): its window starts now.
local function onDialogClosed()
    for _, r in ipairs(open) do
        if r.awaiting then
            r.awaiting = nil
            openWindow(r)
            API.Debug("send dialog closed, its 120 s window starts")
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    local ok, err = pcall(function()
        if event == "SECURE_TRANSFER_CONFIRM_SEND_MAIL" then
            confirmAt = GetTime()
        elseif event == "MAIL_SEND_SUCCESS" then
            onSuccess()
        elseif event == "UI_ERROR_MESSAGE" then
            onError(arg1)
        elseif event == "PLAYER_LOGOUT" then
            for i = #open, 1, -1 do save(open[i], "unconfirmed") end
        end
    end)
    if not ok then API.Fail("sent " .. event, err) end
end)
API.RegisterEvents(events, { "SECURE_TRANSFER_CONFIRM_SEND_MAIL", "MAIL_SEND_SUCCESS", "UI_ERROR_MESSAGE",
    "PLAYER_LOGOUT" })

-- A return Trash confirmed: mail travelling back to its sender. `m` is the
-- scanned mail (Core/Scan.lua).
function Sent.AddReturn(m, items)
    return Store.AddSent({ kind = "return", day = Store.PlayDay(), at = time(), from = Registry.CurrentGUID(),
        to = Names.Display(m.sender), subject = m.subject, money = m.money, cod = m.cod, items = items,
        state = "sent" })
end

-- Called at PLAYER_LOGIN (the hooked global is Blizzard_MailFrame's).
local hooked = false
function Sent.Start()
    if hooked or type(rawget(_G, "SendMailFrame_EnableSendMailButton")) ~= "function" then return end
    hooked = true
    hooksecurefunc("SendMailFrame_EnableSendMailButton", function()
        local ok, err = pcall(onDialogClosed)
        if not ok then API.Fail("sent dialog", err) end
    end)
end

GM._test = GM._test or {}
GM._test.sent = { open = function() return open end }
