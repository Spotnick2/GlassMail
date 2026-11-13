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
-- The looks: clear and smoked glass, class (from Glass UI's suite only), and
-- "stock" (Blizzard's own art). Which one is Suite.lua's answer (the suite's
-- tint, an override, or the `skin` setting); Skin keeps the one APPLIED, and
-- every paint path paints from it. A body is Glass UI's Suite.Body shape (a
-- tint or a class shade, a wash factor, a backing): Glass UI's numbers while
-- following, else our copy (Skin.BODIES, the same numbers). Surfaces are built
-- from the material as Glass.lua made it (nothing pushed into STYLE) and the
-- body is painted on after building: SetSurfaceTint, and SetWash at the
-- material's own wash times the body's factor. The looks differ in the body
-- and the panes, never in the rim: GLASS-MATERIAL.md, a darkened rim reads as
-- smoked plastic. The switch is live: we own a handful of surfaces and repaint
-- them (SetWash: a gradient ignores SetAlpha, LibGlass #47).
--
-- In combat a change that crosses the stock boundary (it turns the letter, and
-- an open letter is re-shown through Blizzard's OpenMailFrame:Update) waits
-- for PLAYER_REGEN_ENABLED, the applied look kept meanwhile; glass-to-glass
-- changes only repaint colours and alphas, and apply at once.
--
-- The letter (the send tab's body and the open letter) goes dark under glass,
-- as in docs/mockups/inbox-and-send.png (owner, 2026-10-10): the stationery is
-- faded like the rest of the art, a pane takes its place, and the letter's
-- text, a dark font made for parchment, is turned light. Only the mail widgets
-- are recoloured (SetTextColor on each), never the shared font objects
-- MailTextFontNormal / InvoiceTextFontNormal, which other windows use too.
-- Under "stock" every colour goes back to what it was.
--
-- Under glass the windows' portraits give way to ours: the Glass Mail envelope
-- over the mail window's parcel, the glass scroll over an open letter's
-- stationery icon. Ours on top, Blizzard's faded, back under "stock".

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
-- backing: under the glass of our floating panels (the address book's picker,
-- the item grid), clipped by its mask: Glass UI's body over the world, as its
-- quest tracker wears it (GlassUI Suite.BODY and Suite.BACKING; the owner,
-- 2026-11-12: the picker's bare tint let Shatter's window read through).
-- The bodies, in Glass UI's Suite.Body shape (GlassUI Suite.lua, the numbers it
-- moved from its Theme.PRESETS, which are AltStable's): used when not
-- following, and when Glass UI's answer is missing or bad. `wash` is a factor
-- of the material's own wash (smoked's 0.14 / 0.18 keeps clean's old ratio);
-- `backing` the alpha of the opaque layer under a floating panel's tint.
Skin.BODIES = {
    clear = { tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1, backing = 0.35 },
    smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, wash = 0.14 / 0.18, backing = 0.92 },
    class = { classShade = 0.6, wash = 1, backing = 0.35 },
}
Skin.BACKING = { 0.04, 0.05, 0.07 }
-- The panes, Glass Mail's own; class reads on clear's (neutral, dense).
Skin.PANES = {
    clear = { pane = { 0.04, 0.05, 0.07, 0.62 }, section = { 0.04, 0.05, 0.07, 0.94 } },
    smoked = { pane = { 0.03, 0.03, 0.04, 0.80 }, section = { 0.03, 0.03, 0.04, 0.94 } },
}
-- Every value of the setting, in the order the options page lists them.
Skin.NAMES = { "clear", "smoked", "stock" }
Skin.LABELS = { clear = "Clear glass", smoked = "Smoked glass", stock = "Blizzard's own", class = "Class colour" }

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
-- Our portraits, round already: Blizzard masks its portraits to a circle.
Skin.PORTRAITS = {
    MailFrame = "Interface\\AddOns\\GlassMail\\Media\\Envelope",
    OpenMailFrame = "Interface\\AddOns\\GlassMail\\Media\\Scroll",
}
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
-- The inbox's guides (addGuides): white, faint enough to sit under a mail's
-- icon and text, the same in both presets; the empty inbox's envelope and line.
Skin.GUIDES = { slot = { 1, 1, 1, 0.07 }, line = { 1, 1, 1, 0.09 }, envelope = 0.35, text = { 0.6, 0.6, 0.6 } }
Skin.EMPTY_TEXT = "No mail"

local function rowCount()
    local n = rawget(_G, "INBOXITEMS_TO_DISPLAY")   -- MailFrame.lua:1
    return type(n) == "number" and n or 7
end

local skinned = {}   -- window -> { panel = frame, g = glass regions, art = { region, ... } }
local portraits = {}  -- window name -> { frame, stock }: our portrait over Blizzard's, and Blizzard's
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

-- The applied look's name ("clear" | "smoked" | "class" | "stock"), its
-- resolved paint (nil under stock), and whether a stock-boundary change waits
-- for combat's end.
local applied, current, pending

-- A look's paint: { name, body, pane, section, backing }, nil for stock. The
-- body is Suite.Body's (Glass UI's, checked, or ours), resolved once here and
-- shared by every surface.
local function resolve(name)
    if name == "stock" or name == nil then return nil end
    local body = GM.Suite.Body(name) or GM.Suite.Body("clear")
    local panes = Skin.PANES[name] or Skin.PANES.clear
    return { name = name, body = body, pane = panes.pane, section = panes.section, backing = body.backing }
end

-- The applied look's paint, or nil under stock.
local function preset() return current end

-- The player's class colour, or nil while it can't be read (early in a login).
local function classColour()
    local _, token = UnitClass("player")
    if API.IsSecret(token) or type(token) ~= "string" then return nil end
    local colours = rawget(_G, "RAID_CLASS_COLORS")
    local c = type(colours) == "table" and colours[token]
    if type(c) ~= "table" then return nil end
    local r, g, b = c.r, c.g, c.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return r, g, b
end

-- The body on one surface: its tint (the class colour times the shade, at the
-- surface's built alpha; the built tint while the colour can't be read) and
-- its wash, a factor of the material's own.
local function paintBody(g, p)
    local body = p.body
    if body.tint then
        local t = body.tint
        Glass.SetSurfaceTint(g, t[1], t[2], t[3], t[4])
    else
        local r, gg, b = classColour()
        if r then
            local s = body.classShade
            Glass.SetSurfaceTint(g, r * s, gg * s, b * s)
        else
            Glass.SetSurfaceTint(g)
        end
    end
    Glass.SetWash(g, GM.BaseWash() * body.wash)
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
    local g = Glass.Apply(panel, "large")
    skinned[window] = { panel = panel, g = g, art = art }
end

-- Our portrait over a window's (ButtonFrameTemplate's PortraitContainer,
-- SharedUIPanelTemplates.xml:574-596): our frame a level above the container, our
-- texture on the circle Blizzard masks the portrait to. Blizzard sets the
-- portraits' textures (MailFrame.lua:26, and per letter at :424), never their
-- alpha, so a fade holds.
local function addPortrait(name)
    local window = rawget(_G, name)
    local container = window and window.PortraitContainer
    local stock = container and container.portrait
    if not stock then return end
    local circle = container.CircleMask or stock
    local f = CreateFrame("Frame", nil, window)
    f:SetFrameLevel(container:GetFrameLevel() + 1)
    f:SetAllPoints(circle)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Skin.PORTRAITS[name])
    t:SetAllPoints(f)
    portraits[name] = { frame = f, stock = stock }
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

