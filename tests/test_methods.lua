-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- exercises the addon, then Kit.checkMethods checks each recorded
-- "Type:Method" pair against the pinned build's widget methods. It fails,
-- never skips, when the data is missing or nothing was recorded.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Exercise everything so every method is recorded.
local GM = loadAddon()
WoW.fireAllRegistered()
WoW.tick()
GM.Options._test.panel:Show()
for _, cmd in ipairs({ "", "failures", "version", "glass off", "glass on", "options" }) do
    SlashCmdList.GLASSMAIL(cmd)
end

-- The window (Window.lua, built on first open): a row of each kind, an icon's
-- tooltip, the forget button's, the search, the scroll.
local Store = GM.Store
Store.AddSent({ kind = "send", day = Store.PlayDay(), at = time(), from = WoW.playerGUID, to = "Kaleid Sumner",
    state = "sent", items = { { id = 2589, count = 5 } } })
Store.AddTrash({ at = time(), from = WoW.playerGUID, expires = time() + 86400, sender = "Kaleid Sumner" })
Store.SetSnapshot(WoW.playerGUID, { at = time(), loaded = 1, total = 1, complete = true,
    mails = { { expires = time() + 86400, type = "player", money = 5 } } })
SlashCmdList.GLASSMAIL("mail")
local ui = GM._test.window.ui()
local row = ui.rows[1]
row.icons[1]:GetScript("OnEnter")(row.icons[1])
row.forget:GetScript("OnEnter")(row.forget)
row.forget:GetScript("OnLeave")(row.forget)
GM.Window.mailButton:GetScript("OnEnter")(GM.Window.mailButton)
for _, key in ipairs(GM.Window.FOLDERS) do ui.folders[key]:GetScript("OnClick")(ui.folders[key]) end
ui.rows[1]:GetScript("OnClick")(ui.rows[1])
ui.search:SetText("kaleid")
ui.list:GetScript("OnMouseWheel")(ui.list, -1)
GM.Settings.SetSkin("smoked")

-- The address book (Address.lua): its button's tooltip, a pick, and the fill
-- on the send tab.
local A = GM.Address
A.button:GetScript("OnEnter")(A.button)
A.button:GetScript("OnLeave")(A.button)
Store.AddRecent("Kaleid Sumner")
Store.SetLastTo(WoW.playerGUID, "kaleid sumner")
A.button:GetScript("OnClick")(A.button)
local picker = GM._test.address.ui()
picker.search:SetText("kal")
picker.list:GetScript("OnMouseWheel")(picker.list, -1)
picker.scroll:SetValue(0)
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
A.button:GetScript("OnClick")(A.button)
picker.rows[2]:GetScript("OnClick")(picker.rows[2])
SendMailNameEditBox:SetText("")
MailFrame:Show()
MailFrameTab_OnClick(MailFrameTab2)

-- The item grid (Bag.lua): the toggle, a button's tooltip, a click, the Stop.
local Bag = GM.Bag
WoW.inbox = { { sender = "A", subject = "ore", items = { [1] = { id = 2770, count = 5 } } } }
InboxFrame:Show()
Bag.toggle:GetScript("OnEnter")(Bag.toggle)
Bag.toggle:GetScript("OnClick")(Bag.toggle)
local bagUI = GM._test.bag.ui()
bagUI.buttons[1]:GetScript("OnEnter")(bagUI.buttons[1])
bagUI.buttons[1]:GetScript("OnClick")(bagUI.buttons[1])
bagUI.stop:GetScript("OnClick")(bagUI.stop)
bagUI.content:GetScript("OnMouseWheel")(bagUI.content, -1)

local recorded = Kit.checkMethods({ allow = {
    ["GameTooltip:SetItemByID"] = "a Lua accessor of Blizzard's tooltip mixin, over C_TooltipInfo.GetItemByID "
        .. "(Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:525; QuestInfo.lua:1285 calls it)",
} })
-- What loading plus the exercise records today (the window included), rounded down: the exercise
-- can't quietly shrink.
check(recorded >= 120, "the exercise reached the windows (" .. recorded .. " recorded)")
done("test_methods")
