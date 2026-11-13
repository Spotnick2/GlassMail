-- Inbox.lua: I2 selection and I3 row extras, on our own frames inside
-- InboxFrame.
--
-- Each inbox row gets a checkbox and a Return / Delete icon at its bottom
-- right, under the expiry (Blizzard's subject is narrowed to make room; the
-- full subject is in the tooltip). The selection is a set of fingerprints for
-- this mailbox visit. A mail can be ticked, and its icon used, only while no
-- other mail has its fingerprint: there is no stable mail ID (CLAUDE.md).
-- Every action goes through Core/Ops.lua. The bar above the rows offers
-- Open (n), Return next (n left) (one click per mail: several returns in a
-- row are unmeasured, FOREVER-PROBE session 5) and Clear.
--
-- The row tooltip gets one line per attachment and the full subject, added
-- after Blizzard's own lines (it rebuilds them every frame while the tooltip
-- is up, MailFrame.xml:160, so the hook runs every frame too).
--
-- GlassMail.Selection is the selection's public read API (issue #26, for
-- Shatter's Mail Mode): Get() and OnChange(fn), at the end of this file.
--
-- N2's recalls (Core/Recall.lua) show here too: a tint on each row that could
-- be a recalled mail (the accent when sure, amber when only possible), a line
-- in its tooltip, and a notice under the rows, whatever the page, with a
-- Return button for a sure one. The button is the only thing that acts.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Scan, Ops, Recall, Store = GM.Scan, GM.Ops, GM.Recall, GM.Store
local say = API.Print
local Inbox = {}
GM.Inbox = Inbox
local Selection = {}
GM.Selection = Selection

local ROWS = 7               -- INBOXITEMS_TO_DISPLAY
local MAILBOX = 17           -- Enum.PlayerInteractionType.MailInfo
local SUBJECT_WIDTH = 204    -- Blizzard's 248 (MailFrame.xml:43), less our two controls
local RETURN_ICON = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local DELETE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local LOADING = "Loading..."
local TWIN = "Identical to another mail: use the row itself"
local WAITING = "Waiting for mail to load"
local AMBER = { 1, 0.7, 0.28 }
local TINT_ALPHA = 0.16
Inbox.RECALL_SURE = "Glass Mail: you asked to send this back"
Inbox.RECALL_POSSIBLE = "Glass Mail: this could be a mail you asked to send back. Check it before returning it."

local rows = {}              -- [i] = { check, icon, tint, fp, action, why, recall }
local rowOf = {}             -- Blizzard's MailItemNButton -> i (our table, nothing written on theirs)
local selected = {}          -- fingerprint -> true
local anchor                 -- the last plainly clicked fingerprint, for shift ranges
local bar                    -- { frame, open, ret, clear }
local notice                 -- { frame, text, ret, fp }: N2's line under the rows
local itemLines = {}         -- [inbox index] = the tooltip's attachment lines, until the next update
local snap, counts = { mails = {} }, {}
local listeners = {}         -- Selection.OnChange callbacks
local reported = ""          -- the selection's indices as listeners last saw them

local function busy() return API.InCombat() or Ops.Running() end

-- What the checkboxes show: during the selection's own run, its live targets
-- (moved to each residual inside Ops, so Blizzard's refresh, which runs
-- before Ops confirms on the same MAIL_INBOX_UPDATE, can't lose one).
local function live()
    if Ops.Kind() == "selected" then return Ops.Targets() or {} end
    return selected
end

-- What the public API sees: nothing while the mailbox is closed, even in the
-- moment between our close handler and Ops' (a selected run's targets are
-- still live until Ops stops it).
local mailboxOpen = false
local function public()
    if not mailboxOpen then return {} end
    return live()
end

