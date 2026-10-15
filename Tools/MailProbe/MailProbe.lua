-- MailProbe: the throwaway measurement addon for GlassMail (M0, M1's
-- session 5 and M2's session 6). It answers the questions docs/PLAN.md's probe
-- checklist leaves open before any feature code is written. It is a
-- ForeverProbe module (..\ForeverProbe, its docs/GUIDE.md): its lines go to the
-- ForeverProbe console (/fp), never to chat, and to MailProbeDB.log
-- (SavedVariables), so a /reload leaves the session on disk for review. The
-- host's baseline logs ADDON_ACTION_BLOCKED / _FORBIDDEN in the same console.
-- It logs mail headers (senders, subjects, amounts) of the player's own inbox,
-- and, with `names`, friends' and guild members' names: blur them in anything
-- shared.
--
-- Passive, always on (no command needed):
--   L  lifecycle: MAIL_SHOW / interaction manager SHOW and HIDE (MailInfo) /
--      PLAYER_LEAVING_WORLD, in order, with duplicates visible. The interaction
--      HIDE is the close signal: MAIL_CLOSED never fired (FOREVER-PROBE.md
--      session 2) and stays registered only to show it if it ever does.
--   I  every MAIL_INBOX_UPDATE that changes loaded/total counts
--   R  results: MAIL_SUCCESS / MAIL_FAILED (itemID), MAIL_SEND_SUCCESS,
--      CLOSE_INBOX_ITEM, UI_ERROR_MESSAGE, send lock/unlock, money/COD changes,
--      SECURE_TRANSFER_*; UPDATE_PENDING_MAIL with HasNewMail and the minimap mail indicator
--   C  calls: TakeInboxItem, TakeInboxMoney, AutoLootMailItem, ReturnInboxItem,
--      DeleteInboxItem, SendMail, ClickSendMailItemButton, C_Mail.SetOpeningAll
--      (post-hooks, whoever calls them: Blizzard's Open All included)
--
-- Commands (/fp mail <command>; /fp mail alone lists them):
--   state            inbox counts, CanCheckInbox, pending command, bag space, money secrecy, new mail
--   strings          the client's AUCTION_*_MAIL_SUBJECT templates
--   inbox            every loaded mail's header, attachments with links, invoice, AH template
--   dupes            mails that look identical (identity without a server id)
--   watch on/off     log every mail whenever an inbox update changes it (index shifts, residuals)
--   fit N            for mail N's attachments: max stack, item family, room in partial
--                    stacks, specialty and general free slots (what I1 decides from)
--   refill           CheckInbox() when allowed, and how long until the next update
--   readtest N       does GetInboxText mark mail N read?
--   bags             free slots per bag, with the bag family (specialty bags)
--   take N [slot]    TakeInboxItem from the command (a key press)
--   money N          TakeInboxMoney from the command (try it with full bags)
--   taketimer N      TakeInboxItem of mail N, slot by slot, from timers after one key press
--   returnnow N      ReturnInboxItem from the command        (ONLY on a test mail!)
--   returntimer N    ReturnInboxItem from a timer, 1 s later  (ONLY on a test mail!)
--   returnmany A B.. ReturnInboxItem of several mails in a row, each found again by its
--                    fingerprint, the first from the key press, the rest from timers (ONLY test mails!)
--   hidestock / showstock   hide or show Blizzard's Open All button (then try a gamepad)
--   rows on/off      our own T / R / D buttons on the inbox rows, children of InboxFrame: take
--                    (money, else the first item), return, delete (empty mail only)
--   picker NAME      a button by the recipient box that fills it with NAME; then press Send yourself
--   draft            the send draft: recipient, subject, attachments, money, COD, postage
--   split BAG SLOT N split N off a stack and attach it to the draft
--   sendnow          SendMail(draft) from the command (a key press)
--   sendtimer        SendMail(draft) from a timer, 1 s later
--   sendwatch on/off (session 6) each send numbered: the draft at the Send click, at SendMail's
--                    post-hook and at MAIL_SEND_SUCCESS; which events fire inside SendMail;
--                    every result line timed from the last send; the Send button's state
--   capture on/off   (session 6) at each DeleteInboxItem / ReturnInboxItem post-hook: is the
--                    mail still at its index, and do the next updates show it gone (5 s)?
--   names            (session 6) your own name and realm, friends' and guild members' name
--                    formats (realm suffix, secrets), in or out of an instance
--   clear            empty the saved log (the console shows it: /fp)
--
-- Procedures (/fp steps mail <name>; /fp steps lists them): session 6 as panels
-- of buttons, every outcome saved: send, timing, capture, picker, names, release.
--
-- Every client call that may be missing or throw goes through try() (the
-- host's Probe:Try), so one refusal cannot stop the rest of the probe.

local ADDON, NS = ...
local MAX_LOG = 4000

--------------------------------------------------------------------------------
-- Log: the ForeverProbe module. Lines go to the console and, from this addon's
-- ADDON_LOADED, to MailProbeDB.log (bound with UseLog).
--------------------------------------------------------------------------------

local Probe = ForeverProbe:Module("MailProbe", { api = 1, cmd = "mail" })

local function say(msg) Probe:Say(msg) end

-- A value as text, never operating on a secret one (strings quoted, as the
-- log always had them).
local function show(v) return Probe.Show(v) end

local pack = Probe.Pack
local function try(label, fn, ...) return Probe:Try(label, fn, ...) end

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

-- nil when there is no mail i: the call itself succeeds with no values, so a
-- table of nils would otherwise look like a mail.
local function header(i)
    local loaded = counts()
    if type(loaded) ~= "number" or i < 1 or i > loaded then return nil end
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

-- Mail N's attachments, by slot: { slot, itemID, count, link }. The link is
-- nil when the client can't give it (the question M1's identity rule hangs on).
local function attachments(i)
    local out = {}
    for a = 1, ATTACH_MAX do
        local ok, name, itemID, _, count = try("GetInboxItem", global("GetInboxItem"), i, a)
        if ok and name ~= nil then
            local okL, link = try("GetInboxItemLink", global("GetInboxItemLink"), i, a)
            out[#out + 1] = { slot = a, itemID = plain(itemID), count = plain(count), link = okL and plain(link) or nil }
        end
    end
    return out
end

-- M1's fingerprint: sender, subject, money, COD, wasReturned and each
-- attachment's link x count, without slot numbers (whether slots renumber
-- after a take is one of the things `watch` shows). A missing link leaves it
-- unresolved: the second return is false.
local function fingerprint(h, i)
    local parts = { plain(h.sender), plain(h.subject), plain(h.money), plain(h.CODAmount), plain(h.wasReturned) }
    for k = 1, #parts do parts[k] = tostring(parts[k]) end
    local items, resolved = {}, true
    -- itemCount is nil without items (session 2): no per-slot calls then.
    for _, it in ipairs(plain(h.itemCount) and attachments(i) or {}) do
        if not it.link then resolved = false end
        items[#items + 1] = tostring(it.link or ("id" .. tostring(it.itemID))) .. "x" .. tostring(it.count)
    end
    table.sort(items)
    parts[#parts + 1] = table.concat(items, ",")
    return table.concat(parts, "|"), resolved
end

-- Every loaded mail's fingerprint: byIndex[i] = fp, count[fp] = n.
local function scanAll()
    local byIndex, count = {}, {}
    local loaded = counts()
    for i = 1, loaded or 0 do
        local h = header(i)
        if h then
            local fp = fingerprint(h, i)
            byIndex[i] = fp
            count[fp] = (count[fp] or 0) + 1
        end
    end
    return byIndex, count
end

local function indexOf(fp)
    local byIndex, count = scanAll()
    if (count[fp] or 0) ~= 1 then return nil, count[fp] or 0 end
    for i, f in pairs(byIndex) do if f == fp then return i, 1 end end
end

-- Blizzard's own rule: the letter's button deletes what InboxItemCanDelete
-- allows and returns everything else (OpenMailDeleteMixin:Delete).
local function returnable(i)
    local ok, can = try("InboxItemCanDelete", global("InboxItemCanDelete"), i)
    return ok and not can
end

-- The client's AH subject templates, by global name.
local function subjectTemplates()
    local t = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^AUCTION_.*MAIL_SUBJECT$") and type(v) == "string" then t[k] = v end
    end
    return t
end

-- A format string as an anchored Lua pattern: every specifier (%s, %d, %i,
-- and the positional %1$s that localized strings use) matches anything, a
-- literal %% stays a percent sign, everything else is literal.
local function templatePattern(fmt)
    local p = fmt:gsub("%%%%", "\2"):gsub("%%%d*%$?[sdi]", "\1")
    p = p:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("\1", ".+"):gsub("\2", "%%%%")
    return "^" .. p .. "$"
end

local patterns   -- name -> pattern, built once (a walk of _G is not cheap)
local function subjectMatch(subject)
    if type(plain(subject)) ~= "string" then return nil end
    if not patterns then
        patterns = {}
        for name, fmt in pairs(subjectTemplates()) do patterns[name] = templatePattern(fmt) end
    end
    local names = {}
    for name, pattern in pairs(patterns) do
        if subject:find(pattern) then names[#names + 1] = name end
    end
    table.sort(names)
    return names[1] and table.concat(names, ",") or nil
end

-- Blizzard's minimap mail indicator (Mainline Minimap.xml: MinimapCluster.
-- IndicatorFrame.MailFrame, shown while HasNewMail() on UPDATE_PENDING_MAIL).
local function indicator()
    local mc = global("MinimapCluster")
    local f = mc and mc.IndicatorFrame and mc.IndicatorFrame.MailFrame
    if not f then return "MISSING" end
    return show(f:IsShown())
end

-- One line per mail, slot numbers included, for `watch`.
local function describe(i)
    local h = header(i)
    if not h then return nil end
    local slots = {}
    for _, it in ipairs(attachments(i)) do
        slots[#slots + 1] = it.slot .. ":" .. tostring(it.link or ("id" .. tostring(it.itemID) .. "(no link)")) .. "x"
            .. tostring(it.count)
    end
    return string.format("%d: %s %s money=%s cod=%s ret=%s read=%s [%s]", i, show(h.sender), show(h.subject),
        show(h.money), show(h.CODAmount), show(h.wasReturned), show(h.wasRead), table.concat(slots, " "))
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

-- Enum.PlayerInteractionType.MailInfo, else 17, the value measured on 70291
-- (FOREVER-PROBE.md session 1): the close signal must not vanish with the enum.
local MAIL_INFO_MEASURED = 17
local function mailInfoType()
    local e = global("Enum")
    return (e and e.PlayerInteractionType and e.PlayerInteractionType.MailInfo) or MAIL_INFO_MEASURED
end

local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN",
    "MAIL_SHOW", "MAIL_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "PLAYER_LEAVING_WORLD", "MAIL_INBOX_UPDATE", "MAIL_SUCCESS", "MAIL_FAILED", "MAIL_SEND_SUCCESS",
    "MAIL_SEND_INFO_UPDATE", "CLOSE_INBOX_ITEM", "MAIL_LOCK_SEND_ITEMS", "MAIL_UNLOCK_SEND_ITEMS",
    "SEND_MAIL_MONEY_CHANGED", "SEND_MAIL_COD_CHANGED", "UPDATE_PENDING_MAIL", "UI_ERROR_MESSAGE",
    "SECURE_TRANSFER_CONFIRM_SEND_MAIL", "SECURE_TRANSFER_CANCEL", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE_DELAYED",
}

local QUIET = { MAIL_SEND_INFO_UPDATE = true, BAG_UPDATE_DELAYED = true }   -- logged only while a test runs
local busy = false   -- a timed test is running: log the quiet events too

local frame = CreateFrame("Frame")
Probe:RegisterEvents(frame, EVENTS)

local hooksDone = false
local installHooks   -- defined below
local watching, lastWatch = false, {}   -- watch on: every mail line as last logged
local refillAt                          -- GetTime() of our CheckInbox, until the next update

-- Session 6. sendwatch: sends numbered; phase "click" from the Send button's
-- PreClick, nil once SendMail's post-hook ran. Each setup call's post-hook
-- (SetSendMailCOD / Money, MailFrame.lua:1252-1266) empties insideSend, so what
-- it holds at SendMail's post-hook fired inside SendMail itself.
local sendwatch = false
local sendN, lastSend, phase, insideSend = 0, nil, nil, {}
local draft   -- the send draft, defined with the commands
-- capture: the inbox as of the last update (index -> { fp, line }, with the
-- GetTime() it was taken), the one before it, the inbox a button saw just
-- before its removal call (a pre-call point: PreClick), and the delete/return
-- waiting for an update that shows its mail gone.
local capturing = false
local before, prev, boundary, capture = {}, nil, nil, nil

-- The mail of each index now ({ fp, line }), the loaded count, and how many
-- mails share each fingerprint.
local function snapshot()
    local out = { loaded = counts() or 0, count = {} }
    for i = 1, out.loaded do
        local h = header(i)
        if h then
            local fp = fingerprint(h, i)
            out[i] = { fp = fp, line = describe(i) }
            out.count[fp] = (out.count[fp] or 0) + 1
        end
    end
    return out
end

local function fpCount(fp)
    local _, count = scanAll()
    return count[fp] or 0
end

-- Confirmed: its fingerprint one fewer and one mail fewer than before the call.
-- Committed a frame later: an update can fire inside a later call (a take that
-- empties the mail) before that call's post-hook drops the capture, and every
-- post-hook of this frame has run by the next one.
local function checkCapture(label)
    local c = capture
    local loaded, n = counts(), fpCount(c.fp)
    say(string.format("X %s +%.2f s after %s of mail %d: loaded %s -> %s, its fingerprint %d -> %d", label,
        GetTime() - c.at, c.kind, c.index, show(c.loaded), show(loaded), c.count, n))
    if n == c.count - 1 and loaded == c.loaded - 1 then
        C_Timer.After(0, function()
            if capture ~= c then return end
            say("X " .. c.kind .. " of mail " .. c.index .. " confirmed: one fewer of it, one mail fewer")
            capture = nil
        end)
    end
end

-- A button about to remove a mail: the inbox now is the inbox before the call.
local function markBoundary()
    if not capturing then return end
    boundary = snapshot()
    boundary.at = GetTime()
end

-- How long after the last send / delete / return a result came. An event
-- during the click is only collected here: whether it fired inside SendMail
-- is known at SendMail's post-hook (a later setup call clears the list).
local function since(event)
    local parts = {}
    if phase then
        insideSend[#insideSend + 1] = event
        parts[#parts + 1] = "during the Send click"
    end
    if sendwatch and lastSend then
        parts[#parts + 1] = string.format("+%.2f s after send #%d", GetTime() - lastSend.at, lastSend.n)
    end
    if capture then
        parts[#parts + 1] = string.format("+%.2f s after %s of mail %d", GetTime() - capture.at, capture.kind, capture.index)
    end
    return #parts > 0 and (" [" .. table.concat(parts, "; ") .. "]") or ""
end

local function sendButton()
    local b = global("SendMailMailButton")
    return b and show(b:IsEnabled()) or "MISSING"
end

local function logWatch()
    local loaded = counts() or 0
    for i = 1, math.max(loaded, #lastWatch) do
        local line = i <= loaded and describe(i) or (i .. ": (none)")
        if line ~= lastWatch[i] then say("W " .. line) end
        lastWatch[i] = line
    end
    for i = #lastWatch, loaded + 1, -1 do lastWatch[i] = nil end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        Probe:Ready()   -- logs EARLY if the host somehow isn't loaded
        if type(MailProbeDB) ~= "table" then MailProbeDB = {} end
        if type(MailProbeDB.log) ~= "table" then MailProbeDB.log = {} end
        Probe:UseLog(MailProbeDB.log, MAX_LOG)   -- from here on, lines are saved too
        MailProbeDB.loads = (MailProbeDB.loads or 0) + 1
        say("loaded (" .. MailProbeDB.loads .. " loads). /fp mail for the commands, /fp steps for session 6")
        return
    elseif event == "PLAYER_LOGIN" then
        installHooks()
        return
    end
    if event == "MAIL_INBOX_UPDATE" then
        local loaded, total = counts()
        if loaded ~= lastLoaded or total ~= lastTotal then
            say("I inbox loaded=" .. show(loaded) .. " total=" .. show(total))
            lastLoaded, lastTotal = loaded, total
        end
        if refillAt then
            say(string.format("refill: MAIL_INBOX_UPDATE %.2f s after CheckInbox, loaded=%s total=%s",
                GetTime() - refillAt, show(loaded), show(total)))
            refillAt = nil
        end
        if watching then logWatch() end
        if capture then checkCapture("update") end
        if capturing then
            prev, before = before, snapshot()
            before.at = GetTime()
        end
        return
    end
    if event == "UPDATE_PENDING_MAIL" then
        local okN, new = try("HasNewMail", global("HasNewMail"))
        local okS, s1, s2, s3 = try("GetLatestThreeSenders", global("GetLatestThreeSenders"))
        say("R UPDATE_PENDING_MAIL hasNewMail=" .. show(new) .. " senders=" .. args(s1, s2, s3)
            .. " minimap indicator shown=" .. indicator())
        return
    end
    if QUIET[event] and not busy and not (sendwatch and event == "MAIL_SEND_INFO_UPDATE") then return end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local t = ...
        if t ~= mailInfoType() then return end   -- only the mailbox
        say("L " .. event .. " (MailInfo=" .. show(t) .. ")")
        -- The close signal: MAIL_CLOSED never fired in session 2 (FOREVER-PROBE.md).
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and mailOpenSince then
            say(string.format("L mailbox was open %.1f s", GetTime() - mailOpenSince))
            mailOpenSince = nil
        end
        return
    end
    if event == "MAIL_SHOW" then
        mailOpenSince = GetTime()
        lastLoaded, lastTotal = nil, nil
    end
    local tag = (event:find("^MAIL_SHOW") or event:find("^MAIL_CLOSED") or event == "PLAYER_LEAVING_WORLD") and "L"
        or (event:find("SECURE_TRANSFER") and "!") or "R"
    say(tag .. " " .. event .. " (" .. args(...) .. ")" .. since(event))
    if sendwatch and (event == "MAIL_SEND_SUCCESS" or event == "MAIL_FAILED" or event == "MAIL_SEND_INFO_UPDATE") then
        say("S   Send button enabled=" .. sendButton())
    end
    if sendwatch and event == "MAIL_SEND_SUCCESS" then
        if lastSend then lastSend.done = true end
        local d = draft()
        say("S   draft now: to=" .. show(d.to) .. " money=" .. show(d.money) .. " items=" .. #d.items)
    end
    if event == "SECURE_TRANSFER_CONFIRM_SEND_MAIL" then
        local st = global("C_SecureTransfer")
        local ok, info = try("C_SecureTransfer.GetMailInfo", st and st.GetMailInfo)
        if ok and type(info) == "table" then
            say("!   GetMailInfo: target=" .. show(info.target) .. " sendMoney=" .. show(info.sendMoney))
        end
    end
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
            hooksecurefunc(name, function(...)
                say("C " .. name .. "(" .. args(...) .. ")")
                -- Any later mail action voids a removal still waiting (PLAN.md,
                -- Trash): a take that empties a mail must not confirm it.
                if capture and name ~= "DeleteInboxItem" and name ~= "ReturnInboxItem" then
                    say("X   capture (" .. capture.kind .. " of mail " .. capture.index .. ") dropped: " .. name .. " ran")
                    capture = nil
                end
            end)
        else
            say("C " .. name .. ": MISSING")
        end
    end
    -- Session 6: sendwatch and capture (they do nothing while off).
    local button = global("SendMailMailButton")
    if button then
        button:HookScript("PreClick", function()
            if not sendwatch then return end
            phase, insideSend = "click", {}
            local d = draft()
            say("S Send clicked: to=" .. show(d.to) .. " money=" .. show(d.money) .. " cod=" .. show(d.cod) .. " items="
                .. (#d.items > 0 and table.concat(d.items, " ") or "none") .. " postage=" .. show(d.price))
            -- SendMail's post-hook ends the phase in this same frame; this only
            -- catches a click that never reached SendMail.
            C_Timer.After(0, function()
                if phase then say("S the Send click never reached SendMail"); phase = nil end
            end)
        end)
    else
        say("SendMailMailButton: MISSING")
    end
    for _, name in ipairs({ "SetSendMailCOD", "SetSendMailMoney" }) do
        if global(name) then
            hooksecurefunc(name, function()
                -- Events from now until SendMail returns fired inside SendMail.
                if phase then insideSend = {} end
            end)
        end
    end
    if global("SendMail") then
        hooksecurefunc("SendMail", function(to)
            if not sendwatch then return end
            local overlap = lastSend and not lastSend.done
            sendN = sendN + 1
            lastSend = { n = sendN, at = GetTime() }
            local d = draft()
            say("S send #" .. sendN .. " to " .. show(to) .. ": draft at the post-hook money=" .. show(d.money) .. " cod="
                .. show(d.cod) .. " items=" .. (#d.items > 0 and table.concat(d.items, " ") or "none"))
            if phase then
                say("S   inside SendMail: " .. (#insideSend > 0 and table.concat(insideSend, ", ") or "no event"))
            else
                say("S   not from the Send button (no click seen)")
            end
            if overlap then say("S   OVERLAP: send #" .. (sendN - 1) .. " had no MAIL_SEND_SUCCESS yet") end
            phase = nil
        end)
    end
    for _, kind in ipairs({ "DeleteInboxItem", "ReturnInboxItem" }) do
        if global(kind) then
            hooksecurefunc(kind, function(i)
                if not capturing or type(i) ~= "number" then return end
                -- The inbox before the call: a button's PreClick in this frame
                -- saw it; else, with no update in this frame (GetTime() is the
                -- frame's time), the last update's snapshot still is it. An
                -- update in this frame without a pre-call point may have come
                -- inside the call or before it: ambiguous, logged, not captured.
                local base, from = nil, nil
                if boundary and boundary.at == GetTime() then
                    base, from = boundary, "the button's PreClick"
                elseif before.at ~= GetTime() then
                    base, from = before, "the last update"
                end
                boundary = nil
                if not base then
                    say("X " .. kind .. "(" .. i .. "): an inbox update came in this frame and no button marked the "
                        .. "inbox before the call: AMBIGUOUS, not captured")
                    say("X   before the update: " .. (prev and prev[i] and prev[i].line or "(no mail)"))
                    say("X   after it:          " .. (before[i] and before[i].line or "(no mail)"))
                    if capture then
                        say("X   previous capture (" .. capture.kind .. " of mail " .. capture.index .. ") dropped")
                    end
                    capture = nil
                    return
                end
                local was, loaded = base[i], counts()
                local h = header(i)
                local now = h and fingerprint(h, i)
                local inbox = global("InboxFrame")
                local open = global("OpenMailFrame")
                say("X " .. kind .. "(" .. i .. ") post-hook: loaded " .. show(base.loaded) .. " before the call ("
                    .. from .. "), " .. show(loaded) .. " now; open letter=" .. show(inbox and inbox.openMailID) .. " shown="
                    .. show(open and open:IsShown()))
                say("X   before: " .. (was and was.line or "(no mail)"))
                say("X   now:    " .. (h and describe(i) or "(no mail)") .. " -> "
                    .. (was and now == was.fp and "SAME mail at its index" or "NOT the same"))
                if capture then say("X   previous capture (" .. capture.kind .. " of mail " .. capture.index .. ") dropped") end
                capture = nil
                if was then
                    local c = { kind = kind, index = i, fp = was.fp, at = GetTime(), loaded = base.loaded,
                        count = base.count[was.fp] or 0 }
                    capture = c
                    -- Already gone at the hook (the server answered inside the call).
                    checkCapture("at the post-hook")
                    C_Timer.After(5, function()
                        if capture == c then say("X no update showed mail " .. i .. " gone within 5 s"); capture = nil end
                    end)
                end
            end)
        end
    end
    -- The letter's Delete / Return button (MailFrame.lua:1104-1120): a pre-call
    -- point. Its item and money deletes go through a confirmation popup
    -- instead, which has none.
    local letterButton = global("OpenMailDeleteButton")
    if letterButton then
        letterButton:HookScript("PreClick", markBoundary)
    else
        say("OpenMailDeleteButton: MISSING")
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
    say("state: hasNewMail=" .. show(new) .. " latest senders=" .. args(s1, s2, s3) .. " minimap indicator shown="
        .. indicator())
    say("state: freeSlots=" .. show(freeSlots()) .. " money secret=" .. show(okM and issecretvalue and issecretvalue(money))
        .. " UnitName=" .. args(name, second))
    say("state: mail frame shown=" .. show(global("MailFrame") and MailFrame:IsShown()) .. " MailInfo type="
        .. show(mailInfoType()))
end

function C.strings()
    local t = subjectTemplates()
    local names = {}
    for name in pairs(t) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do say("strings: " .. name .. " = " .. show(t[name])) end
    say("strings: " .. #names .. " AUCTION_*_MAIL_SUBJECT global(s)")
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
            -- Postmaster and system mail: anything here that tells them from a player.
            say("   icons package=" .. show(h.packageIcon) .. " stationery=" .. show(h.stationeryIcon) .. " textCreated="
                .. show(h.textCreated) .. " AH template=" .. show(subjectMatch(h.subject)))
            for a = 1, ATTACH_MAX do
                local ok, nm, itemID, _, count, quality, canUse, isCurrency = try("GetInboxItem", global("GetInboxItem"), i, a)
                if ok and nm ~= nil then
                    local okL, link = try("GetInboxItemLink", global("GetInboxItemLink"), i, a)
                    say(string.format("   slot %d: %s id=%s count=%s q=%s usable=%s currency=%s link=%s", a, show(nm),
                        show(itemID), show(count), show(quality), show(canUse), show(isCurrency),
                        okL and show(link) or "ERROR"))
                end
            end
            local inv = pack(try("GetInboxInvoiceInfo", global("GetInboxInvoiceInfo"), i))
            if inv[1] and inv[2] ~= nil then
                say("   invoice: " .. args(unpack(inv, 2, inv.n)))
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
            local fp, resolved = fingerprint(h, i)
            if not resolved then say("dupes: mail " .. i .. " has an attachment with no link (unresolved)") end
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

function C.watch(arg)
    watching = arg ~= "off"
    lastWatch = {}
    if watching then logWatch() end
    say("watch " .. (watching and "on: every mail is logged again whenever an update changes it" or "off"))
end

-- A bitmask AND for the bag family (no bit library in the API dump).
local function band(a, b)
    local r, bitv = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
        a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
    end
    return r
end

-- What I1's fit rule would see for each of mail N's attachments. Compare with
-- what a take then does (`bags` before and after, MAIL_FAILED).
function C.fit(arg)
    local i = tonumber(arg)
    if not i then say("fit N: N is the mail number from /mailprobe inbox, e.g. /mailprobe fit 2"); return end
    local c, ci = global("C_Container"), global("C_Item")
    if not (c and ci) then say("fit: C_Container or C_Item MISSING"); return end
    local nb = global("NUM_BAG_SLOTS") or 4
    local bags = {}
    for bag = 0, nb + 1 do
        local okS, slots = try("GetContainerNumSlots", c.GetContainerNumSlots, bag)
        local okF, free, family = try("GetContainerNumFreeSlots", c.GetContainerNumFreeSlots, bag)
        if okS and slots and slots > 0 then
            bags[#bags + 1] = { bag = bag, slots = slots, free = okF and free or 0, family = okF and family or nil }
        end
    end
    say("fit: general free (Blizzard's total) " .. show(freeSlots()))
    for _, it in ipairs(attachments(i)) do
        local id = it.itemID
        local okM, maxStack = try("GetItemMaxStackSizeByID", ci.GetItemMaxStackSizeByID, id)
        local okFam, itemFamily = try("GetItemFamily", ci.GetItemFamily, id)
        local okC, held = try("GetItemCount", ci.GetItemCount, id)
        local okI, info = try("GetItemInfo", ci.GetItemInfo, id)
        local room, specialty = 0, 0
        for _, b in ipairs(bags) do
            for s = 1, b.slots do
                local okG, item = try("GetContainerItemInfo", c.GetContainerItemInfo, b.bag, s)
                if okG and type(item) == "table" and item.itemID == id and type(maxStack) == "number"
                        and type(item.stackCount) == "number" and item.stackCount < maxStack then
                    room = room + maxStack - item.stackCount
                end
            end
            if type(b.family) == "number" and b.family ~= 0 and type(itemFamily) == "number"
                    and band(b.family, itemFamily) ~= 0 then
                specialty = specialty + (b.free or 0)
            end
        end
        say(string.format("fit %d slot %d: id=%s x%s maxStack=%s family=%s held=%s cached=%s room in partial stacks=%s "
            .. "specialty free=%s", i, it.slot, show(id), show(it.count), okM and show(maxStack) or "ERROR",
            okFam and show(itemFamily) or "ERROR", okC and show(held) or "ERROR", show(okI and info ~= nil),
            show(room), show(specialty)))
    end
end

-- Fetch more mail from the server, as I1's refill would. Only meaningful when
-- the server holds more than the loaded window (total > loaded, past 100).
function C.refill()
    local loaded, total = counts()
    local cm = global("C_Mail")
    local okC, can, wait = try("CanCheckInbox", cm and cm.CanCheckInbox)
    say("refill: loaded=" .. show(loaded) .. " total=" .. show(total) .. " canCheck=" .. show(can) .. " wait=" .. show(wait))
    if not (type(loaded) == "number" and type(total) == "number" and total > loaded) then
        say("refill: total is not above loaded, so there is nothing more to fetch (needs over 100 mails); checking anyway")
    end
    if not can then say("refill: not allowed yet; run it again in " .. show(wait) .. " s"); return end
    if refillAt then say("refill: one is already waiting for its update"); return end
    -- The next MAIL_INBOX_UPDATE is logged as the answer: run nothing else meanwhile.
    local at = GetTime()
    refillAt = at
    try("CheckInbox", global("CheckInbox"))
    C_Timer.After(10, function()
        if refillAt == at then say("refill: no MAIL_INBOX_UPDATE within 10 s"); refillAt = nil end
    end)
end

-- Return several mails in a row: the first from the key press, the rest from
-- timers, each found again by its fingerprint after the previous one is gone.
-- Twins and mails with an unloaded attachment are refused, as M1 will.
function C.returnmany(arg)
    local list = {}
    for n in arg:gmatch("%d+") do list[#list + 1] = tonumber(n) end
    if #list < 2 then
        say("returnmany A B [C...]: two or more mail numbers from /mailprobe inbox (ONLY test mails: they go back)")
        return
    end
    local _, count = scanAll()
    local targets = {}
    for _, i in ipairs(list) do
        local h = header(i)
        if not h then say("returnmany: no mail " .. i); return end
        local fp, resolved = fingerprint(h, i)
        if not resolved then say("returnmany: mail " .. i .. " has an attachment with no link yet; try again"); return end
        if count[fp] ~= 1 then say("returnmany: mail " .. i .. " has an identical twin; pick another"); return end
        if not returnable(i) then say("returnmany: mail " .. i .. " can't be returned (Blizzard would delete it)"); return end
        targets[#targets + 1] = { fp = fp, was = i }
    end
    local cm = global("C_Mail")
    local k, sentAt, before, steps = 1, nil, nil, 0
    busy = true
    local function finish(msg) say("returnmany: " .. msg); busy = false end
    local function step()
        steps = steps + 1
        if steps > 400 then finish("stop (too many steps)"); return end
        local t = targets[k]
        if not t then finish("done, " .. #targets .. " mail(s)"); return end
        if sentAt then
            -- Gone means no match AND one mail fewer: a fingerprint that merely
            -- changed (a link, wasReturned) must not pass for a return.
            local i, n = indexOf(t.fp)
            local loaded = counts()
            if n == 0 and loaded == before - 1 then
                say(string.format("returnmany: mail (was %d) gone %.2f s after its return", t.was, GetTime() - sentAt))
                k, sentAt = k + 1, nil
                C_Timer.After(0.5, step)
            elseif n == 0 and loaded == before then
                finish(string.format("mail (was %d) no longer matches but the inbox didn't shrink; stop (uncertain)", t.was))
            elseif GetTime() - sentAt > 10 then
                finish(string.format("mail (was %d) still there 10 s after its return (now %s); stop", t.was, show(i)))
            else
                C_Timer.After(0.2, step)
            end
            return
        end
        if cm and cm.IsCommandPending and cm.IsCommandPending() then C_Timer.After(0.2, step); return end
        local i, n = indexOf(t.fp)
        if not i then
            say("returnmany: mail (was " .. t.was .. ") now has " .. n .. " matches; skipped")
            k = k + 1
            C_Timer.After(0.2, step)
            return
        end
        if not returnable(i) then finish("mail (was " .. t.was .. ") can no longer be returned; stop"); return end
        local h = header(i)
        say("returnmany: mail (was " .. t.was .. ") is now " .. i .. ", canReply=" .. show(h and h.canReply)
            .. " wasReturned=" .. show(h and h.wasReturned) .. (steps == 1 and " - returning from the key press"
            or " - returning from a timer"))
        sentAt, before = GetTime(), counts()
        try("ReturnInboxItem", global("ReturnInboxItem"), i)
        C_Timer.After(0.2, step)
    end
    step()
end

function C.readtest(arg)
    local i = tonumber(arg)
    if not i then say("readtest N: N is the mail number from /mailprobe inbox, e.g. /mailprobe readtest 2"); return end
    local before = header(i)
    if not before then return end
    try("GetInboxText", global("GetInboxText"), i)
    local after = header(i)
    say("readtest " .. i .. ": wasRead before=" .. show(before.wasRead) .. " right after GetInboxText="
        .. show(after and after.wasRead) .. " (check again with /mailprobe inbox after the next update)")
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
    if not i then say("take N [slot]: N is the mail number from /mailprobe inbox, e.g. /mailprobe take 4"); return end
    try("TakeInboxItem", global("TakeInboxItem"), i, slot)
end

function C.money(arg)
    local i = tonumber(arg)
    if not i then say("money N: N is the mail number from /mailprobe inbox, e.g. /mailprobe money 3"); return end
    say("money: free slots " .. show(freeSlots()))
    try("TakeInboxMoney", global("TakeInboxMoney"), i)
end

-- Take mail N's attachments one by one, every step after the first from a
-- timer: does the client allow a loot chain without a key press per step?
-- Paced like Blizzard's Open All: wait while a command is pending, 0.3 s apart.
function C.taketimer(arg)
    local i = tonumber(arg)
    if not i then say("taketimer N: N is the mail number from /mailprobe inbox, e.g. /mailprobe taketimer 2"); return end
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
    if not i then say("returnnow N: N is the mail number from /mailprobe inbox"); return end
    local h = header(i)
    say("returnnow " .. i .. ": sender=" .. show(h and h.sender) .. " subject=" .. show(h and h.subject))
    try("ReturnInboxItem", global("ReturnInboxItem"), i)
end

function C.returntimer(arg)
    local i = tonumber(arg)
    if not i then say("returntimer N: N is the mail number from /mailprobe inbox"); return end
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

-- The mail's first occupied attachment slot, or nil. Slots don't renumber
-- after a take (session 5): slot 1 empties, slot 2 stays slot 2. An uncached
-- item has the name "" but its itemID, so either one marks the slot taken.
local function firstSlot(i)
    for a = 1, ATTACH_MAX do
        local ok, nm, itemID = try("GetInboxItem", global("GetInboxItem"), i, a)
        if ok and (nm ~= nil or itemID ~= nil) then return a end
    end
end

-- Our own row controls, as M1 will build them: children of InboxFrame (so
-- they show and hide with it), one level above each row, never fields on
-- Blizzard's frames. Click them in and out of combat; watch for "!" lines.
local ROW_ACTIONS = {
    { "T", function(i, h)
        -- COD needs Blizzard's confirmation (COD_CONFIRMATION): never from here.
        if (plain(h.CODAmount) or 0) > 0 then say("rows: mail " .. i .. " is COD; not taken"); return end
        if plain(h.money) and h.money > 0 then
            try("TakeInboxMoney", global("TakeInboxMoney"), i)
            return
        end
        local a = firstSlot(i)
        if not a then say("rows: mail " .. i .. " has nothing left to take"); return end
        try("TakeInboxItem", global("TakeInboxItem"), i, a)
    end },
    { "R", function(i, h)
        if not returnable(i) then say("rows: mail " .. i .. " can't be returned; not sent"); return end
        markBoundary()
        try("ReturnInboxItem", global("ReturnInboxItem"), i)
    end },
    { "D", function(i, h)
        local okD, can = try("InboxItemCanDelete", global("InboxItemCanDelete"), i)
        if plain(h.itemCount) or (plain(h.money) or 0) > 0 or not (okD and can) then
            say("rows: mail " .. i .. " isn't empty or can't be deleted; not sent")
            return
        end
        markBoundary()
        try("DeleteInboxItem", global("DeleteInboxItem"), i)
    end },
}
local rowButtons = {}
function C.rows(arg)
    local on = arg ~= "off"
    local inbox = global("InboxFrame")
    if not inbox then say("InboxFrame: MISSING"); return end
    local perPage = global("INBOXITEMS_TO_DISPLAY") or 7
    for r = 1, perPage do
        local row = global("MailItem" .. r)
        if row and not rowButtons[r] then
            rowButtons[r] = {}
            for n, action in ipairs(ROW_ACTIONS) do
                local b = CreateFrame("Button", nil, inbox, "UIPanelButtonTemplate")
                b:SetSize(20, 16)
                b:SetText(action[1])
                b:SetFrameLevel(row:GetFrameLevel() + 2)
                -- Bottom right: the row's expiry text is at its top right.
                b:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2 - (#ROW_ACTIONS - n) * 21, 2)
                b:SetScript("OnClick", function()
                    local i = ((inbox.pageNum or 1) - 1) * perPage + r
                    local h = header(i)
                    say("rows: " .. action[1] .. " on row " .. r .. " -> mail " .. i .. " sender=" .. show(h and h.sender)
                        .. " combat=" .. show(InCombatLockdown()))
                    if h then action[2](i, h) end
                end)
                rowButtons[r][n] = b
            end
        end
        for _, b in ipairs(rowButtons[r] or {}) do b:SetShown(on) end
    end
    say("rows " .. (on and "on" or "off") .. ": T take, R return, D delete (empty mail only)")
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

function draft()
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

-- Session 6. Send with Blizzard's own button; every S line is about a send.
function C.sendwatch(arg)
    sendwatch = arg ~= "off"
    say("sendwatch " .. (sendwatch and "on: send as usual; each send is numbered, results are timed from it"
        or "off"))
end

-- Session 6. Delete or return as usual (the letter's buttons, our row icons):
-- every X line is about the last one.
function C.capture(arg)
    capturing = arg ~= "off"
    before, prev, boundary = capturing and snapshot() or {}, nil, nil
    before.at = GetTime()
    if not capturing then capture = nil end
    say("capture " .. (capturing and "on: delete or return a mail as usual" or "off"))
end

-- A name as S1 would read it: secret or not, a realm suffix or not.
local function nameLine(label, name)
    if issecretvalue and issecretvalue(name) then return label .. " <secret>" end
    if type(name) ~= "string" then return label .. " " .. show(name) end
    local amb = global("Ambiguate")
    local okA, short = try("Ambiguate", amb, name, "none")
    return string.format("%s %s suffix=%s Ambiguate(none)=%s", label, show(name), show(name:find("-", 1, true) ~= nil),
        okA and show(short) or "ERROR")
end

-- Session 6. The guild roster loads on request: run it again a few seconds
-- later if the count is 0. Names go to the log: blur them in anything shared.
function C.names()
    local okU, n, realm = try("UnitFullName", global("UnitFullName"), "player")
    local okR, rn = try("GetRealmName", global("GetRealmName"))
    local okN, norm = try("GetNormalizedRealmName", global("GetNormalizedRealmName"))
    local okI, inInstance, kind = try("IsInInstance", global("IsInInstance"))
    say("names: you " .. args(n, realm) .. " realm=" .. show(rn) .. " normalized=" .. show(norm) .. " instance="
        .. args(inInstance, kind))
    local fl = global("C_FriendList")
    local okF, nf = try("C_FriendList.GetNumFriends", fl and fl.GetNumFriends)
    say("names: " .. show(nf) .. " friend(s)")
    for i = 1, (okF and type(plain(nf)) == "number") and nf or 0 do
        local ok, info = try("GetFriendInfoByIndex", fl.GetFriendInfoByIndex, i)
        if ok and type(info) == "table" then
            say(nameLine("names: friend " .. i, info.name) .. " connected=" .. show(info.connected))
        end
    end
    local okG, inGuild = try("IsInGuild", global("IsInGuild"))
    if not (okG and inGuild) then say("names: not in a guild"); return 0, false end
    local gi = global("C_GuildInfo")
    try("C_GuildInfo.GuildRoster", gi and gi.GuildRoster)
    local okM, members = try("GetNumGuildMembers", global("GetNumGuildMembers"))
    local count = (okM and type(plain(members)) == "number") and members or 0
    say("names: " .. show(members) .. " guild member(s); the first 10:")
    for i = 1, math.min(count, 10) do
        local ok, name = try("GetGuildRosterInfo", global("GetGuildRosterInfo"), i)
        if ok then say(nameLine("names: guild " .. i, name)) end
    end
    local suffixed, secret = 0, 0
    for i = 1, count do
        local ok, name = try("GetGuildRosterInfo", global("GetGuildRosterInfo"), i)
        if ok and issecretvalue and issecretvalue(name) then
            secret = secret + 1
        elseif ok and type(name) == "string" and name:find("-", 1, true) then
            suffixed = suffixed + 1
        end
    end
    say("names: guild: " .. suffixed .. " with a realm suffix, " .. secret .. " secret, of " .. count)
    return count, true
end

function C.clear() Probe:ClearLog(); say("log cleared") end

-- /fp mail <command>: the commands, with the help /fp mail lists.
local COMMANDS = {
    { "state", "inbox counts, CanCheckInbox, pending command, bag space, money secrecy, new mail" },
    { "strings", "the client's AUCTION_*_MAIL_SUBJECT templates" },
    { "inbox", "every loaded mail's header, attachments with links, invoice, AH template" },
    { "dupes", "mails that look identical (identity without a server id)" },
    { "watch", "on/off: log every mail whenever an inbox update changes it" },
    { "fit", "N: mail N's attachments against the bags (what Open All decides from)" },
    { "refill", "CheckInbox() when allowed, and how long until the next update" },
    { "readtest", "N: does GetInboxText mark mail N read?" },
    { "bags", "free slots per bag, with the bag family" },
    { "take", "N [slot]: TakeInboxItem from the command" },
    { "money", "N: TakeInboxMoney from the command" },
    { "taketimer", "N: mail N's attachments slot by slot, from timers" },
    { "returnnow", "N: ReturnInboxItem from the command (ONLY a test mail)" },
    { "returntimer", "N: ReturnInboxItem from a timer, 1 s later (ONLY a test mail)" },
    { "returnmany", "A B ..: several returns in a row, each found again (ONLY test mails)" },
    { "hidestock", "hide Blizzard's Open All button" },
    { "showstock", "show Blizzard's Open All button" },
    { "rows", "on/off: our T / R / D buttons on the inbox rows" },
    { "picker", "NAME: a button by the recipient box that fills it with NAME" },
    { "draft", "the send draft: recipient, subject, attachments, money, COD, postage" },
    { "split", "BAG SLOT N: split N off a stack and attach it to the draft" },
    { "sendnow", "SendMail(draft) from the command" },
    { "sendtimer", "SendMail(draft) from a timer, 1 s later" },
    { "sendwatch", "on/off: each send numbered, timed, and what fires inside SendMail (session 6)" },
    { "capture", "on/off: what a delete/return post-hook sees, and its confirmation (session 6)" },
    { "names", "own, friends' and guild members' name formats (session 6)" },
    { "clear", "empty the saved log" },
}
for _, c in ipairs(COMMANDS) do
    local fn = C[c[1]]
    Probe:Command(c[1], function(arg) fn(arg or "") end, c[2])
end

--------------------------------------------------------------------------------
-- Session 6 as procedures: /fp steps mail <name>. Each step is one thing to do;
-- the probe's own lines (S, X, names) are the measurement, the panel's Note box
-- takes what only the owner sees.
--------------------------------------------------------------------------------

local function watchBoth()
    C.sendwatch("on")
    C.capture("on")
    return "sendwatch and capture on"
end

-- A send step: it completes on MAIL_SEND_SUCCESS; Done if the mail never goes.
local function sendStep(text) return { text = text .. " The step completes when the mail is sent (Done if it isn't).",
    event = "MAIL_SEND_SUCCESS" } end

Probe:Steps("send", {
    title = "Session 6: sends",
    { text = "At a mailbox, open the Send Mail tab.", auto = true, run = watchBoth },
    sendStep("Send a plain letter to one of your alts: no item, no gold."),
    sendStep("Send an alt a letter with one item attached."),
    sendStep("Send an alt a letter with some gold (Send Money)."),
    sendStep("Send an alt an item with C.O.D. set."),
    sendStep("Send a stranger an item, and CONFIRM the dialog that appears."),
    { text = "Did a confirmation dialog appear for the stranger?", ask = true },
    { text = "Send a stranger an item again, and this time CANCEL the dialog. Then press Next." },
    { text = "Send a letter to a name that doesn't exist. Press Next once the error shows." },
    { text = "If you can, send with too little gold for the postage (Skip if not). Press Next after." },
    { text = "Send to a character of the other faction (Skip if you have none). Note what happened." },
    { text = "Send to a character on another ruleset (Skip if none). Note what happened." },
    { text = "Send to a character on your other account (Skip if none). Note what happened." },
})

Probe:Steps("timing", {
    title = "Session 6: send timing",
    { text = "At a mailbox, open the Send Mail tab.", auto = true, run = watchBoth },
    sendStep("Send an alt a letter, then close the mailbox at once (walk away or Esc)."),
    { text = "Open the mailbox. Send an alt a letter, then at once shift-click an inbox row to take its mail. "
        .. "Press Next after." },
    { text = "Send an alt a letter, and as fast as you can fill a second one and Send it too. "
        .. "Press Next once both are sent (or failed)." },
})

Probe:Steps("capture", {
    title = "Session 6: delete and return",
    { text = "Open the mailbox's inbox.", auto = true, run = function()
        C.capture("on")
        C.rows("on")
        return "capture on, row buttons on"
    end },
    { text = "Open an EMPTY mail (no item, no gold) and press Delete in the letter. Press Next after." },
    { text = "Open a test mail you can send back and press Return in the letter. Press Next after." },
    { text = "Press the R button on another test mail's row (it returns it). Press Next after." },
    { text = "Open an Auction House mail with items, press Delete, and accept the popup. Press Next after." },
    { text = "Done: turning the row buttons off.", auto = true, run = function()
        C.rows("off")
        return "row buttons off"
    end },
})

Probe:Steps("picker", {
    title = "Session 6: picker to a stranger",
    { text = "At a mailbox's Send Mail tab, type /fp mail picker First Surname with a stranger's name. "
        .. "An @ button appears by the recipient box. Press Next." },
    { text = "Attach an item, click @, press Send and CONFIRM the dialog.", event = "MAIL_SEND_SUCCESS" },
    { text = "Was anything blocked (a red BLOCKED or FORBIDDEN line in /fp, or an error)?", ask = true },
})

-- The guild roster loads on request: ask, wait for it, then read. A read with
-- an empty roster in a guild is a FAIL on the step, not a silent empty sample.
local lastNames = {}
local function readNames(where)
    local count, inGuild = C.names()
    lastNames = { count = count, inGuild = inGuild }
    return "names read " .. where
end
local function namesRead()
    if not lastNames.inGuild then return true, "not in a guild" end
    return (lastNames.count or 0) > 0, "guild members read: " .. tostring(lastNames.count)
end

Probe:Steps("names", {
    title = "Session 6: name formats",
    rev = 2,
    { text = "In town: asking for your guild's roster.", auto = true, run = function()
        local gi = global("C_GuildInfo")
        try("C_GuildInfo.GuildRoster", gi and gi.GuildRoster)
        return "roster requested"
    end },
    { text = "Waiting for the guild roster. Press Done if you aren't in a guild, or nothing happens within "
        .. "a few seconds.", event = "GUILD_ROSTER_UPDATE" },
    { text = "Reading your own, your friends' and your guild's names. If the check fails (no guild member "
        .. "read), wait a few seconds and press Back, then Done.", auto = true,
        run = function() return readNames("in town") end, check = namesRead },
    { text = "Enter an instance (a dungeon is fine), then press Read.", button = "Read",
        run = function() return readNames("in an instance") end, check = namesRead },
})

Probe:Steps("release", {
    title = "Session 6: the v0.1.0 checks",
    { text = "At a mailbox with gold in a mail, click Glass Mail's Open All, then close the mailbox." },
    { text = "Was the gold Open All took said in chat when the mailbox closed?", ask = true },
    { text = "Open the mailbox again and use a row's Return or Delete icon once (a test mail). Press Next." },
    { text = "Was anything blocked (a red BLOCKED or FORBIDDEN line in /fp, or an error)?", ask = true },
    { text = "Type /reload to save the results.", reload = true },
})

NS._test = { Probe = Probe }   -- the test seam, never on _G
