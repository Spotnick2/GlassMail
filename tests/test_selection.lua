-- GlassMail.Selection (Inbox.lua), the selection's public read API (issue #26),
-- as Shatter's Mail Mode reads it: Get() as { [inbox index] = true }, and
-- OnChange(fn) once per change.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local FOOD, ORE = 6290, 2770
WoW.itemInfo = { [FOOD] = { maxStack = 20, family = 0 }, [ORE] = { maxStack = 20, family = 0 } }
WoW.bags = { [0] = { size = 16, family = 0, items = {} } }
WoW.now = 100

local function hello(n) return { sender = "Kaleid Sumner", subject = "hello " .. n } end
local function supplies()
    return { sender = "Cowruzo Kashmere", subject = "supplies", money = 250,
             items = { [1] = { id = FOOD, count = 2 } } }
end

WoW.inbox = { hello(1), hello(2), hello(3), hello(4) }
local GM = loadAddon()
local Sel = GM.Selection
local rows, bar = GM._test.inbox.rows, GM._test.inbox.bar()
local function update() InboxFrame:Update() end
local function click(b) b._scripts.OnClick(b, "LeftButton") end
local function step(dt) WoW.now = WoW.now + (dt or 0.2); WoW.tick(dt or 0.2) end
local function keys(t)
    local out = {}
    for k, v in pairs(t) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(out)
    return table.concat(out, ",")
end

check(type(Sel) == "table" and type(Sel.Get) == "function" and type(Sel.OnChange) == "function",
    "GlassMail.Selection.Get / OnChange exist (Shatter's detection)")
eq(type(Sel.Get()), "table", "nothing selected: a table, not nil")
eq(keys(Sel.Get()), "", "  empty")

WoW.fire("MAIL_SHOW")
update()
click(rows[3].check)   -- selected before anyone listens
local fired = 0
Sel.OnChange(function() fired = fired + 1 end)
Sel.OnChange("not a function")   -- ignored
update()
eq(fired, 0, "registered while something is selected: no call until it changes")
click(rows[3].check)
eq(fired, 1, "  then it does")
fired = 0

-- Get: the selected mails, by inbox index.
click(rows[2].check)
eq(keys(Sel.Get()), "2=true", "a click: that mail's index")
eq(fired, 1, "  OnChange once")
update()
WoW.fire("MAIL_INBOX_UPDATE")
eq(fired, 1, "a refresh that changes nothing: no call")

-- A copy each time.
local got = Sel.Get()
got[2], got[4] = nil, true
eq(keys(Sel.Get()), "2=true", "changing the returned table changes nothing")
check(Sel.Get() ~= Sel.Get(), "  a new table each call")

-- The index follows the mail.
table.insert(WoW.inbox, 1, supplies())
WoW.fire("MAIL_INBOX_UPDATE")
eq(keys(Sel.Get()), "3=true", "a mail arriving above: the new index")
eq(fired, 2, "  OnChange (what Get returns changed)")
table.remove(WoW.inbox, 1)
WoW.fire("MAIL_INBOX_UPDATE")
eq(keys(Sel.Get()), "2=true", "and back")
eq(fired, 3, "  OnChange")

-- Shift range, ctrl sender, Clear: one call each.
click(rows[1].check)   -- the anchor; 1 and 2 selected
eq(fired, 4, "a second click")
WoW.shift = true
click(rows[4].check)
WoW.shift = false
eq(keys(Sel.Get()), "1=true,2=true,3=true,4=true", "shift: the range")
eq(fired, 5, "  one call for the whole range")
click(bar.clear)
eq(keys(Sel.Get()), "", "Clear: empty")
eq(fired, 6, "  one call")
click(bar.clear)
eq(fired, 6, "Clear on nothing: no call")
WoW.ctrl = true
click(rows[1].check)
WoW.ctrl = false
eq(keys(Sel.Get()), "1=true,2=true,3=true,4=true", "ctrl: the sender's mail")
eq(fired, 7, "  one call")

-- Only unique, resolved mail.
table.insert(WoW.inbox, hello(3))
WoW.fire("MAIL_INBOX_UPDATE")
eq(keys(Sel.Get()), "1=true,2=true,4=true", "a selected mail gains a twin: it drops out")
eq(fired, 8, "  OnChange")
table.remove(WoW.inbox)
table.remove(WoW.inbox, 1)
WoW.fire("MAIL_INBOX_UPDATE")
eq(keys(Sel.Get()), "1=true,3=true", "a selected mail goes away: it drops out, the others renumber")
eq(fired, 9, "  OnChange")
WoW.inbox[1].items = { [1] = { id = ORE, count = 1, link = false } }
WoW.fire("MAIL_INBOX_UPDATE")
eq(keys(Sel.Get()), "3=true", "a mail not resolved (a link loading): left out")
table.insert(WoW.inbox, hello(4))   -- hello 4 is at index 3: a twin, not pruned while a mail loads
WoW.fire("MAIL_INBOX_UPDATE")
eq(keys(Sel.Get()), "", "  a twin appearing meanwhile: left out too")
table.remove(WoW.inbox)
WoW.inbox[1].items = nil
WoW.fire("MAIL_INBOX_UPDATE")

-- A listener that throws is recorded, and the others still hear.
local later = 0
Sel.OnChange(function() error("boom") end)
Sel.OnChange(function() later = later + 1 end)
click(rows[2].check)
check(GM.failures["selection listener"] ~= nil and GM.failures["selection listener"]:find("boom", 1, true) ~= nil,
    "a listener's error is recorded")
eq(later, 1, "  the next listener still runs")
check(rows[2].check:GetChecked(), "  and the refresh finished")

-- The mailbox closing empties it.
local before = fired
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
eq(keys(Sel.Get()), "", "the mailbox closed: empty")
eq(fired, before + 1, "  OnChange")

-- Closed during Open (n), whichever handler hears the close first.
WoW.fire("MAIL_SHOW")
WoW.inbox = { supplies(), hello(1) }
update()
click(rows[1].check)
click(bar.open)
eq(GM.Ops.Kind(), "selected", "Open (n) runs")
step()
local frames = WoW.frames
local reversed = {}
for k = #frames, 1, -1 do reversed[#reversed + 1] = frames[k] end
WoW.frames = reversed   -- the inbox clears its selection before Ops stops the run
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
WoW.frames = frames
eq(GM.Ops.Kind(), nil, "  the close stops it")
eq(keys(Sel.Get()), "", "  the run's leftovers don't come back as a selection")
eq(next(GM._test.inbox.selected()), nil, "  nor in the inbox")

done("test_selection")
