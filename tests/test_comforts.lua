-- X3 (Comforts.lua): the gold collected this visit, the trade block, the
-- new-mail alert; and their settings.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.bags = { [0] = { size = 16, family = 0, items = {} } }
WoW.now = 100
WoW.inbox = {}
local GM = loadAddon()
local OA = GM._test.openAll
local function step(dt) WoW.now = WoW.now + (dt or 0.2); WoW.tick(dt or 0.2) end
local function last() return WoW.mailCalls[#WoW.mailCalls] end
local function click(b) b._scripts.OnClick(b, "LeftButton") end
local function show() WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17); WoW.fire("MAIL_SHOW") end
local function hide() WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17) end
local function blocked() return WoW.cvars.blockTrades end
local function chatLine(pattern)
    for _, line in ipairs(newChat()) do if line:find(pattern) then return line end end
end
local function combat(on)
    -- As on the client: InCombatLockdown() is still false inside REGEN_DISABLED.
    if on then WoW.fire("PLAYER_REGEN_DISABLED"); WoW.combat = true
    else WoW.combat = false; WoW.fire("PLAYER_REGEN_ENABLED") end
end
local function openAll()   -- one Open All run over the inbox, every take served
    click(OA.button())
    for _ = 1, 10 do
        step()
        local c = last()
        if c and not c.served then c.served = true; WoW.serve(c) end
    end
    step(1)
end

-- Gold collected: what Ops confirmed, over every run of the visit, said once.
GlassMailDB.tradeBlock = false   -- the trade block has its own section
show()
WoW.inbox = { { sender = "Kaleid Sumner", subject = "one", money = 250 } }
WoW.fire("MAIL_INBOX_UPDATE")
openAll()
table.insert(WoW.inbox, { sender = "Cowruzo Kashmere", subject = "two", money = 500 })
WoW.fire("MAIL_INBOX_UPDATE")
openAll()
eq(GM.Ops.Running(), false, "two Open All runs, both done")
newChat()
hide()
eq(chatLine("Collected"), "|cff7fd4ffGlassMail|r Collected 750c this visit.", "closing: the sum of both runs, once")
hide()
eq(chatLine("Collected"), nil, "  a second HIDE (logout) says nothing more")
show()
hide()
eq(chatLine("Collected"), nil, "a visit that took nothing says nothing")
show()
WoW.inbox = { { sender = "Kaleid Sumner", subject = "three", money = 100 } }
WoW.fire("MAIL_INBOX_UPDATE")
click(OA.button())
step()
eq(last()[1], "TakeInboxMoney", "a take sent")
step(6)
eq(GM.Ops.Running(), false, "  never confirmed: the run stops as uncertain")
hide()
eq(chatLine("Collected"), nil, "  and it isn't counted")
WoW.inbox[1].money = 100
WoW.fire("MAIL_INBOX_UPDATE")
openAll()   -- money taken with no visit (no SHOW): not this visit's
show()
hide()
eq(chatLine("Collected"), nil, "a new visit starts at 0")
WoW.inbox = {}
GlassMailDB.tradeBlock = nil

-- Trade block: the CVar while the mailbox is open; only our own block undone.
eq(GM.db.tradeBlock, true, "on by default")
show()
eq(blocked(), "1", "the mailbox opens: trades blocked")
eq(GlassMailCharDB.tradeBlocked, true, "  the claim saved, for a session that ends uncleanly")
hide()
eq(blocked(), "0", "it closes: unblocked")
eq(GlassMailCharDB.tradeBlocked, nil, "  the claim cleared")
WoW.cvars.blockTrades = "1"   -- the player blocks trades themselves
show()
hide()
eq(blocked(), "1", "the player's own block is never undone")
WoW.cvars.blockTrades = "0"
show()
WoW.fire("PLAYER_LEAVING_WORLD")
eq(blocked(), "0", "leaving the world unblocks")
hide()

-- Combat: nothing written in combat; a pending change waits for it to end.
combat(true)
show()
eq(blocked(), "0", "opened in combat: nothing written")
combat(false)
eq(blocked(), "1", "  blocked when combat ends")
combat(true)
hide()
eq(blocked(), "1", "closed in combat: still blocked")
combat(false)
eq(blocked(), "0", "  unblocked when combat ends")
show()
combat(true)
hide()
show()
combat(false)
eq(blocked(), "1", "closed in combat, reopened before it ended: still blocked")
hide()
eq(blocked(), "0", "  until the mailbox closes")

-- A change we didn't make ends our claim; an "off" lasts the visit.
show()
SetCVar("blockTrades", "0")   -- the player, in Settings > Social
eq(blocked(), "0", "turned off during the visit: left off")
combat(true); combat(false)
eq(blocked(), "0", "  not re-blocked after combat")
eq(GlassMailCharDB.tradeBlocked, nil, "  the claim dropped")
hide()
eq(blocked(), "0", "  nor at close")
show()
eq(blocked(), "1", "the next visit blocks again")
SetCVar("blockTrades", "0")
SetCVar("blockTrades", "1")   -- off, then on again: the player's block now
hide()
eq(blocked(), "1", "off then on during the visit: their block is kept")
WoW.cvars.blockTrades = "0"
show()
SetCVar("someOtherSetting", "1")
hide()
eq(blocked(), "0", "another CVar changing doesn't end our claim")