-- The inbox's guides on the reading pane, in place of the faded stock row art
-- (owner, 2026-11-12: an empty inbox under glass read as one bare pane, where
-- Blizzard's shows seven slots on ruled paper). Per row a rounded slot behind
-- the item button (where its icon goes, MailFrame.xml:69: 37 x 37 at 4, -3) and
-- a line under every row but the last; and, when the inbox holds no mail, our
-- envelope faded in the middle with "No mail", the lines then hidden. All of it on the pane's own
-- frame, under the rows (children of InboxFrame, a level up): a mail's icon
-- and text draw over its slot. Shown under glass while `inboxGuides` is on.
local guides   -- { slots = { texture, ... }, lines = { texture, ... }, empty = { icon, text } }
local function addGuides()
    if not pane then return end
    local host = pane.frame
    local g = { slots = {}, lines = {} }
    local n = rowCount()
    -- Every row first: a missing one builds nothing (an unpainted texture
    -- draws nothing, but none is left behind either).
    for i = 1, n do
        if not (rawget(_G, "MailItem" .. i) and rawget(_G, "MailItem" .. i .. "Button")) then
            error("MailItem" .. i .. " or its button missing", 0)
        end
    end
    for i = 1, n do
        local row, button = rawget(_G, "MailItem" .. i), rawget(_G, "MailItem" .. i .. "Button")
        local slot = host:CreateTexture(nil, "BORDER")
        slot:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
        slot:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
        slot:AddMaskTexture(Glass.Mask(host, "body_mask_small", 8, -1, button))
        g.slots[i] = slot
        if i < n then
            local line = host:CreateTexture(nil, "BORDER")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 4, 0)
            line:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", -4, 0)
            g.lines[#g.lines + 1] = line
        end
    end
    local icon = host:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Skin.PORTRAITS.MailFrame)
    icon:SetSize(72, 72)
    icon:SetPoint("CENTER", host, "CENTER", 0, 16)
    local text = Glass.Font(host, 14, "CENTER")
    text:SetPoint("TOP", icon, "BOTTOM", 0, -10)
    text:SetText(Skin.EMPTY_TEXT)
    g.empty = { icon = icon, text = text }
    guides = g
