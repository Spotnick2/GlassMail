-- The glass look on the mail windows: a panel under each, the stock art faded
-- (never hidden, never a field written on a Blizzard frame), and the toggle.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Snapshot every field of the mail windows before the addon loads: the skin
-- may call their methods, but must not write onto them.
local function fields(w)
    local t = {}
    for k, v in pairs(w) do t[k] = v end
    return t
end
local before = { MailFrame = fields(MailFrame), OpenMailFrame = fields(OpenMailFrame) }

local GM = loadAddon()
for _, name in ipairs({ "MailFrame", "OpenMailFrame" }) do
    local w = _G[name]
    check(GM.Skin.IsSkinned(w), name .. " is skinned")
    local after = fields(w)
    for k, v in pairs(after) do check(before[name][k] == v, name .. ": no field written: " .. tostring(k)) end
    for k in pairs(before[name]) do check(after[k] ~= nil, name .. ": no field removed: " .. tostring(k)) end
    local s = GM._test.skin.skinned[w]
    check(s.panel:IsShown(), name .. ": the glass panel shows")
    check(s.panel:GetFrameLevel() < w:GetFrameLevel(), name .. ": the panel sits under the window")
    for _, key in ipairs(GM._test.skin.ART) do
        eq(w[key]:GetAlpha(), 0, name .. ": stock " .. key .. " faded")
        check(w[key]:IsShown(), name .. ": stock " .. key .. " not hidden (Blizzard keeps control)")
    end
end

-- Off: Blizzard's own art back, the panel gone.
GM.Settings.SetGlass(false)
local s = GM._test.skin.skinned[MailFrame]
check(not s.panel:IsShown(), "glass off hides the panel")
eq(MailFrame.Bg:GetAlpha(), 1, "glass off restores the stock art")
GM.Settings.SetGlass(true)
eq(MailFrame.Bg:GetAlpha(), 0, "glass on fades it again")

-- Starting twice (PLAYER_LOGIN, then ADDON_LOADED for the mail frame) builds
-- one panel per window.
local n = 0
for _ in pairs(GM._test.skin.skinned) do n = n + 1 end
WoW.fire("ADDON_LOADED", "Blizzard_MailFrame")
local m = 0
for _ in pairs(GM._test.skin.skinned) do m = m + 1 end
eq(m, n, "a second start adds no panels")
eq(next(GM.failures), nil, "no failures recorded")

done("test_skin")
