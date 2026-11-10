-- LootValue auto-loot: when a loot window opens, take what is worth having
-- and leave cheap junk (murloc fins and the like) on the body.
--
-- Always taken: money, quest items, green or better, cloth and other
-- gathering materials, consumables, recipes, bags, keys and reagents.
-- Everything else is taken only when its value (the best of vendor, AH and
-- disenchant, the same numbers as the tooltip line, times the stack size)
-- reaches a threshold that grows with your level (10c a level, so 2s80c at
-- level 28). With 3 or fewer free bag slots the threshold is 3x. An item
-- that fits on a stack you already carry costs no slot, so any value takes
-- it. An item we cannot judge (no item info yet) is taken.
--
-- The game's own Auto Loot must be off for this to choose, so turning
-- auto-loot on sets the autoLootDefault CVar to 0 and turning it off puts
-- the old value back. Shift (the game's auto-loot key) while you open the
-- body makes the game take everything, as before.
--
-- Modes: "review" (default) takes the good items and leaves the loot window
-- open on what it skipped, so you can click one to take it after all.
-- "quiet" closes the window and prints one chat line with what it left.
local LV = LootValue
local AL = {}
LV.autoLoot = AL

local C_GOLD, C_GREY = "|cffffd100", "|cff9d9d9d"
local R = "|r"
local PREFIX = C_GOLD .. "LootValue:" .. R .. " "

AL.PER_LEVEL = 10      -- copper of threshold per character level
AL.LOW_BAGS = 3        -- free slots at or below which the threshold rises
AL.LOW_BAGS_FACTOR = 3
AL.HISTORY = 30        -- skipped items kept for /lv skipped

-- Cloth by item ID (subclass numbers differ between clients).
local CLOTH = { [2589] = true, [2592] = true, [4306] = true, [4338] = true, [14047] = true, [14256] = true }
-- Item classes always taken: 0 consumable, 1 container, 5 reagent,
-- 9 recipe, 11 quiver, 12 quest, 13 key.
local ALWAYS_CLASS = { [0] = true, [1] = true, [5] = true, [9] = true, [11] = true, [12] = true, [13] = true }
-- Trade goods (class 7) subclasses always taken: cloth, leather,
-- metal and stone, herb, elemental, enchanting.
local ALWAYS_TRADE = { [5] = true, [6] = true, [7] = true, [9] = true, [10] = true, [12] = true }

local function db()
  LootValueDB = LootValueDB or {}
  local d = LootValueDB
  d.autoLoot = d.autoLoot or {}
  local a = d.autoLoot
  if a.enabled == nil then a.enabled = true end
  a.mode = a.mode or "review"
  a.skipped = a.skipped or {}
  return a
end
AL.db = db

local function say(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) else print(PREFIX .. msg) end end

local function getCVar(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
  return GetCVar and GetCVar(name)
end
local function setCVar(name, value)
  if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
  if SetCVar then return SetCVar(name, value) end
end

-- Copper threshold for an item that needs a new bag slot.
function AL.threshold(level, freeSlots)
  local a = db()
  local t = a.min or math.max(1, level or 1) * AL.PER_LEVEL
  if freeSlots and freeSlots <= AL.LOW_BAGS then t = t * AL.LOW_BAGS_FACTOR end
  return t
end

-- What one item is worth to you in copper: the best of the vendor price,
-- the AH after the cut (only when LootValue would advise the AH over the
-- vendor) and the disenchant value (with Enchanting). nil when unknown.
function AL.itemValue(link)
  local info = C_Item and C_Item.GetItemInfo
  if not info then return nil end
  local ok, _, _, _, _, _, _, _, _, equipLoc, _, sell = pcall(info, link)
  if not ok or type(sell) ~= "number" then return nil end
  local best = sell
  local ah = LV.call("GetAuctionPriceByItemLink", link)
  if ah and ah > 0 then
    local market = LV.marketInfo(link)
    if LV.ahWins(ah, sell, sell, market.slow) then best = math.max(best, math.floor(ah * 0.95)) end
  end
  if LV.isGear(link) and LV.knowsEnchanting() then
    local de = LV.call("GetDisenchantPriceByItemLink", link)
    if not de or de <= 0 then de = LV.estimateDisenchant(link) end
    if de and de > best then best = de end
  end
  return best
end

-- Bags: free general slots, and whether an item of this ID fits on a stack
-- you carry.
local BAGS = { 0, 1, 2, 3, 4 }
function AL.freeSlots()
  local free = 0
  local C = C_Container
  for _, bag in ipairs(BAGS) do
    local n, family
    if C and C.GetContainerNumFreeSlots then n, family = C.GetContainerNumFreeSlots(bag)
    elseif GetContainerNumFreeSlots then n, family = GetContainerNumFreeSlots(bag) end
    if n and (family == nil or family == 0) then free = free + n end
  end
  return free
end

function AL.fitsOnStack(id, quantity, maxStack)
  local C = C_Container
  if not id or not maxStack or maxStack <= 1 or not C or not C.GetContainerNumSlots then return false end
  for _, bag in ipairs(BAGS) do
    for slot = 1, C.GetContainerNumSlots(bag) or 0 do
      local it = C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
      if type(it) == "table" and it.itemID == id and (it.stackCount or 0) + (quantity or 1) <= maxStack then
        return true
      end
    end
  end
  return false
end

-- Decide one loot slot. s = { coin, link, quantity, quality, quest, locked }.
-- ctx = { level, free }. Returns take (bool), reason (string), value.
function AL.decide(s, ctx)
  if s.locked then return false, "locked" end
  if s.coin then return true, "money" end
  if s.quest then return true, "quest item" end
  if not s.link then return true, "no link" end
  local id = tonumber(s.link:match("item:(%d+)"))
  if (s.quality or 0) >= 2 then return true, "green or better" end
  if id and CLOTH[id] then return true, "cloth" end
  local info = C_Item and C_Item.GetItemInfo
  local ok, name, _, _, _, _, _, _, maxStack, _, _, sell, classID, subclassID
  if info then ok, name, _, _, _, _, _, _, maxStack, _, _, sell, classID, subclassID = pcall(info, s.link) end
  if not ok or not name then return true, "item not known yet" end
  if s.quality ~= 0 then
    if classID and ALWAYS_CLASS[classID] then return true, "useful kind" end
    if classID == 7 and subclassID and ALWAYS_TRADE[subclassID] then return true, "material" end
  end
  local value = AL.itemValue(s.link)
  if not value then return true, "no value known" end
  value = value * (s.quantity or 1)
  if AL.fitsOnStack(id, s.quantity, maxStack) then
    if value > 0 then return true, "fits on a stack", value end
    return false, "worthless", value
  end
  if ctx.free and ctx.free <= 0 then return false, "bags full", value end
  if value >= AL.threshold(ctx.level, ctx.free) then return true, "worth it", value end
  return false, "cheap", value
end

local function slotData(i)
  local texture, item, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin =
    GetLootSlotInfo(i)
  local coin = isCoin
  if coin == nil and GetLootSlotType then
    local money = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2
    coin = GetLootSlotType(i) == money
  end
  return { coin = coin, link = GetLootSlotLink and GetLootSlotLink(i), name = item, quantity = quantity,
    quality = quality, quest = isQuestItem or (questID ~= nil and questID ~= 0), locked = locked }
end

-- Run once per loot window. autoLoot: the game is taking everything itself.
local session -- { pending = {slot=true}, skipped = {...}, bagsFull = bool }
function AL.onLootReady(autoLoot)
  local a = db()
  if session or not a.enabled then return end
  session = { pending = {}, skipped = {} }
  if autoLoot then
    if not AL.warnedCVar and getCVar("autoLootDefault") == "1" then
      AL.warnedCVar = true
      say("the game's Auto Loot is on, so it takes everything. /lv autoloot on turns it off again.")
    end
    session.done = true
    return
  end
  if IsFishingLoot and IsFishingLoot() then session.done = true return end
  local ctx = { level = UnitLevel and UnitLevel("player") or 1, free = AL.freeSlots() }
  for i = 1, GetNumLootItems() do
    local s = slotData(i)
    if s.link or s.coin or s.name then
      local take, reason, value = AL.decide(s, ctx)
      if take then
        session.pending[i] = true
        LootSlot(i)
      else
        if reason == "bags full" then session.bagsFull = true end
        table.insert(session.skipped, { link = s.link or s.name, quantity = s.quantity, value = value, reason = reason })
      end
    end
  end
  for _, sk in ipairs(session.skipped) do
    table.insert(a.skipped, 1, { link = sk.link, quantity = sk.quantity, value = sk.value, reason = sk.reason,
      t = time and time() or 0 })
  end
  while #a.skipped > AL.HISTORY do table.remove(a.skipped) end
  AL.maybeClose()
end

local function skippedText(list)
  local parts = {}
  for _, sk in ipairs(list) do
    local q = (sk.quantity and sk.quantity > 1) and (" x" .. sk.quantity) or ""
    local v = sk.value and (C_GREY .. " " .. LV.money(sk.value) .. R) or ""
    local why = sk.reason ~= "cheap" and (C_GREY .. " (" .. sk.reason .. ")" .. R) or ""
    table.insert(parts, tostring(sk.link) .. q .. v .. why)
  end
  return table.concat(parts, ", ")
end
AL.skippedText = skippedText

-- In quiet mode, close the window once every item we took is in the bags.
-- Never close while a wanted item is still there (bags full, a bind
-- confirmation, a slow server).
function AL.maybeClose()
  if not session or session.done or next(session.pending) then return end
  session.done = true
  if #session.skipped == 0 then return end
  if db().mode == "quiet" and not session.bagsFull then
    say("left " .. skippedText(session.skipped) .. C_GREY .. "  (Shift+loot takes all)" .. R)
    CloseLoot()
  end
end

function AL.onSlotCleared(slot)
  if not session then return end
  session.pending[slot] = nil
  AL.maybeClose()
end

function AL.onLootClosed() session = nil end

-- Turn on or off, setting the game's Auto Loot CVar to match.
function AL.setEnabled(on)
  local a = db()
  a.enabled = on
  if on then
    local cur = getCVar("autoLootDefault")
    if cur == "1" then
      a.savedCVar = cur
      setCVar("autoLootDefault", "0")
      say("auto-loot on. It turned off the game's Auto Loot so it can choose; Shift+loot takes everything.")
    end
  elseif a.savedCVar then
    setCVar("autoLootDefault", a.savedCVar)
    a.savedCVar = nil
  end
end

function AL.status()
  local a = db()
  local lvl = UnitLevel and UnitLevel("player") or 1
  return string.format("auto-loot %s, mode %s, leaves items under %s%s. /lv autoloot on|off|review|quiet|min 3s|min auto, /lv skipped, /lv sales",
    a.enabled and "on" or "off", a.mode, LV.money(AL.threshold(lvl, 99)), a.min and " (set)" or " (10c a level)")
end

-- "3s", "1g50s", "75c" or a plain number of copper.
function AL.parseMoney(text)
  text = (text or ""):lower():gsub("%s", "")
  if text:match("^%d+$") then return tonumber(text) end
  local total, any = 0, false
  for n, unit in text:gmatch("(%d+)([gsc])") do
    any = true
    total = total + tonumber(n) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
  end
  return any and total or nil
end

function AL.slash(msg)
  local a = db()
  local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "sales" and LV.sales then LV.sales.slash(rest) return end
  if cmd == "skipped" then
    if #a.skipped == 0 then say("nothing skipped yet.") return end
    local recent = {}
    for i = 1, math.min(10, #a.skipped) do recent[i] = a.skipped[i] end
    say("last skipped: " .. skippedText(recent))
    return
  end
  if cmd ~= "autoloot" and cmd ~= "al" then say(AL.status()) return end
  local sub, arg = rest:match("^(%S*)%s*(.-)$")
  if sub == "on" then AL.setEnabled(true)
  elseif sub == "off" then AL.setEnabled(false)
  elseif sub == "review" or sub == "quiet" then a.mode = sub
  elseif sub == "min" then
    if arg == "auto" or arg == "" then a.min = nil
    else
      local c = AL.parseMoney(arg)
      if not c then say("min wants an amount such as 3s or 1g.") return end
      a.min = c
    end
  elseif sub ~= "" then say("unknown: " .. sub) end
  say(AL.status())
end

SLASH_LOOTVALUE1 = "/lv"
SLASH_LOOTVALUE2 = "/lootvalue"
SlashCmdList = SlashCmdList or {}
SlashCmdList.LOOTVALUE = AL.slash

local f = CreateFrame and CreateFrame("Frame")
if f then
  f:RegisterEvent("PLAYER_LOGIN")
  f:RegisterEvent("LOOT_READY")
  f:RegisterEvent("LOOT_OPENED")
  f:RegisterEvent("LOOT_SLOT_CLEARED")
  f:RegisterEvent("LOOT_CLOSED")
  f:SetScript("OnEvent", function(_, event, arg1)
    local ok, err = pcall(function()
      if event == "PLAYER_LOGIN" then
        local a = db()
        if a.enabled then
          if not a.introduced then
            a.introduced = true
            say("auto-loot is on: it leaves cheap junk on the body. " .. AL.status())
          end
          AL.setEnabled(true)
        end
      elseif event == "LOOT_READY" or event == "LOOT_OPENED" then AL.onLootReady(arg1)
      elseif event == "LOOT_SLOT_CLEARED" then AL.onSlotCleared(arg1)
      elseif event == "LOOT_CLOSED" then AL.onLootClosed() end
    end)
    if not ok and not AL.reported then
      AL.reported = true
      say("auto-loot error: " .. tostring(err))
    end
  end)
end
