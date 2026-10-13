-- Skin.lua: the glass look on Blizzard's mail windows (MailFrame, the inbox and
-- send tabs, and OpenMailFrame, the open letter).
--
-- A glass panel under each window, a reading pane under the inbox rows, and
-- the stock frame art faded out while glass is on. Everything is done with
-- method calls on our own frames and on the windows' declared regions (the
-- template's parentKeys, named textures, and the regions GetRegions lists): no
-- field is ever written onto a Blizzard frame, and no Blizzard function is
-- replaced. Fading uses SetAlpha, never Hide, so Blizzard's own Show/Hide logic
-- for those regions keeps working.
--
-- Two glass presets, clear and smoked, plus "stock" (Blizzard's own art). The
-- presets are AltStable's tint, wash and pane numbers (AltStable/Skin.lua), on
-- LibGlass's clean material (Glass.lua), which has no grain: their grain is 0,
-- or a repaint would put it back. They differ only in the body (tint, wash) and the pane, never
-- in the rim: GLASS-MATERIAL.md, a darkened rim reads as smoked plastic.
-- Unlike AltStable, the switch is live: we own a handful of surfaces and
-- repaint them (LibGlass SetSurfaceTint, the grain's alpha, the wash's
-- gradient), where AltStable has too many to repaint and asks for a /reload.
--
-- The letter (the send tab's body and the open letter) goes dark under glass,
-- as in docs/mockups/inbox-and-send.png (owner, 2026-10-10): the stationery is
-- faded like the rest of the art, a pane takes its place, and the letter's
-- text, a dark font made for parchment, is turned light. Only the mail widgets
-- are recoloured (SetTextColor on each), never the shared font objects
-- MailTextFontNormal / InvoiceTextFontNormal, which other windows use too.
-- Under "stock" every colour goes back to what it was.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Glass = GM.Glass
local Skin = {}
GM.Skin = Skin

-- pane: the reading panes (inbox rows, letters), AltStable's numbers. section:
-- the window's content and footer panels, denser: one pane at the pane's alpha
-- still let a bright quest tracker read through (owner's screenshots,
-- 2026-10-11), and so did 0.88 in clear. The same in both presets: they
-- differ where there is no section (title, headers, rim). The reading panes
-- stack on a section, darker still.
Skin.PRESETS = {
    clear = {
        tint = { 0.13, 0.16, 0.22, 0.24 }, grain = 0, wash = 0.18,
        pane = { 0.04, 0.05, 0.07, 0.62 },
        section = { 0.04, 0.05, 0.07, 0.94 },
    },
    smoked = {
        tint = { 0.05, 0.06, 0.08, 0.62 }, grain = 0, wash = 0.14,
        pane = { 0.03, 0.03, 0.04, 0.80 },
        section = { 0.03, 0.03, 0.04, 0.94 },
    },
}
-- Every value of the setting, in the order the options page lists them.
Skin.NAMES = { "clear", "smoked", "stock" }
Skin.LABELS = { clear = "Clear glass", smoked = "Smoked glass", stock = "Blizzard's own" }

-- The stock frame art of ButtonFrameTemplate (SharedUIPanelTemplates.xml:566-711).
local ART = { "NineSlice", "Bg", "TopTileStreaks" }
-- The three horizontal bars (MailFrame.xml:479-506, 922-935). Each has an
-- unnamed right-hand piece anchored to it, found through GetRegions.
local BARS = {
    MailFrame = { "SendMailHorizontalBarLeft", "SendMailHorizontalBarLeft2" },
    OpenMailFrame = { "OpenMailHorizontalBarLeft" },
}
-- The send tab's money box: an inset like the window's (MailFrame.xml:791). Its
-- gold-edged value field (SendMailMoneyBg) stays, as the edit boxes' borders do.
local INSETS = { MailFrame = { "SendMailMoneyInset" } }
-- The letters: each scroll frame and the stationery it draws (MailFrame.xml:
-- 510-533, 975-1000). Blizzard sets the stationery's texture and height per
-- letter (MailFrame.lua:777-781, 967-970), never its alpha, so a fade holds.
local LETTERS = {
    MailFrame = { scroll = "SendMailScrollFrame", paper = { "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight" },
        edit = "SendMailBodyEditBox" },
    OpenMailFrame = { scroll = "OpenMailScrollFrame", paper = { "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight" },
        html = "OpenMailBodyText", child = "OpenMailScrollChildFrame" },
}
-- The letter's text under glass: a warm off-white, the same in both presets.
Skin.LETTER_TEXT = { 0.92, 0.90, 0.86 }
-- The send body's selection under glass. Blizzard's is a pale grey
-- (MailFrame.xml:581), made for dark text: light text on it can't be read.
Skin.LETTER_HIGHLIGHT = { 0.30, 0.36, 0.48 }

local function rowCount()
    local n = rawget(_G, "INBOXITEMS_TO_DISPLAY")   -- MailFrame.lua:1
    return type(n) == "number" and n or 7
end

local skinned = {}   -- window -> { panel = frame, g = glass regions, art = { region, ... } }
local pane           -- { frame, tex } under the inbox rows
-- window name -> { paper = { texture, ... }, pane = { frame, tex }, text = { { widget, kind, r, g, b, a }, ... },
-- light = bool }: the stationery, the pane in its place, the letter's text with Blizzard's
-- colours, and whether we have turned it light.
local letters = {}
-- The sections, in the mockup's dark panels: window name (or "footer") ->
-- { frame, tex }. Each window's content box, and the send tab's footer.
local sections = {}
-- What Start has already tried to build (window name, "sections"): a failed build
-- is recorded once and not retried on every later ADDON_LOADED.
local tried = {}

-- The current preset, or nil under "stock".
local function preset()
    return Skin.PRESETS[GM.db.skin]
end

-- The preset's body into this addon's LibGlass STYLE, before an Apply: COPIED,
-- never aliased (AltStable #184: the library fills STYLE in place, and an
-- alias would let that edit the preset itself).
local function pushStyle(p)
    local st = Glass.STYLE
    st.tint = { p.tint[1], p.tint[2], p.tint[3], p.tint[4] }
    st.grain, st.wash = p.grain, p.wash
end

local function paintBody(g, p)
    Glass.SetSurfaceTint(g, p.tint[1], p.tint[2], p.tint[3], p.tint[4])
    g.grain:SetAlpha(p.grain)
    g.wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, p.wash))
