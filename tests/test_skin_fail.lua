-- A window whose regions can't be read is left untouched: no half-built glass
-- panel under it, the failure recorded, the other window still skinned.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local children = 0
for _, w in ipairs(WoW.frames) do if w._parent == MailFrame then children = children + 1 end end
SendMailFrame.GetRegions = function() error("regions unavailable") end

local GM = loadAddon()
check(not GM.Skin.IsSkinned(MailFrame), "MailFrame is not skinned")
local after = 0
for _, w in ipairs(WoW.frames) do if w._parent == MailFrame then after = after + 1 end end
eq(after, children, "no orphan panel is left under MailFrame")
check(GM.failures["skin MailFrame"] ~= nil, "the failure is recorded for /gmail failures")
check(GM.Skin.IsSkinned(OpenMailFrame), "the open letter is still skinned")
GM.Settings.SetSkin("stock")
GM.Settings.SetSkin("smoked")
eq(MailFrame.Bg:GetAlpha(), 1, "switching looks leaves the unskinned window's art alone")
-- Its letter stays Blizzard's: parchment and dark text, no pane over them.
local T = GM._test.skin
eq(T.letters.MailFrame, nil, "no letter pane in an unskinned window")
eq(T.sections.MailFrame, nil, "  nor sections")
eq(T.sections.footer, nil, "  nor a footer")
check(T.sections.OpenMailFrame ~= nil, "the open letter's window has its section")
eq(SendStationeryBackgroundLeft:GetAlpha(), 1, "  its stationery stays")
local r = SendMailBodyEditBox:GetTextColor()
check(r < 0.5, "  and its text stays dark")
check(T.letters.OpenMailFrame ~= nil, "the open letter, in a skinned window, is dark glass")
eq(OpenStationeryBackgroundLeft:GetAlpha(), 0, "  its stationery faded")

done("test_skin_fail")