end

-- No mail loaded: nothing to show, and nothing on its way (a secret count
-- isn't read as empty).
local function inboxEmpty()
    local loaded, total = GetInboxNumItems()
    if API.IsSecret(loaded) or API.IsSecret(total) then return false end
    return loaded == 0 and total == 0
end

local function paintGuides(p)
    if not guides then return end
    local on = p ~= nil and GM.db.inboxGuides == true
    local c = Skin.GUIDES
    for _, t in ipairs(guides.slots) do
        t:SetShown(on)
        t:SetColorTexture(c.slot[1], c.slot[2], c.slot[3], c.slot[4])
    end
    -- An empty inbox's envelope and "No mail" sit across the rows: no lines
    -- through them (owner, 2026-11-12, from a screenshot).
    local empty = on and inboxEmpty()
    for _, t in ipairs(guides.lines) do
        t:SetShown(on and not empty)
        t:SetColorTexture(c.line[1], c.line[2], c.line[3], c.line[4])
    end
    guides.empty.icon:SetShown(empty)
    guides.empty.icon:SetAlpha(c.envelope)
    guides.empty.text:SetShown(empty)
    guides.empty.text:SetTextColor(c.text[1], c.text[2], c.text[3])
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

-- Glass Mail's own window (Window.lua): always glass, with no Blizzard art to
-- fall back on, so `stock` shows it smoked. Its body and panes repaint here.
local own = {}   -- { g = surface } or { tex = texture, key = "pane" | "section" }
local ownStock   -- the smoked paint our own windows wear under stock
local function ownPreset()
    if current then return current end
    if not ownStock then ownStock = resolve("smoked") end
    return ownStock
end
local function paintOwn(o, p)
    if o.g then paintBody(o.g, p) else
        local c = p[o.key]
        o.tex:SetColorTexture(c[1], c[2], c[3], c[4])
    end
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
    if pane and not tried.guides then
        tried.guides = true
        local ok, err = pcall(addGuides)
        if not ok then
            API.Fail("skin guides", err)
        else
            -- Blizzard's own refresh of the rows, after every inbox change (MailFrame.lua:325).
            local inbox = rawget(_G, "InboxFrame")
            if guides and inbox and inbox.Update then
                hooksecurefunc(inbox, "Update", function()
                    local okPaint, errPaint = pcall(paintGuides, preset())
                    if not okPaint then API.Fail("skin guides", errPaint) end
                end)
            end
        end
    end
    for name in pairs(LETTERS) do
        local window = rawget(_G, name)
        if window and skinned[window] and not tried[name] then
            tried[name] = true
            local ok, err = pcall(addLetter, name)
            if not ok then API.Fail("skin letter " .. name, err) end
        end
    end
    for name in pairs(Skin.PORTRAITS) do
        local window = rawget(_G, name)
        local key = "portrait " .. name
        if window and skinned[window] and not tried[key] then
            tried[key] = true
            local ok, err = pcall(addPortrait, name)
            if not ok then API.Fail("skin " .. key, err) end
        end
    end
    if next(skinned) and not tried.sections then
        tried.sections = true
        local ok, err = pcall(addSections)
        if not ok then API.Fail("skin sections", err) end
    end
    Skin.Refresh()
end

-- PLAYER_REGEN_ENABLED, while a stock-boundary change waits: apply the latest
-- request whole, and report it (Suite.Changed).
local regen = CreateFrame("Frame")
regen:SetScript("OnEvent", function(_, event)
    API.NoteCombat(event)
    if event == "PLAYER_REGEN_ENABLED" and pending then
        local ok, err = pcall(GM.Suite.Changed)
        if not ok then API.Fail("skin after combat", err) end
    end
end)
API.RegisterEvents(regen, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })

