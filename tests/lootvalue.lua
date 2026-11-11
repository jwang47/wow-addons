-- Offline tests for LootValue with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/lootvalue.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/lootvalue%.lua$") or ""
local failures = 0
local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function has(s, part) return s ~= nil and strip(s):find(part, 1, true) ~= nil end

-- Mock state ----------------------------------------------------------------
_G.time = os.time
local SKILLS = { { "Professions", true }, { "Tailoring", false, nil, 100 } }
function GetNumSkillLines() return #SKILLS end
function GetSkillLineInfo(i) return unpack(SKILLS[i]) end

-- id -> { quality, item level, sell price, class, stack, equip slot }
local ITEMS = {
  [9001] = { 2, 22, 800, 4, 1, "INVTYPE_CHEST" },     -- green robe
  [9002] = { 3, 24, 500, 4, 1, "INVTYPE_HEAD" },      -- blue helm
  [9003] = { 1, 10, 24, 7, 20, "" },                   -- trade good
}
local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end
C_Item = {
  GetItemInfo = function(link)
    local it = ITEMS[idOf(link)]
    if not it then return nil end
    return "Item", link, it[1], it[2], 1, "", "", it[5], it[6], 0, it[3], it[4]
  end,
  GetItemInfoInstant = function(link)
    local it = ITEMS[idOf(link)]
    if it then return idOf(link), "", "", it[6] end
  end,
  GetItemMaxStackCount = function(link) local it = ITEMS[idOf(link)] return it and it[5] end,
}

local AH, DE, AGE, HIST = { [9001] = 4500, [9003] = 353, [10978] = 800 }, {}, {}, {}
local SAVED = {}
Auctionator = {
  API = { v1 = {
    GetAuctionPriceByItemLink = function(caller, link) assert(caller == "LootValue") return AH[idOf(link)] end,
    GetAuctionPriceByItemID = function(caller, id) assert(caller == "LootValue") return AH[id] end,
    GetDisenchantPriceByItemLink = function(_, link) return DE[idOf(link)] end,
    -- What a vendor charges, not what it pays: LootValue must not use it.
    GetVendorPriceByItemLink = function() return 90000 end,
    GetVendorPriceByItemID = function() return 90000 end,
    GetAuctionAgeByItemLink = function(_, link) return AGE[idOf(link)] end,
  } },
  Database = { GetPriceHistory = function(_, key) return HIST[key] end },
  Utilities = { BasicDBKeyFromLink = function(link) return idOf(link) end },
  SavedState = SAVED,
}
local hooked
GameTooltip = { HookScript = function(_, _, fn) hooked = fn end }

assert(loadfile(root .. "LootValue/LootValue.lua"))("LootValue", {})
local LV = LootValue
local CTX = { bound = false }

-- Money and the AH rule --------------------------------------------------
check("money format", LV.money(19100) == "1g91s" and LV.money(2900) == "29s" and LV.money(205) == "2s5c"
  and LV.money(50) == "50c")
check("ahWins: no sure option", LV.ahWins(100, nil, 0, true))
check("ahWins: needs 1s more", not LV.ahWins(190, 0, 90, false) and LV.ahWins(200, 0, 90, false))
check("ahWins: slow market needs 2x", LV.ahWins(400, 0, 250, false) and not LV.ahWins(400, 0, 250, true))

-- Advice line --------------------------------------------------------------
local robe = LV.adviceLine("|Hitem:9001:0|h", true, CTX)
check("vendor is the game's sell price, not Auctionator's buy price", has(robe, "(or vendor 8s")
  and not has(robe, "9g"))
check("no Enchanting: AH beats vendor", has(robe, "LootValue: AH ~42s") and has(robe, "(or vendor 8s)"))
check("bound copy: no AH option", LV.adviceLine("|Hitem:9001:0|h", true, { bound = true }) == nil)
check("without tooltip context the AH says if tradable", has(LV.adviceLine("|Hitem:9001:0|h", true), "AH if tradable"))

table.insert(SKILLS, { "Enchanting", false, nil, 50 })
DE[9001] = 3000
robe = LV.adviceLine("|Hitem:9001:0|h", true, CTX)
check("AH needs a clear margin over disenchant", has(robe, "LootValue: Disenchant ~30s")
  and has(robe, "(or AH 42s, vendor 8s)"))
