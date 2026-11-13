-- wow_stubs.lua: GlassMail's WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- The mechanics are WowTestKit's core (tests/kit.lua loads the commit and the
-- build tests/kit.pin names): strict globals, secrets, events checked against
-- the build, widgets that record every method called, print with the
-- stray-"|" check, timers, hooksecurefunc, fire / fireAllRegistered / tick,
-- check / eq / done. Its README is the reference. This file adds the client
-- APIs the mailbox touches and the mail windows' frames, and the widget
-- methods the core doesn't have (methods are looked up at call time).

dofile("tests/kit.lua")
local Methods = WoW.Methods
local newWidget = WoW.newWidget

-- What WoW.reset() clears besides the core's state.
local function resetMail()
    WoW.cvars = { blockTrades = "0" }
    WoW.newMail, WoW.senders = false, {}
end
table.insert(WoW.onReset, resetMail)
resetMail()

--------------------------------------------------------------------------------
-- Templates (CreateFrame's fourth argument)
--------------------------------------------------------------------------------

-- The template's bar, shown by default as on the client.
WoW.templates.UIPanelScrollFrameTemplate = function(w) w.ScrollBar = newWidget("Slider", w) end
-- The radio template's own label (CheckButtonTemplates.xml: parentKey "text").
WoW.templates.UIRadioButtonTemplate = function(w) w.text = Methods.CreateFontString(w) end

--------------------------------------------------------------------------------
-- Widgets: the methods the core doesn't have
--------------------------------------------------------------------------------

-- A button's state textures: Set*Texture(file) makes one, Get*Texture reads it.
for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Checked", "Disabled" }) do
    local key = "_" .. state:lower() .. "Texture"
    Methods["Set" .. state .. "Texture"] = function(b, file)
        b[key] = b[key] or newWidget("Texture", b)
        b[key]._file = file
    end
    Methods["Get" .. state .. "Texture"] = function(b) return b[key] end
end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
-- An EditBox's selection colour (MailFrame.xml:581 gives the send body 0.82 grey).
function Methods.SetHighlightColor(e, r, g, b, a) e._highlight = { r, g, b, a } end
function Methods.GetHighlightColor(e)
    local c = e._highlight or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Methods.GetFontString(b) return b._fontString end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

SlashCmdList = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- The local date and the epoch clock, scriptable: WoW.today ("YYYY-MM-DD")
-- answers date("%Y-%m-%d"), WoW.clock answers time() (the play-day clock and
-- Trash's expiry, Core/Store.lua). Anything else is the real os.date / os.time.
function date(fmt, t)
    if fmt == "%Y-%m-%d" and t == nil and WoW.today then return WoW.today end
    return os.date(fmt, t)
end
WoW.clock = 1793000000
function time(t)
    if t == nil then return WoW.clock end
    return os.time(t)
end
function GetServerTime() return time() end
function GetBuildInfo() return "1.60.1", "70291", "Oct 8 2026", 16001 end
-- CVars; SetCVar fires CVAR_UPDATE synchronously, as the client documents it.
-- WoW.cvarFail makes SetCVar throw; WoW.cvarRefuse makes it return false
-- and change nothing.
function GetCVar(name) return WoW.cvars[name] end
function SetCVar(name, value)
    if WoW.cvarFail then error("SetCVar refused") end
    if WoW.cvarRefuse then return false end
    WoW.cvars[name] = tostring(value)
    WoW.fire("CVAR_UPDATE", name, tostring(value))
    return true
end
-- New mail: HasNewMail, and the latest three senders (WoW.senders, up to 3).
function HasNewMail() return WoW.newMail end
function GetLatestThreeSenders() return WoW.senders[1], WoW.senders[2], WoW.senders[3] end

-- The player: GUID, and the name split across UnitName's two returns, one of
-- the two shapes the client has used (AltStable #56).
WoW.playerGUID = "Player-1-AAA"
function UnitGUID(unit) if unit == "player" then return WoW.playerGUID end end
function UnitName(unit) if unit == "player" then return WoW.playerName or "Karuzo", "Morphisto" end end
WoW.realm, WoW.faction = "Doomhowl", "Horde"
function GetRealmName() return WoW.realm end
function UnitFactionGroup(unit) if unit == "player" then return WoW.faction, WoW.faction end end

WoW.addonVersion = "dev"
C_AddOns = {
    GetAddOnMetadata = function(name, field) if field == "Version" then return WoW.addonVersion end end,
}

-- The Settings framework (Blizzard_Settings): canvas categories, recorded.
WoW.categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local c = { frame = frame, name = name, id = #WoW.categories + 1 }
        function c:GetID() return self.id end
        table.insert(WoW.categories, c)
        return c
    end,
    RegisterAddOnCategory = function(c) c.registered = true end,
    OpenToCategory = function(id) WoW.openedCategory = id end,
}

--------------------------------------------------------------------------------
-- The mail windows (Blizzard_MailFrame, loaded before any addon): MailFrame
-- and OpenMailFrame are ButtonFrameTemplate windows, whose frame art is the
-- parentKeys NineSlice (a frame), Bg and TopTileStreaks (textures)
-- (SharedUIPanelTemplates.xml:566-711).
--------------------------------------------------------------------------------

local function mailWindow(name)
    local w = CreateFrame("Frame", name, UIParent)
    w:Hide()
    w._level = 10
    w.NineSlice = CreateFrame("Frame", nil, w)
    w.Bg = Methods.CreateTexture(w)
    w.TopTileStreaks = Methods.CreateTexture(w)
    -- InsetFrameTemplate: its own Bg texture and NineSlice frame.
    w.Inset = CreateFrame("Frame", nil, w)
    w.Inset.Bg = Methods.CreateTexture(w.Inset)
    w.Inset.NineSlice = CreateFrame("Frame", nil, w.Inset)
    -- PortraitFrameTemplate's portrait, masked to a circle (SharedUIPanelTemplates.xml:574-596).
    w.PortraitContainer = CreateFrame("Frame", nil, w)
    w.PortraitContainer.portrait = Methods.CreateTexture(w.PortraitContainer)
    w.PortraitContainer.CircleMask = Methods.CreateTexture(w.PortraitContainer)
    return w
end
local mail = mailWindow("MailFrame")
local open = mailWindow("OpenMailFrame")

-- A named horizontal bar and its unnamed right-hand piece, anchored to it
-- (MailFrame.xml:479-506, 922-935).
local function bar(owner, name)
    local left = Methods.CreateTexture(owner, name, "BACKGROUND")
    Methods.SetPoint(left, "TOPLEFT", owner, "TOPLEFT", 2, -337)
    local right = Methods.CreateTexture(owner, nil, "BACKGROUND")
    Methods.SetPoint(right, "LEFT", left, "RIGHT", 0, 0)
    return left, right
end

-- The inbox: InboxFrameBg and seven MailItemTemplate rows, each with its two
-- MailItemBorder halves and divider line (textures) and its sender and
-- subject (font strings), as MailFrame.xml:11-50 declares them.
mail.InboxFrame = CreateFrame("Frame", "InboxFrame", mail)
Methods.CreateTexture(InboxFrame, "InboxFrameBg", "BACKGROUND")
InboxFrame.pageNum = 1   -- MailFrame.lua:28
for i = 1, 7 do
    local row = CreateFrame("Frame", "MailItem" .. i, InboxFrame)
    for _ = 1, 3 do Methods.CreateTexture(row, nil, "BACKGROUND") end
    Methods.CreateFontString(row, "MailItem" .. i .. "Sender")
    Methods.CreateFontString(row, "MailItem" .. i .. "Subject")
    -- The row's mail button (parentKey Button); InboxMixin:Update sets .index.
    row.Button = CreateFrame("CheckButton", "MailItem" .. i .. "Button", row)
end

-- GameTooltip: its owner and lines, as text. SetOwner starts it over.
GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
GameTooltip._lines = {}
function Methods.SetOwner(t, owner) t._owner, t._lines = owner, {} end
function Methods.IsOwned(t, f) return t._owner == f end
function Methods.AddLine(t, text) table.insert(t._lines, text) end
function Methods.SetItemByID(t, id) t._lines, t._itemID = {}, id end
-- A tooltip's SetText starts it over with one line; any other widget's is the core's.
local coreSetText = Methods.SetText
function Methods.SetText(t, text, ...)
    if t._type == "GameTooltip" then t._lines = { text }; return end
    if t._type == "EditBox" then t._cursor, t._hl, t._highlighted = nil, nil, nil end
    return coreSetText(t, text, ...)
end
function Methods.IsTruncated(fs) return fs._truncated == true end
-- Kept per widget, so a test can tell a disabled control still shows its tooltip.
function Methods.SetMotionScriptsWhileDisabled(w, v) w._motionWhileDisabled = v == true end
function Methods.GetMotionScriptsWhileDisabled(w) return w._motionWhileDisabled == true end
function GameTooltip_Hide() GameTooltip:Hide() end
-- Blizzard's row tooltip (MailFrame.lua:489), shortened: its own first line.
function InboxFrameItem_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("mail " .. tostring(self.index))
    GameTooltip:Show()
end
WoW.shift, WoW.ctrl = false, false
function IsShiftKeyDown() return WoW.shift end
function IsControlKeyDown() return WoW.ctrl end

-- The send tab: its two bars, plus a texture anchored to something else
-- (SendMailErrorIcon-like) that the skin must leave alone.
mail.SendMailFrame = CreateFrame("Frame", "SendMailFrame", mail)
INBOXITEMS_TO_DISPLAY = 7   -- MailFrame.lua:1
-- Blizzard's Open All (MailFrame.xml:444): its OnHide stops it, which calls
-- C_Mail.SetOpeningAll(false) (session 2). And InboxMixin:Update, which the
-- addon post-hooks.
InboxFrame.OpenAllMail = CreateFrame("Button", "OpenAllMail", InboxFrame, "UIPanelButtonTemplate")
InboxFrame.OpenAllMail:SetScript("OnHide", function() C_Mail.SetOpeningAll(false) end)
rawset(InboxFrame, "Update", function() end)
-- The money box: an inset (faded) and its gold-edged value field (kept).
CreateFrame("Frame", "SendMailMoneyInset", SendMailFrame)
SendMailMoneyInset.Bg = Methods.CreateTexture(SendMailMoneyInset)
SendMailMoneyInset.NineSlice = CreateFrame("Frame", nil, SendMailMoneyInset)
CreateFrame("Frame", "SendMailMoneyBg", SendMailFrame)
CreateFrame("Button", "SendMailCancelButton", SendMailFrame)
bar(SendMailFrame, "SendMailHorizontalBarLeft")
bar(SendMailFrame, "SendMailHorizontalBarLeft2")
local errorText = Methods.CreateFontString(SendMailFrame, "SendMailErrorText")
local errorIcon = Methods.CreateTexture(SendMailFrame, "SendMailErrorIcon", "BACKGROUND")
Methods.SetPoint(errorIcon, "LEFT", errorText, "RIGHT", 1, -1)

-- The open letter: its bar.
bar(open, "OpenMailHorizontalBarLeft")

-- The letters (MailFrame.xml:510-580, 975-1160): a scroll frame drawing the
-- stationery, and in its scroll child the text in the dark mail fonts. The
-- shared font objects are client globals; only the mail widgets are ours to
-- recolour.
MailTextFontNormal = newWidget("Font")
InvoiceTextFontNormal = newWidget("Font")
NumberFontNormal = newWidget("Font")
local DARK = { 0.18, 0.12, 0.06, 1 }
local function letter(owner, prefix)
    local scroll = CreateFrame("ScrollFrame", prefix .. "ScrollFrame", owner)
    Methods.CreateTexture(scroll, prefix:gsub("Mail$", "") .. "StationeryBackgroundLeft", "BACKGROUND")
    Methods.CreateTexture(scroll, prefix:gsub("Mail$", "") .. "StationeryBackgroundRight", "BACKGROUND")
    return scroll, CreateFrame("Frame", prefix .. "ScrollChildFrame", scroll)
end
local _, sendChild = letter(SendMailFrame, "SendMail")
-- The money area (MailFrame.xml:740-788): a small frame with the label as a
-- region and the amount boxes and the two radios as children.
local moneyHolder = CreateFrame("Frame", "SendMailMoneyButton", SendMailFrame)
Methods.CreateFontString(moneyHolder, "SendMailMoneyText")
CreateFrame("Frame", "SendMailMoney", moneyHolder)
CreateFrame("CheckButton", "SendMailSendMoneyButton", moneyHolder)
CreateFrame("CheckButton", "SendMailCODButton", moneyHolder)
local edit = CreateFrame("EditBox", "SendMailBodyEditBox", sendChild)
edit._fontObject, edit._textColor, edit._highlight = MailTextFontNormal, DARK, { 0.82, 0.82, 0.82, 1 }
local _, openChild = letter(open, "OpenMail")
local body = CreateFrame("SimpleHTML", "OpenMailBodyText", openChild)
body._htmlColor = { P = DARK }
-- OpenMailMixin:Update, Blizzard's refresh of the open letter (MailFrame.lua:747):
-- it sets the body's text again, which lays it out in the current colour.
rawset(open, "Update", function(self)
    self._updates = (self._updates or 0) + 1
    body._shownColor = { body:GetTextColor("P") }
end)
-- The AH invoice: labels in the invoice font, a money amount in a number font
-- (stays), nested a frame deeper.
local invoice = CreateFrame("Frame", "OpenMailInvoiceFrame", openChild)
for _, n in ipairs({ "OpenMailInvoiceItemLabel", "OpenMailInvoiceSalePrice" }) do
    local fs = Methods.CreateFontString(invoice, n)
    fs._fontObject, fs._textColor = InvoiceTextFontNormal, DARK
end
local money = CreateFrame("Frame", nil, invoice)
local amount = Methods.CreateFontString(money, "OpenMailInvoiceMoneyAmount")
amount._fontObject, amount._textColor = NumberFontNormal, { 1, 1, 1, 1 }

--------------------------------------------------------------------------------
-- The mail server and the bags, as plain tables the tests script.
-- WoW.inbox = { { sender, subject, money, cod, daysLeft, wasRead, wasReturned,
--   canReply, isGM, items = { [slot] = { id, count, link } } }, ... }
-- A take or return is only RECORDED (WoW.mailCalls); WoW.serve(call) applies
-- its effect the way the server did in the probe sessions, and fires
-- MAIL_INBOX_UPDATE, so tests choose the order and timing of every reply.
--------------------------------------------------------------------------------

WoW.inbox, WoW.mailCalls, WoW.inboxTotal = {}, {}, nil
WoW.commandPending, WoW.openingAll = false, nil
ATTACHMENTS_MAX_RECEIVE = 16
-- The six AH subjects as session 5 read them.
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_INVOICE_MAIL_SUBJECT = "Sale Pending: %s"
AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction canceled: %s"
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"

-- Blizzard's Return-or-Delete rule (MailFrame.lua:1109): a test sets
-- m.canDelete; else mail that can't be replied to, or was returned, deletes.
function InboxItemCanDelete(i)
    local m = WoW.inbox[i]
    if not m then return false end
    if m.canDelete ~= nil then return m.canDelete end
    return m.canReply == false or m.wasReturned == true
end
function GetInboxNumItems() return #WoW.inbox, WoW.inboxTotal or #WoW.inbox end
-- m.missing: the header isn't there yet (nothing returned); m.daysLeft =
-- false: no days left given; m.itemCount: a header count other than the slots.
function GetInboxHeaderInfo(i)
    local m = WoW.inbox[i]
    if not m or m.missing then return end
    local n = 0
    for _ in pairs(m.items or {}) do n = n + 1 end
    if m.itemCount ~= nil then n = m.itemCount end
    local daysLeft = m.daysLeft
    if daysLeft == nil then daysLeft = 29.5 elseif daysLeft == false then daysLeft = nil end
    -- A secret flag comes back as is; a plain one as the client's boolean.
    local function flag(v, default)
        if issecretvalue(v) then return v end
        if v == nil then return default end
        return v == true
    end
    return 134937, nil, m.sender, m.subject, m.money or 0, m.cod or 0, daysLeft, n > 0 and n or nil,
        flag(m.wasRead, false), flag(m.wasReturned, false), false, flag(m.canReply, true), flag(m.isGM, false)
end
-- name, itemID, texture, count, quality, canUse, isCurrency; an uncached
-- item's name is "" (session 2).
function GetInboxItem(i, a)
    local it = WoW.inbox[i] and WoW.inbox[i].items and WoW.inbox[i].items[a]
    if it then return it.name or "", it.id, 134, it.count or 1, 1, true, it.currency == true end
end
function GetInboxItemLink(i, a)
    local it = WoW.inbox[i] and WoW.inbox[i].items and WoW.inbox[i].items[a]
    if it then
        if it.link == false then return nil end
        return it.link or ("|Hitem:" .. it.id .. "::::::::16:1485|h[item " .. it.id .. "]|h")
    end
end
for _, fn in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem", "ReturnInboxItem", "DeleteInboxItem" }) do
    _G[fn] = function(...) table.insert(WoW.mailCalls, { fn, ... }) end
end
C_Mail = {
    IsCommandPending = function() return WoW.commandPending end,
    SetOpeningAll = function(v) WoW.openingAll = v end,
    CanCheckInbox = function() return true, 0 end,
    HasInboxMoney = function(i) return WoW.inbox[i] ~= nil and (WoW.inbox[i].money or 0) > 0 end,
}

-- The server's answer to a recorded call: money taken, a slot emptied (slots
-- keep their numbers), an emptied item mail removed; then MAIL_INBOX_UPDATE.
function WoW.serve(call)
    local fn, i, a = call[1], call[2], call[3]
    local m = WoW.inbox[i]
    if not m then return end
    m.wasRead = true
    if fn == "TakeInboxMoney" then m.money = 0
    elseif fn == "TakeInboxItem" then
        local hadItems = next(m.items or {}) ~= nil
        m.items[a] = nil
        -- Removed once empty, unless it has letter text (m.text): then it stays, empty.
        if hadItems and next(m.items) == nil and (m.money or 0) == 0 and not m.text then table.remove(WoW.inbox, i) end
    elseif fn == "ReturnInboxItem" or fn == "DeleteInboxItem" then table.remove(WoW.inbox, i) end
    WoW.fire("MAIL_INBOX_UPDATE")
end

-- Sending. WoW.draft = { money, cod, items = { [slot] = { id, count } } } is
-- the send tab's draft; SendMail only records the call (WoW.sends). With
-- WoW.confirmNext set, the stranger confirmation fires INSIDE the call, as
-- session 6 saw it; the dialog's close is SendMailFrame_EnableSendMailButton,
-- which the test calls. Results (MAIL_SEND_SUCCESS, UI_ERROR_MESSAGE) are
-- fired by the test.
ATTACHMENTS_MAX_SEND = 12   -- MailFrame.lua:4
WoW.draft, WoW.sends = {}, {}
function GetSendMailMoney() return WoW.draft.money or 0 end
function GetSendMailCOD() return WoW.draft.cod or 0 end
-- name, itemID, texture, count, quality (MailFrame.lua:1297)
function GetSendMailItem(i)
    local it = WoW.draft.items and WoW.draft.items[i]
    if it then return "item " .. tostring(it.id), it.id, 134, it.count or 1, 1 end
end
function SendMail(to, subject, body)
    table.insert(WoW.sends, { to = to, subject = subject, body = body })
    if WoW.confirmNext then
        WoW.confirmNext = nil
        WoW.fire("SECURE_TRANSFER_CONFIRM_SEND_MAIL")
    end
end
function SendMailFrame_EnableSendMailButton() end

-- The To box (MailFrame.xml:593) and what Blizzard does with it: the tabs
-- (MailFrameTab_OnClick, MailFrame.lua:189: tab 2 shows the send tab and sets
-- sendMode "send"), Reply (1091-1093: tab 2, then the sender), the reset
-- after a send (1422-1424) and the MAIL_SEND_SUCCESS handler (144-150: reset,
-- then back to the inbox after a reply). WoW.blizzardSendLate: the handler
-- runs from a frame the test makes after the addon loads (its handlers first).
local nameBox = CreateFrame("EditBox", "SendMailNameEditBox", SendMailFrame)
nameBox._text = ""
-- An EditBox's highlight and cursor, in bytes. HighlightText(start, stop):
-- both optional, the whole text without them (a negative stop: to the end);
-- e._hl keeps the range, e._highlighted its text. SetText (the core's, wrapped
-- below) puts the cursor at the end and drops the highlight.
function Methods.HighlightText(e, s, t)
    local text = e._text or ""
    s = s or 0
    if t == nil or t < 0 then t = #text end
    e._hl, e._highlighted = { s, t }, text:sub(s + 1, t)
end
function Methods.GetCursorPosition(e) return math.min(e._cursor or math.huge, #(e._text or "")) end
function Methods.SetCursorPosition(e, n) e._cursor = n end
function Methods.GetUTF8CursorPosition(e) return strlenutf8((e._text or ""):sub(1, e:GetCursorPosition())) end
function Methods.IsInIMECompositionMode(e) return e._ime == true end
function strlenutf8(s) return select(2, s:gsub("[^\128-\191]", "")) end
function Methods.SetFocus(e) WoW.focus = e end
function Methods.HasFocus(e) return WoW.focus == e end
function Methods.ClearFocus(e) if WoW.focus == e then WoW.focus = nil end end
-- The frame under the mouse (a test sets WoW.mouseOver).
function Methods.IsMouseOver(w) return WoW.mouseOver == w end
-- The tabs hang below the window as in MailFrame.xml:868-881 (PanelTabButtonTemplate: 32 high).
do
    local t1 = CreateFrame("Button", "MailFrameTab1", mail)
    t1:SetID(1); t1:SetHeight(32); t1:SetPoint("BOTTOMLEFT", mail, "BOTTOMLEFT", 14, -30)
    local t2 = CreateFrame("Button", "MailFrameTab2", mail)
    t2:SetID(2); t2:SetHeight(32); t2:SetPoint("LEFT", t1, "RIGHT", -8, 0)
end
function MailFrameTab_OnClick(self, tabID)
    if not tabID then tabID = self:GetID() end
    if tabID == 1 then SendMailFrame:Hide() else
        SendMailFrame:Show()
        SendMailFrame.sendMode = "send"
    end
end
SendMailFrame:Hide()
function SendMailFrame_Reset()
    SendMailNameEditBox:SetText("")
    SendMailNameEditBox:SetFocus()
end
function WoW.reply(sender)
    MailFrameTab_OnClick(nil, 2)
    SendMailNameEditBox:SetText(sender)
    SendMailFrame.sendMode = "reply"
end
function WoW.blizzardSendSuccess()
    SendMailFrame_Reset()
    if SendMailFrame.sendMode == "reply" then MailFrameTab_OnClick(nil, 1) end
end
local blizzardSend = CreateFrame("Frame")
blizzardSend:SetScript("OnEvent", function() if not WoW.blizzardSendLate then WoW.blizzardSendSuccess() end end)
blizzardSend:RegisterEvent("MAIL_SEND_SUCCESS")
-- The mailbox opening shows the mail window (MailFrame.lua:99, MailFrame_Show), before
-- any addon's handler: Blizzard_MailFrame registers first. Its children's OnShow
-- (OpenAllMail's) fire only under a shown parent (WowTestKit #21).
local blizzardShow = CreateFrame("Frame")
blizzardShow:SetScript("OnEvent", function() MailFrame:Show() end)
blizzardShow:RegisterEvent("MAIL_SHOW")

-- Blizzard's autocomplete on the To box (AutoComplete.lua; MailFrame.xml:628-657),
-- enough of it for S1's completion. C_AutoComplete answers from
-- WoW.autocomplete (names): the text up to the UTF-8 cursor starts the name,
-- case aside (WoW.autocompleteCalls counts the calls). AutoCompleteBox shows
-- the results (.parent, .first: the selected entry); a lone exact match isn't
-- shown (AutoComplete.lua:202). The box's OnTextChanged updates it on user
-- input (367-378), OnChar completes inline (392-418), OnEnterPressed takes
-- the shown entry or moves on (MailFrame.xml:643-647, AutoComplete.lua:358).
WoW.autocomplete, WoW.autocompleteCalls = {}, 0
AUTOCOMPLETE_LIST = { MAIL = { include = 1, exclude = 2 } }
local function utf8Prefix(s, n)
    local out, i = {}, 0
    for ch in s:gmatch("[%z\1-\127\192-\247][\128-\191]*") do
        if i >= n then break end
        out[#out + 1], i = ch, i + 1
    end
    return table.concat(out)
end
-- Blizzard's side calls this local, so a test can take C_AutoComplete away
-- (or make it throw) for the addon only.
local function results(text, num, cursor, allowFullMatch, include, exclude)
    WoW.autocompleteCalls = WoW.autocompleteCalls + 1
    local typed, out = utf8Prefix(text, cursor):lower(), {}
    for _, name in ipairs(WoW.autocomplete) do
        if #out < num and name:lower():sub(1, #typed) == typed then out[#out + 1] = { name = name, priority = 0 } end
    end
    return out
end
C_AutoComplete = { GetAutoCompleteResults = results }
local dropdown = CreateFrame("Frame", "AutoCompleteBox", UIParent)
dropdown:Hide()
local function hideDropdown(box)
    if dropdown.parent == box then dropdown.parent, dropdown.first = nil, nil; dropdown:Hide() end
end
local function updateDropdown(box, text, cursor)
    if text == "" then return hideDropdown(box) end
    local r = results(text, 6, cursor, true, 1, 2)
    if #r == 1 and r[1].name == text then r[1] = nil end
    if #r > 0 then
        dropdown.parent, dropdown.first = box, r[1].name
        dropdown:Show()
    else
        hideDropdown(box)
    end
end
nameBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then updateDropdown(self, self:GetText(), self:GetUTF8CursorPosition()) end
    if self:GetText() == "" then hideDropdown(self) end
end)
nameBox:SetScript("OnChar", function(self)
    local text = self:GetText()
    local cursor = self:GetUTF8CursorPosition()
    if cursor ~= strlenutf8(text) then return end
    local info = results(text, 1, cursor, true, 1, 2)[1]
    if info then
        updateDropdown(self, text, cursor)
        self:SetText(info.name)
        self:HighlightText(#text, #info.name)
        self:SetCursorPosition(#text)
    end
end)
nameBox:SetScript("OnEnterPressed", function(self)
    if dropdown:IsShown() and dropdown.parent == self then
        local name = dropdown.first
        hideDropdown(self)
        self:SetText(name)
        self:SetCursorPosition(#name)
    else
        self:ClearFocus()   -- SendMailSubjectEditBox:SetFocus()
        self._hl, self._highlighted = nil, nil   -- EditBox_ClearHighlight on focus lost
    end
end)
-- A typed character as the client handles it: it replaces the highlight (or
-- goes in at the cursor), the cursor after it; then OnTextChanged(true) and
-- OnChar, in that order, or OnChar first with WoW.charFirst. With OnChar first,
-- a SetText inside it takes the typed change's own update away (SetText clears
-- userInput, AutoComplete.lua:401): the worst case.
function WoW.typeInto(e, ch)
    local text, cur = e._text or "", e:GetCursorPosition()
    local s, t = cur, cur
    if e._hl and e._hl[2] > e._hl[1] then s, t = e._hl[1], e._hl[2] end
    text = text:sub(1, s) .. ch .. text:sub(t + 1)
    e._text, e._cursor, e._hl, e._highlighted = text, s + #ch, nil, nil
    local changed, onChar = e:GetScript("OnTextChanged"), e:GetScript("OnChar")
    if WoW.charFirst then
        if onChar then onChar(e, ch) end
        if changed and e._text == text then changed(e, true) end
    else
        if changed then changed(e, true) end
        if onChar then onChar(e, ch) end
    end
end
function WoW.typeText(e, s)
    for ch in s:gmatch("[%z\1-\127\192-\247][\128-\191]*") do WoW.typeInto(e, ch) end
end

-- Friends and the guild (S1's picker). WoW.friends = { { name = ... } };
-- WoW.guild = { names } (nil: not in a guild); WoW.rosterRequests counts
-- C_GuildInfo.GuildRoster().
WoW.friends, WoW.rosterRequests = {}, 0
C_FriendList = {
    GetNumFriends = function() return WoW.friendCount or #WoW.friends end,
    GetFriendInfoByIndex = function(i) return WoW.friends[i] end,
}
function IsInGuild() return WoW.guild ~= nil end
function GetNumGuildMembers() return WoW.guild and #WoW.guild or 0 end
-- A member is a name, or { name, className (localized, 5th), classFile (11th) }:
-- the returns' order is Retail's, unmeasured on Forever.
function GetGuildRosterInfo(i)
    local g = WoW.guild and WoW.guild[i]
    if type(g) == "table" then return g.name, "Member", 1, 20, g.className, "Zone", "", "", true, 0, g.classFile end
    return g
end
-- Classes: the player's (UnitClass's second return is the file token), the
-- colours (Blizzard_SharedXML/ClassColors.lua) and the localized names.
WoW.playerClass = "WARLOCK"
function UnitClass(unit) if unit == "player" then return "Warlock", WoW.playerClass, 9 end end
-- The priest's is white in the client; off-white here, so a test can tell it from
-- the white a name gets when its class isn't known.
RAID_CLASS_COLORS = { WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, PRIEST = { r = 0.98, g = 0.97, b = 0.96 },
    MAGE = { r = 0.25, g = 0.78, b = 0.92 }, ROGUE = { r = 1, g = 0.96, b = 0.41 } }
LOCALIZED_CLASS_NAMES_MALE = { WARLOCK = "Warlock", PRIEST = "Priest", MAGE = "Mage", ROGUE = "Rogue" }
LOCALIZED_CLASS_NAMES_FEMALE = { WARLOCK = "Warlock", PRIEST = "Priestess", MAGE = "Mage", ROGUE = "Rogue" }
C_GuildInfo = { GuildRoster = function() WoW.rosterRequests = WoW.rosterRequests + 1 end }
-- "Name-Realm" to "Name" on the player's own realm (normalized: no spaces).
function Ambiguate(name, context)
    local base, realm = name:match("^(.-)%-(.+)$")
    if base and realm == (WoW.realm or ""):gsub("%s", "") then return base end
    return name
end

-- Bags 0-4: WoW.bags[b] = { size, family, items = { [slot] = { id, count, locked } } }.
-- Item facts: WoW.itemInfo[id] = { maxStack, family } (nil = not cached).
WoW.bags, WoW.itemInfo = {}, {}
NUM_BAG_SLOTS = 4
C_Container = {
    GetContainerNumSlots = function(b) return WoW.bags[b] and WoW.bags[b].size or 0 end,
    GetContainerNumFreeSlots = function(b)
        local bag = WoW.bags[b]
        if not bag then return 0, 0 end
        local used = 0
        for _ in pairs(bag.items) do used = used + 1 end
        return bag.size - used, bag.family or 0
    end,
    GetContainerItemInfo = function(b, s)
        local it = WoW.bags[b] and WoW.bags[b].items[s]
        if it then return { itemID = it.id, stackCount = it.count, isLocked = it.locked == true } end
    end,
    CalculateTotalNumberOfFreeBagSlots = function() return 0 end,
}
-- Item names: WoW.itemNames[id] is the cached name (nil: a cache miss);
-- RequestLoadItemDataByID is recorded in WoW.itemRequests, and a test fires
-- ITEM_DATA_LOAD_RESULT itself.
WoW.itemNames, WoW.itemRequests = {}, {}
C_Item = {
    GetItemMaxStackSizeByID = function(id) return WoW.itemInfo[id] and WoW.itemInfo[id].maxStack end,
    GetItemFamily = function(id) return WoW.itemInfo[id] and WoW.itemInfo[id].family end,
    GetItemNameByID = function(id) return WoW.itemNames[id] end,
    GetItemIconByID = function(id) return 1000 + id end,
    RequestLoadItemDataByID = function(id) table.insert(WoW.itemRequests, id) end,
}
-- The Escape list (UIParent.lua): CloseSpecialWindows hides each named frame.
UISpecialFrames = {}
C_CurrencyInfo = { GetCoinTextureString = function(c) return tostring(c) .. "c" end }
-- The client's bit library (Lua 5.1 has none): band over non-negative ints.
bit = { band = function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end }
-- MenuUtil.CreateContextMenu (Blizzard_Menu): the generator fills a root
-- description; WoW.menu holds its elements ({ kind, text, isSelected,
-- setSelected, data }) so a test can read and click them.
-- CreateButton(text, callback) returns its own description (a submenu when
-- given items: { kind = "button", text, callback, items, scroll }).
local function description()
    local d = { items = {} }
    local function add(kind) return function(self, text, isSel, setSel, data)
        table.insert(self.items, { kind = kind, text = text, isSelected = isSel, setSelected = setSel, data = data })
    end end
    d.CreateTitle, d.CreateCheckbox, d.CreateRadio = add("title"), add("checkbox"), add("radio")
    function d.CreateButton(self, text, callback)
        local b = description()
        b.kind, b.text, b.callback = "button", text, callback
        table.insert(self.items, b)
        return b
    end
    function d.SetScrollMode(self, extent) self.scroll = extent end
    return d
end
MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = description()
    gen(owner, root)
    WoW.menu = root
end }
WoW.gamepad = false
InputUtil = { IsGamepadUIEnabled = function() return WoW.gamepad end }

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
-- AltStable: an optional dependency, absent unless a test sets it.
Kit.strict({ GlassMail = true, GlassMailDB = true, GlassMailCharDB = true, MailProbeDB = true,
    LibStub = true, AltStable = true })

-- EventRegistry, Blizzard's callback registry (the client has it; the kit
-- doesn't): what Suite.lua uses to hear Glass UI's LookChanged. The callback
-- gets its owner first, then the event's arguments, as on the client.
WoW.callbacks = {}
EventRegistry = {
    RegisterCallback = function(_, event, fn, owner)
        WoW.callbacks[event] = WoW.callbacks[event] or {}
        table.insert(WoW.callbacks[event], { fn = fn, owner = owner })
    end,
    TriggerEvent = function(_, event, ...)
        for _, c in ipairs(WoW.callbacks[event] or {}) do c.fn(c.owner, ...) end
    end,
}
