-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
-- Lifted from GlassChat's stubs (the generic part: secrets, events, widgets,
-- strict globals), trimmed to what the mailbox touches, plus the mail
-- windows' frames.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump; defining
--   something Forever lacks is how a missing API survives into a build.
-- - SECRETS as newproxy userdata: arithmetic, ordering, tostring, concat and
--   string.format on one throw. Lua 5.1 cannot make a truth test or == throw,
--   so those two misuses are NOT caught here (only in game / in review).
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare
--   (tests/events-70291.txt when the dump is absent, as on CI).
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.

WoW = {}
local DUMP = os.getenv("GLASSMAILBOX_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70291.md"
WoW.DUMP = DUMP

--------------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })

function WoW.Secret(label)
    local p = newproxy(true)
    local mt = getmetatable(p)
    local function boom() error("secret value touched in Lua: " .. label, 2) end
    for _, k in ipairs({ "__tostring", "__concat", "__add", "__sub", "__mul", "__div", "__mod",
                         "__pow", "__unm", "__lt", "__le", "__len", "__index", "__newindex", "__call" }) do
        mt[k] = boom
    end
    secrets[p] = label
    return p
end

function issecretvalue(v) return secrets[v] ~= nil end

-- Mark an existing value secret for issecretvalue. The client's secrets keep
-- their type (a secret string is still type "string"), which a proxy can't
-- model; use this to reach `type(x) == "string"` branches.
function WoW.MarkSecret(v, label) secrets[v] = label or "marked" end

--------------------------------------------------------------------------------
-- Known events (from the dump when present, else the checked-in fixture)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
WoW.dumpAvailable = false
do
    local f = io.open(DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
        WoW.dumpAvailable = next(WoW.KNOWN_EVENTS) ~= nil
    end
    if not WoW.dumpAvailable then
        -- No dump (CI): the list generated from it, so validation stays
        -- exactly as strict. test_toc fails if the two ever drift.
        local fixture = io.open("tests/events-70291.txt", "r")
        assert(fixture, "tests/events-70291.txt missing: event validation needs the dump or the fixture")
        for line in fixture:lines() do
            local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
            if name then WoW.KNOWN_EVENTS[name] = true end
        end
        fixture:close()
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = {}
    WoW.combat = false
    WoW.timers = {}
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- shared implementations, by method name

local function record(w, name)
    WoW.methodsCalled[w._type .. ":" .. name] = true
end

local widgetMT = {
    __index = function(w, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end  -- fields read as nil
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
}

local function newWidget(wtype, parent, name)
    return setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                          _scripts = {}, _events = {},
                          _level = parent and parent._level and (parent._level + 1) or 1,
                          _width = 0, _height = 0, _name = name }, widgetMT)
end
WoW.newWidget = newWidget

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    -- The template's bar, shown by default as on the client.
    if template == "UIPanelScrollFrameTemplate" then w.ScrollBar = newWidget("Slider", w) end
    -- The radio template's own label (CheckButtonTemplates.xml: parentKey "text").
    if template == "UIRadioButtonTemplate" then w.text = Methods.CreateFontString(w) end
    table.insert(WoW.frames, w)
    if parent then
        parent._children = parent._children or {}
        table.insert(parent._children, w)
    end
    if name then rawset(_G, name, w) end
    return w
end
function Methods.GetChildren(w) return unpack(w._children or {}) end

function Methods.Show(w) w._shown = true; if w._scripts.OnShow then w._scripts.OnShow(w) end end
function Methods.Hide(w)
    local was = w._shown
    w._shown = false
    if was and w._scripts.OnHide then w._scripts.OnHide(w) end
end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
function Methods.SetPoint(w, ...) table.insert(w._points, { ... }) end
function Methods.ClearAllPoints(w) w._points = {} end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
function Methods.SetAlpha(w, a) w._alpha = a end
function Methods.GetAlpha(w) return w._alpha or 1 end
function Methods.GetParent(w) return w._parent end
function Methods.SetParent(w, p) w._parent = p end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.EnableMouse(w, v) w._mouse = v end
-- A button's enabled state (enabled until told otherwise).
function Methods.Enable(b) b._disabled = false end
function Methods.Disable(b) b._disabled = true end
function Methods.SetEnabled(b, v) b._disabled = not v end
function Methods.IsEnabled(b) return not b._disabled end
function Methods.IsMouseEnabled(w) return w._mouse == true end
function Methods.GetName(w) return w._name end
function Methods.GetDebugName(w) return w._name or ("<" .. w._type .. ">") end
function Methods.IsForbidden(w) return false end

-- Attributes: recorded; like the client, refused on a protected frame in
-- combat.
function Methods.SetAttribute(w, k, v)
    if WoW.combat and w._protected then return end
    w._attrs = w._attrs or {}
    w._attrs[k] = v
end
function Methods.GetAttribute(w, k) return w._attrs and w._attrs[k] end
function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil end
function Methods.IsEventRegistered(w, e) return w._events[e] == true end

-- Regions: listed in creation order for GetRegions, as the client lists a
-- frame's textures and font strings.
local function addRegion(w, r)
    w._regions = w._regions or {}
    table.insert(w._regions, r)
    return r
end
function Methods.CreateTexture(w, name, layer, template, sublevel)
    local t = addRegion(w, newWidget("Texture", w, name))
    t._layer, t._sublevel = layer, sublevel
    if name then rawset(_G, name, t) end
    return t
end
function Methods.CreateMaskTexture(w) return newWidget("MaskTexture", w) end
function Methods.CreateFontString(w, name)
    local fs = addRegion(w, newWidget("FontString", w, name))
    if name then rawset(_G, name, fs) end
    return fs
