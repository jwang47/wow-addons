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

if failures > 0 then error(failures .. " LootValue test(s) failed") end
print("all LootValue tests passed")
