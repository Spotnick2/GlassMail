-- Bank.lua: N1's frames (docs/PLAN.md, "N1: the bank character"): the button
-- on the Send tab's title bar that fills an empty draft for the bank (and,
-- for keep N exactly, prepares the split stacks first), the chat line at the
-- mailbox, and the Bank page in the Glass Mail window.
--
-- We never send: the player presses Blizzard's Send. Our code only lifts
-- stacks from the bags onto the draft's attachment slots, as the player's own
-- clicks do, and checks every step (session 7, FOREVER-PROBE.md):
-- - a pickup with something on the cursor swaps it, so the cursor is checked
--   empty before each one;
-- - a split dropped on the draft attaches the whole source stack, so a split
--   goes into an empty bag slot first (Prepare), and the bags show it only
--   when the server answers (session 7b: up to a second, in pieces);
-- - a refused drop stays on the cursor; ClearCursor puts it back.

GlassMail = GlassMail or {}
local GM = GlassMail
local API, Bank, Ops, Registry, Names = GM.API, GM.Bank, GM.Ops, GM.Registry, GM.Names
local Glass, Skin = GM.Glass, GM.Skin
local BankUI = {}
GM.BankUI = BankUI

local ICON = "Interface\\Icons\\INV_Box_02"
local GREY = "|cff9d9d9d"
local PENDING_SEND_S = 60
local PREPARE_S = 5

