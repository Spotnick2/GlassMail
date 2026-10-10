-- A letter whose text can't be read is left whole (parchment and dark text):
-- never light text on parchment, nor dark text on bare glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function children(parent)
    local n = 0
    for _, w in ipairs(WoW.frames) do if w._parent == parent then n = n + 1 end end
    return n
end
local before = children(OpenMailFrame)
OpenMailScrollChildFrame.GetChildren = function() error("children unavailable") end
local GM = loadAddon()
local T = GM._test.skin
check(GM.Skin.IsSkinned(OpenMailFrame), "the open letter's window is skinned")
eq(T.letters.OpenMailFrame, nil, "its letter isn't built")
eq(children(OpenMailFrame), before + 1, "  and no orphan pane is left (only the glass panel was added)")
eq(OpenStationeryBackgroundLeft:GetAlpha(), 1, "  its stationery stays")
check(OpenMailBodyText:GetTextColor("P") < 0.5, "  and its text stays dark")
check(GM.failures["skin letter OpenMailFrame"] ~= nil, "the failure is recorded")
GM.Settings.SetSkin("smoked")
eq(OpenStationeryBackgroundLeft:GetAlpha(), 1, "switching looks leaves it alone")
check(T.letters.MailFrame ~= nil, "the send letter is still dark glass")

done("test_letter_fail")
