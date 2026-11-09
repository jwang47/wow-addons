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
    GetVendorPriceByItemLink = function() return nil end,  -- falls back to C_Item's sell price
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
check("newest scan as an age", LV.scanText() == "AH scan 3h ago")
check("scan age on a line with an AH price", has(LV.adviceLine("|Hitem:9001:0|h", true, CTX), "· AH scan 3h ago"))
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

if failures > 0 then error(failures .. " LootValue test(s) failed") end
print("all LootValue tests passed")