local function say(msg) API.Print(msg) end
local function safely(key, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then API.Fail(key, err) end
    end
end

local button
local visit = 0           -- bumped at each mailbox open
local pendingSend         -- { token } between a send and its answer
local sendToken = 0
local prepared            -- { token, state = "preparing" | "ready", splits, batch }
local prepToken = 0
local lockedSend = false  -- Blizzard's refund confirmation is up (MAIL_LOCK_SEND_ITEMS)

--------------------------------------------------------------------------------
-- The cursor, the draft, the bags
--------------------------------------------------------------------------------

-- What the cursor holds: nil (nothing), an itemID, or "other".
local function cursorItem()
    local ok, kind, id = pcall(GetCursorInfo)
    if not ok then return "other" end
    if API.IsSecret(kind) or API.IsSecret(id) then return "other" end
    if kind == nil then return nil end
    if kind == "item" and type(id) == "number" then return id end
    return "other"
end
local function cursorHas() return cursorItem() ~= nil end

local function slotInfo(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" then return nil end
    local id, count, locked = info.itemID, info.stackCount, info.isLocked
    if API.IsSecret(id) or API.IsSecret(count) or API.IsSecret(locked) then return { unreadable = true } end
    return { itemID = id, count = count, locked = locked }
end

-- The slot holds exactly that stack, unlocked.
local function holds(s, count)
    local i = slotInfo(s.bag, s.slot)
    return i ~= nil and i.itemID == s.itemID and i.count == (count or s.count) and i.locked == false
end

local function freeAttachment()
    for a = 1, Bank.MaxAttach() do
        if not HasSendMailItem(a) then return a end
    end
end

local function itemName(id)
    local n = C_Item.GetItemNameByID(id)
    if type(n) == "string" and n ~= "" and not API.IsSecret(n) then return n end
    return "item " .. tostring(id)
end

-- True for an empty draft, else false and why. Money is read from the
-- widget: GetSendMailMoney() stays 0 until the Send click copies it (session 6).
local function draftEmpty()
    local subj, body = rawget(_G, "SendMailSubjectEditBox"), rawget(_G, "SendMailBodyEditBox")
    local money, cod = rawget(_G, "SendMailMoney"), rawget(_G, "SendMailCODButton")
    local copper = rawget(_G, "MoneyInputFrame_GetCopper")
    if not (subj and body and money and cod and copper) then return false, "The draft can't be read." end
    for a = 1, Bank.MaxAttach() do
        if HasSendMailItem(a) then return false, "Fill works on an empty draft: this one has an attachment." end
    end
    local s, b = subj:GetText(), body:GetText()
    if API.IsSecret(s) or API.IsSecret(b) then return false, "The draft can't be read." end
    if (s or "") ~= "" then return false, "Fill works on an empty draft: this one has a subject." end
    if (b or "") ~= "" then return false, "Fill works on an empty draft: this one has a letter." end
    local ok, c = pcall(copper, money)
    if not ok or API.IsSecret(c) or type(c) ~= "number" then return false, "The draft can't be read." end
    if c ~= 0 then return false, "Fill works on an empty draft: this one has money in it." end
    if cod:GetChecked() then return false, "Fill works on an empty draft: C.O.D. is on." end
    return true
end

--------------------------------------------------------------------------------
-- The state: what a click would do, or why not
--------------------------------------------------------------------------------

local function sum(list)
    local n = 0
    for _, s in ipairs(list) do n = n + (s.count or s.n) end
    return n
end

-- mode ("fill", "prepare", "preparing", "off"), the tooltip text, and the
-- bank and what the click would use.
function BankUI.State()
    local bank, why = Bank.For()
    if not bank then return "off", why end
    if API.InCombat() then return "off", "Not in combat.", bank end
    if prepared and prepared.state == "preparing" then
        return "preparing", "Preparing: waiting for the bags to show the split stacks.", bank
    end
    if Ops.Running() then return "off", "Busy: wait for the current mail action.", bank end
    if pendingSend then return "off", "Waiting for the last send to go through.", bank end
    if cursorHas() then return "off", "Put down what the cursor holds first.", bank end
    local empty, w = draftEmpty()
    if not empty then return "off", w, bank end
    if prepared and prepared.state == "ready" then
        return "fill", "Fill for " .. bank.name .. ": " .. sum(prepared.batch) .. " items, prepared. Then check the "
            .. "draft and press Send.", bank, prepared.batch, true
    end
    local plan = Bank.Plan()
    if #plan.splits > 0 then
        return "prepare", "Prepare for " .. bank.name .. ": split " .. #plan.splits .. " stack(s) into empty bag "
            .. "slots, so the rest stays as you set it. Then click again to fill.", bank, plan
    end
    if #plan.attach > 0 then
        return "fill", "Fill for " .. bank.name .. ": " .. plan.units .. " items in " .. #plan.attach .. " stack(s)"
            .. (plan.left > 0 and (", " .. plan.left .. " more after this mail") or "")
            .. ". Then check the draft and press Send.", bank, plan.attach, false
    end
    return "off", "Nothing for " .. bank.name .. " in your bags.", bank
end

local function refresh()
    if not button then return end
    local mode = BankUI.State()
    local on = mode == "fill" or mode == "prepare"
    button:SetEnabled(on)
    local tex = button:GetNormalTexture()
    if tex then tex:SetDesaturated(not on) end
    if GameTooltip:IsOwned(button) then BankUI.Tip(button) end
end
BankUI.Refresh = refresh

function BankUI.Tip(self)
    local mode, text = BankUI.State()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Glass Mail: the bank")
    GameTooltip:AddLine(text or "", 1, 1, 1, true)
    if mode == "off" or mode == "preparing" then GameTooltip:AddLine("Rules: /gmail bank", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Fill and Prepare (inside the click: nothing is scheduled)
--------------------------------------------------------------------------------

local function forget(why)
    if prepared and why then say(why) end
    prepared = nil
end

-- One stack onto the next free attachment slot; nil, or why it stopped.
local function attachOne(s)
    if cursorHas() then return "the cursor holds something" end
    if not holds(s) then return "a stack moved since the plan" end
    local a = freeAttachment()
    if not a then return "the draft is full" end
    C_Container.PickupContainerItem(s.bag, s.slot)
    local held = cursorItem()
    if held ~= s.itemID then
        if held ~= nil then ClearCursor() end   -- whatever came from that slot goes back to it
        return "the pickup didn't give " .. itemName(s.itemID)
    end
    ClickSendMailItemButton(a)
    if cursorItem() == s.itemID then
        ClearCursor()
        Bank.Refuse(s.itemID)
        if cursorHas() then return "the game refused " .. itemName(s.itemID) .. ", still on the cursor: put it back" end
        return "the game refused " .. itemName(s.itemID) .. " (back in its bag; skipped from now on)"
    end
    if cursorHas() then return "the cursor holds something else now; left alone" end
    if lockedSend then return "Blizzard asks you to confirm an item: answer it, then Fill again" end
    local _, id, _, count = GetSendMailItem(a)
    if id ~= s.itemID or count ~= s.count then return "an attachment isn't what was planned" end
end

-- The draft against the list (each { itemID, count } once): true when they agree.
local function verify(list)
    local want = {}
    for _, s in ipairs(list) do
        local k = s.itemID .. "x" .. s.count
        want[k] = (want[k] or 0) + 1
    end
    for a = 1, Bank.MaxAttach() do
        if HasSendMailItem(a) then
            local _, id, _, count = GetSendMailItem(a)
            local k = tostring(id) .. "x" .. tostring(count)
            if not want[k] then return false end
            want[k] = want[k] - 1
            if want[k] == 0 then want[k] = nil end
        end
    end
    return next(want) == nil
end

-- After Prepare: every remembered stack still there, and each item's units
-- outside the batch still meet its keep (Codex's round 5).
local function stillPrepared(batch)
    local ids, sent = {}, {}
    for _, s in ipairs(batch) do
        if not holds(s) then return false end
        if not sent[s.itemID] then ids[#ids + 1] = s.itemID end
        sent[s.itemID] = (sent[s.itemID] or 0) + s.count
    end
    local totals = Bank.Totals(ids)
    for _, id in ipairs(ids) do
        local rule = Bank.Rule(id)
        if not (rule and totals[id] and totals[id] - sent[id] >= rule.keep) then return false end
    end
    return true
end

local function fill(bank, list, fromPrepare)
    if fromPrepare then
        local ok = stillPrepared(list)
        prepared = nil
        if not ok then return say("Your bags changed since Prepare: click again to plan anew.") end
    end
    rawget(_G, "SendMailNameEditBox"):SetText(bank.name)
    local done = {}
    for _, s in ipairs(list) do
        local why = attachOne(s)
        if why then
            say("Stopped filling for " .. bank.name .. ": " .. why .. ".")
            break
        end
        done[#done + 1] = s
    end
    if not verify(done) then say("The draft isn't what Glass Mail planned: check it before you send.") end
end

local function prepare(plan)
    local list = {}
    for _, sp in ipairs(plan.splits) do
        local src, dest = sp.source, sp.dest
        local why
        if cursorHas() then
            why = "the cursor holds something"
        elseif not holds(src, src.before) then
            why = "a stack moved since the plan"
        elseif C_Container.GetContainerItemInfo(dest.bag, dest.slot) ~= nil then
            why = "the empty bag slot isn't empty"
        else
            C_Container.SplitContainerItem(src.bag, src.slot, sp.n)
            local held = cursorItem()
            if held ~= src.itemID then
                if held ~= nil then ClearCursor() end
                why = "the split didn't happen"
            else
                C_Container.PickupContainerItem(dest.bag, dest.slot)
                if cursorHas() then
                    if cursorItem() == src.itemID then ClearCursor() end
                    why = "the split couldn't go in an empty bag slot"
                end
            end
        end
        if why then
            say("Stopped preparing: " .. why .. ".")
            break
        end
        list[#list + 1] = sp
    end
    if #list == 0 then return end
    local batch = {}
    for _, s in ipairs(plan.attach) do batch[#batch + 1] = s end
    for _, sp in ipairs(list) do
        batch[#batch + 1] = { bag = sp.dest.bag, slot = sp.dest.slot, itemID = sp.source.itemID, count = sp.n }
    end
    prepToken = prepToken + 1
    local token = prepToken
    prepared = { token = token, state = "preparing", splits = list, batch = batch }
    C_Timer.After(PREPARE_S, function()
        if prepared and prepared.token == token and prepared.state == "preparing" then
            forget("The split stacks didn't show in your bags in time. Nothing was lost: click again.")
            refresh()
        end
    end)
end

-- On each bag update while preparing: every source and destination in an
-- expected state (the old count or the new one; empty or the new stack);
-- ready when all show their new counts, unlocked. Anything else forgets it.
local function advance()
    if not (prepared and prepared.state == "preparing") then return end
    local all = true
    for _, sp in ipairs(prepared.splits) do
        local src, dest = sp.source, sp.dest
        local s, d = slotInfo(src.bag, src.slot), slotInfo(dest.bag, dest.slot)
        local srcOk = s and s.itemID == src.itemID and (s.count == src.before or s.count == src.after)
        local destOk = d == nil or (d.itemID == src.itemID and d.count == sp.n)
        if not (srcOk and destOk) then
            return forget("Your bags changed while preparing. Nothing was lost: click again.")
        end
        if not (s.count == src.after and s.locked == false and d and d.locked == false) then all = false end
    end
    if all then prepared.state = "ready" end
end
BankUI._advance = advance

local function onClick()
    local mode, _, bank, what, fromPrepare = BankUI.State()
    if mode == "fill" then
        fill(bank, what, fromPrepare)
    elseif mode == "prepare" then
        prepare(what)
    end
    refresh()
end

--------------------------------------------------------------------------------
-- The chat line at the mailbox
--------------------------------------------------------------------------------

-- Once per visit: it runs only from MAIL_SHOW.
local function notice()
    if not GM.db.bankNotice then return end
    local bank = Bank.For()
    if not bank then return end
    local units = Bank.Available()
    if units > 0 then say(units .. " items ready for " .. bank.name .. " (Fill on the Send tab).") end
end

--------------------------------------------------------------------------------
-- The Bank page in the Glass Mail window
--------------------------------------------------------------------------------

local page, pui
local ROWS, ROW_H = 7, 30
local offset = 0
local asked = {}

local function categoryName(c)
    if c.sub then
        local ok, n = pcall(C_Item.GetItemSubClassInfo, c.class, c.sub)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    local ok, n = pcall(C_Item.GetItemClassInfo, c.class)
    if ok and type(n) == "string" and n ~= "" then return n end
    return "category " .. c.class .. (c.sub and ("." .. c.sub) or "")
end
BankUI.CategoryName = categoryName

local function ruleText(r)
    if r.item then
        local n = C_Item.GetItemNameByID(r.item)
        if type(n) == "string" and n ~= "" then return n end
        if not asked[r.item] then
            asked[r.item] = true
            C_Item.RequestLoadItemDataByID(r.item)
        end
        return "item " .. r.item
    end
    return categoryName(r) .. GREY .. " (category)|r"
end

local function menu(owner, gen)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local ok, err = pcall(MenuUtil.CreateContextMenu, owner, gen)
    if not ok then API.Fail("bank menu", err) end
end

-- Your characters of the current group, by name: the banks you can pick.
function BankUI.Candidates(group)
    local out = {}
    for _, c in ipairs(Registry.Characters()) do
        if not c.hidden and Bank.Group(c) == group then out[#out + 1] = c end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

local function chooseBank(owner)
    local group = Bank.CurrentGroup()
    if not group then return say(Bank.WHY_GROUP) end
    menu(owner, function(_, root)
        root:CreateTitle("Bank for " .. Bank.GroupLabel(group))
        for _, c in ipairs(BankUI.Candidates(group)) do
            root:CreateButton(c.name, function() Bank.Set(group, c.name, c.guid) end)
        end
        if Bank.Get(group) then root:CreateButton("No bank", function() Bank.Clear(group) end) end
    end)
end

local function addCategory(owner)
    menu(owner, function(_, root)
        root:CreateTitle("Add a category")
        for _, c in ipairs(Bank.CATEGORIES) do
            root:CreateButton(categoryName(c), function() Bank.AddCategory(c.class, c.sub, 0) end)
        end
    end)
end

-- The cursor's item becomes a rule (keep 0); the item goes back to its bag.
local function dropItem()
    local id = cursorItem()
    if type(id) ~= "number" then return end
    Bank.AddItem(id, 0)
    ClearCursor()
end
BankUI.DropItem = dropItem

local function newRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name = Glass.Font(row, 12, "LEFT")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -130, 0)
    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(16, 16)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    row.remove:SetScript("OnClick", function() if row.rule then Bank.Remove(row.rule) end end)
    row.keep = CreateFrame("EditBox", nil, row)
    row.keep:SetSize(52, 20)
    row.keep:SetPoint("RIGHT", row.remove, "LEFT", -10, 0)
    row.keep:SetAutoFocus(false)
    row.keep:SetNumeric(true)
    row.keep:SetMaxLetters(4)
    row.keep:SetFontObject("ChatFontNormal")
    row.keep:SetTextInsets(6, 6, 0, 0)
    Skin.AddPane(row.keep, "pane")
    local function save(self)
        if row.rule then Bank.SetKeep(row.rule, tonumber(self:GetText()) or 0) end
        self:ClearFocus()
    end
    row.keep:SetScript("OnEnterPressed", save)
    row.keep:SetScript("OnEditFocusLost", function(self) if row.rule then Bank.SetKeep(row.rule, tonumber(self:GetText()) or 0) end end)
    row.keep:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local label = Glass.Font(row, 11, "RIGHT")
    label:SetPoint("RIGHT", row.keep, "LEFT", -6, 0)
    label:SetText(GREY .. "keep|r")
    return row
end

function BankUI.RefreshPage()
    if not (page and page:IsShown()) then return end
    local group = Bank.CurrentGroup()
    pui.title:SetText(group and ("Bank for " .. Bank.GroupLabel(group)) or "Bank")
    local b = Bank.Get(group)
    local r = Bank.Resolve(b)
    pui.choose:SetText(r and r.name or "Choose a character")
    pui.choose:SetEnabled(group ~= nil and not API.InCombat())
    local _, why = Bank.For()
    if r and not r.char then
        why = r.name .. " isn't one of the characters Glass Mail or AltStable knows; mail still goes to that name."
    end
    pui.why:SetText(why and r and (GREY .. why .. "|r") or (group and "" or Bank.WHY_GROUP))
    -- The other groups' banks.
    local others = {}
    for g, ob in pairs(Bank.Banks()) do
        if g ~= group then others[#others + 1] = { group = g, name = ob.name } end
    end
    table.sort(others, function(x, y) return x.group < y.group end)
    for i, line in ipairs(pui.others) do
        local o = others[i]
        line.group = o and o.group
        line.text:SetText(o and (GREY .. Bank.GroupLabel(o.group) .. ":|r " .. o.name) or "")
        line.clear:SetShown(o ~= nil)
    end
    -- The rules.
    local rules = Bank.Rules()
    offset = math.max(0, math.min(offset, #rules - ROWS))
    for i, row in ipairs(pui.rows) do
        local rule = rules[offset + i]
        row.rule = rule
        row:SetShown(rule ~= nil)
        if rule then
            row.icon:SetTexture(rule.item and C_Item.GetItemIconByID(rule.item) or "Interface\\Icons\\INV_Misc_Bag_10")
            row.name:SetText(ruleText(rule))
            if not row.keep:HasFocus() then row.keep:SetText(tostring(rule.keep)) end
        end
    end
    pui.empty:SetText(#rules == 0 and "No rules yet: drop an item on the slot, or add a category." or "")
end

function BankUI.BuildPage(parent)
    if page then return page end
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    pui = { rows = {}, others = {} }
    pui.title = Glass.Font(page, 14, "LEFT")
    pui.title:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -10)
    pui.choose = API.Button(page, "Choose a character", 200, safely("bank choose", function(self) chooseBank(self) end))
    pui.choose:SetPoint("TOPLEFT", pui.title, "BOTTOMLEFT", 0, -8)
    pui.why = Glass.Font(page, 11, "LEFT")
    pui.why:SetPoint("TOPLEFT", pui.choose, "BOTTOMLEFT", 2, -6)
    pui.why:SetPoint("RIGHT", page, "RIGHT", -10, 0)
    for i = 1, 3 do
        local line = CreateFrame("Frame", nil, page)
        line:SetSize(300, 16)
        line:SetPoint("TOPLEFT", pui.choose, "TOPRIGHT", 16, -(i - 1) * 16 + 4)
        line.text = Glass.Font(line, 11, "LEFT")
        line.text:SetPoint("LEFT", line, "LEFT", 18, 0)
        line.clear = CreateFrame("Button", nil, line)
        line.clear:SetSize(14, 14)
        line.clear:SetPoint("LEFT", line, "LEFT", 0, 0)
        line.clear:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        line.clear:SetScript("OnClick", function() if line.group then Bank.Clear(line.group) end end)
        pui.others[i] = line
    end

    local rulesTitle = Glass.Font(page, 13, "LEFT")
    rulesTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -96)
    rulesTitle:SetText("What goes to the bank (what is above each keep)")
    pui.slot = CreateFrame("Button", nil, page)
    pui.slot:SetSize(30, 30)
    pui.slot:SetPoint("TOPLEFT", rulesTitle, "BOTTOMLEFT", 0, -8)
    pui.slot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-White")
    pui.slot:SetScript("OnReceiveDrag", safely("bank drop", dropItem))
    pui.slot:SetScript("OnClick", safely("bank drop", dropItem))
    local slotHint = Glass.Font(page, 11, "LEFT")
    slotHint:SetPoint("LEFT", pui.slot, "RIGHT", 8, 0)
    slotHint:SetText(GREY .. "Drop an item here, or|r")
    pui.add = API.Button(page, "Add a category", 130, safely("bank category", function(self) addCategory(self) end))
    pui.add:SetPoint("LEFT", slotHint, "RIGHT", 8, 0)

    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", pui.slot, "BOTTOMLEFT", 0, -10)
    list:SetPoint("RIGHT", page, "RIGHT", -10, 0)
    list:SetHeight(ROWS * ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        BankUI.RefreshPage()
    end)
    for i = 1, ROWS do pui.rows[i] = newRow(list, i) end
    pui.empty = Glass.Font(list, 12, "CENTER")
    pui.empty:SetPoint("TOP", list, "TOP", 0, -20)
    local foot = Glass.Font(page, 11, "LEFT")
    foot:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 10, 8)
    foot:SetPoint("RIGHT", page, "RIGHT", -10, 0)
    foot:SetText(GREY .. "On another character, Fill on the Send tab's title bar puts what is above each keep in the "
        .. "draft; you press Send. Soulbound items stay.|r")
    page:SetScript("OnShow", BankUI.RefreshPage)
    page:Hide()
    return page
end

--------------------------------------------------------------------------------
-- Events and start
--------------------------------------------------------------------------------

local function sendStarted()
    sendToken = sendToken + 1
    local token = sendToken
    pendingSend = { token = token }
    forget()
    C_Timer.After(PENDING_SEND_S, function()
        if pendingSend and pendingSend.token == token then pendingSend = nil; refresh() end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", safely("bank events", function(_, event, a1)
    API.NoteCombat(event)
    if event == "MAIL_SHOW" then
        visit = visit + 1
        prepared, pendingSend, lockedSend = nil, nil, false
        C_Timer.After(0, safely("bank notice", notice))
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if a1 == (Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.MailInfo or 17) then
            prepared, pendingSend, lockedSend = nil, nil, false
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        forget()
    elseif event == "SECURE_TRANSFER_CONFIRM_SEND_MAIL" then
        sendStarted()
    elseif event == "MAIL_SEND_SUCCESS" or event == "MAIL_FAILED" or event == "SECURE_TRANSFER_CANCEL" then
        pendingSend = nil
        if event == "MAIL_SEND_SUCCESS" then forget() end
    elseif event == "MAIL_LOCK_SEND_ITEMS" then
        lockedSend = true
    elseif event == "MAIL_UNLOCK_SEND_ITEMS" then
        lockedSend = false
    elseif event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_DELAYED" then
        advance()
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if asked[a1] then BankUI.RefreshPage() end
    end
    refresh()
end))

-- Called at PLAYER_LOGIN.
function BankUI.Start()
    local frame, mail = rawget(_G, "SendMailFrame"), rawget(_G, "MailFrame")
    API.RegisterEvents(events, { "MAIL_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "SECURE_TRANSFER_CONFIRM_SEND_MAIL", "SECURE_TRANSFER_CANCEL", "MAIL_SEND_SUCCESS",
        "MAIL_FAILED", "MAIL_LOCK_SEND_ITEMS", "MAIL_UNLOCK_SEND_ITEMS", "ITEM_LOCK_CHANGED", "BAG_UPDATE_DELAYED",
        "MAIL_SEND_INFO_UPDATE", "CURSOR_CHANGED", "ITEM_DATA_LOAD_RESULT" })
    Bank.OnChange(function() refresh(); BankUI.RefreshPage() end)
    Ops.Watch(refresh)
    if rawget(_G, "SendMail") then hooksecurefunc("SendMail", safely("bank send", sendStarted)) end
    if not (frame and mail) or button then return end
    -- On the title bar, left of the address book's (Address.lua).
    button = CreateFrame("Button", nil, frame)
    button:SetSize(20, 20)
    button:SetPoint("TOPRIGHT", mail, "TOPRIGHT", -72, -2)
    button:SetNormalTexture(ICON)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", safely("bank fill", onClick))
    button:SetScript("OnEnter", BankUI.Tip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The draft's text and money boxes change without an event: a light
    -- recheck while the Send tab shows (the button's OnUpdate runs only then).
    local since = 0
    button:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= 0.5 then
            since = 0
            refresh()
        end
    end)
    BankUI.button = button
    refresh()
end

GM._test = GM._test or {}
GM._test.bankui = {
    prepared = function() return prepared end, pendingSend = function() return pendingSend end,
    page = function() return page, pui end, visit = function() return visit end,
}
