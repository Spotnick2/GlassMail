-- Window.lua: the Glass Mail window, its folders, rows, search and forget
-- actions (PLAN.md, "The window PR in detail").
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.today = "2026-11-06"
local GM = loadAddon()
local Store, Window = GM.Store, GM.Window
local T = GM._test.window
local db = GlassMailDB
local ME, ALT, ALT2 = WoW.playerGUID, "Player-1-BBB", "Player-1-CCC"
local DAY = 86400
local NOW = WoW.clock

Store.SetChar(ALT, { name = "Kaleid Sumner", lastPlayDay = Store.PlayDay() })
Store.SetChar(ALT2, { name = "Bank Alt", lastPlayDay = Store.PlayDay() })

local function frame() WoW.advance(0.01) end
local function rows()
    local out = {}
    for i, row in ipairs(T.ui().rows) do
        if row:IsShown() then out[i] = row end
    end
    return out
end
local function top(i) return T.ui().rows[i].top:GetText() end
local function bottom(i) return T.ui().rows[i].bottom:GetText() end
local function right(i) return T.ui().rows[i].right:GetText() end
local function has(s, part) return type(s) == "string" and s:find(part, 1, true) ~= nil end
local function click(widget) widget:GetScript("OnClick")(widget) end
local function folder(key) click(T.ui().folders[key]) end
local function search(text) T.ui().search:SetText(text) end
local function sent(over)
    local r = { kind = "send", day = Store.PlayDay(), at = NOW, from = ME, to = "Kaleid Sumner", state = "sent",
        subject = "ore", money = 0, cod = 0, items = { { id = 2589, count = 5 } } }
    for k, v in pairs(over or {}) do r[k] = v end
    Store.AddSent(r)
end
local function inEscape()
    for _, n in ipairs(UISpecialFrames) do if n == T.NAME then return true end end
    return false
end