-- The setting.
SlashCmdList.GLASSMAIL("tradeblock off")
eq(GM.db.tradeBlock, false, "/gmail tradeblock off")
show()
eq(blocked(), "0", "  off: nothing blocked")
SetCVar("someOtherSetting", "2")
SlashCmdList.GLASSMAIL("tradeblock on")
eq(blocked(), "1", "turned on at the mailbox: blocked at once")
GM.Settings.SetTradeBlock(false)
eq(blocked(), "0", "turned off at the mailbox: unblocked at once")
GM.Settings.SetTradeBlock(true)
eq(blocked(), "1", "  and back on: blocked again (our own writes aren't someone else's)")
hide()
eq(blocked(), "0", "closed")
WoW.cvarFail = true
show()
eq(blocked(), "0", "a refused write: nothing blocked")
eq(GM._test.comforts.owned(), false, "  and nothing claimed")
check(GM.failures["trade block"] ~= nil, "  recorded in /gmail failures")
hide()
WoW.cvarFail = nil
GM.failures["trade block"] = nil
show()
eq(blocked(), "1", "blocked")
WoW.cvarRefuse = true   -- SetCVar returns false, no error
hide()
eq(blocked(), "1", "the restore refused at close: still blocked")
eq(GM._test.comforts.owned(), true, "  the claim kept")
eq(GlassMailCharDB.tradeBlocked, true, "  and its saved flag, for the next login")
check(GM.failures["trade block"] ~= nil, "  recorded")
WoW.cvarRefuse = nil
combat(true); combat(false)
eq(blocked(), "0", "the next change retries: unblocked")
eq(GlassMailCharDB.tradeBlocked, nil, "  claim cleared")
WoW.cvarRefuse = true
show()
eq(GM._test.comforts.owned(), false, "a refused block claims nothing")
WoW.cvarRefuse = nil
hide()

-- New-mail alert: when the latest senders change, away from the mailbox.
newChat()
WoW.newMail, WoW.senders = true, {}
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), nil, "the first of the login pair has no names yet: nothing")
WoW.senders = { "Cowruzo Kashmere" }
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), "|cff7fd4ffGlassMail|r New mail from Cowruzo Kashmere.", "the second has them: one line")
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), nil, "  the same list again: nothing")
WoW.senders = { "Kaleid Sumner", "Cowruzo Kashmere" }
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), "|cff7fd4ffGlassMail|r New mail from Kaleid Sumner, Cowruzo Kashmere.", "a new sender: announced")
show()
WoW.senders = { "Tarthosuk", "Kaleid Sumner", "Cowruzo Kashmere" }
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), nil, "at the mailbox: nothing")
hide()
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), nil, "  nor after it, for mail seen there")
show()
WoW.newMail = false   -- everything read
WoW.fire("UPDATE_PENDING_MAIL")
hide()
WoW.newMail = true
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), "|cff7fd4ffGlassMail|r New mail from Tarthosuk, Kaleid Sumner, Cowruzo Kashmere.",
    "all read, then new mail from the same senders: announced")
WoW.newMail = false
WoW.fire("UPDATE_PENDING_MAIL")
WoW.newMail, WoW.senders = true, { WoW.Secret("sender"), "Kaleid Sumner" }
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), "|cff7fd4ffGlassMail|r New mail from Kaleid Sumner.", "a secret name is skipped")
WoW.newMail = WoW.Secret("hasNewMail")
WoW.fire("UPDATE_PENDING_MAIL")
WoW.newMail = true
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), "|cff7fd4ffGlassMail|r New mail from Kaleid Sumner.", "a secret HasNewMail: as none (no error)")
SlashCmdList.GLASSMAIL("alert off")
eq(GM.db.newMailAlert, false, "/gmail alert off")
WoW.senders = { "Tarthosuk" }
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), nil, "  off: nothing")
SlashCmdList.GLASSMAIL("alert on")
WoW.fire("UPDATE_PENDING_MAIL")
eq(chatLine("New mail"), nil, "  back on: mail it already saw isn't announced late")

-- The options page: two checkboxes, re-read on every show.
local O = GM.Options._test
O.panel:Show()
check(O.trade:GetChecked() and O.alert:GetChecked(), "both checkboxes show on")
O.trade:SetChecked(false)
click(O.trade)
eq(GM.db.tradeBlock, false, "a click turns the trade block off")
GM.db.newMailAlert = false
O.panel:Hide(); O.panel:Show()
eq(O.alert:GetChecked(), false, "  the page re-reads the settings on show")
check(table.concat(GM.HelpLines(), "\n"):find("/gmail tradeblock on/off", 1, true) ~= nil, "/gmail help lists them")

done("test_comforts")
