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
date = os.date
time = os.time
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
function GetRealmName() return "Doomhowl" end

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
    w._shown = false
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
-- A tooltip's SetText starts it over with one line; any other widget's is the core's.
local coreSetText = Methods.SetText
function Methods.SetText(t, text, ...)
    if t._type == "GameTooltip" then t._lines = { text } else return coreSetText(t, text, ...) end
end
function Methods.IsTruncated(fs) return fs._truncated == true end
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
function GetInboxHeaderInfo(i)
    local m = WoW.inbox[i]
    if not m then return end
    local n = 0
    for _ in pairs(m.items or {}) do n = n + 1 end
    -- A secret flag comes back as is; a plain one as the client's boolean.
    local function flag(v, default)
        if issecretvalue(v) then return v end
        if v == nil then return default end
        return v == true
    end
    return 134937, nil, m.sender, m.subject, m.money or 0, m.cod or 0, m.daysLeft or 29.5, n > 0 and n or nil,
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
C_Item = {
    GetItemMaxStackSizeByID = function(id) return WoW.itemInfo[id] and WoW.itemInfo[id].maxStack end,
    GetItemFamily = function(id) return WoW.itemInfo[id] and WoW.itemInfo[id].family end,
}
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
MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = { items = {} }
    local function add(kind) return function(self, text, isSel, setSel, data)
        table.insert(self.items, { kind = kind, text = text, isSelected = isSel, setSelected = setSel, data = data })
    end end
    root.CreateTitle, root.CreateCheckbox, root.CreateRadio = add("title"), add("checkbox"), add("radio")
    gen(owner, root)
    WoW.menu = root
end }
WoW.gamepad = false
InputUtil = { IsGamepadUIEnabled = function() return WoW.gamepad end }

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
Kit.strict({ GlassMail = true, GlassMailDB = true, GlassMailCharDB = true, MailProbeDB = true,
    LibStub = true })
