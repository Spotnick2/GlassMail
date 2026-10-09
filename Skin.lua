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
-- presets are AltStable's numbers (AltStable/Skin.lua), so the two addons look
-- alike. They differ only in the body (tint, grain, wash) and the pane, never
-- in the rim: GLASS-MATERIAL.md, a darkened rim reads as smoked plastic.
-- Unlike AltStable, the switch is live: we own a handful of surfaces and
-- repaint them (LibGlass SetSurfaceTint, the grain's alpha, the wash's
-- gradient), where AltStable has too many to repaint and asks for a /reload.
--
-- The letter's stationery (OpenStationeryBackground*, SendStationeryBackground*)
-- is NOT faded: the letter body is a dark mail font made for parchment, and
-- recolouring Blizzard's text is not ours to do.

GlassMailbox = GlassMailbox or {}
local GM = GlassMailbox
local API = GM.API
local Glass = GM.Glass
local Skin = {}
GM.Skin = Skin

Skin.PRESETS = {
    clear = {
        label = "Clear glass",
        tint = { 0.13, 0.16, 0.22, 0.24 }, grain = 0.45, wash = 0.18,
        pane = { 0.04, 0.05, 0.07, 0.62 },
    },
    smoked = {
        label = "Smoked glass",
        tint = { 0.05, 0.06, 0.08, 0.62 }, grain = 0.35, wash = 0.14,
        pane = { 0.03, 0.03, 0.04, 0.80 },
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
local ROWS = 7   -- INBOXITEMS_TO_DISPLAY (MailFrame.lua:1)

local skinned = {}   -- window -> { panel = frame, g = glass regions, art = { region, ... } }
local pane           -- { frame, tex } under the inbox rows

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
    local inset = window.Inset
    if inset then
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
        for i = 1, ROWS do
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
    local panel = CreateFrame("Frame", nil, window)
    panel:SetAllPoints(window)
    panel:SetFrameLevel(math.max(0, window:GetFrameLevel() - 1))
    pushStyle(preset() or Skin.PRESETS.clear)
    local g = Glass.Apply(panel, "large")
    skinned[window] = { panel = panel, g = g, art = collectArt(window, name) }
end

-- The reading pane: a plain translucent fill under the seven rows, rounded by
-- the material's small mask. Not another glass layer: just enough density for
-- Blizzard's row text over a bright world.
local function addPane()
    local inbox = rawget(_G, "InboxFrame")
    local first, last = rawget(_G, "MailItem1"), rawget(_G, "MailItem" .. ROWS)
    if not (inbox and first and last) then return end
    local f = CreateFrame("Frame", nil, inbox)
    f:SetPoint("TOPLEFT", first, "TOPLEFT", -4, 4)
    f:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 4, -4)
    f:SetFrameLevel(inbox:GetFrameLevel())
    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(f)
    tex:AddMaskTexture(Glass.Mask(f, "body_mask_small", 8))
    pane = { frame = f, tex = tex }
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
    Skin.Refresh()
end

-- Repaint everything we built in the current preset, live.
function Skin.Refresh()
    local p = preset()
    if p then pushStyle(p) end
    for window in pairs(skinned) do applyOne(window, p) end
    if pane then
        pane.frame:SetShown(p ~= nil)
        if p then pane.tex:SetColorTexture(p.pane[1], p.pane[2], p.pane[3], p.pane[4]) end
    end
end

function Skin.IsSkinned(window) return skinned[window] ~= nil end

function Skin.IsValid(name) return name == "stock" or Skin.PRESETS[name] ~= nil end

GM._test = GM._test or {}
GM._test.skin = { skinned = skinned, ART = ART, pane = function() return pane end }
