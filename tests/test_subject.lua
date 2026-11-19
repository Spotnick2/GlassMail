-- Subject.lua: S2, the subject filled from the first item or the gold
-- (PLAN.md, "S2: the subject", #59). The stubs' SendMailFrame_Update is
-- Blizzard's subject part as on 70959: its own item fill only while COD is
-- enabled.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GM = loadAddon()
local Subject = GM.Subject
local box = SendMailSubjectEditBox

local function attach(slot, id, count, name)
    WoW.draft.items = WoW.draft.items or {}
    WoW.draft.items[slot] = { id = id, count = count, name = name }
    SendMailFrame_Update()
end
local function detach(slot)
    WoW.draft.items[slot] = nil
    SendMailFrame_Update()
end
local function clear()
    WoW.draft = {}
    WoW.codEnabled = false
    SendMailRadioButton_OnClick(1)
    WoW.setMoney(0)
    box:SetText("")
    SendMailFrame_Update()
    GM.Settings.SetSubjectFill(true)
end

-- Hooks, never replacements ------------------------------------------------------
eq(WoW.hooked[_G].SendMailFrame_Update, 1, "SendMailFrame_Update is post-hooked")
eq(WoW.hooked[_G].SendMailRadioButton_OnClick, 1, "SendMailRadioButton_OnClick is post-hooked")
local before = WoW.sendUpdates or 0
SendMailFrame_Update()
eq(WoW.sendUpdates, before + 1, "  Blizzard's own update still runs")

-- Items (COD off: Blizzard's fill doesn't run) -------------------------------------
clear()
attach(1, 2589, 5, "Linen Cloth")
eq(box:GetText(), "Linen Cloth (5)", "an item fills the empty subject, with its count")
attach(2, 2592, 1, "Wool Cloth")
eq(box:GetText(), "Linen Cloth (5)", "  a second item changes nothing")
detach(1)
eq(box:GetText(), "Wool Cloth", "  the first gone: the next one's name, no count for one")
detach(2)
eq(box:GetText(), "", "  every item gone: cleared")
eq(Subject._test.Ours(), nil, "  and forgotten")

clear()
attach(3, 2589, 1, "Linen Cloth")
eq(box:GetText(), "Linen Cloth", "the first slot with an item, wherever it is")

clear()
box:SetText("For the bank")
attach(1, 2589, 5, "Linen Cloth")
eq(box:GetText(), "For the bank", "a typed subject is never touched")
detach(1)
eq(box:GetText(), "For the bank", "  and stays after the item goes")

clear()
attach(1, 2589, 5, "Linen Cloth")
box:SetText("Linen for you")
attach(2, 2592, 1, "Wool Cloth")
detach(1)
eq(box:GetText(), "Linen for you", "our text edited by the player is theirs")
detach(2)
eq(box:GetText(), "Linen for you", "  kept when the items go")

-- A key typed makes it the player's, even back to our text (Codex, round 1).
local function typeIn(text)
    box._text = text
    box:GetScript("OnTextChanged")(box, true)
end
clear()
attach(1, 2589, 5, "Linen Cloth")
typeIn("Linen Cloth (5)!")
typeIn("Linen Cloth (5)")
detach(1)
eq(box:GetText(), "Linen Cloth (5)", "typed back to our text: still the player's")
typeIn("")
attach(1, 2589, 2, "Linen Cloth")
eq(box:GetText(), "Linen Cloth (2)", "  emptied by the player: filled again")

-- The box keeps 64 letters (MailFrame.xml:681): ours is what it kept.
clear()
local realSetText = box.SetText
rawset(box, "SetText", function(self, t) realSetText(self, t:sub(1, 64)) end)
local long = string.rep("x", 70)
attach(1, 2589, 1, long)
eq(box:GetText(), long:sub(1, 64), "a long title, cut by the box")
local writes = 0
local cutSetText = box.SetText
rawset(box, "SetText", function(self, t) writes = writes + 1; cutSetText(self, t) end)
SendMailFrame_Update()
eq(writes, 0, "  the same title again: not rewritten")
detach(1)
eq(box:GetText(), "", "  its item gone: cleared, still ours")
rawset(box, "SetText", nil)

clear()
attach(1, 2589, 1, "")
eq(box:GetText(), "", "an uncached item (empty name) gives nothing")
attach(2, 2592, 2, "Wool Cloth")
eq(box:GetText(), "Wool Cloth (2)", "  the next named one does")

-- Secrets: our refresh alone (the stubbed Blizzard update would touch them first).
clear()
WoW.draft.items = { [1] = { id = 2589, count = 1, name = WoW.Secret("name") } }
Subject.Refresh()
eq(box:GetText(), "", "a secret name: nothing")
WoW.draft.items = { [1] = { id = 2589, count = WoW.Secret("count"), name = "Linen Cloth" } }
Subject.Refresh()
eq(box:GetText(), "", "a secret count: nothing")
check(GM.failures.subject == nil, "  neither throws")

clear()
attach(1, 2589, 1, "Odd|cffname")
eq(box:GetText(), "", "a | in the name: nothing")

-- COD enabled: items are Blizzard's -----------------------------------------------
clear()
WoW.codEnabled = true
attach(1, 2589, 5, "Linen Cloth")
eq(box:GetText(), "Linen Cloth (5)", "COD enabled: Blizzard's own fill names it")
eq(Subject._test.Ours(), nil, "  not ours")
detach(1)
eq(box:GetText(), "", "  Blizzard clears its own")

-- Gold -------------------------------------------------------------------------------
clear()
WoW.setMoney(125000)
eq(box:GetText(), "12 Gold, 50 Silver", "gold fills the empty subject, in the client's words")
WoW.setMoney(30000)
eq(box:GetText(), "3 Gold", "  follows the amount")
WoW.setMoney(0)
eq(box:GetText(), "", "  cleared at 0")

clear()
box:SetText("Rent")
WoW.setMoney(30000)
eq(box:GetText(), "Rent", "a typed subject stays with gold")

clear()
SendMailRadioButton_OnClick(2)
WoW.setMoney(30000)
eq(box:GetText(), "", "COD checked: the amount is a price, no subject")
SendMailRadioButton_OnClick(1)
eq(box:GetText(), "3 Gold", "  Send Money again: the gold")
SendMailRadioButton_OnClick(2)
eq(box:GetText(), "", "  COD again: ours cleared")

-- Items beat gold ----------------------------------------------------------------------
clear()
WoW.setMoney(30000)
attach(1, 2589, 5, "Linen Cloth")
eq(box:GetText(), "Linen Cloth (5)", "gold, then an item: the item names it")
detach(1)
eq(box:GetText(), "3 Gold", "  the item gone: the gold again")

clear()
WoW.codEnabled = true
WoW.setMoney(30000)
eq(box:GetText(), "3 Gold", "COD enabled: gold still filled")

-- The send's reset (MailFrame.lua:1422-1428): the subject cleared, the update
-- (which still sees the gold and fills it), then the coin boxes one by one.
clear()
attach(1, 2589, 5, "Linen Cloth")
WoW.setMoney(30000)
WoW.draft = {}
SendMailFrame_Reset()
eq(box:GetText(), "", "after a send's reset: empty")
eq(Subject._test.Ours(), nil, "  nothing remembered")
clear()
WoW.setMoney(125003)
eq(box:GetText(), "12 Gold, 50 Silver, 3 Copper", "every coin box set in turn: the whole amount")
SendMailFrame_Reset()
eq(box:GetText(), "", "a gold-only draft's reset: empty after the coin boxes clear")
eq(Subject._test.Ours(), nil, "  nothing remembered")

-- The setting ---------------------------------------------------------------------------
clear()
GM.Settings.SetSubjectFill(false)
attach(1, 2589, 5, "Linen Cloth")
WoW.setMoney(30000)
eq(box:GetText(), "", "off: nothing filled")
GM.Settings.SetSubjectFill(true)
SendMailFrame_Update()
eq(box:GetText(), "Linen Cloth (5)", "  on again: the next update fills")
GM.Settings.SetSubjectFill(false)
detach(1)
eq(box:GetText(), "Linen Cloth (5)", "  turned off: what was written stays")

eq(GM.DEFAULTS.subjectFill, true, "subjectFill is on by default")
GlassMailDB.subjectFill = "yes"
GM._test.ensureDefaults()
eq(rawget(GlassMailDB, "subjectFill"), nil, "a non-boolean subjectFill is dropped at load")
SlashCmdList.GLASSMAIL("subject off")
eq(GM.db.subjectFill, false, "/gmail subject off")
SlashCmdList.GLASSMAIL("subject on")
eq(GM.db.subjectFill, true, "/gmail subject on")
check(table.concat(GM.HelpLines(), " "):find("/gmail subject on/off", 1, true) ~= nil, "  /gmail help lists it")
local O = GM.Options._test
O.panel:Show()
eq(O.subjectFill:GetChecked(), true, "the options page's checkbox shows it on")
O.subjectFill:SetChecked(false)
O.subjectFill:GetScript("OnClick")(O.subjectFill)
eq(GM.db.subjectFill, false, "  a click turns it off")

-- A failure is recorded, not thrown --------------------------------------------------------
clear()
local real = C_Mail.IsCODEnabled
C_Mail.IsCODEnabled = function() error("boom") end
SendMailFrame_Update()
check(GM.failures.subject ~= nil, "a failing refresh is recorded under 'subject'")
C_Mail.IsCODEnabled = real

done("test_subject")
