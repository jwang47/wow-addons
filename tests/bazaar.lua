-- Offline tests for Bazaar with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/bazaar.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/bazaar%.lua$") or ""
local failures = 0
local function check(name, ok, detail)
  if not ok then
    failures = failures + 1
    print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
  else
    print("ok   " .. name)
  end
end

local function widget(name)
  local w = { scripts = {}, shown = true, name = name, text = "", events = {} }
  function w:SetScript(what, fn) self.scripts[what] = fn end
  function w:GetScript(what) return self.scripts[what] end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:IsShown() return self.shown end
  function w:SetText(t) self.text = t end
  function w:GetText() return self.text end
  function w:CreateTexture() return widget() end
  function w:CreateFontString() return widget() end
  function w:RegisterEvent(e) self.events[e] = true end
  function w:SetTexture(t) self.texture = t end
  return setmetatable(w, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end
function CreateFrame(_, name)
  local f = widget(name)
  if name then _G[name] = f end
  return f
end
UIParent, GameTooltip = widget("UIParent"), widget("GameTooltip")
UISpecialFrames, SlashCmdList = {}, {}
function time() return 100000 end
local clock = 0
function debugprofilestop() clock = clock + 1 return clock end
local timers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }

-- Items: 1 Linen Bag (bag), 2 Small Silk Pack (bag), 3 Silk Cloth (trade
-- goods), 4 an item whose name has not loaded yet (gear).
local ITEMS = {
  [1] = { "Linen Bag", 1, 5, 0, 1, 0 }, [2] = { "Small Silk Pack", 2, 20, 0, 1, 0 },
  [3] = { "Silk Cloth", 1, 1, 0, 7, 5 }, [4] = { "Thick Bracers", 2, 25, 20, 4, 2 },
}
local loaded = { [1] = true, [2] = true, [3] = true }
local requested = {}
C_Item = {
  GetItemInfo = function(id)
    local it = loaded[id] and ITEMS[id]
    if not it then return nil end
    return it[1], "|Hitem:" .. id .. "|h", it[2], it[3], it[4], "", "", 20, "", "icon" .. id, 0, it[5], it[6]
  end,
  GetItemInfoInstant = function(id) local it = ITEMS[id] return id, "", "", "", "icon" .. id, it and it[5], it and it[6] end,
  RequestLoadItemDataByID = function(id) requested[id] = true end,
  GetItemClassInfo = function(c) return ({ [1] = "Container", [4] = "Armor", [7] = "Trade Goods" })[c] end,
  GetItemSubClassInfo = function(c, s) return ({ [1] = { [0] = "Bag" }, [4] = { [2] = "Leather" }, [7] = { [5] = "Cloth" } })[c][s] end,
}

-- LootValue's full scan: "owner,count,buyout,band;..." per item.
LootValueDB = { snap = { t = 100000 - 3 * 3600, n = 6, owners = { "Ann", "Bo" }, items = {
  [1] = "1,1,5000,4;2,1,4000,3", [2] = "1,1,30000,4", [3] = "1,20,2000,4;2,10,1500,2", [4] = "2,1,90000,4",
} } }
LootValue = { scan = {
  decode = function(str, owners)
    local list = {}
    for o, c, b, t in str:gmatch("(%d+),(%d+),(%d+),(%d+)") do
      table.insert(list, { owners[tonumber(o)] or "", tonumber(c), tonumber(b), tonumber(t) })
    end
    return list
  end,
  price = function(id) return ({ [1] = 4500, [3] = 120 })[id] end,
  stats = function(id) return ({ [1] = { sold = 4 }, [2] = { sold = 0 }, [3] = { sold = 60 } })[id] end,
} }

local function load(file)
  local chunk = assert(loadfile(root .. file))
  chunk("Bazaar", {})
end
load("Bazaar/Core.lua")
load("Bazaar/UI.lua")
local B = Bazaar

-- Rows from the scan.
B.SLICE = 1
local b = B.begin()
check("the build runs in slices", B.step(0) == false and select(1, B.progress()) == 1)
B.buildAll()
local byID = B.current().byID
check("cheapest buyout per item and items listed", byID[1].min == 4000 and byID[1].listed == 2
  and byID[3].min == 100 and byID[3].listed == 30, byID[3].min)
check("fair price and sales from LootValue", byID[1].fair == 4500 and byID[3].sold == 60 and byID[4].sold == nil)
check("a name not loaded yet asks the server", byID[4].name == "item 4" and requested[4] and byID[4].classID == 4)

-- Filters and sorting.
local function names(list)
  local out = {}
  for _, r in ipairs(list) do table.insert(out, r.name) end
  return table.concat(out, ",")
end
check("default: most sold first, unknown sales last", names(B.query({}, "sold", true)) == "Silk Cloth,Linen Bag,Small Silk Pack,item 4")
check("search words", names(B.query({ text = "silk" }, "name")) == "Silk Cloth,Small Silk Pack")
check("category", names(B.query({ classID = 1 }, "min")) == "Linen Bag,Small Silk Pack")
check("subclass", names(B.query({ classID = 7, subclassID = 5 }, "min")) == "Silk Cloth")
check("cheapest first", names(B.query({}, "min")) == "Silk Cloth,Linen Bag,Small Silk Pack,item 4")
check("max price", names(B.query({ maxPrice = 10000 }, "min")) == "Silk Cloth,Linen Bag")
loaded[4] = true
check("an item that loads fills its row", B.fillName(4) and byID[4].name == "Thick Bracers" and byID[4].req == 20)
check("required level", names(B.query({ minReq = 10, maxReq = 30 }, "name")) == "Thick Bracers")
local cats = B.categories()
check("categories with counts and subclasses", #cats == 3 and cats[1].name == "Armor" and cats[2].name == "Container"
  and cats[2].count == 2 and cats[3].subs[1].name == "Cloth")
check("footer names the scan and its age", B.sourceText():find("Full scan 3h ago: 6 auctions of 4 items", 1, true) ~= nil,
  B.sourceText())

-- The window.
SlashCmdList.BAZAAR("silk")
check("/bazaar silk opens the window with the search", BazaarFrame:IsShown() and BazaarFrame.search:GetText() == "silk")
check("the status line counts what is shown", BazaarFrame.status:GetText():find("2 shown") ~= nil, BazaarFrame.status:GetText())
SlashCmdList.BAZAAR("")
check("/bazaar again closes it", not BazaarFrame:IsShown())
check("Esc closes it", UISpecialFrames[1] == "BazaarFrame")
B.money(0)
check("money", B.money(12345) == "1g 23s" and B.money(150) == "1s 50c" and B.money(7) == "7c")

-- Without a LootValue scan: Auctionator's prices.
LootValue, LootValueDB = nil, nil
Auctionator = { Database = { db = { ["3"] = {}, ["1"] = {} } },
  API = { v1 = { GetAuctionPriceByItemID = function(_, id) return ({ [3] = 90 })[id] end } } }
B.buildAll()
check("Auctionator fallback: items with a price", #B.current().rows == 1 and B.current().rows[1].min == 90
  and B.sourceText():find("Auctionator prices only") ~= nil)

if failures > 0 then
  print(failures .. " FAILED")
  os.exit(1)
end
print("all Bazaar tests passed")
