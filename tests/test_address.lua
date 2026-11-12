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

-- The picker: our panel, a search over the sections --------------------------------
local T = GM._test.address
local function panel() return T.panel() end
local function shown() return panel() ~= nil and panel():IsShown() end
-- The button as the mouse uses it: its mouse down (excluded from the outside
-- close), then its click.
local function press()
    WoW.mouseOver = Address.button
    WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    Address.button:GetScript("OnClick")(Address.button, "LeftButton")
    WoW.mouseOver = nil
end
local function search(text) T.ui().search:SetText(text) end
local function texts()
    local out = {}
    for _, r in ipairs(T.rows()) do out[#out + 1] = r.title and ("# " .. r.title) or r.name end
    return table.concat(out, " | ")
end
local function listening(event) return panel()._events[event] == true end

check(Address.button and Address.button:GetParent() == SendMailFrame, "the picker's button is on the send tab")
db.recents = {}
WoW.friends, WoW.guild = {}, nil
for guid in pairs(db.chars) do if guid ~= ME then db.chars[guid] = nil end end
local ownBefore = #GM._test.skin.own
press()
check(shown(), "the button opens the picker")
eq(#GM._test.skin.own, ownBefore + 3, "  glass, its backing and its search pane, in the skin's repaint list")
local backing = GM._test.skin.own[ownBefore + 2]
eq(backing.key, "backing", "  a backing under the glass (Glass UI's tracker body)")
eq(backing.tex._color[4], 0.35, "  at clear's opacity (Glass UI's clear body)")
check(backing.tex._masks and backing.tex._masks[1] == GM._test.skin.own[ownBefore + 1].g.mask, "  clipped by the glass's mask")
GM.Settings.SetSkin("smoked")
eq(backing.tex._color[4], 0.92, "  smoked's after the setting changes")
GM.Settings.SetSkin("stock")
eq(backing.tex._color[4], 0.92, "  and smoked's under the stock look")
GM.Settings.SetSkin("clear")
eq(panel():GetParent(), SendMailFrame, "  on the send tab")
eq(texts(), "", "nothing known: no rows")
eq(T.ui().empty:GetText(), "No names yet", "  and a line says so")
press()
check(not shown(), "the button again closes it")

-- My characters: reachable, not hidden, not this one; recents; friends; guild.
Store.SetChar("Player-1-ZZZ", { name = "Zed Alt", realm = "Doomhowl", faction = "Horde", lastPlayDay = db.playDay })
Store.SetChar("Player-1-CCC", { name = "Bank Alt", realm = "Doomhowl", faction = "Horde", lastPlayDay = db.playDay })
Store.SetChar("Player-1-DDD", { name = "Other Side", realm = "Doomhowl", faction = "Alliance", lastPlayDay = db.playDay })
Store.SetChar("Player-1-EEE", { name = "Far Away", realm = "Elsewhere PvP", faction = "Horde", lastPlayDay = db.playDay })
Store.SetChar("Player-1-GGG", { name = "Other Realm", realm = "Doomhowl Two", faction = "Horde", lastPlayDay = db.playDay })
db.recents["old friend"] = { name = "Old Friend", day = db.playDay - 2 }
db.recents["new friend"] = { name = "New Friend", day = db.playDay }
db.recents["bank alt"] = { name = "Bank Alt", day = db.playDay }
WoW.friends = { { name = "Pal Two" }, { name = "pal one" }, { name = "New Friend" }, { name = "Realm Guy-Elsewhere" },
    { name = WoW.Secret("Hidden Pal") } }
WoW.friendCount = #WoW.friends + 1   -- one index that returns nothing (MayReturnNothing)
WoW.guild = { "Guildie Bee", "Karuzo Morphisto", "Guildie Ace-Doomhowl", "", "Old Friend" }
local requests = WoW.rosterRequests
WoW.focus = box
press()
eq(WoW.rosterRequests, requests + 1, "opening the picker asks for the guild roster")
eq(WoW.focus, T.ui().search, "  its search box has the focus")
check(listening("GLOBAL_MOUSE_DOWN") and listening("GUILD_ROSTER_UPDATE"), "  it listens for outside clicks and the roster")
eq(texts(), "# My characters | Bank Alt | Other Realm | Zed Alt | # Recent | New Friend | Old Friend"
    .. " | # Friends | pal one | Pal Two | # Guild | Guildie Ace | Guildie Bee",
    "sections in order, each sorted; own characters of this ruleset and faction (any realm); one name once"
    .. " (first wins); the guild a section like the others")
eq(T.ui().rows[1].label:GetText(), "My characters", "  a title row shows its section")
check(not T.ui().rows[1]:IsEnabled(), "  and isn't clickable")

-- Filtering.
search("pal")
eq(texts(), "# Friends | pal one | Pal Two", "a search filters every section; one with no match hides, title too")
search("PAL TWO")
eq(texts(), "# Friends | Pal Two", "  case ignored; every word must match")
search("guildie a")
eq(texts(), "# Guild | Guildie Ace", "  two words")
search("a.t")
eq(texts(), "", "  a '.' is taken literally")
eq(T.ui().empty:GetText(), "No match", "  and nothing left says so")
T.ui().search:GetScript("OnEnterPressed")(T.ui().search)
check(shown(), "Enter with nothing listed does nothing")
search("")
eq(T.ui().empty:GetText(), "", "an empty search lists everything again")

-- Pooled rows: name -> title -> unused -> name, nothing kept.
search("bank")
eq(T.ui().rows[2].name, "Bank Alt", "row 2: a name")
search("pal")
eq(T.ui().rows[1].name, nil, "row 1 now a title: no name to pick")
T.ui().rows[1]:GetScript("OnClick")(T.ui().rows[1])
check(shown(), "  a click on a title does nothing")
search("zzz")
check(not T.ui().rows[2]:IsShown() and T.ui().rows[2].name == nil, "  unused: hidden, no name")
search("zed")
eq(T.ui().rows[2].name, "Zed Alt", "  a name again: the new one")
check(T.ui().rows[2]:IsEnabled(), "  enabled")

-- Enter picks the first name; a pick fills the To box, closes, sends nothing.
box:SetText("")
search("guildie")
local sends = #WoW.sends
T.ui().search:GetScript("OnEnterPressed")(T.ui().search)
eq(box:GetText(), "Guildie Ace", "Enter picks the first name listed (titles skipped)")
check(not shown(), "  and closes the picker")
eq(#WoW.sends, sends, "  nothing is sent")
check(WoW.focus ~= T.ui().search, "  the search's focus is cleared")
check(not listening("GLOBAL_MOUSE_DOWN") and not listening("GUILD_ROSTER_UPDATE"), "  both events unregistered")
press()
eq(T.ui().search:GetText(), "", "reopened: the search box is empty again")
eq(texts():sub(1, 15), "# My characters", "  and lists everything")
T.ui().rows[2]:GetScript("OnClick")(T.ui().rows[2])
eq(box:GetText(), "Bank Alt", "a click on a name picks it")
check(not shown(), "  and closes")

-- Escape, the x, an outside mouse down; the panel and the button don't close it.
press()
T.ui().search:GetScript("OnEscapePressed")(T.ui().search)
check(not shown(), "Escape in the search closes it")
press()
T.ui().close:GetScript("OnClick")(T.ui().close)
check(not shown(), "the x closes it")
press()
WoW.mouseOver = panel()
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
check(shown(), "a mouse down on the panel leaves it open")
WoW.mouseOver = nil
WoW.fire("GLOBAL_MOUSE_DOWN", "MiddleButton")
check(shown(), "  a middle button outside too")
WoW.fire("GLOBAL_MOUSE_DOWN", "RightButton")
check(not shown(), "a right or left mouse down outside closes it")
check(WoW.focus ~= T.ui().search and not listening("GLOBAL_MOUSE_DOWN"), "  with the same cleanup")

-- A send's success closes it: Blizzard's reset focuses the To box, ours doesn't take it back.
press()
WoW.fire("MAIL_SEND_SUCCESS")
check(not shown(), "MAIL_SEND_SUCCESS closes the picker")
eq(WoW.focus, box, "  the To box keeps the focus Blizzard's reset gave it")
press()
WoW.blizzardSendLate = true
local lateReset = CreateFrame("Frame")
lateReset:SetScript("OnEvent", function() WoW.blizzardSendSuccess() end)
lateReset:RegisterEvent("MAIL_SEND_SUCCESS")
WoW.fire("MAIL_SEND_SUCCESS")
check(not shown(), "  with Blizzard's handler after ours too")
eq(WoW.focus, box, "  the focus still the To box's")
lateReset:UnregisterEvent("MAIL_SEND_SUCCESS")
WoW.blizzardSendLate = nil
frame()

-- The send tab hidden, or the mailbox closed: closed for good.
press()
tab(1)
check(not shown(), "the inbox tab closes it")
tab(2)
check(not shown(), "  back on the send tab it stays closed")
press()
MailFrame:Hide()
-- The client fires a shown child's OnHide when its parent hides; the pinned kit doesn't.
SendMailFrame:GetScript("OnHide")(SendMailFrame)
check(not shown() and not listening("GLOBAL_MOUSE_DOWN"), "the mailbox's close closes it, cleaned up")
openMailbox()
tab(2)
check(not shown(), "  and it stays closed at the next visit")

-- A big guild: the pool, the scroll, a roster update while open.
local guild = {}
for i = 1, 500 do guild[i] = string.format("Member %03d", i) end
WoW.guild = guild
local frames = #WoW.frames
press()
eq(#WoW.frames, frames, "500 guild members build no frame")
eq(#T.ui().rows, Address.ROWS, "  the pool stays its rows")
T.ui().list:GetScript("OnMouseWheel")(T.ui().list, -1)
eq(T.offset(), 3, "the wheel scrolls 3 rows")
T.ui().scroll:SetValue(100)
eq(T.offset(), 100, "the slider scrolls")
T.setOffset(5000)
eq(T.offset(), #T.rows() - Address.ROWS, "  never past the end")
search("member 1")
eq(T.offset(), 0, "a new query starts at the top")
check(T.ui().rows[2].name == "Member 001", "  with the first match")
T.setOffset(50)
search("member")
T.setOffset(200)
-- The roster changes while open and scrolled: fewer, reordered; query, offset (clamped) and focus kept.
local fewer = {}
for i = 120, 1, -1 do fewer[#fewer + 1] = string.format("Member %03d", i) end
WoW.guild = fewer
WoW.focus = nil
WoW.fire("GUILD_ROSTER_UPDATE")
eq(T.ui().search:GetText(), "member", "a roster update keeps the query")
eq(#T.rows(), 121, "  re-reads the guild (a title and 120 names)")
eq(T.rows()[2].name, "Member 001", "  sorted again")
eq(T.offset(), 121 - Address.ROWS, "  the offset clamped to the shorter list")
eq(WoW.focus, nil, "  and takes no focus")
press()
press()
eq(T.offset(), 0, "reopened: at the top")
Address.Close()

-- Hidden characters (AltStable) are left out.
WoW.guild = nil
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true },
    GetCharacters = function()
        return { { guid = "Player-1-ZZZ", name = "Zed Alt", realm = "Doomhowl", faction = "Horde", hidden = true,
            provenance = "self" },
            { guid = "Player-1-FFF", name = "Shown Alt", realm = "Doomhowl", faction = "Horde", provenance = "own-account" } }
    end })
press()
check(texts():find("# My characters | Shown Alt | # Recent", 1, true) ~= nil, "AltStable's list: hidden characters left out")
Address.Close()
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
