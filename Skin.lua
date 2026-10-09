-- Skin.lua: the glass look on Blizzard's mail windows (MailFrame, the inbox and
-- send tabs, and OpenMailFrame, the open letter).
--
-- First pass (M0): a glass panel under each window, and the stock frame art
-- faded out while glass is on. Everything is done with method calls on our
-- own frames and on the template's parentKey children (NineSlice, Bg,
-- TopTileStreaks): no field is ever written onto a Blizzard frame, and no
-- Blizzard function is replaced. Fading uses SetAlpha, never Hide, so
-- Blizzard's own Show/Hide logic for those regions keeps working.

GlassMailbox = GlassMailbox or {}
local GM = GlassMailbox
local API = GM.API
local Glass = GM.Glass
local Skin = {}
GM.Skin = Skin

-- The stock frame art of ButtonFrameTemplate (SharedUIPanelTemplates.xml:566-711).
local ART = { "NineSlice", "Bg", "TopTileStreaks" }

local skinned = {}   -- window -> { panel = frame, g = glass regions }

local function setArt(window, alpha)
    for _, key in ipairs(ART) do
        local region = window[key]
        if region and region.SetAlpha then region:SetAlpha(alpha) end
    end
end

-- A panel just under the window: a child at one frame level below, so the
-- window's own regions and children draw over it (GlassChat's edit-box panel).
local function addPanel(window)
    local panel = CreateFrame("Frame", nil, window)
    panel:SetAllPoints(window)
    panel:SetFrameLevel(math.max(0, window:GetFrameLevel() - 1))
    local g = Glass.Apply(panel, "large")
    skinned[window] = { panel = panel, g = g }
end

local function applyOne(window)
    local s = skinned[window]
    if not s then return end
    local on = GM.db.glass
    s.panel:SetShown(on)
    setArt(window, on and 0 or 1)
end

-- Skin the windows that exist now. MailFrame and OpenMailFrame come from
-- Blizzard_MailFrame, which is not load-on-demand, so they exist by
-- PLAYER_LOGIN; ADDON_LOADED covers a client where that changes.
function Skin.Start()
    for _, name in ipairs({ "MailFrame", "OpenMailFrame" }) do
        local window = rawget(_G, name)
        if window and not skinned[window] then
            local ok, err = pcall(addPanel, window)
            if not ok then API.Fail("skin " .. name, err) end
        end
    end
    Skin.Refresh()
end

function Skin.Refresh()
    for window in pairs(skinned) do applyOne(window) end
end

function Skin.IsSkinned(window) return skinned[window] ~= nil end

GM._test = GM._test or {}
GM._test.skin = { skinned = skinned, ART = ART }