local function size(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local function unique(m) return m ~= nil and m.fp ~= nil and counts[m.fp] == 1 end

-- The mails of snapshot s (with its counts c) that are in set and have no
-- twin, as { [inbox index] = true }, and their indices as a key ("2,5").
local function picked(s, c, set)
    local out, keys = {}, {}
    for _, m in ipairs(s.mails) do
        if m.fp and c[m.fp] == 1 and set[m.fp] then
            out[m.index] = true
            keys[#keys + 1] = m.index
        end
    end
    return out, table.concat(keys, ",")
end

-- Tell the OnChange listeners, once, when what Selection.Get returns changed.
local function report()
    if #listeners == 0 then return end
    local _, key = picked(snap, counts, public())
    if key == reported then return end
    reported = key
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then API.Fail("selection listener", err) end
    end
end

-- The selected mails Blizzard would return, in inbox order.
local function returnable()
    local list = {}
    for _, m in ipairs(snap.mails) do
        if unique(m) and selected[m.fp] and Ops.RowAction(m) == "return" then list[#list + 1] = m end
    end
    return list
end

local function quoted(s) return '"' .. (s or "") .. '"' end

-- N2's notice: the first sure recall with its Return button, else what the
-- first possible one needs from the player; "+N more" for the rest.
local function paintNotice(found, ready)
    notice.fp = nil
    if #found == 0 then return notice.frame:Hide() end
    local first
    for _, f in ipairs(found) do
        if f.sure then first = f; break end
    end
    local more = #found - 1
    local text
    if first then
        local m = first.sure
        text = "Recall: " .. quoted(m.subject) .. " from " .. (m.sender or "?")
        notice.fp = m.fp
    else
        first = found[1]
        local n, subject = #first.mails, quoted(first.rec.subject)
        local twins = n > 1 and first.mails[1].fp ~= nil
        for _, m in ipairs(first.mails) do
            if m.fp ~= first.mails[1].fp then twins = false end
        end
        if twins then
            text = "Recall: " .. n .. " identical mails could be " .. subject .. ": open one and use its Return button"
        elseif n > 1 then
            text = "Recall: " .. n .. " mails could be " .. subject .. ": check the highlighted rows"
        else
            text = "Recall: a mail could be " .. subject .. ": check the highlighted row"
        end
    end
    if more > 0 then text = text .. " (+" .. more .. " more)" end
    notice.text:SetText(text)
    notice.ret:SetShown(notice.fp ~= nil)
    notice.ret:SetEnabled(notice.fp ~= nil and ready and counts[notice.fp] == 1)
    notice.frame:Show()
end

local function refresh()
    if not bar then return end
    snap = Scan.Inbox()
    counts = Scan.Count(snap)
    local recalls = Recall.Inbox(snap, counts)
    -- Outside the selection's own run, a selected mail that is gone or now has
    -- a twin leaves the selection. Not while a mail is loading: its
    -- fingerprint isn't counted yet.
    if Ops.Kind() ~= "selected" and snap.resolved then
        for fp in pairs(selected) do
            if counts[fp] ~= 1 then selected[fp] = nil end
        end
    end
    local byIndex = {}
    for _, m in ipairs(snap.mails) do byIndex[m.index] = m end
    local page = InboxFrame.pageNum or 1
    local set, letter = live(), Ops.LetterOpen()
    local idle = not busy() and not letter
    local ready = idle and snap.resolved   -- an action waits for the whole inbox (Ops)
    for i, row in ipairs(rows) do
        local m = byIndex[(page - 1) * ROWS + i]
        row.fp, row.action, row.why = m and m.fp, nil, nil
        row.recall = m and recalls.rows[m.index] or nil
        if row.recall then
            local c = row.recall == "sure" and GM.Suite.AccentColor() or AMBER
            row.tint.tex:SetColorTexture(c[1], c[2], c[3], TINT_ALPHA)
        end
        row.tint:SetShown(row.recall ~= nil)
        if not m then
            row.check:Hide()
            row.icon:Hide()
        else
            local one = unique(m)
            if not m.fp then row.why = LOADING elseif not one then row.why = TWIN end
            row.check:Show()
            row.check:SetChecked(one and set[m.fp] == true)
            row.check:SetEnabled(one and idle)
            row.action = m.fp and Ops.RowAction(m) or nil
            row.icon:SetShown(row.action ~= nil)
            if row.action then
                local file = row.action == "return" and RETURN_ICON or DELETE_ICON
                row.icon:SetNormalTexture(file)
                row.icon:SetDisabledTexture(file)   -- greyed: a Button has no disabled look of its own
                row.icon:GetDisabledTexture():SetDesaturated(true)
                row.icon:SetEnabled(one and ready)
            end
        end
    end
    local own = Ops.Kind() == "selected"
    local shown = own or next(selected) ~= nil
    bar.frame:SetShown(shown)
    GM.OpenAll.ShowCount(not shown)   -- the bar takes the message count's place
    if own then
        bar.open:SetText("Stop")
        bar.open:Enable()
    else
        bar.open:SetText("Open (" .. size(selected) .. ")")
        bar.open:SetEnabled(ready and next(selected) ~= nil)
    end
    local n = #returnable()
    bar.ret:SetText("Return next (" .. n .. " left)")
    bar.ret:SetEnabled(ready and n > 0)
    bar.clear:SetEnabled(idle)
    paintNotice(recalls.found, ready)
    report()
end

local function mailOf(fp)
    for k, m in ipairs(snap.mails) do
        if m.fp == fp then return m, k end
    end
end

-- Plain click toggles; shift adds every eligible mail from the anchor to this
-- one (inbox order, across pages); ctrl adds every eligible mail from the
-- same sender.
local function onCheck(i)
    local row = rows[i]
    local m = row.fp and mailOf(row.fp)
    if busy() or Ops.LetterOpen() or not unique(m) then return refresh() end
    local from = anchor and select(2, mailOf(anchor))
    if IsShiftKeyDown() and from and unique(snap.mails[from]) then
        local _, to = mailOf(m.fp)
        if from > to then from, to = to, from end
        for k = from, to do
            if unique(snap.mails[k]) then selected[snap.mails[k].fp] = true end
        end
    elseif IsControlKeyDown() then
        for _, other in ipairs(snap.mails) do
            if unique(other) and other.sender == m.sender then selected[other.fp] = true end
        end
    else
        selected[m.fp] = not selected[m.fp] or nil
        anchor = m.fp
    end
    refresh()
end

local function act(kind, fp)
    -- A returned or deleted mail leaves the selection at the next refresh (gone).
    Ops.Act(kind, fp, function(r)
        if r.stopReason ~= "done" then say(kind .. " stopped: " .. r.stopReason) end
    end)
end

local function onIcon(i)
    local row = rows[i]
    if busy() or Ops.LetterOpen() or not snap.resolved or not row.action or counts[row.fp] ~= 1 then return end
    act(row.action, row.fp)
end

local function onOpen()
    if Ops.Kind() == "selected" then return Ops.Stop("stopped") end
    if busy() or Ops.LetterOpen() or not snap.resolved or next(selected) == nil then return end
    Ops.OpenSelected(selected, { keepFree = GM.db.keepFree }, function(r)
        -- What is left of the run's targets, moved to their residuals, is the
        -- selection again; not once the mailbox closed (its close may have
        -- cleared the selection before this run heard of it).
        selected = {}
        if r.stopReason ~= "mailbox closed" then
            for fp in pairs(r.opts.only) do selected[fp] = true end
        end
        GM.OpenAll.Summary(r)
    end, refresh)
end

-- The notice's Return: the sure recall's mail, with the row icon's guards.
local function onRecallReturn()
    local fp = notice.fp
    if busy() or Ops.LetterOpen() or not snap.resolved or not fp or counts[fp] ~= 1 then return refresh() end
    act("return", fp)
end

local function onReturnNext()
    if busy() or Ops.LetterOpen() or not snap.resolved then return end
    local m = returnable()[1]
    if m then act("return", m.fp) end
end

local function clear()
    if busy() or Ops.LetterOpen() then return end
    selected, anchor = {}, nil
    refresh()
end

-- Tooltips on our controls say why one is disabled.
local function tip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function why(row)
    if row.why then return row.why end
    if API.InCombat() then return "Not in combat" end
    if Ops.Running() then return "Busy: wait for the current action" end
    if Ops.LetterOpen() then return "Close the letter first" end
end

local function checkTip(i)
    local w = why(rows[i])
    if w then tip(rows[i].check, w) end
end

local function iconTip(i)
    local row = rows[i]
    local text = row.action == "return" and "Return to sender" or "Delete"
    local w = why(row) or (not snap.resolved and WAITING)
    tip(row.icon, w and (text .. "\n" .. w) or text)
end

-- The row tooltip's extra lines: each attachment of a mail with two or more,
-- cached per index until the next inbox update (once every link is known).
local function attachmentLines(index)
    if itemLines[index] then return itemLines[index] end
    local lines, complete = {}, true
    local itemCount = select(8, GetInboxHeaderInfo(index))
    if API.IsSecret(itemCount) or not itemCount or itemCount < 2 then return lines end
    for a = 1, rawget(_G, "ATTACHMENTS_MAX_RECEIVE") or 16 do
        local _, itemID, _, count = GetInboxItem(index, a)
        if API.IsSecret(itemID) or API.IsSecret(count) then
            complete = false
        elseif itemID then
            local link = GetInboxItemLink(index, a)
            if link == nil or API.IsSecret(link) then
                link, complete = LOADING, false
            end
            lines[#lines + 1] = (count or 1) > 1 and (link .. " x" .. count) or link
        end
    end
    if complete then itemLines[index] = lines end
    return lines
end

local function onRowEnter(button)
    local i = rowOf[button]
    local index = button.index   -- Blizzard's own field, read only
    if not i or type(index) ~= "number" then return end
    local lines = attachmentLines(index)
    local subject = rawget(_G, "MailItem" .. i .. "Subject")
    local full = subject and subject:IsTruncated() and subject:GetText()
    if full ~= nil and API.IsSecret(full) then full = nil end
    local recall = rows[i].recall
    if #lines == 0 and not full and not recall then return end
    if #lines > 0 then
        GameTooltip:AddLine(" ")
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1) end
    end
    if full then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(full, 1, 1, 1, true)
    end
    if recall then
        local c = recall == "sure" and GM.Suite.AccentColor() or AMBER
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(recall == "sure" and Inbox.RECALL_SURE or Inbox.RECALL_POSSIBLE, c[1], c[2], c[3], true)
    end
    GameTooltip:Show()
end

local function hideTip() GameTooltip:Hide() end

local function control(frame, item)
    frame:SetFrameLevel(item:GetFrameLevel() + 5)
    frame:SetMotionScriptsWhileDisabled(true)
    frame:SetScript("OnLeave", hideTip)
    return frame
end

function Inbox.Start()
    local inbox = rawget(_G, "InboxFrame")
    if not inbox or bar then return end
    for i = 1, ROWS do
        local item = rawget(_G, "MailItem" .. i)
        if not item then return API.Fail("inbox rows", "MailItem" .. i .. " missing") end
    end
    for i = 1, ROWS do
        local item = rawget(_G, "MailItem" .. i)
        local subject = rawget(_G, "MailItem" .. i .. "Subject")
        if subject then subject:SetWidth(SUBJECT_WIDTH) end
        local icon = control(CreateFrame("Button", nil, inbox), item)
        icon:SetSize(16, 16)
        icon:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -6, 6)
        icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        icon:SetScript("OnClick", function() onIcon(i) end)
        icon:SetScript("OnEnter", function() iconTip(i) end)
        local check = control(CreateFrame("CheckButton", nil, inbox, "UICheckButtonTemplate"), item)
        check:SetSize(20, 20)
        check:SetPoint("RIGHT", icon, "LEFT", -2, 0)
        check:SetScript("OnClick", function() onCheck(i) end)
        check:SetScript("OnEnter", function() checkTip(i) end)
        -- N2's tint: over the row, under our controls, never taking a click.
        local tint = CreateFrame("Frame", nil, inbox)
        tint:SetAllPoints(item)
        tint:SetFrameLevel(item:GetFrameLevel() + 1)
        tint:EnableMouse(false)
        tint.tex = tint:CreateTexture(nil, "ARTWORK")
        tint.tex:SetAllPoints(tint)
        tint:Hide()
        rows[i] = { check = check, icon = icon, tint = tint }
        local button = rawget(_G, "MailItem" .. i .. "Button")
        if button then rowOf[button] = i end
    end
    local frame = CreateFrame("Frame", nil, inbox)
    frame:SetSize(250, 22)
    frame:SetPoint("TOPRIGHT", inbox, "TOPRIGHT", -12, -36)
    bar = { frame = frame }
    bar.clear = API.Button(frame, "Clear", 50, clear)
    bar.clear:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    bar.ret = API.Button(frame, "Return next", 126, onReturnNext)
    bar.ret:SetPoint("RIGHT", bar.clear, "LEFT", -2, 0)
    bar.open = API.Button(frame, "Open", 66, onOpen)
    bar.open:SetPoint("RIGHT", bar.ret, "LEFT", -2, 0)
    local nf = CreateFrame("Frame", nil, inbox)
    nf:SetHeight(22)
    nf:SetPoint("TOPLEFT", rawget(_G, "MailItem" .. ROWS), "BOTTOMLEFT", 4, -2)
    nf:SetPoint("RIGHT", inbox, "RIGHT", -12, 0)
    notice = { frame = nf }
    notice.ret = API.Button(nf, "Return", 70, onRecallReturn)
    notice.ret:SetPoint("RIGHT", nf, "RIGHT", 0, 0)
    notice.ret:SetMotionScriptsWhileDisabled(true)
    notice.ret:SetScript("OnEnter", function(self)
        local w = (API.InCombat() and "Not in combat") or (Ops.Running() and "Busy: wait for the current action")
            or (Ops.LetterOpen() and "Close the letter first") or (not snap.resolved and WAITING) or nil
        tip(self, w and ("Return to sender\n" .. w) or "Return to sender")
    end)
    notice.ret:SetScript("OnLeave", hideTip)
    notice.text = nf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    notice.text:SetPoint("LEFT", nf, "LEFT", 0, 0)
    notice.text:SetPoint("RIGHT", notice.ret, "LEFT", -6, 0)
    notice.text:SetJustifyH("LEFT")
    nf:Hide()
    if rawget(_G, "InboxFrameItem_OnEnter") then
        hooksecurefunc("InboxFrameItem_OnEnter", function(button)
            local ok, err = pcall(onRowEnter, button)
            if not ok then API.Fail("inbox tooltip", err) end
        end)
    end
    if inbox.Update then hooksecurefunc(inbox, "Update", refresh) end
    Ops.Watch(refresh)
    -- A recall marked, unmarked, forgotten or ended while the mailbox is open
    -- repaints at once (Ops checks the mail, not the recall).
    Store.OnChange(refresh)
    local letter = rawget(_G, "OpenMailFrame")
    if letter then
        letter:HookScript("OnShow", refresh)
        letter:HookScript("OnHide", refresh)
    end
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, arg1)
        API.NoteCombat(event)
        if event == "MAIL_SHOW" then
            mailboxOpen = true
        elseif event == "MAIL_INBOX_UPDATE" then
            itemLines = {}
        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            if arg1 ~= MAILBOX then return end
            selected, anchor, itemLines, mailboxOpen = {}, nil, {}, false
        end
        refresh()
    end)
    API.RegisterEvents(events, { "MAIL_SHOW", "MAIL_INBOX_UPDATE", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    refresh()
end

--------------------------------------------------------------------------------
-- The public read API (issue #26). Other addons read the selection; nothing
-- here changes it, and nothing runs until they call.
--------------------------------------------------------------------------------

-- The selected mails that have no twin (resolved, one mail per fingerprint:
-- what the bar acts on), as { [inbox index] = true }, from a fresh scan. A
-- new table on every call, empty (never nil) when nothing is selected or the
-- mailbox is closed. The indices hold until the next MAIL_INBOX_UPDATE.
function Selection.Get()
    local set = bar and public() or {}
    if next(set) == nil then return {} end
    local s = Scan.Inbox()
    return (picked(s, Scan.Count(s), set))
end

-- fn() is called, with no arguments, after anything changes what Get
-- returns: a click, a shift range, a ctrl sender, Clear, a selected mail gone
-- or now with a twin, the mailbox closing, an index shift. Not on a refresh
-- that changes nothing. An error in fn is recorded (/gmail failures).
function Selection.OnChange(fn)
    if type(fn) ~= "function" then return end
    if #listeners == 0 then reported = select(2, picked(snap, counts, public())) end
    listeners[#listeners + 1] = fn
end

GM._test = GM._test or {}
GM._test.inbox = { rows = rows, bar = function() return bar end, selected = function() return selected end,
    notice = function() return notice end }