-- Repaint everything we built in the applied look, live.
local function paintPane(pn, p, key)
    if not pn then return end
    pn.frame:SetShown(p ~= nil)
    local c = p and p[key or "pane"]
    if c then pn.tex:SetColorTexture(c[1], c[2], c[3], c[4]) end
end

-- The look Suite asks for, applied: at once, unless it crosses the stock
-- boundary in combat (then the applied look stays, and PLAYER_REGEN_ENABLED
-- brings the latest request; a request back cancels it).
function Skin.Refresh()
    local want = GM.Suite.Requested()
    if applied ~= nil and (applied == "stock") ~= (want == "stock") and API.InCombat() then
        pending, want = true, applied
    else
        pending = false
    end
    applied = want
    current, ownStock = resolve(applied), nil
    local p = current
    for window in pairs(skinned) do applyOne(window, p) end
    paintPane(pane, p)
    paintGuides(p)
    for _, pn in pairs(sections) do paintPane(pn, p, "section") end
    for _, portrait in pairs(portraits) do
        portrait.frame:SetShown(p ~= nil)
        portrait.stock:SetAlpha(p and 0 or 1)
    end
    for name, letter in pairs(letters) do
        paintPane(letter.pane, p)
        for _, paper in ipairs(letter.paper) do paper:SetAlpha(p and 0 or 1) end
        paintLetterText(name, letter, p)
    end
    for _, o in ipairs(own) do paintOwn(o, ownPreset()) end
end

-- The glass body on frame (its content goes at Glass.ContentLevel(frame)).
-- backing: an opaque layer under the tint, clipped by the glass's mask (a
-- floating panel's, as Glass UI's tracker: the preset's `backing`).
function Skin.AddWindow(frame, backing)
    local p = ownPreset()
    local o = { g = Glass.Apply(frame, "large") }
    own[#own + 1] = o
    paintOwn(o, p)
    if backing then
        local b = { tex = frame:CreateTexture(nil, "BACKGROUND", nil, -7), key = "backing" }
        b.tex:SetAllPoints(frame)
        b.tex:AddMaskTexture(o.g.mask)
        own[#own + 1] = b
        paintOwn(b, p)
    end
    return o.g
end

-- A pane filling frame, in the preset's `key` colour ("pane" or "section").
function Skin.AddPane(frame, key)
    local o = { tex = frame:CreateTexture(nil, "BACKGROUND"), key = key }
    o.tex:SetAllPoints(frame)
    own[#own + 1] = o
    paintOwn(o, ownPreset())
    return o.tex
end

function Skin.IsSkinned(window) return skinned[window] ~= nil end

-- A value of the `skin` setting (the local look): clear, smoked or stock.
function Skin.IsValid(name) return name == "stock" or Skin.PANES[name] ~= nil end

-- The look on screen: "clear" | "smoked" | "class" | "stock" (nil before the first refresh).
function Skin.Applied() return applied end
function Skin.Pending() return pending == true end

-- PLAYER_ENTERING_WORLD: the class colour can be read by now.
function Skin.Retry()
    if applied == "class" then Skin.Refresh() end
end

GM._test = GM._test or {}
GM._test.skin = { skinned = skinned, ART = ART, pane = function() return pane end, letters = letters,
    sections = sections, portraits = portraits, own = own, guides = function() return guides end,
    current = function() return current end }