-- Built in combat: Escape's entry waits for the fight's end -----------------------
WoW.fire("PLAYER_REGEN_DISABLED")
SlashCmdList.GLASSMAIL("mail")
check(T.frame():IsShown(), "/gmail mail opens the window")
check(not inEscape(), "a window built in combat isn't in the Escape list")
WoW.fire("PLAYER_REGEN_ENABLED")
check(inEscape(), "  it joins after the fight")
WoW.fire("PLAYER_REGEN_DISABLED")
check(not inEscape(), "it leaves the Escape list in combat")
WoW.fire("PLAYER_REGEN_ENABLED")
check(inEscape(), "  and comes back after")
eq(#UISpecialFrames, 1, "  once, never twice")
SlashCmdList.GLASSMAIL("mail")
check(not T.frame():IsShown(), "/gmail mail closes it again")

-- The mailbox's button toggles it.
check(Window.mailButton ~= nil and Window.mailButton:GetParent() == MailFrame, "our button sits on the mailbox")
click(Window.mailButton)
check(T.frame():IsShown(), "  and opens the window")

-- Empty folders -----------------------------------------------------------------------
eq(T.ui().heading:GetText(), "Sent", "the first open shows Sent")
eq(T.ui().empty:GetText(), "Nothing sent yet.", "  empty: says so")
folder("trash")
eq(T.ui().empty:GetText(), "Trash is empty.", "an empty Trash says so")
check(has(T.ui().note:GetText(), "Trash holds the deletes Glass Mail confirmed"), "  with its note")
folder("inbox")
check(has(T.ui().empty:GetText(), "No mailbox seen yet"), "an empty Inbox says so")
T.frame():Hide()
Window.Show()
check(has(T.ui().heading:GetText(), "Every character's mailbox"), "a reopen shows the folder last shown")
eq(T.ui().note:GetText(), "", "  Trash's note only in Trash")

-- Sent ------------------------------------------------------------------------------
folder("sent")
sent({ to = "First One", at = NOW - 2 * DAY, money = 150 })
sent({ to = "Kaleid Sumner", from = ALT, state = "unconfirmed", subject = "herbs" })
sent({ kind = "return", to = "Some Stranger", subject = "spam", items = {} })
check(not has(top(1), "Some Stranger"), "a new record shows a frame later, not before")
frame()
check(has(top(1), "returned to Some Stranger"), "Sent is newest first: the return")
check(has(top(2), "to Kaleid Sumner") and has(top(2), "from Kaleid Sumner"), "  the other character's send")
check(has(top(2), "unconfirmed"), "  marked unconfirmed")
check(not has(top(3), "unconfirmed"), "  a sent one isn't")
check(has(bottom(2), '"herbs"'), "  the subject")
check(has(bottom(3), "150c"), "  the money")
eq(right(1), date("%H:%M", NOW), "  today's: the time")
eq(right(3), date("%b %d", NOW - 2 * DAY), "  older: the date")
local icon = T.ui().rows[2].icons[1]
check(icon:IsShown() and icon.itemID == 2589, "  the items as icons")
eq(icon.count:GetText(), 5, "  with counts")
check(not T.ui().rows[1].icons[1]:IsShown(), "  none when there are none")
icon:GetScript("OnEnter")(icon)
check(GameTooltip:IsOwned(icon), "an icon has a tooltip")
eq(GameTooltip._itemID, 2589, "  the item's")
check(has(T.ui().folders.sent.label:GetText(), "3"), "the folder shows its count")

-- A record added while hidden shows on the next open.
T.frame():Hide()
sent({ to = "While Hidden" })
Window.Show()
check(has(top(1), "While Hidden"), "a record added while hidden shows on the next open")

-- Search ------------------------------------------------------------------------------
search("Kaleid")
eq(#T.entries(), 1, "search by name (the recipient, or the sending character)")
search("karuzo")
eq(#T.entries(), 3, "  the sending character's name finds its sends")
search("herbs")
eq(#T.entries(), 1, "by subject")
search("KALEID herbs")
eq(#T.entries(), 1, "every word must match, in any case")
search("kaleid nothing")
eq(#T.entries(), 0, "  one that doesn't: nothing")
eq(T.ui().empty:GetText(), "Nothing matches.", "  and says so")
search("k.leid")
eq(#T.entries(), 0, "a plain find: no patterns")

-- Item names: a miss asks once; a load refreshes; a failure isn't asked again.
search("copper")
eq(#T.entries(), 0, "an item whose name isn't cached doesn't match yet")
local asks = 0
for _, id in ipairs(WoW.itemRequests) do if id == 2589 then asks = asks + 1 end end
eq(asks, 1, "  its data is asked for once")
search("coppe")
search("copper")
asks = 0
for _, id in ipairs(WoW.itemRequests) do if id == 2589 then asks = asks + 1 end end
eq(asks, 1, "  and not again this session")
WoW.itemNames[2589] = "Copper Ore"
WoW.fire("ITEM_DATA_LOAD_RESULT", 2589, true)
eq(#T.entries(), 0, "the load refreshes a frame later")
frame()
eq(#T.entries(), 3, "  then the item's name matches")
WoW.itemNames[2589] = nil
local before = #WoW.itemRequests
Store.AddSent({ kind = "send", day = Store.PlayDay(), at = NOW, from = ME, to = "X", state = "sent",
    items = { { id = 4242, count = 1 } } })
frame()
search("widget")
eq(#WoW.itemRequests, before + 1, "a new item is asked for")
local refreshes = 0
local refresh = Window.Refresh
Window.Refresh = function(...) refreshes = refreshes + 1; return refresh(...) end
WoW.fire("ITEM_DATA_LOAD_RESULT", 4242, false)
frame()
eq(refreshes, 0, "a failed load refreshes nothing")
Window.Refresh = refresh
search("widge")
eq(#WoW.itemRequests, before + 1, "  a failed load isn't asked again")
WoW.fire("ITEM_DATA_LOAD_RESULT", 9999, true)
check(true, "a load we didn't ask for is ignored")
search("")
check(T.ui().empty:GetText() == "", "clearing the search shows everything")

-- Forget a Sent record.
local n = #db.sent
local first = T.entries()[1].rec
click(T.ui().rows[1].forget)
eq(#db.sent, n - 1, "forget removes a Sent record")
check(db.sent[#db.sent] ~= first, "  that one")
frame()

-- Trash -------------------------------------------------------------------------------
Store.AddTrash({ at = NOW, from = ALT, expires = NOW + 3 * DAY + 60, sender = "Spammer Guy", subject = "buy gold" })
Store.AddTrash({ at = NOW, from = ME, expires = NOW - 1, sender = "Gone Already" })
folder("trash")
eq(#T.entries(), 1, "Trash leaves out an entry past its expiry")
check(has(top(1), "from Spammer Guy") and has(top(1), "in Kaleid Sumner's mailbox"), "  sender and whose mailbox")
eq(right(1), "gone in 3 days", "  when it goes")
check(has(T.ui().note:GetText(), "isn't here"), "  the note")
search("gold")
eq(#T.entries(), 1, "Trash is searched by subject")
search("")
click(T.ui().rows[1].forget)
eq(#db.trash, 1, "forget removes a Trash entry")
eq(db.trash[1].sender, "Gone Already", "  that one")
frame()

-- Inbox -------------------------------------------------------------------------------
local function snapMail(over)
    local m = { expires = NOW + 5 * DAY, type = "player", sender = "Kaleid Sumner", subject = "ore", money = 0,
        cod = 0, wasReturned = false, items = {} }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end
Store.SetSnapshot(ME, { at = NOW - 3 * DAY, loaded = 3, total = 3, complete = true, mails = {
    snapMail({ money = 12000, expires = NOW + 2 * DAY + 60 }),
    snapMail({ items = { { id = 2589, count = 5 } }, subject = "copper", sender = "Miner Joe" }),
    snapMail({ subject = "hello", expires = NOW - 60 }) } })
Store.SetSnapshot(ALT, { at = NOW, loaded = 0, total = 0, complete = true, mails = {} })
Store.SetSnapshot(ALT2, { at = NOW - DAY, loaded = 1, total = 140, complete = false,
    mails = { snapMail({ subject = "just words" }) } })
folder("inbox")
eq(#T.entries(), 3, "Inbox: one row per character")
eq(top(1), "Bank Alt", "  sorted by name")
eq(top(3), "Karuzo Morphisto", "  ...")
eq(right(3), "last seen 3 days ago", "  last seen")
eq(right(2), "last seen today", "  today")
eq(right(1), "last seen 1 day ago", "  one day")
eq(bottom(3), "2 mails with items or gold, 12000c, the first expires in 2 days", "  the summary")
eq(bottom(2), "empty when last seen", "  an inbox seen empty")
check(has(bottom(1), "letters only"), "  letters without items or gold")
check(has(bottom(1), "1 of 140 loaded at the last visit"), "  a partial one says so")
eq(Window.CharacterLine({ at = NOW, loaded = 2, total = 2, complete = true, mails = {} }, NOW),
    "no unexpired mail recorded", "a snapshot whose mails went says only that")
eq(Window.CharacterLine({ at = NOW, loaded = 1, total = 1, complete = true,
    mails = { { expires = NOW - 60, type = "player", subject = "old" } } }, NOW),
    "no unexpired mail recorded", "  and one whose mails expired since the last prune")

-- A character's mails.
click(T.ui().rows[3])
check(has(T.ui().heading:GetText(), "Karuzo Morphisto's mailbox"), "a click opens that character's mails")
check(T.ui().back:IsShown(), "  with a back button")
eq(#T.entries(), 2, "  the expired one left out")
check(has(top(1), "from Kaleid Sumner"), "  soonest expiry first")
eq(right(1), "expires in 2 days", "  when it expires")
check(has(bottom(1), "12000c"), "  its money")
check(T.ui().rows[2].icons[1]:IsShown(), "  its items")
click(T.ui().rows[2].forget)
eq(#db.snapshots[ME].mails, 2, "forget removes a mail from the snapshot")
frame()
eq(#T.entries(), 1, "  and the list shows it gone")
-- A search from a character's mailbox is still over every character.
search("words")
eq(#T.entries(), 1, "a search from a character's mailbox is over every character")
check(has(top(1), "Bank Alt: from Kaleid Sumner"), "  each with its character's name")
check(not T.ui().back:IsShown(), "  no back button while searching")
search("")
check(has(T.ui().heading:GetText(), "Karuzo Morphisto's mailbox"), "  clearing it returns to that mailbox")
eq(#T.entries(), 1, "  ...")
check(T.ui().back:IsShown(), "  with its back button")
click(T.ui().back)
eq(#T.entries(), 3, "back returns to the characters")

-- A search in Inbox lists matching mails across characters.
search("words")
eq(#T.entries(), 1, "a search in Inbox finds mails")
check(has(top(1), "Bank Alt: from Kaleid Sumner"), "  each with its character's name")
search("bank")
eq(#T.entries(), 1, "  by character name too")
search("")

-- Forget a character's snapshot.
click(T.ui().rows[1].forget)
eq(db.snapshots[ALT2], nil, "forget on a character drops its snapshot")
frame()
eq(#T.entries(), 2, "  and its row")

-- A character's mailbox with nothing to list says what is known of it.
click(T.ui().rows[1])
check(has(T.ui().heading:GetText(), "Kaleid Sumner's mailbox"), "an empty snapshot opens")
eq(T.ui().empty:GetText(), "Empty when last seen", "  and says it was empty, not that none was seen")
click(T.ui().back)
click(T.ui().rows[2])
click(T.ui().rows[1].forget)
frame()
eq(#T.entries(), 0, "a mailbox whose last mail was forgotten")
eq(T.ui().empty:GetText(), "No unexpired mail recorded", "  says only that")
click(T.ui().back)
-- An open character whose snapshot goes is no longer open.
click(T.ui().rows[1])
Store.ForgetSnapshot(ALT)
frame()
eq(#T.entries(), 1, "an open snapshot that goes returns to the characters")
eq(T.ui().heading:GetText(), "Every character's mailbox, as last seen", "  ...")
check(not T.ui().back:IsShown(), "  with no back button")

-- The pool and the scroll --------------------------------------------------------------
folder("sent")
local frames = #WoW.frames
for i = 1, 1000 do sent({ to = "Bulk " .. i }) end
frame()
eq(#db.sent, 1000, "a thousand Sent records")
eq(#WoW.frames, frames, "  build no new frames")
eq(#T.ui().rows, T.ROWS, "  the pool stays its rows")
local list = T.ui().list
list:GetScript("OnMouseWheel")(list, -1)
eq(T.offset(), 3, "the wheel scrolls")
list:GetScript("OnMouseWheel")(list, 5)
eq(T.offset(), 0, "  never above the top")
T.setOffset(5000)
eq(T.offset(), 1000 - T.ROWS, "  never past the end")
check(has(top(T.ROWS), "Bulk 1"), "  the last row is the oldest")
T.ui().scroll:SetValue(10)
eq(T.offset(), 10, "the scroll bar moves the list")

-- The look: the window repaints with the setting; `stock` shows it smoked.
local pane
for _, o in ipairs(GM._test.skin.own) do if o.key == "pane" then pane = o.tex; break end end
GM.Settings.SetSkin("clear")
eq(pane._color[4], GM.Skin.PRESETS.clear.pane[4], "the window's panes take the clear preset")
GM.Settings.SetSkin("stock")
eq(pane._color[4], GM.Skin.PRESETS.smoked.pane[4], "  and smoked under the stock look")
GM.Settings.SetSkin("clear")

-- The store not ready.
Store.loaded = false
Window.Refresh()
eq(T.ui().empty:GetText(), "Glass Mail's memory couldn't load.", "the store not ready: says so")
eq(#T.entries(), 0, "  and shows nothing")
Store.loaded = true

done("test_window")