DE[9001] = nil
check("unknown disenchant price is shown", has(LV.adviceLine("|Hitem:9001:0|h", true, CTX), "disenchant: no price"))
check("blue gives a shard estimate", LV.estimateDisenchant("|Hitem:9002:0|h") == 800)
check("blue helm: disenchant from the estimate", has(LV.adviceLine("|Hitem:9002:0|h", true, CTX), "LootValue: Disenchant ~8s"))
check("no Auctionator data at all: no line", LV.adviceLine("|Hitem:7777:0|h", false, CTX) == nil)

-- Market notes ---------------------------------------------------------------
HIST[9003] = { { available = 999, minSeen = 300 }, { available = 900, minSeen = 400 } }
local info = LV.marketInfo("|Hitem:9003:0|h")
check("listed counts full stacks", info.listed == 999 and info.note == "price falling")
HIST[9003][1].available = 1000
check("50 full stacks is slow", has(LV.marketInfo("|Hitem:9003:0|h").note, "slow: 1000 listed"))
HIST[9003] = nil
AGE[9003] = 4
check("old price noted", LV.marketInfo("|Hitem:9003:0|h").note == "price 4 days old")
AGE[9003] = nil
check("cheap item, AH pays 14x the vendor", has(LV.adviceLine("|Hitem:9003:0|h", false, CTX), "LootValue: AH ~3s35c"))

-- Scan age -------------------------------------------------------------------
check("no scan time: nothing shown", LV.scanText() == nil and has(robe, "AH 42s") and not has(robe, "AH scan"))
SAVED.TimeOfLastGetAllScan = os.time() - 3 * 3600 - 5
SAVED.TimeOfLastBrowseScan = os.time() - 5 * 3600
check("newest full scan as an age", LV.scanText() == "AH full scan 3h ago")
check("scan age on a line with an AH price", has(LV.adviceLine("|Hitem:9001:0|h", true, CTX), "· AH full scan 3h ago"))
-- A full scan since midnight that did not see the item: its price is old,
-- and yesterday's listings and trend no longer count.
local realMidnight = LV.midnight
LV.midnight = function() return os.time() - 4 * 3600 end
AGE[9003], HIST[9003] = 1, { { available = 9999, minSeen = 300 }, { minSeen = 400 } }
local mi = LV.marketInfo("|Hitem:9003:0|h")
check("not in today's full scan", mi.unlisted and mi.note == "not in today's full scan" and mi.slow)
LV.midnight = function() return os.time() - 2 * 3600 end
check("full scan before midnight: the old notes", LV.marketInfo("|Hitem:9003:0|h").note == "slow: 9999 listed, price falling")
AGE[9003], HIST[9003], LV.midnight = nil, nil, realMidnight
check("midnight is today", LV.midnight() <= os.time() and LV.midnight() > os.time() - 86400)
check("age wording", LV.ago(os.time() - 30) == "just now" and LV.ago(os.time() - 600) == "10m ago"
  and LV.ago(os.time() - 2 * 86400) == "2d ago")

-- Tooltip hook -----------------------------------------------------------------
local lines = {}
local tip = { GetName = function() return "GameTooltip" end, NumLines = function() return 0 end,
  GetItem = function() return "Robe", "|Hitem:9001:0|h" end,
  AddLine = function(_, l) table.insert(lines, l) end, Show = function() end }
