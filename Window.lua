-- Window.lua: Glass Mail's own window (M2: X1, X2). Folders like Gmail's:
-- Inbox (each character's mailbox as last seen), Sent, Trash. PLAN.md, "The
-- window" and "The window PR in detail".
--
-- Our frame, nothing of Blizzard's: it works away from the mailbox and in
-- combat (nothing here is protected). It reads the Store and never touches
-- the mailbox; forgetting a row changes only Glass Mail's memory.
-- - Escape closes it through UISpecialFrames, out of combat only: an addon's
--   entry taints the Escape pass, which would then fail to hide a protected
--   frame in combat (GlassGear's rule). Only table.insert / table.remove on
--   that table, never an assignment.
-- - The list is a pool of rows and an offset: a thousand Sent records never
--   build a thousand frames.
-- - Item names (for search) may not be cached after a restart: a miss asks
--   RequestLoadItemDataByID once per item per session, and a load refreshes.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Glass, Skin, Store, Summary = GM.Glass, GM.Skin, GM.Store, GM.Summary
local Window = {}
GM.Window = Window

local NAME = "GlassMailWindow"
local WIDTH, HEIGHT = 640, 440
local ROWS, ROW_H = 8, 38
local ICONS = 6
local DAY = 86400
local FORGET_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local OPEN_ICON = "Interface\\Icons\\INV_Letter_15"
local GREY = "|cff9d9d9d"
local AMBER = "|cffffb347"

Window.FOLDERS = { "inbox", "sent", "trash" }
local LABELS = { inbox = "Inbox", sent = "Sent", trash = "Trash" }
Window.TRASH_NOTE = "Trash holds the deletes Glass Mail confirmed. One made while another mail action "
    .. "was still in flight isn't here."

local frame, ui            -- built on first open
local folder = "sent"      -- the first open of a session shows Sent
local character            -- Inbox: the GUID whose mails are shown, or nil for the characters
local query = ""           -- lower-cased search text
local offset = 0
local entries = {}
local asked = {}           -- itemID -> true: its data was requested this session
local pending = false      -- a refresh is queued for the next frame

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function coins(c) return C_CurrencyInfo.GetCoinTextureString(c) end

local function span(sec)
    local d = math.floor(sec / DAY)
    if d <= 0 then return "less than a day" end
    return d == 1 and "1 day" or (d .. " days")
end

local function when(at)
    if date("%Y-%m-%d", at) == date("%Y-%m-%d", time()) then return date("%H:%M", at) end
    return date("%b %d", at)
end

local function ago(at)
    local d = math.floor((time() - at) / DAY)
    if d <= 0 then return "last seen today" end
    return "last seen " .. (d == 1 and "1 day" or (d .. " days")) .. " ago"
end

local function charName(guid)
    local c = Store.Chars()[guid]
    return c and c.name or "another character"
end

-- Subject, money and COD, as one line.
local function contents(r)
    local parts = {}
    if r.subject and r.subject ~= "" then parts[#parts + 1] = '"' .. r.subject .. '"' end
    if r.money and r.money > 0 then parts[#parts + 1] = coins(r.money) end
    if r.cod and r.cod > 0 then parts[#parts + 1] = "COD " .. coins(r.cod) end
    return table.concat(parts, ", ")
end

-- What an Inbox character row says: the summary, or only what is known.
function Window.CharacterLine(snap, now)
    local s = Summary.Of(snap, now)
    local text
    if s then
        text = s.count .. (s.count == 1 and " mail" or " mails") .. " with items or gold"
        if s.money > 0 then text = text .. ", " .. coins(s.money) end
        text = text .. ", the first expires in " .. span(s.soonest - now)
    elseif snap.complete and snap.total == 0 then
        text = "empty when last seen"
    else
        local left = false
        for _, m in ipairs(snap.mails) do
            if m.expires > now then left = true; break end
        end
        text = left and "letters only" or "no unexpired mail recorded"
    end
    if not snap.complete then
        text = text .. GREY .. " (" .. snap.loaded .. " of " .. snap.total .. " loaded at the last visit)|r"
    end
    return text
end

--------------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------------

-- An item's name, or nil; a miss asks the client to load it, once per session.
local function itemName(id)
    local name = C_Item.GetItemNameByID(id)
    if type(name) == "string" and not API.IsSecret(name) then return name end
    if not asked[id] then
        asked[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    return nil
end

local function words()
    local out = {}
    for w in query:gmatch("%S+") do out[#out + 1] = w end
    return out
end

-- True when every word of the query is in one of the fields (plain find).
local function matches(ws, fields, items)
    if #ws == 0 then return true end
    local hay = {}
    for _, f in ipairs(fields) do
        if type(f) == "string" then hay[#hay + 1] = f:lower() end
    end
    for _, it in ipairs(items or {}) do
        local name = itemName(it.id)
        if name then hay[#hay + 1] = name:lower() end
    end
    for _, w in ipairs(ws) do
        local found = false
        for _, h in ipairs(hay) do
            if h:find(w, 1, true) then found = true; break end
        end
        if not found then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Entries: what the list shows, for the open folder and search
--------------------------------------------------------------------------------

local function mailEntries(guid, snap, now, ws, out, withName)
    local list = {}
    for _, m in ipairs(snap.mails) do
        if m.expires > now and matches(ws, { m.sender, m.subject, withName and charName(guid) }, m.items) then
            list[#list + 1] = { kind = "mail", rec = m, guid = guid, withName = withName }
        end
    end
    table.sort(list, function(a, b) return a.rec.expires < b.rec.expires end)
    for _, e in ipairs(list) do out[#out + 1] = e end
end

local function build()
    local out, ws, now = {}, words(), time()
    if folder == "sent" then
        local sent = Store.Sent()
        for i = #sent, 1, -1 do
            local r = sent[i]
            if matches(ws, { r.to, charName(r.from), r.subject }, r.items) then
                out[#out + 1] = { kind = "sent", rec = r }
            end
        end
    elseif folder == "trash" then
        local trash = Store.Trash()
        for i = #trash, 1, -1 do
            local e = trash[i]
            if e.expires >= now and matches(ws, { e.sender, charName(e.from), e.subject }, e.items) then
                out[#out + 1] = { kind = "trash", rec = e }
            end
        end
    else
        local snaps = Store.Snapshots()
        if character and snaps[character] then
            mailEntries(character, snaps[character], now, ws, out, false)
        elseif #ws > 0 then
            for guid, snap in pairs(snaps) do mailEntries(guid, snap, now, ws, out, true) end
            table.sort(out, function(a, b) return a.rec.expires < b.rec.expires end)
        else
            for guid, snap in pairs(snaps) do out[#out + 1] = { kind = "char", guid = guid, rec = snap } end
            table.sort(out, function(a, b)
                local x, y = charName(a.guid), charName(b.guid)
                if x ~= y then return x < y end
                return a.guid < b.guid
            end)
        end
    end
    return out
end
Window.Entries = function() return build() end

local function forget(e)
    if e.kind == "sent" then Store.ForgetSent(e.rec)
    elseif e.kind == "trash" then Store.ForgetTrash(e.rec)
    elseif e.kind == "char" then Store.ForgetSnapshot(e.guid)
    elseif e.kind == "mail" then Store.ForgetMail(e.guid, e.rec) end
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

local function paintIcons(row, items)
    items = items or {}
    for i = 1, ICONS do
        local icon, it = row.icons[i], items[i]
        if it then
            icon.itemID = it.id
            icon.tex:SetTexture(C_Item.GetItemIconByID(it.id))
            icon.count:SetText(it.count > 1 and it.count or "")
            icon:Show()
        else
            icon.itemID = nil
            icon:Hide()
        end
    end
    row.more:SetText(#items > ICONS and ("+" .. (#items - ICONS)) or "")
end

local function paintRow(row, e, now)
    row.entry = e
    if not e then return row:Hide() end
    local r = e.rec
    local top, right, bottom, items
    if e.kind == "sent" then
        top = (r.kind == "return" and "returned to " or "to ") .. r.to .. GREY .. "  from " .. charName(r.from) .. "|r"
        if r.state == "unconfirmed" then top = top .. AMBER .. "  unconfirmed|r" end
        right, bottom, items = when(r.at), contents(r), r.items
    elseif e.kind == "trash" then
        top = "from " .. (r.sender or "unknown") .. GREY .. "  in " .. charName(r.from) .. "'s mailbox|r"
        right, bottom, items = "gone in " .. span(r.expires - now), contents(r), r.items
    elseif e.kind == "char" then
        top, right, bottom = charName(e.guid), ago(r.at), Window.CharacterLine(r, now)
    else
        top = (e.withName and (charName(e.guid) .. ": ") or "") .. "from " .. (r.sender or "unknown")
        if r.wasReturned then top = top .. GREY .. "  returned|r" end
        right, bottom, items = "expires in " .. span(r.expires - now), contents(r), r.items
    end
    row.top:SetText(top)
    row.right:SetText(right)
    row.bottom:SetText(bottom)
    paintIcons(row, items)
    row:Show()
end

local function emptyText()
    if not Store.Ready() then return "Glass Mail's memory couldn't load." end
    if query ~= "" then return "Nothing matches." end
    if folder == "sent" then return "Nothing sent yet." end
    if folder == "trash" then return "Trash is empty." end
    return "No mailbox seen yet: open one on each character."
end

local function paint()
    local now = time()
    for i = 1, ROWS do paintRow(ui.rows[i], entries[offset + i], now) end
    local max = math.max(0, #entries - ROWS)
    ui.scroll:SetMinMaxValues(0, max)
    ui.scroll:SetValue(offset)
    ui.scroll:SetShown(max > 0)
    ui.empty:SetText(#entries == 0 and emptyText() or "")
    ui.note:SetText(folder == "trash" and Window.TRASH_NOTE or "")
end

local function setOffset(n)
    n = math.max(0, math.min(math.floor(n), math.max(0, #entries - ROWS)))
    if n == offset then return end
    offset = n
    paint()
end

function Window.Refresh()
    if not ui then return end
    entries = Store.Ready() and build() or {}
    offset = math.max(0, math.min(offset, #entries - ROWS))
    local sent, trash = Store.Ready() and #Store.Sent() or 0, Store.Ready() and #Store.Trash() or 0
    for _, key in ipairs(Window.FOLDERS) do
        local b = ui.folders[key]
        local n = key == "sent" and sent or key == "trash" and trash or nil
        b.label:SetText(LABELS[key] .. (n and (GREY .. "  " .. n .. "|r") or ""))
        b.selected:SetShown(key == folder)
    end
    local heading
    if folder == "inbox" and character and query == "" then
        heading = charName(character) .. "'s mailbox"
    elseif folder == "inbox" and query == "" then
        heading = "Every character's mailbox, as last seen"
    else
        heading = LABELS[folder] .. (query ~= "" and (": " .. #entries .. " found") or "")
    end
    ui.heading:SetText(heading)
    ui.back:SetShown(folder == "inbox" and character ~= nil)
    paint()
end

-- A refresh a frame later, once however many changes come in that frame.
local function schedule()
    if pending or not (frame and frame:IsShown()) then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if frame:IsShown() then Window.Refresh() end
    end)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function setEscape(on)
    local list = rawget(_G, "UISpecialFrames")
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do
        if list[i] == NAME then table.remove(list, i) end
    end
    if on then table.insert(list, NAME) end
end

function Window.Show()
    Window.Build()
    frame:Show()   -- OnShow repaints from the Store
end

local function showFolder(key)
    folder, character, offset = key, nil, 0
    Window.Refresh()
end

local function newRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
    Skin.AddPane(row, "pane")
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    row.top = Glass.Font(row, 13, "LEFT")
    row.top:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
    row.top:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    row.right = Glass.Font(row, 11, "RIGHT")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -26, -5)
    row.bottom = Glass.Font(row, 11, "LEFT")
    row.bottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 4)
    row.bottom:SetPoint("RIGHT", row, "RIGHT", -(26 + ICONS * 18 + 22), 0)
    row.bottom:SetTextColor(0.75, 0.75, 0.75)
    row.icons = {}
    for k = 1, ICONS do
        local icon = CreateFrame("Button", nil, row)
        icon:SetSize(16, 16)
        icon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -26 - (ICONS - k) * 18, 3)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints(icon)
        icon.count = Glass.Font(icon, 9, "RIGHT")
        icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        icon:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.icons[k] = icon
    end
    row.more = Glass.Font(row, 10, "LEFT")
    row.more:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -26 - ICONS * 18, 6)
    row.forget = CreateFrame("Button", nil, row)
    row.forget:SetSize(14, 14)
    row.forget:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.forget:SetNormalTexture(FORGET_ICON)
    row.forget:SetAlpha(0.35)
    row.forget:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Forget: Glass Mail stops remembering this. Your mailbox doesn't change.")
        GameTooltip:Show()
    end)
    row.forget:SetScript("OnLeave", function(self) self:SetAlpha(0.35); GameTooltip:Hide() end)
    row.forget:SetScript("OnClick", function()
        if row.entry then forget(row.entry) end
    end)
    row:SetScript("OnClick", function()
        local e = row.entry
        if e and e.kind == "char" then
            character, offset = e.guid, 0
            Window.Refresh()
        end
    end)
    return row
end

local function newFolder(parent, key, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(116, 26)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -4 - (i - 1) * 28)
    b.selected = b:CreateTexture(nil, "BACKGROUND")
    b.selected:SetAllPoints(b)
    b.selected:SetColorTexture(1, 0.82, 0, 0.12)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    b.label = Glass.Font(b, 13, "LEFT")
    b.label:SetPoint("LEFT", b, "LEFT", 10, 0)
    b:SetScript("OnClick", function() showFolder(key) end)
    return b
end

function Window.Build()
    if frame then return end
    frame = CreateFrame("Frame", NAME, UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    Skin.AddWindow(frame)
    ui = { folders = {}, rows = {} }
    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints(frame)
    content:SetFrameLevel(Glass.ContentLevel(frame))

    local bar = CreateFrame("Frame", nil, content)
    bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -30, 0)
    bar:SetHeight(30)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local title = Glass.Font(bar, 15, "LEFT")
    title:SetPoint("LEFT", bar, "LEFT", 14, -2)
    title:SetText("Glass Mail")
    local close = CreateFrame("Button", nil, content, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() frame:Hide() end)

    local side = CreateFrame("Frame", nil, content)
    side:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -36)
    side:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 10, 10)
    side:SetWidth(120)
    Skin.AddPane(side, "section")
    for i, key in ipairs(Window.FOLDERS) do ui.folders[key] = newFolder(side, key, i) end

    local main = CreateFrame("Frame", nil, content)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
    main:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -10, 10)
    Skin.AddPane(main, "section")

    local search = CreateFrame("EditBox", nil, main)
    search:SetPoint("TOPLEFT", main, "TOPLEFT", 8, -6)
    search:SetPoint("TOPRIGHT", main, "TOPRIGHT", -8, -6)
    search:SetHeight(22)
    search:SetAutoFocus(false)
    search:SetFontObject("ChatFontNormal")
    search:SetTextInsets(8, 8, 0, 0)
    Skin.AddPane(search, "pane")
    local hint = Glass.Font(search, 12, "LEFT")
    hint:SetPoint("LEFT", search, "LEFT", 8, 0)
    hint:SetText(GREY .. "Search names, subjects and items|r")
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        hint:SetShown(text == "")
        query, offset = text:lower(), 0
        Window.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    ui.search = search

    ui.back = CreateFrame("Button", nil, main)
    ui.back:SetSize(60, 18)
    ui.back:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    ui.back.label = Glass.Font(ui.back, 12, "LEFT")
    ui.back.label:SetPoint("LEFT", ui.back, "LEFT", 0, 0)
    ui.back.label:SetText("< Back")
    ui.back:SetScript("OnClick", function()
        character, offset = nil, 0
        Window.Refresh()
    end)
    ui.heading = Glass.Font(main, 13, "LEFT")
    ui.heading:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 66, -8)

    local list = CreateFrame("Frame", nil, main)
    list:SetPoint("TOPLEFT", main, "TOPLEFT", 8, -58)
    list:SetPoint("TOPRIGHT", main, "TOPRIGHT", -8, -58)
    list:SetHeight(ROWS * ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - delta * 3) end)
    for i = 1, ROWS do ui.rows[i] = newRow(list, i) end
    ui.list = list

    local scroll = CreateFrame("Slider", nil, list)
    scroll:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    scroll:SetWidth(8)
    scroll:SetOrientation("VERTICAL")
    scroll:SetValueStep(1)
    scroll:SetObeyStepOnDrag(true)
    scroll:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = scroll:GetThumbTexture()
    if thumb then
        thumb:SetSize(8, 32)
        thumb:SetVertexColor(1, 1, 1, 0.35)
    end
    scroll:SetScript("OnValueChanged", function(_, v) setOffset(v) end)
    ui.scroll = scroll

    ui.empty = Glass.Font(list, 13, "CENTER")
    ui.empty:SetPoint("TOP", list, "TOP", 0, -40)
    ui.note = Glass.Font(main, 11, "LEFT")
    ui.note:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 10, 8)
    ui.note:SetPoint("RIGHT", main, "RIGHT", -10, 0)
    ui.note:SetTextColor(0.6, 0.6, 0.6)

    frame:SetScript("OnShow", function() Window.Refresh() end)
    frame:SetScript("OnHide", function() GameTooltip:Hide() end)
    -- Escape, out of combat only; a window built in combat waits for its end.
    setEscape(not API.InCombat())
end

function Window.Toggle()
    if frame and frame:IsShown() then return frame:Hide() end
    Window.Show()
end

function Window.IsShown() return frame ~= nil and frame:IsShown() end

-- Our button on the mailbox's title bar, left of its close button.
local function addMailButton()
    local mail = rawget(_G, "MailFrame")
    if not mail then return end
    local b = CreateFrame("Button", nil, mail)
    b:SetSize(20, 20)
    b:SetPoint("TOPRIGHT", mail, "TOPRIGHT", -28, -2)
    b:SetNormalTexture(OPEN_ICON)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function() Window.Toggle() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Glass Mail: Sent, Trash and every character's mailbox")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Window.mailButton = b
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a1, a2)
    API.NoteCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then
        if frame then setEscape(false) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if frame then setEscape(true) end
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if asked[a1] and a2 == true and query ~= "" then schedule() end
    end
end)
API.RegisterEvents(events, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ITEM_DATA_LOAD_RESULT" })

-- Called at PLAYER_LOGIN.
function Window.Start()
    Store.OnChange(schedule)
    addMailButton()
end

GM._test = GM._test or {}
GM._test.window = {
    ui = function() return ui end, frame = function() return frame end,
    entries = function() return entries end, offset = function() return offset end,
    asked = asked, ROWS = ROWS, setOffset = setOffset, NAME = NAME,
}
