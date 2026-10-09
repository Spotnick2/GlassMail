-- MailProbe: the throwaway measurement addon for GlassMailbox, milestone M0.
-- It answers the questions docs/PLAN.md's probe checklist leaves open before
-- any feature code is written. Every line it prints also goes to
-- MailProbeDB.log (SavedVariables), so a full client exit leaves the session
-- on disk for review. It logs mail headers (senders, subjects, amounts) of
-- the player's own inbox only.
--
-- Passive, always on (no command needed):
--   L  lifecycle: MAIL_SHOW / MAIL_CLOSED / interaction manager (MailInfo) /
--      PLAYER_LEAVING_WORLD, in order, with duplicates visible
--   I  every MAIL_INBOX_UPDATE that changes loaded/total counts
--   R  results: MAIL_SUCCESS / MAIL_FAILED (itemID), MAIL_SEND_SUCCESS,
--      CLOSE_INBOX_ITEM, UI_ERROR_MESSAGE, send lock/unlock, money/COD changes,
--      SECURE_TRANSFER_*, and taint: ADDON_ACTION_BLOCKED / _FORBIDDEN
--   C  calls: TakeInboxItem, TakeInboxMoney, AutoLootMailItem, ReturnInboxItem,
--      DeleteInboxItem, SendMail, ClickSendMailItemButton, C_Mail.SetOpeningAll
--      (post-hooks, whoever calls them: Blizzard's Open All included)
--
-- Commands (/mprobe):
--   state            inbox counts, CanCheckInbox, pending command, bag space, money secrecy
--   inbox            every loaded mail's header and attachments (sender formats, isGM, currency)
--   dupes            mails that look identical (identity without a server id)
--   readtest N       does GetInboxText mark mail N read?
--   bags             free slots per bag, with the bag family (specialty bags)
--   take N [slot]    TakeInboxItem from the command (a key press)
--   money N          TakeInboxMoney from the command (try it with full bags)
--   taketimer N      TakeInboxItem of mail N, slot by slot, from timers after one key press
--   returnnow N      ReturnInboxItem from the command        (ONLY on a test mail!)
--   returntimer N    ReturnInboxItem from a timer, 1 s later  (ONLY on a test mail!)
--   hidestock / showstock   hide or show Blizzard's Open All button (then try a gamepad)
--   rows on/off      our own small buttons on the inbox rows; a click takes that mail's money/first item
--   picker NAME      a button by the recipient box that fills it with NAME; then press Send yourself
--   draft            the send draft: recipient, subject, attachments, money, COD, postage
--   split BAG SLOT N split N off a stack and attach it to the draft
--   sendnow          SendMail(draft) from the command (a key press)
--   sendtimer        SendMail(draft) from a timer, 1 s later
--   log [N]          the last N log lines (default 30); clear: empty the log
--
-- Every client call that may be missing or throw goes through try(), so one
-- refusal cannot stop the rest of the probe.

local ADDON = ...
local MAX_LOG = 4000

--------------------------------------------------------------------------------
-- Log
--------------------------------------------------------------------------------

local function stamp()
    local t = GetTime and GetTime() or 0
    return string.format("%.2f%s", t, InCombatLockdown() and " C" or "")
end

local function say(msg)
    msg = tostring(msg)
    print("|cff7fd4ffMailProbe|r " .. msg)
    if type(MailProbeDB) == "table" and type(MailProbeDB.log) == "table" then
        local log = MailProbeDB.log
        log[#log + 1] = stamp() .. " " .. msg
        if #log > MAX_LOG then table.remove(log, 1) end
    end
end

-- Describe a value without ever operating on a secret one.
local function show(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if v == nil then return "nil" end
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

-- Returns pcall's results, nils inside included (header returns have holes).
local function pack(...) return { n = select("#", ...), ... } end
local function try(label, fn, ...)
    if type(fn) ~= "function" then
        say(label .. ": MISSING")
        return false
    end
    local r = pack(pcall(fn, ...))
    if not r[1] then say(label .. ": ERROR " .. show(r[2])) end
    return unpack(r, 1, r.n)
end

local function args(...)
    local out = {}
    for i = 1, select("#", ...) do out[#out + 1] = show((select(i, ...))) end
    return table.concat(out, ", ")
end

local function global(name) return rawget(_G, name) end

--------------------------------------------------------------------------------
-- Inbox helpers
--------------------------------------------------------------------------------

local ATTACH_MAX = global("ATTACHMENTS_MAX_RECEIVE") or 16

local function counts()
    local ok, loaded, total = try("GetInboxNumItems", global("GetInboxNumItems"))
    if not ok then return nil, nil end
    return loaded, total
end

-- GetInboxHeaderInfo's 15 returns, in Blizzard's order (MailFrame.lua).
local HEADER = { "packageIcon", "stationeryIcon", "sender", "subject", "money", "CODAmount", "daysLeft",
    "itemCount", "wasRead", "wasReturned", "textCreated", "canReply", "isGM", "firstItemQuantity",
    "firstItemLink" }

local function header(i)
    local r = { try("GetInboxHeaderInfo(" .. i .. ")", global("GetInboxHeaderInfo"), i) }
    if not r[1] then return nil end
    local h = {}
    for k, name in ipairs(HEADER) do h[name] = r[k + 1] end
    return h
end

local function plain(v)   -- a value usable in Lua, or nil
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function fingerprint(h, i)
    local parts = { plain(h.sender), plain(h.subject), plain(h.money), plain(h.CODAmount), plain(h.itemCount),
        plain(h.wasReturned) }
    for a = 1, ATTACH_MAX do
        local ok, name, itemID, _, count = try("GetInboxItem", global("GetInboxItem"), i, a)
        if ok and name ~= nil then parts[#parts + 1] = tostring(plain(itemID)) .. "x" .. tostring(plain(count)) end
    end
    for k = 1, #parts do parts[k] = tostring(parts[k]) end
    return table.concat(parts, "|")
end

local function freeSlots()
    local c = global("C_Container")
    local ok, n = try("CalculateTotalNumberOfFreeBagSlots", c and c.CalculateTotalNumberOfFreeBagSlots)
    return ok and n or nil
end

--------------------------------------------------------------------------------
-- Passive: events
--------------------------------------------------------------------------------

local lastLoaded, lastTotal
local mailOpenSince

local function mailInfoType()
    local e = global("Enum")
    return e and e.PlayerInteractionType and e.PlayerInteractionType.MailInfo
end

local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN",
    "MAIL_SHOW", "MAIL_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "PLAYER_LEAVING_WORLD", "MAIL_INBOX_UPDATE", "MAIL_SUCCESS", "MAIL_FAILED", "MAIL_SEND_SUCCESS",
    "MAIL_SEND_INFO_UPDATE", "CLOSE_INBOX_ITEM", "MAIL_LOCK_SEND_ITEMS", "MAIL_UNLOCK_SEND_ITEMS",
    "SEND_MAIL_MONEY_CHANGED", "SEND_MAIL_COD_CHANGED", "UPDATE_PENDING_MAIL", "UI_ERROR_MESSAGE",
    "SECURE_TRANSFER_CONFIRM_SEND_MAIL", "SECURE_TRANSFER_CANCEL", "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED",
}

local QUIET = { MAIL_SEND_INFO_UPDATE = true, BAG_UPDATE_DELAYED = true }   -- logged only while a test runs
local busy = false   -- a timed test is running: log the quiet events too

local frame = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do
    local ok, registered = pcall(frame.RegisterEvent, frame, e)
    if not ok or registered == false then print("MailProbe: could not register " .. e) end
end

local hooksDone = false
local installHooks   -- defined below

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        if type(MailProbeDB) ~= "table" then MailProbeDB = {} end
        if type(MailProbeDB.log) ~= "table" then MailProbeDB.log = {} end
        MailProbeDB.loads = (MailProbeDB.loads or 0) + 1
        return
    elseif event == "PLAYER_LOGIN" then
        say("session " .. tostring(MailProbeDB and MailProbeDB.loads) .. ", build " .. args(GetBuildInfo()))
        installHooks()
        return
    end
    if event == "MAIL_INBOX_UPDATE" then
        local loaded, total = counts()
        if loaded ~= lastLoaded or total ~= lastTotal then
            say("I inbox loaded=" .. show(loaded) .. " total=" .. show(total))
            lastLoaded, lastTotal = loaded, total
        end
        return
    end
    if QUIET[event] and not busy then return end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local t = ...
        if t ~= mailInfoType() then return end   -- only the mailbox
        say("L " .. event .. " (MailInfo=" .. show(t) .. ")")
        return
    end
    if event == "MAIL_SHOW" then
        mailOpenSince = GetTime()
        lastLoaded, lastTotal = nil, nil
    elseif event == "MAIL_CLOSED" and mailOpenSince then
        say(string.format("L mailbox was open %.1f s", GetTime() - mailOpenSince))
        mailOpenSince = nil
    end
    local tag = (event:find("^MAIL_SHOW") or event:find("^MAIL_CLOSED") or event == "PLAYER_LEAVING_WORLD") and "L"
        or ((event:find("ADDON_ACTION") or event:find("SECURE_TRANSFER")) and "!") or "R"
    say(tag .. " " .. event .. " (" .. args(...) .. ")")
end)

--------------------------------------------------------------------------------
-- Passive: call hooks (post-hooks; they never change what the call does)
--------------------------------------------------------------------------------

local HOOKED = { "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem", "ReturnInboxItem", "DeleteInboxItem",
    "SendMail", "ClickSendMailItemButton" }

installHooks = function()
    if hooksDone then return end
    hooksDone = true
    for _, name in ipairs(HOOKED) do
        if global(name) then
            hooksecurefunc(name, function(...) say("C " .. name .. "(" .. args(...) .. ")") end)
        else
            say("C " .. name .. ": MISSING")
        end
    end
    local cm = global("C_Mail")
    if cm and cm.SetOpeningAll then
        hooksecurefunc(cm, "SetOpeningAll", function(v) say("C C_Mail.SetOpeningAll(" .. show(v) .. ")") end)
    end
    local stock = global("OpenAllMail")
    if stock then
        stock:HookScript("OnClick", function(_, button) say("C stock OpenAllMail clicked (" .. show(button) .. ")") end)
        stock:HookScript("OnHide", function() say("C stock OpenAllMail hidden") end)
    else
        say("OpenAllMail: MISSING")
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local C = {}

function C.state()
    local loaded, total = counts()
    local cm = global("C_Mail")
    local okC, can, wait = try("CanCheckInbox", cm and cm.CanCheckInbox)
    local okP, pending = try("IsCommandPending", cm and cm.IsCommandPending)
    local okN, new = try("HasNewMail", global("HasNewMail"))
    local okS, s1, s2, s3 = try("GetLatestThreeSenders", global("GetLatestThreeSenders"))
    local okM, money = try("GetMoney", global("GetMoney"))
    local name, second = UnitName("player")
    say("state: loaded=" .. show(loaded) .. " total=" .. show(total) .. " canCheck=" .. show(can) .. " wait="
        .. show(wait) .. " pending=" .. show(pending))
    say("state: hasNewMail=" .. show(new) .. " latest senders=" .. args(s1, s2, s3))
    say("state: freeSlots=" .. show(freeSlots()) .. " money secret=" .. show(okM and issecretvalue and issecretvalue(money))
        .. " UnitName=" .. args(name, second))
    say("state: mail frame shown=" .. show(global("MailFrame") and MailFrame:IsShown()) .. " MailInfo type="
        .. show(mailInfoType()))
end

function C.inbox()
    local loaded = counts()
    if not loaded then return end
    for i = 1, loaded do
        local h = header(i)
        if h then
            say(string.format("mail %d: sender=%s subject=%s money=%s cod=%s days=%s items=%s read=%s returned=%s "
                .. "reply=%s gm=%s first=%s", i, show(h.sender), show(h.subject), show(h.money), show(h.CODAmount),
                show(h.daysLeft), show(h.itemCount), show(h.wasRead), show(h.wasReturned), show(h.canReply),
                show(h.isGM), show(h.firstItemLink)))
            for a = 1, ATTACH_MAX do
                local ok, nm, itemID, _, count, quality, canUse, isCurrency = try("GetInboxItem", global("GetInboxItem"), i, a)
                if ok and nm ~= nil then
                    say(string.format("   slot %d: %s id=%s count=%s q=%s usable=%s currency=%s", a, show(nm),
                        show(itemID), show(count), show(quality), show(canUse), show(isCurrency)))
                end
            end
            local okI, invoiceType, itemName, player = try("GetInboxInvoiceInfo", global("GetInboxInvoiceInfo"), i)
            if okI and invoiceType ~= nil then
                say("   invoice: " .. args(invoiceType, itemName, player))
            end
        end
    end
end

function C.dupes()
    local loaded = counts()
    if not loaded then return end
    local seen, groups = {}, 0
    for i = 1, loaded do
        local h = header(i)
        if h then
            local fp = fingerprint(h, i)
            if seen[fp] then
                groups = groups + 1
                say("dupes: mail " .. i .. " looks identical to mail " .. seen[fp])
            else
                seen[fp] = i
            end
        end
    end
    say("dupes: " .. groups .. " identical pair(s) among " .. loaded .. " loaded")
end

function C.readtest(arg)
    local i = tonumber(arg)
    if not i then say("readtest N"); return end
    local before = header(i)
    if not before then return end
    try("GetInboxText", global("GetInboxText"), i)
    local after = header(i)
    say("readtest " .. i .. ": wasRead before=" .. show(before.wasRead) .. " right after GetInboxText="
        .. show(after and after.wasRead) .. " (check again with /mprobe inbox after the next update)")
end

function C.bags()
    local c = global("C_Container")
    if not c then say("C_Container: MISSING"); return end
    local nb = global("NUM_BAG_SLOTS") or 4
    for bag = 0, nb + 1 do
        local okS, slots = try("GetContainerNumSlots", c.GetContainerNumSlots, bag)
        local okF, free, family = try("GetContainerNumFreeSlots", c.GetContainerNumFreeSlots, bag)
        if okS and slots and slots > 0 then
            say(string.format("bag %d: %s slots, %s free, family %s", bag, show(slots), show(free), show(family)))
        end
    end
    say("bags: total free " .. show(freeSlots()))
end

function C.take(arg)
    local i, slot = arg:match("^(%d+)%s*(%d*)$")
    i, slot = tonumber(i), tonumber(slot) or 1
    if not i then say("take N [slot]"); return end
    try("TakeInboxItem", global("TakeInboxItem"), i, slot)
end

function C.money(arg)
    local i = tonumber(arg)
    if not i then say("money N"); return end
    say("money: free slots " .. show(freeSlots()))
    try("TakeInboxMoney", global("TakeInboxMoney"), i)
end

-- Take mail N's attachments one by one, every step after the first from a
-- timer: does the client allow a loot chain without a key press per step?
-- Paced like Blizzard's Open All: wait while a command is pending, 0.3 s apart.
function C.taketimer(arg)
    local i = tonumber(arg)
    if not i then say("taketimer N"); return end
    local cm = global("C_Mail")
    local steps = 0
    busy = true
    local function step()
        steps = steps + 1
        local h = header(i)
        if not h or steps > 40 then say("taketimer: stop (" .. steps .. " steps)"); busy = false; return end
        if cm and cm.IsCommandPending and cm.IsCommandPending() then C_Timer.After(0.3, step); return end
        for a = ATTACH_MAX, 1, -1 do
            local ok, nm = try("GetInboxItem", global("GetInboxItem"), i, a)
            if ok and nm ~= nil then
                say("taketimer: step " .. steps .. " slot " .. a .. (steps == 1 and " (from the key press)" or " (from a timer)"))
                try("TakeInboxItem", global("TakeInboxItem"), i, a)
                C_Timer.After(0.3, step)
                return
            end
        end
        say("taketimer: mail " .. i .. " has no attachments left after " .. steps .. " steps")
        busy = false
    end
    step()
end

function C.returnnow(arg)
    local i = tonumber(arg)
    if not i then say("returnnow N"); return end
    local h = header(i)
    say("returnnow " .. i .. ": sender=" .. show(h and h.sender) .. " subject=" .. show(h and h.subject))
    try("ReturnInboxItem", global("ReturnInboxItem"), i)
end

function C.returntimer(arg)
    local i = tonumber(arg)
    if not i then say("returntimer N"); return end
    local h = header(i)
    say("returntimer " .. i .. ": sender=" .. show(h and h.sender) .. " subject=" .. show(h and h.subject)
        .. " - returning in 1 s, from a timer")
    busy = true
    C_Timer.After(1, function()
        try("ReturnInboxItem (timer)", global("ReturnInboxItem"), i)
        C_Timer.After(3, function() busy = false end)
    end)
end

function C.hidestock()
    local b = global("OpenAllMail")
    if not b then say("OpenAllMail: MISSING"); return end
    b:Hide()
    say("stock Open All hidden; shown=" .. show(b:IsShown()) .. ". Try it from a gamepad now; reopening the mailbox may show it again.")
end

function C.showstock()
    local b = global("OpenAllMail")
    if not b then say("OpenAllMail: MISSING"); return end
    b:Show()
    say("stock Open All shown=" .. show(b:IsShown()))
end

-- Our own row controls: separate frames on top of the inbox rows, never
-- fields on Blizzard's. A click takes that row's money, else its first item.
local rowButtons = {}
function C.rows(arg)
    local on = arg ~= "off"
    local perPage = global("INBOXITEMS_TO_DISPLAY") or 7
    for r = 1, perPage do
        local row = global("MailItem" .. r)
        if row and not rowButtons[r] then
            local b = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
            b:SetSize(22, 18)
            b:SetText("P")
            b:SetFrameStrata("HIGH")
            b:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            b:SetScript("OnClick", function()
                local page = (InboxFrame and InboxFrame.pageNum) or 1
                local i = (page - 1) * perPage + r
                local h = header(i)
                say("rows: our button on row " .. r .. " -> mail " .. i .. " sender=" .. show(h and h.sender))
                if h and plain(h.money) and h.money > 0 then
                    try("TakeInboxMoney", global("TakeInboxMoney"), i)
                elseif h then
                    try("TakeInboxItem", global("TakeInboxItem"), i, 1)
                end
            end)
            rowButtons[r] = b
        end
        if rowButtons[r] then rowButtons[r]:SetShown(on and MailFrame:IsShown()) end
    end
    say("rows " .. (on and "on" or "off") .. " (shown while the mailbox is open when you run this)")
end

-- A picker button by the recipient box: SetText from our click, then the
-- player sends with Blizzard's own Send button. Watch for "!" lines.
local pickerButton, pickerName
function C.picker(arg)
    pickerName = arg ~= "" and arg or nil
    if not pickerName then say("picker NAME (as typed, e.g. First Surname)"); return end
    local box = global("SendMailNameEditBox")
    if not box then say("SendMailNameEditBox: MISSING"); return end
    if not pickerButton then
        pickerButton = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
        pickerButton:SetSize(26, 20)
        pickerButton:SetText("@")
        pickerButton:SetFrameStrata("HIGH")
        pickerButton:SetPoint("LEFT", box, "RIGHT", 4, 0)
        pickerButton:SetScript("OnClick", function()
            box:SetText(pickerName)
            say("picker: recipient set to " .. show(pickerName) .. "; now press Send yourself")
        end)
    end
    pickerButton:Show()
    say("picker ready for " .. show(pickerName) .. " (the @ by the recipient box)")
end

local function draft()
    local box, subj = global("SendMailNameEditBox"), global("SendMailSubjectEditBox")
    local d = { to = box and box:GetText(), subject = subj and subj:GetText(), items = {} }
    local maxSend = global("ATTACHMENTS_MAX_SEND") or 12
    for a = 1, maxSend do
        local ok, nm, itemID, _, count = try("GetSendMailItem", global("GetSendMailItem"), a)
        if ok and nm ~= nil then d.items[#d.items + 1] = a .. ":" .. show(itemID) .. "x" .. show(count) end
    end
    d.money = select(2, try("GetSendMailMoney", global("GetSendMailMoney")))
    d.cod = select(2, try("GetSendMailCOD", global("GetSendMailCOD")))
    d.price = select(2, try("GetSendMailPrice", global("GetSendMailPrice")))
    return d
end

function C.draft()
    local d = draft()
    say("draft: to=" .. show(d.to) .. " subject=" .. show(d.subject) .. " money=" .. show(d.money) .. " cod="
        .. show(d.cod) .. " postage=" .. show(d.price) .. " items=" .. (#d.items > 0 and table.concat(d.items, " ") or "none"))
end

function C.split(arg)
    local bag, slot, n = arg:match("^(%-?%d+)%s+(%d+)%s+(%d+)$")
    bag, slot, n = tonumber(bag), tonumber(slot), tonumber(n)
    if not n then say("split BAG SLOT N"); return end
    local c = global("C_Container")
    try("SplitContainerItem", c and c.SplitContainerItem, bag, slot, n)
    local okH, has = try("CursorHasItem", global("CursorHasItem"))
    say("split: cursor has item=" .. show(has))
    local maxSend = global("ATTACHMENTS_MAX_SEND") or 12
    for a = 1, maxSend do
        local ok, used = try("HasSendMailItem", global("HasSendMailItem"), a)
        if ok and not used then
            try("ClickSendMailItemButton", global("ClickSendMailItemButton"), a)
            say("split: dropped on attachment slot " .. a)
            return
        end
    end
    say("split: no free attachment slot")
end

local function send(fromTimer)
    local d = draft()
    if type(d.to) ~= "string" or d.to == "" then say("send: fill in a recipient first"); return end
    local body = global("SendMailBodyEditBox")
    local text = body and body:GetText() or ""
    say("send" .. (fromTimer and "timer" or "now") .. ": to=" .. show(d.to) .. " items=" .. #d.items .. " money="
        .. show(d.money) .. " cod=" .. show(d.cod))
    try("SendMail", global("SendMail"), d.to, d.subject or "", text)
end

function C.sendnow() send(false) end

function C.sendtimer()
    busy = true
    say("sendtimer: sending in 1 s, from a timer")
    C_Timer.After(1, function()
        send(true)
        C_Timer.After(5, function() busy = false end)
    end)
end

function C.log(arg)
    if arg == "clear" then MailProbeDB.log = {}; print("MailProbe: log cleared"); return end
    local n = tonumber(arg) or 30
    local log = MailProbeDB.log
    for i = math.max(1, #log - n + 1), #log do print(log[i]) end
end

local HELP = {
    "state | inbox | dupes | readtest N | bags",
    "take N [slot] | money N | taketimer N",
    "returnnow N | returntimer N  (ONLY on a test mail: it goes back to the sender)",
    "hidestock | showstock | rows on/off | picker NAME",
    "draft | split BAG SLOT N | sendnow | sendtimer",
    "log [N] | log clear",
}

SLASH_MAILPROBE1 = "/mprobe"
SlashCmdList.MAILPROBE = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if C[cmd] then
        local ok, err = pcall(C[cmd], arg)
        if not ok then say(cmd .. ": ERROR " .. show(err)) end
    else
        for _, line in ipairs(HELP) do print("|cff7fd4ffMailProbe|r /mprobe " .. line) end
    end
end