check("hooks the game tooltip", hooked ~= nil)
hooked(tip)
check("tooltip gets one LootValue line", #lines == 1 and has(lines[1], "LootValue:"))
LV.deferTo = "MageMentor"
hooked(tip)
check("quiet when MageMentor draws the line", #lines == 1)
LV.deferTo = nil
check("isGear: robe yes, trade good no", LV.isGear("item:9001") and not LV.isGear("item:9003"))

-- Auto-loot -------------------------------------------------------------------
local handlers, cvars, chat = {}, { autoLootDefault = "1" }, {}
CreateFrame = function()
  local fr = {}
  function fr:RegisterEvent(e) handlers[e] = true end
  function fr:SetScript(_, fn) fr.onEvent = fn end
  _G.LAST_FRAME = fr
  return fr
end
C_CVar = { GetCVar = function(n) return cvars[n] end, SetCVar = function(n, v) cvars[n] = v end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, m) end }
local level, free = 28, 10
UnitLevel = function() return level end
local BAG = {} -- bag 0 slots: { itemID, stackCount }
C_Container = {
  GetContainerNumFreeSlots = function(bag) return bag == 0 and free or 0, 0 end,
  GetContainerNumSlots = function(bag) return bag == 0 and #BAG or 0 end,
  GetContainerItemInfo = function(bag, slot) return bag == 0 and BAG[slot] or nil end,
}
-- id -> { quality, item level, sell price, class, stack, equip slot, subclass }
ITEMS[1468] = { 0, 15, 6, 15, 10, "", 0 }         -- murloc fin, grey junk
ITEMS[730] = { 1, 15, 14, 7, 10, "", 8 }          -- murloc eye, white meat
ITEMS[2589] = { 1, 5, 13, 7, 20, "", 5 }          -- linen cloth
ITEMS[4306] = { 1, 25, 150, 7, 20, "", 0 }        -- silk, subclass 0 on some clients
ITEMS[3000] = { 0, 27, 900, 2, 1, "INVTYPE_WEAPON", 0 } -- grey sword, 9s
ITEMS[3001] = { 1, 25, 25, 0, 20, "", 0 }         -- white potion
local baseInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(link)
  local it = ITEMS[idOf(link)]
  if not it then return nil end
  return "Item", link, it[1], it[2], 1, "", "", it[5], it[6], 0, it[3], it[4], it[7] or 0
end
assert(baseInfo)
LootValueDB = nil
assert(loadfile(root .. "LootValue/AutoLoot.lua"))("LootValue", {})
local AL = LV.autoLoot
local frame = LAST_FRAME
local function link(id) return "|Hitem:" .. id .. ":0|h[x]|h" end
local CTX28 = { level = 28, free = 10 }
local function decide(id, q, extra)
  local s = { link = link(id), quantity = q or 1, quality = ITEMS[id] and ITEMS[id][1] or 1 }
  for k, v in pairs(extra or {}) do s[k] = v end
  return AL.decide(s, CTX28)
end
check("threshold is 10c a level", AL.threshold(28, 10) == 280 and AL.threshold(28, 3) == 840)
check("money and quest items always", AL.decide({ coin = true }, CTX28) and decide(1468, 1, { quest = true }))
check("locked slots are left", not AL.decide({ coin = true, locked = true }, CTX28))
check("murloc fin left", not decide(1468, 2))
check("murloc eye left", not decide(730, 3))
check("cloth taken by ID", decide(2589) and decide(4306))
check("green taken", decide(9001, 1, { quality = 2 }))
check("grey sword worth 9s taken", decide(3000))
check("white potion taken", decide(3001))
check("unknown item taken", decide(5555))
BAG[1] = { itemID = 1468, stackCount = 4 }
check("fits on a carried stack: taken", decide(1468, 2))
BAG[1] = { itemID = 1468, stackCount = 9 }
check("full stack: left", not decide(1468, 2))
BAG[1] = nil
local _, why = AL.decide({ link = link(3000), quantity = 1, quality = 0 }, { level = 28, free = 0 })
check("bags full: left with a reason", why == "bags full")
AH[730] = 2000
check("AH price that clearly wins counts", decide(730, 1))
AH[730] = nil
check("money parse", AL.parseMoney("1g50s") == 15000 and AL.parseMoney("75c") == 75 and AL.parseMoney("3s") == 300
  and AL.parseMoney("x") == nil)

-- Event flow: login turns the game's Auto Loot off; a loot window takes the
-- good slots and leaves the rest.
check("listens to loot events", handlers.LOOT_READY and handlers.LOOT_SLOT_CLEARED and handlers.PLAYER_LOGIN)
frame.onEvent(frame, "PLAYER_LOGIN")
check("login turns the game's Auto Loot off and saves it", cvars.autoLootDefault == "0"
  and LootValueDB.autoLoot.savedCVar == "1")
local LOOT, looted, closed = {}, {}, 0
GetNumLootItems = function() return #LOOT end
GetLootSlotInfo = function(i) local l = LOOT[i]
  return "tex", l.name or "Item", l.q or 1, nil, l.quality or 1, false, l.quest or false, nil, true, l.coin or false end
GetLootSlotLink = function(i) return LOOT[i].link end
LootSlot = function(i) table.insert(looted, i) end
CloseLoot = function() closed = closed + 1 end
IsFishingLoot = function() return false end
local function loot(list)
  LOOT, looted = list, {}
  frame.onEvent(frame, "LOOT_READY", false)
  frame.onEvent(frame, "LOOT_OPENED", false)
end
loot({ { coin = true, name = "5 Silver" }, { link = link(1468), quality = 0, q = 2 }, { link = link(2589), q = 2 } })
check("takes money and cloth, leaves fins, once per window", #looted == 2 and looted[1] == 1 and looted[2] == 3)
frame.onEvent(frame, "LOOT_SLOT_CLEARED", 1)
frame.onEvent(frame, "LOOT_SLOT_CLEARED", 3)
check("review mode keeps the window open", closed == 0)
check("skipped is remembered", LootValueDB.autoLoot.skipped[1].link == link(1468))
frame.onEvent(frame, "LOOT_CLOSED")
AL.slash("autoloot quiet")
loot({ { coin = true, name = "5 Silver" }, { link = link(1468), quality = 0, q = 2 } })
check("quiet mode waits for the taken slot", closed == 0)
frame.onEvent(frame, "LOOT_SLOT_CLEARED", 1)
check("quiet mode closes and says what it left", closed == 1 and has(chat[#chat], "left |Hitem:1468"))
frame.onEvent(frame, "LOOT_CLOSED")
LOOT, looted = { { link = link(1468), quality = 0 } }, {}
frame.onEvent(frame, "LOOT_READY", true)
check("autoloot flag: takes nothing itself", #looted == 0)
frame.onEvent(frame, "LOOT_CLOSED")
AL.slash("autoloot min 1c")
loot({ { link = link(1468), quality = 0 } })
check("own minimum", #looted == 1)
frame.onEvent(frame, "LOOT_CLOSED")
AL.slash("autoloot off")
check("off puts the game's Auto Loot back", cvars.autoLootDefault == "1")
loot({ { link = link(1468), quality = 0 } })
check("off: takes nothing", #looted == 0)
AL.slash("skipped")
check("/lv skipped lists items", has(chat[#chat], "last skipped:"))

-- A recipe tooltip: GetItem gives the made item, the first line names the recipe.
do
  ITEMS[9010] = { 1, 20, 400, 9, 1, "" }
  local realInfo = C_Item.GetItemInfo
  C_Item.GetItemInfo = function(x)
    if x == "Pattern: Robe" or x == 9010 then return "Pattern: Robe", "|Hitem:9010:0|h[Pattern: Robe]|h" end
    return realInfo(x)
  end
  local first = { GetText = function() return "Pattern: Robe" end }
  rawset(_G, "RecipeTipTextLeft1", first)
  local tipR = { GetName = function() return "RecipeTip" end, GetItem = function() return "Robe", "|Hitem:9001:0|h[Robe]|h" end }
  check("recipe tooltip: the recipe, not the made item", LV.tooltipLink(tipR) == "|Hitem:9010:0|h[Pattern: Robe]|h")
  check("recipe tooltip: the data id works too", LV.tooltipLink(tipR, { id = 9010 }) == "|Hitem:9010:0|h[Pattern: Robe]|h")
  first.GetText = function() return "Pattern: Unknown" end
  check("recipe tooltip: unknown recipe, nothing", LV.tooltipLink(tipR) == nil)
  first.GetText = function() return "Robe" end
  check("plain tooltip: its own item", LV.tooltipLink(tipR) == "|Hitem:9001:0|h[Robe]|h")
  C_Item.GetItemInfo = realInfo
end

-- Clear bags ------------------------------------------------------------------
do
  -- A frame that takes any call; scripts, attributes, text and shown are kept.
  local frames, events = {}, {}
  local function stub(name)
    local fr = { scripts = {}, attrs = {}, shown = true, name = name }
    local methods = {
      SetScript = function(self, k, fn) self.scripts[k] = fn end,
      HookScript = function(self, k, fn) self.scripts[k] = fn end,
      RegisterEvent = function(self, e) events[e] = self end,
      SetAttribute = function(self, k, v) self.attrs[k] = v end,
      SetText = function(self, t) self.text = t end,
      Show = function(self) self.shown = true end,
      Hide = function(self) self.shown = false end,
      IsShown = function(self) return self.shown end,
      SetEnabled = function(self, on) self.enabled = on end,
      CreateFontString = function() return stub() end,
      CreateTexture = function() return stub() end,
      GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
    }
    return setmetatable(fr, { __index = function(_, k) return methods[k] or function() end end })
  end
  CreateFrame = function(_, name)
    local fr = stub(name)
    if name then frames[name] = fr end
    return fr
  end
  UIParent = stub("UIParent")
  local combat = false
  InCombatLockdown = function() return combat end
  C_Timer = nil

  -- Bags: bag 0 slots hold { itemID, stackCount, quality, isBound, isLocked }.
  local used = {}
  for k in pairs(BAG) do BAG[k] = nil end
  C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 12 or 0 end
  C_Container.GetContainerItemInfo = function(bag, slot)
    local it = bag == 0 and BAG[slot]
    if not it then return nil end
    return { itemID = it.itemID, stackCount = it.stackCount or 1, quality = ITEMS[it.itemID][1], isBound = it.bound,
      isLocked = it.locked, hyperlink = link(it.itemID) }
  end
  C_Container.UseContainerItem = function(bag, slot)
    table.insert(used, BAG[slot].itemID)
    BAG[slot] = nil
  end
  local WORN = {}
  GetInventoryItemLink = function(_, slot) return WORN[slot] and link(WORN[slot]) end

  ITEMS[9101] = { 2, 20, 700, 4, 1, "INVTYPE_FEET", 1 }    -- green boots, no AH price: vendor
  ITEMS[9102] = { 2, 31, 900, 4, 1, "INVTYPE_FEET", 1 }    -- better boots than worn
  ITEMS[9103] = { 2, 28, 1200, 4, 1, "INVTYPE_FEET", 1 }   -- the boots you wear
  ITEMS[9104] = { 4, 30, 5000, 4, 1, "INVTYPE_HEAD", 1 }   -- epic
  ITEMS[9105] = { 1, 25, 300, 12, 1, "", 0 }               -- quest item
  ITEMS[9106] = { 2, 21, 600, 4, 1, "INVTYPE_HEAD", 1 }    -- green helm to disenchant
  AH[9101], AH[9001], DE[9001] = nil, 4500, nil
  WORN[8], WORN[1] = 9103, 9103
  LootValueDB = nil
  assert(loadfile(root .. "LootValue/Clear.lua"))("LootValue", {})
  local CL = LV.clear
  local function item(id, extra)
    local it = { id = id, link = link(id), count = 1, quality = ITEMS[id][1], bag = 0, slot = 1 }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
  end
  -- No Enchanting in this block until said.
  for i = #SKILLS, 1, -1 do if SKILLS[i][1] == "Enchanting" then table.remove(SKILLS, i) end end

  local r = CL.classify(item(1468, { count = 5 }))
  check("clear: grey junk goes to the vendor, ticked", r.kind == "vendor" and r.on and r.grey and r.value == 30)
  r = CL.classify(item(9101))
  check("clear: gear below what you wear is ticked for the vendor", r.kind == "vendor" and r.on and r.value == 700)
  r = CL.classify(item(9102))
  check("clear: gear above what you wear is not ticked", r.kind == "vendor" and not r.on
    and r.why == "item level 31, you wear 28")
  WORN[8] = nil
  check("clear: an empty slot counts as an upgrade", CL.classify(item(9101)).why == "that slot is empty")
  WORN[8] = 9103
  check("clear: epics and quest items are never listed", CL.classify(item(9104)) == nil
    and CL.classify(item(9105)) == nil)
  check("clear: a locked slot is not listed", CL.classify(item(1468, { locked = true })) == nil)
  check("clear: cloth, potions and other non-gear are not sold", CL.classify(item(2589)) == nil
    and CL.classify(item(3001)) == nil)
  r = CL.classify(item(9001))
  check("clear: an unbound item the AH pays more for goes to the AH list", r.kind == "ah" and r.value == 4275)
  r = CL.classify(item(9001, { bound = true }))
  check("clear: the bound copy goes to the vendor", r.kind == "vendor" and r.value == 800)
  table.insert(SKILLS, { "Enchanting", false, nil, 50 })
  DE[9106] = 2500
  r = CL.classify(item(9106))
  check("clear: with Enchanting, gear worth more as dust is disenchanted", r.kind == "de" and r.on and r.value == 2500)

  -- Your own ticks are kept per item.
  CL.toggle(CL.classify(item(9102)))
  check("clear: ticking an upgrade row sells it", CL.classify(item(9102)).on)
  CL.toggle(CL.classify(item(9102)))
  check("clear: unticking keeps it for good", not CL.classify(item(9102)).on and LootValueDB.clear.choice[9102] == "keep")
  CL.toggle(CL.classify(item(1468)))
  check("clear: a grey item can be kept", not CL.classify(item(1468)).on)
  CL.toggle(CL.classify(item(1468)))
  check("clear: and sold again", CL.classify(item(1468)).on and LootValueDB.clear.choice[1468] == nil)

  -- Scan, totals and the panel lines.
  BAG[1] = { itemID = 1468, stackCount = 5 }
  BAG[2] = { itemID = 9101 }
  BAG[3] = { itemID = 9102 }
  BAG[4] = { itemID = 9001 }
  BAG[5] = { itemID = 9001 }
  BAG[6] = { itemID = 9106 }
  BAG[7] = { itemID = 2589, stackCount = 20 }
  local rows = CL.scan()
  local t = CL.totals(rows)
  check("clear: scan lists vendor, disenchant and AH rows", #rows == 5 and rows[1].kind == "vendor" and rows[1].id == 9101
    and rows[3].id == 9102 and rows[4].kind == "de" and rows[5].kind == "ah")
  check("clear: two AH stacks are one row", rows[5].count == 2 and rows[5].value == 8550)
  check("clear: totals count ticked rows only", t.vendor.n == 2 and t.vendor.value == 730 and t.de.n == 1 and t.ah.n == 1)
  local shown = CL.display(rows, "merchant")
  check("clear: the merchant view has no AH list", #shown == 6 and has(shown[1].header, "Vendor: 2 items, 7s30c")
    and has(shown[5].header, "Disenchant: 1 item, ~25s"))
  shown = CL.display(rows, "ah")
  check("clear: the AH view has only the AH list", #shown == 2 and has(shown[1].header, "Auction House: 1 item, ~85s after the cut"))
  check("clear: the disenchant macro names the bag slot", CL.disenchantMacro(CL.nextDisenchant(rows))
    == "/cast Disenchant\n/use 0 6")

  -- One press sells every grey item and at most 12 others.
  local many = {}
  for i = 1, 15 do many[i] = { kind = "vendor", on = true, value = 1, id = i } end
  many[16] = { kind = "vendor", on = true, grey = true, value = 1, id = 16 }
  many[17] = { kind = "vendor", on = false, value = 1, id = 17 }
  local queue, left = CL.sellQueue(many)
  check("clear: sells grey first, then 12 others", #queue == 13 and queue[1].id == 16 and left == 3)

  -- The merchant flow.
  CL.sell()
  check("clear: no selling away from a merchant", #used == 0 and has(chat[#chat], "open a merchant first"))
  events.MERCHANT_SHOW.scripts.OnEvent(nil, "MERCHANT_SHOW")
  local panel = frames.LootValueClearFrame
  check("clear: the panel opens at a merchant", panel ~= nil and panel:IsShown())
  local deBtn = frames.LootValueDisenchantButton
  check("clear: the disenchant button is a secure down-click macro", deBtn.attrs.type == "macro"
    and deBtn.attrs.pressAndHoldAction == true and deBtn.attrs.macrotext == "/cast Disenchant\n/use 0 6")
  BAG[2] = { itemID = 9101, locked = true }
  BAG[8] = { itemID = 9101 }
  CL.sell()
  check("clear: Sell sells the ticked vendor rows only", #used == 2 and used[1] == 1468 and used[2] == 9101
    and BAG[3] ~= nil and BAG[4] ~= nil and BAG[6] ~= nil and BAG[7] ~= nil and BAG[2] ~= nil)
  check("clear: it says what it sold", has(chat[#chat], "sold 2 items for 7s30c"))
  combat = true
  events.PLAYER_REGEN_DISABLED.scripts.OnEvent(nil, "PLAYER_REGEN_DISABLED")
  check("clear: the panel hides when combat starts", not panel:IsShown())
  check("clear: it does not open in combat", CL.show("all") == false and not panel:IsShown())
  combat = false
  events.MERCHANT_CLOSED.scripts.OnEvent(nil, "MERCHANT_CLOSED")
  AL.slash("clear")
  check("/lv clear opens the panel", panel:IsShown())
  AL.slash("clear auto")
  BAG[1] = { itemID = 1468 }
  CL.hide()
  events.MERCHANT_SHOW.scripts.OnEvent(nil, "MERCHANT_SHOW")
  check("/lv clear auto: no longer opens by itself", not panel:IsShown() and LootValueDB.clear.auto == false)
  events.MERCHANT_CLOSED.scripts.OnEvent(nil, "MERCHANT_CLOSED")
end

if failures > 0 then error(failures .. " LootValue test(s) failed") end
print("all LootValue tests passed")