end
function Methods.GetRegions(w) return unpack(w._regions or {}) end
function Methods.GetObjectType(w) return w._type end
-- A button's state textures: Set*Texture(file) makes one, Get*Texture reads it.
for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Checked", "Disabled" }) do
    local key = "_" .. state:lower() .. "Texture"
    Methods["Set" .. state .. "Texture"] = function(b, file)
        b[key] = b[key] or newWidget("Texture", b)
        b[key]._file = file
    end
    Methods["Get" .. state .. "Texture"] = function(b) return b[key] end
end
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.SetVertexColor(t, r, g, b, a) t._vertex = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.SetGradient(t, orientation, c1, c2) t._gradient = { orientation, c1, c2 } end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
-- Animations: groups record whether they play.
function Methods.CreateAnimationGroup(w) return newWidget("AnimationGroup", w) end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.Play(ag) ag._playing = true end
function Methods.Stop(ag) ag._playing = false end
function Methods.IsPlaying(ag) return ag._playing == true end

-- FontString: the client formats natively and accepts secrets. With any
-- secret argument, keep the arguments unformatted instead of calling
-- string.format (which would throw on the proxy).
-- An EditBox runs its OnTextChanged on SetText, as the client does.
function Methods.SetText(fs, text)
    fs._text = text
    if fs._type == "EditBox" and fs._scripts.OnTextChanged then fs._scripts.OnTextChanged(fs, false) end
end
-- A SimpleHTML colours per text type ("P", "H1", ...), its first argument.
function Methods.SetTextColor(fs, ...)
    if fs._type == "SimpleHTML" then
        local textType, r, g, b, a = ...
        assert(type(textType) == "string", "SimpleHTML:SetTextColor needs a text type first")
        fs._htmlColor = fs._htmlColor or {}
        fs._htmlColor[textType] = { r, g, b, a }
        return
    end
    local r, g, b, a = ...
    fs._textColor = { r, g, b, a }
end
function Methods.GetTextColor(fs, textType)
    local c
    if fs._type == "SimpleHTML" then
        assert(type(textType) == "string", "SimpleHTML:GetTextColor needs a text type")
        c = fs._htmlColor and fs._htmlColor[textType]
    else
        c = fs._textColor
    end
    c = c or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Methods.GetFontObject(fs) return fs._fontObject end
-- An EditBox's selection colour (MailFrame.xml:581 gives the send body 0.82 grey).
function Methods.SetHighlightColor(e, r, g, b, a) e._highlight = { r, g, b, a } end
function Methods.GetHighlightColor(e)
    local c = e._highlight or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Methods.GetText(fs) return fs._text end
function Methods.SetFormattedText(fs, fmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        if secrets[(select(i, ...))] then fs._text = { secretFormat = fmt, n = n }; return end
    end
    fs._text = string.format(fmt, ...)
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end
function Methods.SetFontObject(fs, obj) fs._fontObject = obj end
function Methods.GetFont(fs)
    local f = fs._font or { "Fonts\FRIZQT__.TTF", 10, "" }
    return f[1], f[2], f[3]
end
function Methods.GetFontString(b) return b._fontString end
-- CheckButton.
function Methods.SetChecked(b, v) b._checked = v and true or false end
function Methods.GetChecked(b) return b._checked == true end
-- StatusBar.
function Methods.SetMinMaxValues(b, lo, hi) b._min, b._max = lo, hi end
function Methods.SetStatusBarColor(b, r, g, bl, a) b._color = { r, g, bl, a } end
function Methods.GetValue(b) return b._value end
function Methods.SetValue(b, v) b._value = v end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end

WoW.reset()

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

UIParent = newWidget("Frame", nil, "UIParent")
UIParent._level = 0

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

SlashCmdList = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
date = os.date
time = os.time
function GetTime() return WoW.now or 0 end
function GetServerTime() return time() end
function GetBuildInfo() return "1.60.1", "70291", "Oct 8 2026", 16001 end
function InCombatLockdown() return WoW.combat == true end

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

-- The client's secure hook replaces t[name] with a wrapper: the sanctioned way
-- to hook a Blizzard method. WoW.hooked records it, so the "no field written"
-- checks can tell it from a field the addon wrote.
WoW.hooked = {}
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    WoW.hooked[t] = WoW.hooked[t] or {}
    WoW.hooked[t][name] = true
    local orig = rawget(t, name) or t[name]
    rawset(t, name, function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end)
end

-- Timers keep their delay: WoW.flushTimers(upTo) runs those due within upTo
-- seconds (all when nil) and keeps the rest.
C_Timer = { After = function(s, fn) table.insert(WoW.timers, { s = s, fn = fn }) end }
function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do t.fn() end
end

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
for i = 1, 7 do
    local row = CreateFrame("Frame", "MailItem" .. i, InboxFrame)
    for _ = 1, 3 do Methods.CreateTexture(row, nil, "BACKGROUND") end
    Methods.CreateFontString(row, "MailItem" .. i .. "Sender")
    Methods.CreateFontString(row, "MailItem" .. i .. "Subject")
end

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
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught: a
-- handler that throws fails the test.
function WoW.fire(event, ...)
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler and w._events[event] then handler(w, event, ...) end
    end
end

-- Every event any frame registered, fired once with no payload: strict
-- globals only catch code that actually runs.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
    end
    for e in pairs(seen) do WoW.fire(e) end
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

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
local allowNil = { GlassMailbox = true, GlassMailboxDB = true, GlassMailboxCharDB = true, MailProbeDB = true,
    LibStub = true }
-- Client string alias (in the dump's _G walk); LibStub's version check uses it.
strmatch = string.match
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
