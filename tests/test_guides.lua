-- Skin.lua's inbox guides: under glass, a slot behind each row's item button,
-- a line under every row but the last, and an empty inbox's envelope with
-- "No mail"; the inboxGuides setting turns them off, and "stock" never shows them.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GM = loadAddon()
local T = GM._test.skin
local pane, guides = T.pane(), T.guides()
check(guides ~= nil, "the guides are built")
eq(GM.failures["skin guides"], nil, "  without a failure")
eq(GM.DEFAULTS.inboxGuides, true, "  and on by default")

-- Built ---------------------------------------------------------------------------
eq(#guides.slots, 7, "a slot per row")
eq(#guides.lines, 6, "a line under every row but the last")
for i, slot in ipairs(guides.slots) do
    eq(slot:GetParent(), pane.frame, "slot " .. i .. ": on the pane's frame, under the rows")
    local _, relativeTo = slot:GetPoint(1)
    eq(relativeTo, _G["MailItem" .. i .. "Button"], "  behind its row's item button")
    check(slot._masks and #slot._masks == 1, "  rounded")
end
for i, line in ipairs(guides.lines) do
    local _, relativeTo = line:GetPoint(1)
    eq(relativeTo, _G["MailItem" .. i], "line " .. i .. ": under its row")
    eq(line:GetParent(), pane.frame, "  on the pane's frame")
end
eq(guides.empty.text:GetText(), "No mail", "the empty inbox's line")
eq(guides.empty.icon._file, GM.Skin.PORTRAITS.MailFrame, "  under our envelope")

-- Shown ---------------------------------------------------------------------------
local function shown(list)
    for _, t in ipairs(list) do if not t:IsShown() then return false end end
    return true
end
local function hidden(list)
    for _, t in ipairs(list) do if t:IsShown() then return false end end
    return true
end
local function emptyShown() return guides.empty.icon:IsShown() and guides.empty.text:IsShown() end
local function emptyHidden() return not guides.empty.icon:IsShown() and not guides.empty.text:IsShown() end

WoW.inbox = {}
InboxFrame:Update()
check(shown(guides.slots) and shown(guides.lines), "clear glass: the slots and lines show")
local c = GM.Skin.GUIDES
eq(guides.slots[1]._color[4], c.slot[4], "  in the slot colour")
eq(guides.lines[1]._color[4], c.line[4], "  and the line colour")
check(emptyShown(), "an empty inbox: the envelope and \"No mail\"")
eq(guides.empty.icon:GetAlpha(), c.envelope, "  the envelope faded")

WoW.inbox = { { sender = "A", subject = "hi" } }
InboxFrame:Update()
check(emptyHidden(), "a mail: no \"No mail\" (Blizzard's update repaints it)")
check(shown(guides.slots), "  the slots stay, under the mail's icon")
WoW.inbox, WoW.inboxTotal = {}, 3
InboxFrame:Update()
check(emptyHidden(), "none loaded but some on the server: not empty")
WoW.inboxTotal = nil
local real = GetInboxNumItems
GetInboxNumItems = function() return WoW.Secret(0), WoW.Secret(0) end
GM.Skin.Refresh()   -- not through InboxFrame:Update: the other hooks on it aren't this test's
check(emptyHidden(), "a secret count: not read as empty")
GetInboxNumItems = real
InboxFrame:Update()
check(emptyShown(), "empty again")

-- Off, and stock -------------------------------------------------------------------
check(GM.Settings.SetInboxGuides(false), "the setting turns off")
eq(GlassMailDB.inboxGuides, false, "  and is saved")
check(hidden(guides.slots) and hidden(guides.lines) and emptyHidden(), "  everything hidden, live")
InboxFrame:Update()
check(emptyHidden(), "  and an inbox update doesn't bring \"No mail\" back")
GM.Settings.SetInboxGuides(true)
check(shown(guides.slots) and emptyShown(), "on again: back, live")
GM.Settings.SetSkin("stock")
check(hidden(guides.slots) and hidden(guides.lines) and emptyHidden(), "stock: none of it (Blizzard's own art is back)")
InboxFrame:Update()
check(emptyHidden(), "  not even after an inbox update")
GM.Settings.SetSkin("smoked")
check(shown(guides.slots) and shown(guides.lines) and emptyShown(), "smoked: all back")

-- /gmail guides, the options page, a bad saved value -------------------------------
SlashCmdList.GLASSMAIL("guides off")
eq(GM.db.inboxGuides, false, "/gmail guides off")
check(hidden(guides.slots), "  hides them")
SlashCmdList.GLASSMAIL("guides on")
eq(GM.db.inboxGuides, true, "/gmail guides on")
newChat()
SlashCmdList.GLASSMAIL("guides maybe")
check(chatHas("/gmail guides on/off"), "a bad argument prints the usage")
check(table.concat(GM.HelpLines(), " "):find("/gmail guides on/off", 1, true) ~= nil, "/gmail help lists it")
local O = GM.Options._test
O.panel:Show()
check(O.guides:GetChecked(), "the options page's checkbox follows the setting")
O.guides:SetChecked(false)
O.guides._scripts.OnClick(O.guides)
eq(GM.db.inboxGuides, false, "  and a click sets it")
check(hidden(guides.slots), "  live")

GlassMailDB.inboxGuides = "yes"
GM._test.ensureDefaults()
eq(rawget(GlassMailDB, "inboxGuides"), nil, "a non-boolean inboxGuides is dropped at load")
GlassMailDB.inboxGuides = true
GM._test.ensureDefaults()
eq(rawget(GlassMailDB, "inboxGuides"), nil, "  and one equal to the default")

-- Starting again builds nothing more.
WoW.fire("ADDON_LOADED", "Blizzard_MailFrame")
eq(T.guides(), guides, "a second start builds no second set")

done("test_guides")
