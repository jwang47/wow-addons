-- QuestBoard items: a button for the usable quest item of each quest row
-- on the board, just left of that row (Active first when there are more
-- than ITEM_MAX). A click uses the item. A quest whose row is hidden
-- (trimmed, collapsed or scrolled away) shows no button.
--
-- The buttons are secure (SecureActionButtonTemplate, type "item"), so the
-- game locks them in combat: they are set up only out of combat, and a
-- change made in combat waits for its end. They hang from their own holder
-- frame, not from the board, so the board can still change size and move
-- in combat (a frame that secure buttons are anchored to is locked too).
local addonName, ns = ...
local D = ns.data
local call, api, plain = D.call, D.api, D.plain

ns.ITEM_MAX = 6
local SIZE, GAP = 24, 3
local holder, buttons, pending = nil, {}, false

local function itemID(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- The quest item of a log quest: the game's own (the one its tracker would
-- show), else a Questie source item that you carry and that can be used.
function D.questItem(e)
  if e.index then
    local link, texture, charges = call(rawget(_G, "GetQuestLogSpecialItemInfo"), e.index)
    local id = itemID(link)
    if id then return { id = id, link = link, texture = texture, charges = plain(charges) } end
  end
  local qdb = D.module("QuestieDB")
  local quest = qdb and call(qdb.GetQuest, e.id)
  local id = type(quest) == "table" and quest.sourceItemId
  if type(id) == "number" and id > 0 then
    local count = plain(call(api("C_Item.GetItemCount"), id)) or 0
    local spell = call(api("C_Item.GetItemSpell"), id)
    if count > 0 and spell then
      local _, link = call(api("C_Item.GetItemInfo"), id)
      return { id = id, link = link, texture = call(api("C_Item.GetItemIconByID"), id) }
    end
  end
end

-- The shown row of a quest, or nil.
function ns.rowFor(e)
  for _, r in ipairs(ns.rows or {}) do
    if r.entry == e and r:IsShown() then return r end
  end
end

-- The items to show, in order, one per item, each with the row it sits by.
function ns.itemList(st)
  local list, seen = {}, {}
  if not st then return list end
  for _, kind in ipairs({ "active", "nearby", "log", "turnin" }) do
    for _, e in ipairs(st[kind] or {}) do
      local it = e.item
      local row = it and ns.rowFor(e)
      if row and not seen[it.id] and #list < ns.ITEM_MAX then
        seen[it.id] = true
        it.quest, it.row = e, row
        table.insert(list, it)
      end
    end
  end
  return list
end

local function inCombat() return rawget(_G, "InCombatLockdown") and InCombatLockdown() end

local function makeButton(i)
  local b = CreateFrame("Button", "QuestBoardItem" .. i, holder, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("BOTTOMRIGHT", -1, 1)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.15)
  b:SetScript("OnEnter", function(self)
    local tip = rawget(_G, "GameTooltip")
    if not (tip and self.info) then return end
    tip:SetOwner(self, "ANCHOR_LEFT")
    if self.info.link then tip:SetHyperlink(self.info.link) else tip:AddLine("Quest item") end
    if self.info.quest then tip:AddLine("For: " .. self.info.quest.name, 0.6, 0.8, 1) end
    tip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  buttons[i] = b
  return b
end

-- Count and cooldown: plain frames, fine in combat.
function ns.updateItemState()
  for _, b in ipairs(buttons) do
    if b.info and b:IsShown() then
      local id = b.info.id
      local n = plain(call(api("C_Item.GetItemCount"), id))
      b.count:SetText(n and n > 1 and n or "")
      local start, dur, on = call(api("C_Container.GetItemCooldown"), id)
      if start and dur and b.cd.SetCooldown then
        if on ~= 0 and on ~= false and dur > 0 then b.cd:SetCooldown(start, dur) else b.cd:Clear() end
      end
    end
  end
end

-- Lays the buttons out from the last result. Out of combat only.
function ns.updateItems(st)
  if not ns.panel then return end
  if inCombat() then pending = true return end
  pending = false
  if not holder then
    holder = CreateFrame("Frame", "QuestBoardItems", UIParent)
    holder:SetSize(SIZE, SIZE)
  end
  holder:ClearAllPoints()
  holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  local list = (ns.db.shown and ns.db.items ~= false) and ns.itemList(st) or {}
  -- The board's left edge and each row's top, in screen units: the buttons
  -- go there by position, not by anchor, so the board is never locked.
  local left = ns.panel:GetLeft()
  for i, it in ipairs(list) do
    local b = buttons[i] or makeButton(i)
    local top = it.row:GetTop()
    b:ClearAllPoints()
    if left and top then b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - GAP, top) end
    b.info = it
    b:SetAttribute("item", "item:" .. it.id)
    b.icon:SetTexture(it.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    b:Show()
  end
  for i = #list + 1, #buttons do
    buttons[i]:Hide()
    buttons[i].info = nil
    buttons[i]:SetAttribute("item", nil)
  end
  ns.updateItemState()
end

function ns.itemsPending() return pending end
function ns.itemButtons() return buttons end
