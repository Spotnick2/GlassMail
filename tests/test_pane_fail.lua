-- A pane that fails half-way is hidden, not left showing, and the build isn't
-- retried on every later ADDON_LOADED (each try would leave another frame).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local made = {}
local createFrame = CreateFrame
CreateFrame = function(kind, name, parent, ...)
    local f = createFrame(kind, name, parent, ...)
    if parent == SendMailFrame and name == nil then
        made[#made + 1] = f
        rawset(f, "CreateTexture", function() error("no textures") end)
    end
    return f
end
local GM = loadAddon()
local T = GM._test.skin
eq(T.letters.MailFrame, nil, "the send letter isn't built")
check(GM.failures["skin letter MailFrame"] ~= nil, "  and the failure is recorded")
eq(#made, 2, "two pane frames were made (the letter's and the footer's)")
check(not made[1]:IsShown() and not made[2]:IsShown(), "  and both are hidden")
eq(T.sections.footer, nil, "the footer isn't built")
check(GM.failures["skin sections"] ~= nil, "  and its failure is recorded")
WoW.fire("ADDON_LOADED", "Blizzard_MailFrame")
eq(#made, 2, "a later start doesn't try again")
check(T.letters.OpenMailFrame ~= nil, "the open letter is still built")

done("test_pane_fail")