end

local function add(list, region)
    if region and region.SetAlpha then list[#list + 1] = region end
end

local function isTexture(region)
    return region.GetObjectType and region:GetObjectType() == "Texture"
end

-- The window's stock art, as a list of regions to fade. Only what is named,
-- a template parentKey, or picked out by structure (never by texture path:
-- GetTexture returns file IDs on this client).
local function collectArt(window, name)
    local art = {}
    for _, key in ipairs(ART) do add(art, window[key]) end
    local insets = { window.Inset }
    for _, insetName in ipairs(INSETS[name] or {}) do insets[#insets + 1] = rawget(_G, insetName) end
    for _, inset in pairs(insets) do
        add(art, inset.Bg)
        add(art, inset.NineSlice)
    end
    -- The bars and their unnamed right-hand pieces: a texture on the same
    -- frame whose first anchor is relative to the named bar.
    for _, barName in ipairs(BARS[name] or {}) do
        local bar = rawget(_G, barName)
        if bar then
            add(art, bar)
            local owner = bar:GetParent()
            for _, region in ipairs({ owner:GetRegions() }) do
                local _, relativeTo = region:GetPoint(1)
                if relativeTo == bar and isTexture(region) then add(art, region) end
            end
        end
    end
    if name == "MailFrame" then
        add(art, rawget(_G, "InboxFrameBg"))
        -- Each inbox row's own textures: the two MailItemBorder halves and the
        -- divider line (MailFrame.xml:15-35). Its font strings (sender,
        -- subject) are regions too, and stay.
        for i = 1, rowCount() do
            local row = rawget(_G, "MailItem" .. i)
            if row then
                for _, region in ipairs({ row:GetRegions() }) do
                    if isTexture(region) then add(art, region) end
                end
            end
        end
    end
    return art
end

-- A panel just under the window: a child at one frame level below, so the
-- window's own regions and children draw over it (GlassChat's edit-box panel).
local function addPanel(window, name)
    -- The art first: if reading the regions fails, nothing half-built is left.
    local art = collectArt(window, name)
    local panel = CreateFrame("Frame", nil, window)
    panel:SetAllPoints(window)
    panel:SetFrameLevel(math.max(0, window:GetFrameLevel() - 1))
    pushStyle(preset() or Skin.PRESETS.clear)
    local g = Glass.Apply(panel, "large")
    skinned[window] = { panel = panel, g = g, art = art }
end

-- A pane: a plain translucent fill from one region's top left to another's
-- bottom right, rounded by the material's small mask. Not another glass
-- layer: just enough density for text over a bright world.
-- If building it fails, the frame is hidden before the error goes on: no
-- half-built pane is left showing.
local function newPane(parent, topLeft, bottomRight, level, pad)
    local f = CreateFrame("Frame", nil, parent)
    local ok, tex = pcall(function()
        f:SetPoint("TOPLEFT", topLeft, "TOPLEFT", -pad, pad)
        f:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMRIGHT", pad, -pad)
        f:SetFrameLevel(level)
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints(f)
        t:AddMaskTexture(Glass.Mask(f, "body_mask_small", 8))
        return t
    end)
    if not ok then
        f:Hide()
        error(tex, 0)
    end
    return { frame = f, tex = tex }
end

-- The reading pane under the inbox rows.
local function addPane()
    local inbox = rawget(_G, "InboxFrame")
    local first, last = rawget(_G, "MailItem1"), rawget(_G, "MailItem" .. rowCount())
    if not (inbox and first and last) then return end
    pane = newPane(inbox, first, last, inbox:GetFrameLevel(), 4)
end

-- The letter's text, with the colours Blizzard gave it: the send tab's edit
-- box, the open letter's body (SimpleHTML, coloured per text type: "P"), and
-- every font string under the open letter that uses the mail or invoice font
-- (the AH invoice, crafting order notes). Picked out by font object, never by
-- text.
local function letterTextOf(letter)
    local list = {}
    -- A colour that can't be read is an error: the letter then isn't built,
    -- rather than "restored" to nothing under stock.
    local function keep(widget, kind)
        local r, g, b, a
        if kind == "html" then r, g, b, a = widget:GetTextColor("P") else r, g, b, a = widget:GetTextColor() end
        if type(r) ~= "number" then error("no text colour on a " .. kind .. " widget", 0) end
        local t = { widget = widget, kind = kind, r = r, g = g, b = b, a = a }
        if kind == "edit" then
            t.hr, t.hg, t.hb, t.ha = widget:GetHighlightColor()
            if type(t.hr) ~= "number" then error("no highlight colour on the send body", 0) end
        end
        list[#list + 1] = t
    end
    local edit, body = letter.edit and rawget(_G, letter.edit), letter.html and rawget(_G, letter.html)
    if edit then keep(edit, "edit") end
    if body then keep(body, "html") end
    local fonts = {}
    for _, fontName in ipairs({ "MailTextFontNormal", "InvoiceTextFontNormal" }) do
        local font = rawget(_G, fontName)
        if font then fonts[font] = true end
    end
    local function walk(frame, depth)
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "FontString" and fonts[region:GetFontObject()] then keep(region, "plain") end
        end
        if depth < 6 then
            for _, child in ipairs({ frame:GetChildren() }) do walk(child, depth + 1) end
        end
    end
    local child = letter.child and rawget(_G, letter.child)
    if child then walk(child, 0) end
    return list
end

-- A skinned window's letter: its text read first (if that fails, nothing is
-- built and the stationery stays), then a pane over the stationery's area,
-- anchored to the stationery so it follows the height Blizzard gives it per
-- letter. The pane sits beside the scroll frame at its level: the scroll
-- child, and the text in it, draw above. The stationery, the pane and the
-- text change together: light text on parchment, or dark text on bare glass,
-- would be unreadable.
local function addLetter(name)
    local letter = LETTERS[name]
    local scroll = rawget(_G, letter.scroll)
    local left, right = rawget(_G, letter.paper[1]), rawget(_G, letter.paper[2])
    if not (scroll and left and right) then return end
    local text = letterTextOf(letter)
    letters[name] = { paper = { left, right }, text = text, light = false,
        pane = newPane(scroll:GetParent(), left, right, scroll:GetFrameLevel(), 0) }
end

-- The sections: a pane over each window's content box, its Inset, whose
-- geometry Blizzard sets per tab (MailFrame.lua:215, 222, 465; the button bar,
-- SharedUIPanelTemplates.lua:57-72), so the pane follows it with no offsets of
-- ours. At the window's own level: the tab frames, their rows, letters and
-- buttons (children, a level up) draw above, and the window's own regions are
-- the faded art. And the send tab's footer, from the money inset (left) to
-- Cancel (right): the balance and Send / Cancel, at SendMailFrame's level,
-- whose regions there are only the faded art.
local function addSections()
    for _, name in ipairs({ "MailFrame", "OpenMailFrame" }) do
        local window = rawget(_G, name)
        if window and skinned[window] and window.Inset then
            sections[name] = newPane(window, window.Inset, window.Inset, window:GetFrameLevel(), 0)
        end
    end
    local send, left, cancel = rawget(_G, "SendMailFrame"), rawget(_G, "SendMailMoneyInset"), rawget(_G, "SendMailCancelButton")
    if sections.MailFrame and send and left and cancel then
        sections.footer = newPane(send, left, cancel, send:GetFrameLevel(), 2)
    end
end

-- Light under glass; Blizzard's own colours back under "stock". Only on a
-- change: a letter never turned light is never touched, so under stock the
-- widgets keep following their font objects. The open letter's body is a
-- SimpleHTML, which lays its text out on SetText: if the letter is open, ask
-- Blizzard to show it again (OpenMailFrame:Update, its own refresh) so the
-- text on screen takes the new colour.
local function paintLetterText(name, letter, p)
    local light = p ~= nil
    if letter.light == light then return end
    letter.light = light
    local c, h = Skin.LETTER_TEXT, Skin.LETTER_HIGHLIGHT
    for _, t in ipairs(letter.text) do
        local r, g, b, a = t.r, t.g, t.b, t.a
        if light then r, g, b, a = c[1], c[2], c[3], 1 end
        if t.kind == "html" then t.widget:SetTextColor("P", r, g, b, a) else t.widget:SetTextColor(r, g, b, a) end
        if t.kind == "edit" then
            if light then t.widget:SetHighlightColor(h[1], h[2], h[3], 1)
            else t.widget:SetHighlightColor(t.hr, t.hg, t.hb, t.ha) end
        end
    end
    local window = rawget(_G, name)
    if LETTERS[name].html and window and window:IsShown() then
        local ok, err = pcall(window.Update, window)
        if not ok then API.Fail("skin letter refresh", err) end
    end
end

local function applyOne(window, p)
    local s = skinned[window]
    s.panel:SetShown(p ~= nil)
    if p then paintBody(s.g, p) end
    for _, region in ipairs(s.art) do region:SetAlpha(p and 0 or 1) end
end

-- Skin the windows that exist now. MailFrame and OpenMailFrame come from
-- Blizzard_MailFrame, which is not load-on-demand, so they exist by
-- PLAYER_LOGIN; ADDON_LOADED covers a client where that changes.
function Skin.Start()
    for _, name in ipairs({ "MailFrame", "OpenMailFrame" }) do
        local window = rawget(_G, name)
        if window and not skinned[window] then
            local ok, err = pcall(addPanel, window, name)
            if not ok then API.Fail("skin " .. name, err) end
        end
    end
    if not pane then
        local ok, err = pcall(addPane)
        if not ok then API.Fail("skin pane", err) end
    end
    for name in pairs(LETTERS) do
        local window = rawget(_G, name)
        if window and skinned[window] and not tried[name] then
            tried[name] = true
            local ok, err = pcall(addLetter, name)
            if not ok then API.Fail("skin letter " .. name, err) end
        end
    end
    if next(skinned) and not tried.sections then
        tried.sections = true
        local ok, err = pcall(addSections)
        if not ok then API.Fail("skin sections", err) end
    end
    Skin.Refresh()
end

-- Repaint everything we built in the current preset, live. STYLE is only read
-- when a surface is built (addPanel pushes the preset there), so it isn't
-- touched here.
local function paintPane(pn, p, key)
    if not pn then return end
    pn.frame:SetShown(p ~= nil)
    local c = p and p[key or "pane"]
    if c then pn.tex:SetColorTexture(c[1], c[2], c[3], c[4]) end
end

function Skin.Refresh()
    local p = preset()
    for window in pairs(skinned) do applyOne(window, p) end
    paintPane(pane, p)
    for _, pn in pairs(sections) do paintPane(pn, p, "section") end
    for name, letter in pairs(letters) do
        paintPane(letter.pane, p)
        for _, paper in ipairs(letter.paper) do paper:SetAlpha(p and 0 or 1) end
        paintLetterText(name, letter, p)
    end
end

function Skin.IsSkinned(window) return skinned[window] ~= nil end

function Skin.IsValid(name) return name == "stock" or Skin.PRESETS[name] ~= nil end

GM._test = GM._test or {}
GM._test.skin = { skinned = skinned, ART = ART, pane = function() return pane end, letters = letters,
    sections = sections }
