-- Address.lua: S1, the picker and the last-recipient fill (PLAN.md, "S1: the
-- address book picker", "S1: the last recipient", "The address PR in
-- detail"), with Core/Sent.lua's lastTo.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.today = "2026-11-06"
local GM = loadAddon()
local Store, Address = GM.Store, GM.Address
local db = GlassMailDB
local ME, ALT = WoW.playerGUID, "Player-1-BBB"
local box = SendMailNameEditBox

local function frame() WoW.advance(0.01) end
local function lastTo(guid) return db.chars[guid or ME] and db.chars[guid or ME].lastTo end
local function openMailbox() MailFrame:Show(); MailFrameTab_OnClick(nil, 1) end
local function closeMailbox()
    MailFrame:Hide()
    box:SetText("")   -- MailMixin:OnHide (MailFrame.lua:53)
end
local function tab(id) MailFrameTab_OnClick(_G["MailFrameTab" .. id]) end
local function send(to, opts)
    opts = opts or {}
    WoW.draft = {}
    WoW.confirmNext = opts.stranger
    SendMail(to, "hi", "")
end
local function success() WoW.fire("MAIL_SEND_SUCCESS") end
-- A send to `to` that Sent attributes, the box then reset by Blizzard.
local function sendTo(to)
    box:SetText(to)
    send(to)
    WoW.advance(0.5)
    success()
end

-- lastTo: set by an attributed send ---------------------------------------------
openMailbox()
tab(2)
eq(box:GetText(), "", "no lastTo yet: the send tab opens empty")
sendTo("Kaleid Sumner")
eq(lastTo(), "kaleid sumner", "an attributed send sets this character's lastTo")
eq(box:GetText(), "", "  the box is reset by Blizzard's handler")
frame()
eq(box:GetText(), "Kaleid Sumner", "  and refilled a frame later with that recipient")
eq(box._highlighted, "Kaleid Sumner", "  highlighted, so typing replaces it")

-- Registry.Touch keeps it (the 10-minute tick rewrites the record).
Store.Tick()
eq(lastTo(), "kaleid sumner", "the clock's tick keeps lastTo")

-- The tab: fills only when empty, on tab 2, when on -----------------------------
tab(1)
box:SetText("")
tab(2)
eq(box:GetText(), "Kaleid Sumner", "tab 2 fills the empty box")
box:SetText("Typed Name")
tab(1); tab(2)
eq(box:GetText(), "Typed Name", "  never over typed text")
box:SetText("")
tab(1)
eq(box:GetText(), "", "  not on tab 1")
GM.Settings.SetAutofill(false)
tab(2)
eq(box:GetText(), "", "  not when autofill is off")
GM.Settings.SetAutofill(true)
tab(1)
MailFrameTab_OnClick(nil, 2)
eq(box:GetText(), "Kaleid Sumner", "  the tab ID passed directly counts too")

-- Reply: the sender wins.
tab(1)
box:SetText("")
WoW.reply("Some Sender")
eq(box:GetText(), "Some Sender", "Reply's sender wins over the fill")
-- A reply's success shows the inbox: nothing filled.
send("Some Sender")
WoW.advance(0.5)
success()
frame()
check(not SendMailFrame:IsVisible(), "a reply's success goes back to the inbox")
eq(box:GetText(), "", "  and fills nothing")
eq(lastTo(), "some sender", "  (its recipient is the new lastTo)")
-- Back to Kaleid.
tab(2)
eq(box:GetText(), "Some Sender", "reopening the tab offers it")
box:SetText("")
sendTo("Kaleid Sumner")
frame()

-- lastTo without its recent: nothing.
db.recents["kaleid sumner"] = nil
box:SetText("")
tab(1); tab(2)
eq(box:GetText(), "", "lastTo without its recent fills nothing (it aged out)")
db.recents["kaleid sumner"] = { name = "Kaleid Sumner", day = db.playDay }

-- Another character's lastTo is never used.
Store.SetChar(ALT, { name = "Kaleid Sumner", lastPlayDay = db.playDay })
Store.SetLastTo(ALT, "kaleid sumner")
Store.SetLastTo(ME, nil)
tab(1); tab(2)
eq(box:GetText(), "", "another character's lastTo is never used")
Store.SetLastTo(ME, "kaleid sumner")
-- On that other character, its own is.
db.recents["bank alt"] = { name = "Bank Alt", day = db.playDay }
Store.SetLastTo(ALT, "bank alt")
WoW.playerGUID = ALT
box:SetText("")
tab(1); tab(2)
eq(box:GetText(), "Bank Alt", "  on that character, its own is")
WoW.playerGUID = ME
box:SetText("")
tab(1); tab(2)
eq(box:GetText(), "Kaleid Sumner", "  and back here, ours")

-- A return and a cancelled send don't move it ------------------------------------
tab(1); tab(2)
GM.Sent.AddReturn({ sender = "Returned To", subject = "x", money = 0, cod = 0 }, {})
eq(lastTo(), "kaleid sumner", "a return doesn't move lastTo")
box:SetText("Stranger Name")
send("Stranger Name", { stranger = true })
SendMailFrame_EnableSendMailButton()   -- the dialog closed: cancelled, no success
WoW.advance(130)
eq(db.sent[#db.sent].state, "unconfirmed", "a cancelled stranger send ends unconfirmed")
eq(lastTo(), "kaleid sumner", "  and leaves lastTo as it was")

-- An unattributed success clears it ------------------------------------------------
-- A sent, a stranger cancelled, B inside that window: B's success is ambiguous.
box:SetText("")
send("Stranger Name", { stranger = true })
SendMailFrame_EnableSendMailButton()
WoW.advance(1)
send("Bank Alt")
WoW.advance(0.5)
success()
eq(lastTo(), nil, "an ambiguous success clears lastTo")
frame()
eq(box:GetText(), "", "  the box stays empty after it")
tab(1); tab(2)
eq(box:GetText(), "", "  and reopening the send tab fills nothing")
WoW.advance(130)
-- A success with no candidate at all (a send before a /reload).
sendTo("Kaleid Sumner")
eq(lastTo(), "kaleid sumner", "the next attributed success sets it again")
frame()
success()
eq(lastTo(), nil, "a success with no candidate clears it too")
Store.SetLastTo(ME, "kaleid sumner")
Store.SetChar(ALT, { name = "Kaleid Sumner", lastPlayDay = db.playDay })
Store.SetLastTo(ALT, "bank alt")
success()
eq(lastTo(ALT), "bank alt", "  and never another character's")

-- Failures inside Sent's success handling leave it cleared ---------------------------
Store.SetLastTo(ME, "kaleid sumner")
local addSent = Store.AddSent
rawset(Store, "AddSent", function() error("boom") end)
box:SetText("")
sendTo("Kaleid Sumner")
rawset(Store, "AddSent", addSent)
check(GM.failures["sent MAIL_SEND_SUCCESS"] ~= nil, "an error inside Sent's success handling is recorded")
eq(lastTo(), nil, "  and lastTo is cleared before it")
frame()
eq(box:GetText(), "", "  nothing is filled")
tab(1); tab(2)
eq(box:GetText(), "", "  nor on reopening the send tab")
-- One candidate whose GUID wasn't readable at capture.
Store.SetLastTo(ME, "kaleid sumner")
WoW.playerGUID = WoW.Secret("guid")
box:SetText("Kaleid Sumner")
send("Kaleid Sumner")
WoW.playerGUID = ME
WoW.advance(0.5)
success()
eq(lastTo(), nil, "a send captured without a GUID leaves lastTo cleared")
-- One whose recipient wasn't.
Store.SetLastTo(ME, "kaleid sumner")
send(WoW.Secret("to"))
WoW.advance(0.5)
success()
eq(lastTo(), nil, "  one with a secret recipient too")
frame()
-- An attributed success, then an unattributed one before the frame's timers.
box:SetText("")
sendTo("Kaleid Sumner")
eq(lastTo(), "kaleid sumner", "an attributed success sets it")
success()
frame()
eq(box:GetText(), "", "  an unattributed one before the deferred fill: nothing filled")
-- The setting turned off, or the recent gone, before the deferred fill.
sendTo("Kaleid Sumner")
GM.Settings.SetAutofill(false)
frame()
eq(box:GetText(), "", "autofill turned off before the deferred fill: nothing")
GM.Settings.SetAutofill(true)
sendTo("Kaleid Sumner")
db.recents["kaleid sumner"] = nil
frame()
eq(box:GetText(), "", "  the recent gone before it: nothing")
sendTo("Kaleid Sumner")
frame()
eq(box:GetText(), "Kaleid Sumner", "  (the send made it a recent again)")

-- Handler order: Blizzard's after ours -------------------------------------------
WoW.blizzardSendLate = true
local late = CreateFrame("Frame")
late:SetScript("OnEvent", function() WoW.blizzardSendSuccess() end)
late:RegisterEvent("MAIL_SEND_SUCCESS")
tab(1); tab(2)
box:SetText("")
sendTo("Kaleid Sumner")
eq(box:GetText(), "", "Blizzard's handler after ours: reset")
frame()
eq(box:GetText(), "Kaleid Sumner", "  and still refilled a frame later")
late:UnregisterEvent("MAIL_SEND_SUCCESS")
WoW.blizzardSendLate = nil

-- The deferred fill checks at the moment of filling.
box:SetText("")
sendTo("Kaleid Sumner")
box:SetText("Bank")
frame()
eq(box:GetText(), "Bank", "a name typed before the deferred fill stays")
box:SetText("")
sendTo("Kaleid Sumner")
closeMailbox()
frame()
eq(box:GetText(), "", "the mailbox closed before the deferred fill: nothing")
openMailbox()
tab(2)

-- SetLastTo's refusals.
check(not Store.SetLastTo("Player-9-ZZZ", "x"), "SetLastTo: an unknown GUID is refused")
check(not Store.SetLastTo(ME, 5), "  a non-string")
check(not Store.SetLastTo(WoW.Secret("guid"), "x"), "  a secret GUID")
check(not Store.SetLastTo(ME, WoW.Secret("x")), "  a secret key")
Store.loaded = false
check(not Store.SetLastTo(ME, "x"), "  a Store not ready")
Store.loaded = true
eq(lastTo(), "kaleid sumner", "  none changed it")

-- The picker ------------------------------------------------------------------------
local T = GM._test.address
local function menu()
    T.menu(Address.button)
    return WoW.menu
end
local function texts(d)
    local out = {}
    for _, it in ipairs(d.items) do out[#out + 1] = (it.kind == "title" and "# " or "") .. it.text end
    return table.concat(out, " | ")
end

check(Address.button and Address.button:GetParent() == SendMailFrame, "the picker's button is on the send tab")
db.recents = {}
WoW.friends, WoW.guild = {}, nil
for guid in pairs(db.chars) do if guid ~= ME then db.chars[guid] = nil end end
eq(texts(menu()), "# No names yet", "nothing known: one line says so")

-- My characters: reachable, not hidden, not this one; recents; friends; guild.
Store.SetChar("Player-1-ZZZ", { name = "Zed Alt", realm = "Doomhowl", faction = "Horde", lastPlayDay = db.playDay })
Store.SetChar("Player-1-CCC", { name = "Bank Alt", realm = "Doomhowl", faction = "Horde", lastPlayDay = db.playDay })
Store.SetChar("Player-1-DDD", { name = "Other Side", realm = "Doomhowl", faction = "Alliance", lastPlayDay = db.playDay })
Store.SetChar("Player-1-EEE", { name = "Far Away", realm = "Elsewhere", faction = "Horde", lastPlayDay = db.playDay })
db.recents["old friend"] = { name = "Old Friend", day = db.playDay - 2 }
db.recents["new friend"] = { name = "New Friend", day = db.playDay }
db.recents["bank alt"] = { name = "Bank Alt", day = db.playDay }
WoW.friends = { { name = "Pal Two" }, { name = "pal one" }, { name = "New Friend" }, { name = "Realm Guy-Elsewhere" },
    { name = WoW.Secret("Hidden Pal") } }
WoW.friendCount = #WoW.friends + 1   -- one index that returns nothing (MayReturnNothing)
WoW.guild = { "Guildie Bee", "Karuzo Morphisto", "Guildie Ace-Doomhowl", "", "Old Friend" }
local requests = WoW.rosterRequests
local m = menu()
eq(WoW.rosterRequests, requests + 1, "opening the picker asks for the guild roster")
eq(m.scroll, 400, "the menu scrolls past 400 px")
eq(texts(m), "# My characters | Bank Alt | Zed Alt | # Recent | New Friend | Old Friend | # Friends | pal one | Pal Two | Guild",
    "sections in order, each sorted; own characters only when reachable; one name once (first wins)")
local g = m.items[#m.items]
eq(g.scroll, 400, "  the guild is a scrolling submenu")
eq(texts(g), "Guildie Ace | Guildie Bee", "  this realm's suffix dropped; this character, blanks and repeats left out")

-- A pick fills the box, nothing else.
box:SetText("")
WoW.focus = nil
local sends = #WoW.sends
m.items[2].callback()
eq(box:GetText(), "Bank Alt", "a pick fills the To box")
eq(WoW.focus, nil, "  and moves no focus")
eq(#WoW.sends, sends, "  and sends nothing")

-- Hidden characters (AltStable) are left out.
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true },
    GetCharacters = function()
        return { { guid = "Player-1-ZZZ", name = "Zed Alt", realm = "Doomhowl", faction = "Horde", hidden = true,
            provenance = "self" },
            { guid = "Player-1-FFF", name = "Shown Alt", realm = "Doomhowl", faction = "Horde", provenance = "own-account" } }
    end })
check(texts(menu()):find("# My characters | Shown Alt | # Recent", 1, true) ~= nil,
    "AltStable's list: hidden characters left out")
rawset(_G, "AltStable", nil)

-- The setting -----------------------------------------------------------------------
eq(GM.DEFAULTS.autofill, true, "autofill is on by default")
GlassMailDB.autofill = "yes"
GM._test.ensureDefaults()
eq(rawget(GlassMailDB, "autofill"), nil, "a non-boolean autofill is dropped at load")
SlashCmdList.GLASSMAIL("autofill off")
eq(GM.db.autofill, false, "/gmail autofill off")
SlashCmdList.GLASSMAIL("autofill on")
eq(GM.db.autofill, true, "/gmail autofill on")
check(table.concat(GM.HelpLines(), " "):find("/gmail autofill on/off", 1, true) ~= nil, "  /gmail help lists it")
local O = GM.Options._test
O.panel:Show()
eq(O.autofill:GetChecked(), true, "the options page's checkbox shows it on")
O.autofill:SetChecked(false)
O.autofill:GetScript("OnClick")(O.autofill)
eq(GM.db.autofill, false, "  a click turns it off")
GM.db.autofill = true
O.panel:Hide(); O.panel:Show()
eq(O.autofill:GetChecked(), true, "  re-read on show")
GM.db.autofill = false
O.panel:Hide(); O.panel:Show()
eq(O.autofill:GetChecked(), false, "  off too")
GM.db.autofill = true

-- lastTo at load: a non-string is dropped, the record kept.
local saved = { version = 1, playDay = 5, lastDate = "2026-11-06",
    chars = { [ME] = { name = "Karuzo Morphisto", lastPlayDay = 5, lastTo = 7 } } }
GlassMailDB = saved
Store.Load()
check(db ~= GlassMailDB and GlassMailDB.chars[ME] ~= nil, "a bad lastTo keeps its character")
eq(GlassMailDB.chars[ME].lastTo, nil, "  and is dropped")

done("test_address")
