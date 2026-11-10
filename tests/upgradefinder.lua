-- Offline tests for UpgradeFinder with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/upgradefinder.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/upgradefinder%.lua$") or ""
local failures, chat, calls = 0, {}, {}
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end

-- Generic widget: capitalised unknown methods are no-ops.
local function widget(name)
  local w = { scripts = {}, shown = false, name = name }
  function w:SetScript(what, fn) self.scripts[what] = fn end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:IsShown() return self.shown end
  function w:SetText(t) self.text = t end
  function w:GetText() return self.text end
  function w:RegisterEvent(e) self.events = self.events or {} self.events[e] = true end
  function w:UnregisterEvent(e) if self.events then self.events[e] = nil end end
  function w:CreateTexture() return widget() end
  function w:CreateFontString() return widget() end
  return setmetatable(w, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end

-- Items: id -> { loc, lines = { text or { text, red = true } } }.
local ITEMS = {
  [100] = { loc = "INVTYPE_HEAD", lines = { "Worn Cap", "Head", "+3 Intellect" } },
  [101] = { loc = "INVTYPE_HEAD", lines = { "Silk Hood", "Head", "+6 Intellect", "+4 Stamina", "Requires Level 20" } },
  [102] = { loc = "INVTYPE_HEAD", lines = { "Iron Helm", "Head", { "Plate", red = true }, "+8 Strength" } },
  [103] = { loc = "INVTYPE_HEAD", lines = { "Seer's Hood", "Head", "+9 Intellect", { "Requires Level 26", red = true } } },
  [104] = { loc = "INVTYPE_FINGER", lines = { "Opal Ring", "Finger", "+4 Intellect" } },
  [105] = { loc = "INVTYPE_2HWEAPON", lines = { "Oak Staff", "Two-Hand", "+10 Intellect",
    "Equip: Increases damage and healing done by magical spells and effects by up to 5." } },
  [106] = { loc = nil, lines = { "Linen Cloth", "Trade Goods" } },
  [107] = { loc = "INVTYPE_WEAPON", lines = { "Bone Dagger", "One-Hand", "+2 Intellect" } },
  [108] = { loc = "INVTYPE_HEAD", lines = { "Retrieving item information" } },
  [109] = { loc = "INVTYPE_NECK", lines = { "Late Pendant", "Neck", "+8 Intellect" } }, -- loads late
  [110] = { loc = "INVTYPE_WAIST", lines = { "Unseen Sash", "Waist", "+3 Intellect" } }, -- unknown at first
  [200] = { loc = "INVTYPE_FINGER", lines = { "Copper Band", "Finger", "+1 Intellect" } },
  [201] = { loc = "INVTYPE_FINGER", lines = { "Tin Band", "Finger", "+2 Intellect" } },
  [202] = { loc = "INVTYPE_2HWEAPON", lines = { "Old Staff", "Two-Hand", "+5 Intellect" } },
  [111] = { loc = "INVTYPE_SHOULDER", lines = { "Cave Mantle", "Shoulder", "+5 Intellect" } }, -- a dungeon drop
  [112] = { loc = nil, lines = { "An Unsent Letter", "Quest Item" } }, -- a dungeon drop, not gear
}
local WORN = { [1] = 100, [11] = 200, [12] = 201, [16] = 202 }
local P = { level = 22, class = "MAGE", money = 50000, bagItem = 104 }

local TT, reads = {}, 0
setmetatable(_G, { __index = function(_, k)
  if type(k) ~= "string" then return nil end
  local side, i = k:match("^UpgradeFinderScanTooltipText(%a+)(%d+)$")
  if not side or side ~= "Left" then return nil end
  local l = TT.lines and TT.lines[tonumber(i)]
  if l == nil then return nil end
  local text, red = l, false
  if type(l) == "table" then text, red = l[1], l.red end
  return { GetText = function() return text end,
    GetTextColor = function() if red then return 1, 0.125, 0.125 end return 1, 1, 1 end }
end })
function CreateFrame(kind, name, parent)
  if kind == "GameTooltip" then
    local t = widget(name)
    function t:ClearLines() TT.lines = {} end
    function t:NumLines() return #(TT.lines or {}) end
    function t:SetHyperlink(l) reads = reads + 1 local id = tonumber(l:match("item:(%d+)")) TT.lines = ITEMS[id] and ITEMS[id].lines or {} end
    function t:SetInventoryItem(_, slot) TT.lines = ITEMS[WORN[slot]] and ITEMS[WORN[slot]].lines or {} end
    return t
  end
  local f = widget(name)
  if name then _G[name] = f end
  -- The game lays out a frame when a child gets a texture, and that can fire
  -- the parent's OnSizeChanged before the parent's build has finished.
  function f:SetNormalTexture()
    local h = parent and parent.scripts and parent.scripts.OnSizeChanged
    if h then h(parent) end
  end
  return f
end
UIParent = widget("UIParent")
WorldFrame = widget("WorldFrame")
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, strip(m)) end }
SlashCmdList = {}
GameTooltip = widget("GameTooltip")
function UnitLevel() return P.level end
function UnitClass() return P.class:sub(1, 1) .. P.class:sub(2):lower(), P.class end
function GetMoney() return P.money end
function IsShiftKeyDown() return false end
function GetInventoryItemLink(_, slot) return WORN[slot] and ("item:" .. WORN[slot]) end
local timers, passes = {}, 0
C_Timer = { After = function(wait, f) if wait > 0 then passes = passes + 1 end table.insert(timers, f) end }
local function runTimers() while #timers > 0 do table.remove(timers, 1)() end end
local TALENTS -- { points per tab }, classic return order
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(tab) if TALENTS then return "Tree" .. tab, "icon", TALENTS[tab] or 0, "bg" end end
C_Item = {
  GetItemInfoInstant = function(x)
    local id = tonumber(tostring(x):match("(%d+)"))
    if id == 110 and passes < 1 then return nil end -- the game has not seen it yet
    return id, nil, nil, ITEMS[id] and ITEMS[id].loc, nil, ITEMS[id] and ITEMS[id].class
  end,
  RequestLoadItemDataByID = function(id) table.insert(calls, "load " .. id) end,
  -- 109 arrives on the second look after it was asked for.
  IsItemDataCachedByID = function(id)
    if id ~= 109 then return true end
    local n = 0
    for _, c in ipairs(calls) do if c == "load 109" then n = 1 end end
    return n > 0 and passes >= 2
  end,
}
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
  GetContainerItemInfo = function(bag, slot) if bag == 0 and slot == 1 and P.bagItem then return { itemID = P.bagItem } end end,
}
Auctionator = { Database = { db = { ["101"] = {}, ["102"] = {}, ["103"] = {}, ["105"] = {}, ["106"] = {},
  ["g:107:12"] = {}, ["108"] = {}, ["104"] = {}, ["109"] = {}, ["110"] = {} } },
  API = { v1 = { GetAuctionPriceByItemID = function(_, id)
    return ({ [101] = 12000, [103] = 30000, [105] = 90000, [107] = 4000 })[id] end } } }

local ns = {}
-- Questie: item sources.
local QITEM = { [101] = { questRewards = { 300 } }, [105] = { npcDrops = { 639 } },
  [103] = { npcDrops = { 1, 2, 3, 4, 5 } }, [107] = { vendors = { 500 } },
  [104] = { npcDrops = { 640, 641, 642, 643 } } }
local QNPC = { [639] = { name = "Edwin VanCleef", spawns = { [1581] = { { -1, -1 } } } },
  [500] = { name = "Smith", spawns = { [12] = { { 40, 50 } } } } }
for i = 1, 5 do QNPC[i] = { name = "Gnoll " .. i, spawns = { [40] = { { 10, 10 } } } } end
for i = 640, 643 do QNPC[i] = { name = "Miner " .. i, spawns = { [1581] = { { -1, -1 } } } } end
local AREAS = { [1581] = "The Deadmines", [12] = "Elwynn Forest", [40] = "Westfall" }
QuestieLoader = { ImportModule = function(_, name)
  if name == "QuestieDB" then return {
    QueryItemSingle = function(id, k) return QITEM[id] and QITEM[id][k] end,
    QueryNPCSingle = function(id, k) return QNPC[id] and QNPC[id][k] end,
    QueryQuestSingle = function(id, k) if id == 300 and k == "name" then return "Hood Quest" end end } end
end }
C_Map = { GetAreaInfo = function(a) return AREAS[a] end }

-- The real drop table: well formed. The tests use a small one.
local real = {}
assert(loadfile(root .. "UpgradeFinder/Dungeons.lua"))("UpgradeFinder", real)
local okTable, nIDs = #real.DUNGEONS >= 20, 0
for _, d in ipairs(real.DUNGEONS) do
  okTable = okTable and type(d[1]) == "string" and type(d[2]) == "string" and #d[2] <= 8
    and type(d[3]) == "number" and type(d[4]) == "number" and d[3] <= d[4] and #d >= 5
  for i = 5, #d do
    okTable = okTable and type(d[i][1]) == "string" and #d[i] >= 2
    for j = 2, #d[i] do okTable = okTable and type(d[i][j]) == "number" nIDs = nIDs + 1 end
  end
end
check("the dungeon table is well formed", okTable and nIDs > 1000)
ns.DUNGEONS = {
  { "The Deadmines", "DM", 10, 26, { "Edwin VanCleef", 105, 111, 112 } },
  { "Shadowfang Keep", "SFK", 11, 30, { "Arugal", 111 } },
}

for _, file in ipairs({ "Score.lua", "Scan.lua", "Where.lua", "Craft.lua", "Stats.lua", "Calib.lua", "Spells.lua", "Build.lua", "UI.lua", "Weights.lua", "BuildUI.lua" }) do
  assert(loadfile(root .. "UpgradeFinder/" .. file))("UpgradeFinder", ns)
end
local S = ns.score

-- Parsing and weights -------------------------------------------------------
local st = S.parse({ "+6 Intellect", "+4 Stamina", "(12.5 damage per second)", "120 Armor",
  "Equip: Increases damage and healing done by magical spells and effects by up to 5.",
  "Equip: Increases healing done by up to 41 and damage done by up to 14 for all magical spells and effects." })
check("primary stats", st.int == 6 and st.sta == 4)
local sash = { "Rotmender's Sash", "Waist", "+6 Stamina", "+6 Intellect", "(2) Set: +5 Shadow Resistance.",
  "(3) Set: +10 Intellect.", "Set: Increases damage and healing done by magical spells and effects by up to 9." }
local ss = S.parse(sash)
check("set bonuses are not the item's stats", ss.int == 6 and ss.sp == nil)
local frost = S.parse({ "Equip: Increases damage done by Frost spells and effects by up to 10." })
local amulet = S.parse({ "+4 Stamina", "Equip: Increases damage and healing done by magical spells and effects by up to 5.",
  "Equip: Increases damage done to Undead by magical spells and effects by up to 12." })
check("parse: damage vs Undead is not spell damage", amulet.sp == 5 and amulet.slay == 12)
check("one-school bonus is its own stat", frost.frost == 10 and frost.sp == nil)
check("frost damage counts for a mage, not a priest",
  S.value(frost, S.weightsFor("MAGE")) == 10 and S.value(frost, S.weightsFor("PRIEST")) == 0)
check("shadow damage counts for a shadow priest", S.value({ shadow = 10 }, S.weightsFor("PRIEST", nil, 3)) == 10)
check("weapon dps and armor", st.dps == 12.5 and st.armor == 120)
check("spell power, both wordings", st.sp == 19 and st.heal == 41)
check("class weights differ", S.weightsFor("WARRIOR").str == 1 and (S.weightsFor("MAGE").str or 0) == 0)
check("custom weight wins", S.weightsFor("MAGE", { int = 2 }).int == 2)
check("unknown class falls back", S.weightsFor("MONK").str == 1)
check("protection warrior gets tank weights", S.weightsFor("WARRIOR", nil, 3).def > 0 and S.weightsFor("WARRIOR", nil, 1).def == 0.3)
check("holy priest values healing", S.weightsFor("PRIEST", nil, 2).heal == 1 and S.weightsFor("PRIEST", nil, 3).heal == nil)
check("mage has one weight set", S.specName("MAGE", 1) == nil)

-- What an item replaces ---------------------------------------------------------
check("ring replaces the weaker ring", S.replaced("INVTYPE_FINGER", { [11] = 5, [12] = 2 }) == 2)
check("two-hander replaces both hands", S.replaced("INVTYPE_2HWEAPON", { [16] = 4, [17] = 3 }) == 7)
local v, note = S.replaced("INVTYPE_HOLDABLE", { [16] = 6 }, true)
check("off-hand over a two-hander says so", v == 6 and note == "replaces your two-hander")
local noPrice = S.rank({ { id = 1, gain = 2, source = "AH" }, { id = 2, gain = 1, source = "AH", price = 100 } },
  { affordable = true, money = 0, level = 1 })
check("unknown AH price is not affordable", #noPrice == 0)
check("one-hand without dual wield replaces main hand", S.replaced("INVTYPE_WEAPON", { [16] = 4, [17] = 1 }, false, false) == 4)

-- Full scan (mage, MageMentor not loaded) ---------------------------------------
ns.scan.SLICE = 3
-- Record every font string text, to check the slot column at the end.
local slotTexts = {}
local createFrame = CreateFrame
CreateFrame = function(...)
  local f = createFrame(...)
  local cfs = f.CreateFontString
  f.CreateFontString = function(self, ...)
    local fs = cfs(self, ...)
    local set = fs.SetText
    fs.SetText = function(w, t) table.insert(slotTexts, t) return set(w, t) end
    return fs
  end
  return f
end
ns.open()
check("window opens and scans", UpgradeFinderFrame:IsShown() and ns.scan.state.busy)
runTimers()
check("scan finishes", not ns.scan.state.busy and not ns.scan.state.loading)
check("loading item asked for", table.concat(calls, ","):find("load 108") ~= nil and ns.scan.state.pending == 1)
check("item that loads late is added", ns.scan.cache[109] and ns.scan.cache[109].name == "Late Pendant")
check("never-loading item stops after a few idle passes", passes <= 2 + ns.scan.PATIENCE)
check("item the game did not know at first is read later", ns.scan.cache[110] and ns.scan.cache[110].name == "Unseen Sash")
local names = {}
for _, r in ipairs(ns.view.list) do table.insert(names, r.name) end
local list = table.concat(names, ",")
check("plate (red line) is left out", not list:find("Iron Helm"))
check("level 26 item hidden by default", not list:find("Seer's Hood"))
check("non-gear is left out", not list:find("Linen"))
check("upgrades listed", list:find("Silk Hood") and list:find("Opal Ring") and list:find("Oak Staff"))
check("biggest gain first", names[1] == "Oak Staff")
check("gear keyed g:ID:level is read", ns.scan.cache[107] and ns.scan.cache[107].name == "Bone Dagger")
check("a dagger does not beat the staff it would replace", not list:find("Bone Dagger"))
local ring
for _, r in ipairs(ns.view.list) do if r.name == "Opal Ring" then ring = r end end
check("bag item has no price and source bags", ring.source == "bags" and ring.price == nil)
check("ring gain vs weaker ring", math.abs(ring.gain - (4 - 1) * 0.5) < 1e-9)

-- Where to get it (Questie) ------------------------------------------------------
local W = ns.where
check("quest reward tagged", W.tag(W.of(101)) == "quest" and W.lines(W.of(101))[1] == "Quest reward: Hood Quest")
check("boss drop names the dungeon", W.tag(W.of(105)) == "The Deadmines"
  and W.lines(W.of(105))[1] == "Drops from Edwin VanCleef (The Deadmines)")
check("many open-world droppers: world drop, no tag", W.tag(W.of(103)) == nil and W.lines(W.of(103))[1] == "World drop")
check("many droppers all in one dungeon: dungeon drop", W.tag(W.of(104)) == "The Deadmines"
  and W.lines(W.of(104))[1] == "Drops in The Deadmines")
QITEM[111] = { npcDrops = { 640, 641, 642, 643, 640, 641, 642, 643, 640, 641, 5 } } -- 11 droppers
check("more droppers than checked: no dungeon tag", W.tag(W.of(111)) == nil and W.lines(W.of(111))[1] == "World drop")
QNPC[644] = { name = "Wanderer", spawns = { [1581] = { { -1, -1 } }, [40] = { { 5, 5 } } } }
QITEM[112] = { npcDrops = { 644 } }
check("NPC also outdoors: not a dungeon drop", W.tag(W.of(112)) == nil)
QITEM[113] = { npcDrops = { 639 } }
local qi = QuestieLoader.ImportModule
local broken = true
QuestieLoader.ImportModule = function(self, name)
  local db = qi(self, name)
  if name == "QuestieDB" and broken then db.QueryItemSingle = function() error("not ready") end end
  return db
end
check("failed query shows nothing", W.of(113) == nil)
broken = false
check("and is not cached: a later lookup works", W.tag(W.of(113)) == "The Deadmines")
QuestieLoader.ImportModule = qi
check("vendor", W.tag(W.of(107)) == "vendor" and W.lines(W.of(107))[1] == "Sold by Smith (Elwynn Forest)")
check("unknown to Questie: nothing", W.of(102) == nil and #W.lines(W.of(102)) == 0)
local added = {}
local fakeTT = { GetItem = function() return "Oak Staff", "|Hitem:105::|h[Oak Staff]|h" end,
  AddLine = function(_, l) table.insert(added, l) end }
W.onTooltip(fakeTT)
check("item tooltip gets a Get it line", added[1] == "Get it: Drops from Edwin VanCleef (The Deadmines)")
added = {}
fakeTT.GetItem = function() return "Linen", "item:106" end
W.onTooltip(fakeTT)
check("non-gear tooltip gets nothing", #added == 0)
SlashCmdList.UPGRADEFINDER("where")
added = {}
fakeTT.GetItem = function() return "Oak Staff", "item:105" end
W.onTooltip(fakeTT)
check("/uf where turns it off", #added == 0 and UpgradeFinderDB.opts.where == false)
SlashCmdList.UPGRADEFINDER("where")

-- Options ----------------------------------------------------------------------
ns.cycle("level") -- show up to +2 levels... 26 is +4, still hidden
check("+2 levels still hides a level 26 item", not table.concat((function()
  local t = {} for _, r in ipairs(ns.view.list) do table.insert(t, r.name) end return t end)(), ","):find("Seer"))
P.level = 24
ns.apply()
local seer
for _, r in ipairs(ns.view.list) do if r.name == "Seer's Hood" then seer = r end end
check("at 24 with +2 the level 26 item shows, after the usable ones", seer and ns.view.list[#ns.view.list] == seer)
P.level = 22
ns.cycle("level")
ns.cycle("money") -- affordable only: staff 9g > 5g
local afford = {}
for _, r in ipairs(ns.view.list) do afford[r.name] = true end
check("affordable hides the 9g staff, keeps bag items", not afford["Oak Staff"] and afford["Opal Ring"])
ns.cycle("money")
ns.cycle("sort") -- per gold: bag items (free) first
check("per gold puts owned items first", ns.view.list[1].source == "bags")
ns.cycle("sort")
ns.db().opts.group = 2 -- Head
ns.apply()
check("slot filter Head", #ns.view.list == 1 and ns.view.list[1].name == "Silk Hood")
ns.db().opts.group = 1
ns.apply()

-- MageMentor's score for a mage --------------------------------------------------
MageMentorAPI = { parseStats = function(lines) return { n = #lines } end, score = function(s) return s.n end }
check("mage uses MageMentor's score", ns.valueOf({ "a", "b", "c" }) == 3)
check("set lines never reach MageMentor's reader", ns.valueOf({ "a", "b", "(3) Set: +10 Intellect." }) == 2)
P.class = "WARRIOR"
check("other classes use built-in weights", ns.valueOf({ "+5 Strength" }) == 5)
P.class = "MAGE"
MageMentorAPI = nil

-- Equipment change re-scores against what you wear --------------------------------
WORN[1] = 101
ns.handlers.PLAYER_EQUIPMENT_CHANGED()
local hood
for _, r in ipairs(ns.view.list) do if r.name == "Silk Hood" then hood = r end end
check("wearing the hood removes it from the list", hood == nil)

-- Gear changed while the window was closed
WORN[1] = 100
UpgradeFinderFrame:Hide()
ns.handlers.PLAYER_EQUIPMENT_CHANGED()
ns.open()
hood = nil
for _, r in ipairs(ns.view.list) do if r.name == "Silk Hood" then hood = r end end
check("reopening shows gains against the new gear", hood ~= nil)

local function row(name) for _, r in ipairs(ns.view.list) do if r.name == name then return r end end end
-- Gear changed during a scan: the end of the scan rereads it
ns.scan.forget()
ns.rescan()
WORN[1] = 101
runTimers()
hood = nil
for _, r in ipairs(ns.view.list) do if r.name == "Silk Hood" then hood = r end end
check("gear equipped during a scan counts", hood == nil)

-- Your own gear still loading (just after login): no inflated gains
local realHood = ITEMS[101].lines
ITEMS[101].lines = { "Retrieving item information" }
ns.scan.forget()
UpgradeFinderDB.worn = {} -- a first login: nothing saved yet
local shown = {}
local apply = ns.apply
ns.apply = function(keep) apply(keep) table.insert(shown, row("Oak Staff") ~= nil) end
local before = passes
C_Timer.After = function(wait, f)
  if wait > 0 then passes = passes + 1 end
  if passes - before >= 2 then ITEMS[101].lines = realHood end -- the hood loads
  table.insert(timers, f)
end
ns.rescan()
while ns.scan.state.busy and #timers > 0 do table.remove(timers, 1)() end -- the first pass
check("nothing listed while your gear loads", #shown == 0 and ns.scan.state.gearLoading)
runTimers()
check("listed once your gear loaded", #shown >= 1 and row("Seer's Hood") == nil and not ns.scan.state.loading)
ns.apply = apply
check("status names the slot it waits for", ns.scan.worn().missing == 0)
-- Next login: the hood's score is saved, so no wait.
ITEMS[101].lines = { "Retrieving item information" }
C_Timer.After = function(wait, f) if wait > 0 then passes = passes + 1 end table.insert(timers, f) end
ns.scan.forget()
ns.rescan()
while ns.scan.state.busy and #timers > 0 do table.remove(timers, 1)() end
check("saved score of worn gear: no wait", not ns.scan.state.gearLoading and ns.scan.worn().value[1] > 0)
runTimers()
ITEMS[101].lines = realHood

-- Equipping the only bag copy of a ring
check("bag ring listed as free", row("Opal Ring") and row("Opal Ring").source == "bags")
P.bagItem, WORN[11] = nil, 104
ns.handlers.BAG_UPDATE_DELAYED()
ns.handlers.PLAYER_EQUIPMENT_CHANGED()
check("equipped ring is no longer a free bag item; the AH copy stays", row("Opal Ring") and row("Opal Ring").source == "AH")
P.bagItem, WORN[11] = 104, 200

-- Dual wield comes from the game
CanDualWield = function() return false end
check("no dual wield until learned", ns.scan.readWorn().dualWield == false)
CanDualWield = function() return true end
check("dual wield once learned", ns.scan.readWorn().dualWield == true)
CanDualWield = nil

-- Saved scores ----------------------------------------------------------------------
check("scores are saved in UpgradeFinderDB", UpgradeFinderDB.items == ns.scan.cache and UpgradeFinderDB.items[105] ~= nil)
check("an item that never loaded is remembered", UpgradeFinderDB.missing[108] ~= nil)
reads, calls = 0, {}
ns.rescan() -- like the list after a /reload: the scores are there
runTimers()
check("rescan reads no saved item again", reads == 0 and row("Oak Staff") ~= nil)
check("never-loaded item is skipped, not asked for", ns.scan.state.skipped >= 1
  and not table.concat((function() local t = {} for _, c in ipairs(calls) do table.insert(t, tostring(c)) end return t end)(), ","):find("load 108"))
-- A /reload: SavedVariables hold a copy, the module cache starts empty.
local copy = {}
for k, v in pairs(UpgradeFinderDB.items) do copy[k] = v end
ns.scan.forget()
UpgradeFinderDB.items = copy
reads = 0
ns.rescan()
runTimers()
check("after a reload the saved scores are used", reads == 0 and row("Oak Staff") ~= nil)
MageMentorAPI = { parseStats = function() return {} end, score = function(st) return (st.int or 0) * 9 end }
reads = 0
ns.rescan()
runTimers()
check("new MageMentor weights rescore everything", reads > 0)
MageMentorAPI = nil
ns.scan.forget()

-- Auction House button: classic AuctionFrame (Forever), after a short delay
local made = {}
local cf = CreateFrame
CreateFrame = function(kind, name, parent, tmpl)
  local f = cf(kind, name, parent, tmpl)
  if kind == "Button" and parent == rawget(_G, "AuctionFrame") then table.insert(made, f) end
  return f
end
ns.handlers.AUCTION_HOUSE_SHOW() -- the window is not there yet
AuctionFrame = widget("AuctionFrame")
runTimers()
check("Upgrades button on the classic AuctionFrame", #made == 1 and made[1].text == "Upgrades")
ns.handlers.AUCTION_HOUSE_SHOW()
check("only one button", #made == 1)
CreateFrame = cf

-- The interaction-manager event adds the button only for the auctioneer.
local adds, addAH = 0, ns.addAHButton
ns.addAHButton = function() adds = adds + 1 end
local hadEnum = rawget(_G, "Enum")
Enum = { PlayerInteractionType = { Auctioneer = 21, Merchant = 5 } }
ns.handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(21)
check("auctioneer interaction adds the button", adds == 1)
ns.handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(5)
check("other interactions do not", adds == 1)
Enum = nil
ns.handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(21)
ns.handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(nil)
check("no enum (older client): nothing happens", adds == 1)
Enum, ns.addAHButton = hadEnum, addAH

-- /uf weight ---------------------------------------------------------------------
SlashCmdList.UPGRADEFINDER("weight int 2")
check("weight saved per class", UpgradeFinderDB.weights.MAGE.int == 2)
SlashCmdList.UPGRADEFINDER("weight reset")
check("weight reset", UpgradeFinderDB.weights.MAGE == nil)

-- Spec from talents ----------------------------------------------------------------
P.class, TALENTS = "WARRIOR", { 5, 0, 21 }
check("most points picks the tree", ns.talentTab() == 3 and ns.weightKey() == "WARRIOR:Protection")
local old = GetTalentTabInfo
GetTalentTabInfo = function(tab) return 160 + tab, "Tree", "desc", "icon", ({ 2, 30, 0 })[tab] end
check("newer return order is read", ns.talentTab() == 2 and ns.weightKey() == "WARRIOR")
GetTalentTabInfo = old
SlashCmdList.UPGRADEFINDER("weight def 3")
check("override saved for the spec", UpgradeFinderDB.weights["WARRIOR:Protection"].def == 3 and ns.weights().def == 3)
ns.scan.key = "WARRIOR:Protection"
TALENTS = { 31, 0, 0 }
ns.handlers.CHARACTER_POINTS_CHANGED()
runTimers()
check("spec change rescans with new weights", ns.scan.key == "WARRIOR" and ns.scan.state.ran)
P.class, TALENTS = "MAGE", nil

-- Weight presets -----------------------------------------------------------------
local function lastSay() return chat[#chat] or "" end
local uf = SlashCmdList.UPGRADEFINDER
local wkey = ns.weightKey()
local key0 = ns.scan.cacheKey()
check("default weights have no name", ns.weightsName() == nil)
uf("weight int 2")
check("a changed weight is custom", ns.weightsName() == "custom" and ns.weights().int == 2)
check("a changed weight changes the cache key", ns.scan.cacheKey() ~= key0)
uf("weight bogus 3")
check("an unknown stat is refused", lastSay():find("unknown stat") and ns.weights().bogus == nil)
uf("save leveling")
check("save makes a preset of the weights in use",
  UpgradeFinderDB.presets[ns.class()].leveling.int == 2 and ns.weightsName() == "leveling")
uf("weight reset")
check("reset goes back to the defaults", UpgradeFinderDB.weights[wkey] == nil and ns.weightsName() == nil
  and ns.scan.cacheKey() == key0)
uf("load leveling")
check("load brings the preset back", ns.weights().int == 2 and ns.weightsName() == "leveling")
uf("load nope")
check("loading an unknown preset says so", lastSay():find("no preset") ~= nil and ns.weightsName() == "leveling")
uf("presets")
check("presets lists the one in use", lastSay():find("leveling %(in use%)") ~= nil)
uf("weight int default")
check("one stat back to its default", ns.weights().int == S.weightsFor(ns.class(), nil, ns.talentTab()).int
  and ns.weightsName() ~= "leveling")
uf("delete leveling")
check("delete removes the preset", UpgradeFinderDB.presets[ns.class()].leveling == nil)
uf("weight reset")

-- Weights panel ------------------------------------------------------------------
ns.toggleWeights(true)
local boxes, wui = ns.weightsBoxes, ns.weightsUI
check("the panel has a box per stat", boxes and boxes.int and boxes.frost and boxes.mp5)
local intDefault = S.weightsFor(ns.class(), nil, ns.talentTab()).int or 0
check("a box shows the weight in use", tonumber(boxes.int:GetText()) == intDefault)
boxes.int:SetText("3")
boxes.int.scripts.OnEnterPressed(boxes.int)
check("Enter in a box sets the weight", ns.weights().int == 3 and ns.weightsName() == "custom")
wui.name:SetText("Big Int")
wui.save.scripts.OnClick(wui.save)
check("Save makes a preset (name lower case, no spaces)", UpgradeFinderDB.presets[ns.class()]["big-int"] ~= nil
  and ns.weightsName() == "big-int")
check("the preset gets a button", wui.presets[1].preset == "big-int" and wui.presets[1].shown)
wui.reset.scripts.OnClick(wui.reset)
check("Defaults goes back", ns.weightsName() == nil and tonumber(boxes.int:GetText()) == intDefault)
wui.presets[1].scripts.OnClick(wui.presets[1], "LeftButton")
check("clicking a preset loads it", ns.weights().int == 3 and ns.weightsName() == "big-int")
boxes.int:SetText("")
boxes.int.scripts.OnEditFocusLost(boxes.int)
check("an empty box is the default again", ns.weights().int == intDefault)
wui.presets[1].scripts.OnClick(wui.presets[1], "RightButton")
check("a plain right-click does not delete", UpgradeFinderDB.presets[ns.class()]["big-int"] ~= nil)
IsShiftKeyDown = function() return true end
wui.presets[1].scripts.OnClick(wui.presets[1], "RightButton")
IsShiftKeyDown = nil
check("shift-right-click deletes", UpgradeFinderDB.presets[ns.class()]["big-int"] == nil and not wui.presets[1].shown)
ns.savePreset("spare")
ns.paintWeights()
check("each preset has a delete button", wui.presets[1].preset == "spare" and wui.presets[1].del.shown)
wui.presets[1].del.scripts.OnClick(wui.presets[1].del)
check("the x button deletes the preset", UpgradeFinderDB.presets[ns.class()].spare == nil
  and not wui.presets[1].shown and not wui.presets[1].del.shown)
SlashCmdList.UPGRADEFINDER("weight reset")

-- Slot column -------------------------------------------------------------------
check("slot name for a ring", S.groupName("INVTYPE_FINGER") == "Ring")
check("slot name for a robe", S.groupName("INVTYPE_ROBE") == "Chest")
check("slot name for a wand", S.groupName("INVTYPE_WAND") == "Ranged")
check("no slot name for a non-slot", S.groupName("INVTYPE_BAG") == nil)
local sawSlot = false
for _, t in ipairs(slotTexts) do if t == "Head" or t == "Ring" or t == "Weapon" then sawSlot = true end end
check("rows show their slot", sawSlot)

-- Dungeon drops --------------------------------------------------------------
check("a dungeon drop knows its boss (the first one listed)",
  ns.scan.dropOf(111) and ns.scan.dropOf(111).boss == "Edwin VanCleef" and ns.scan.dropOf(111).short == "DM")
ns.db().opts.from = nil
ns.rescan()
runTimers()
local mantle, staff, letter = row("Cave Mantle"), row("Oak Staff"), row("An Unsent Letter")
check("a dungeon drop is a candidate", mantle and mantle.source == "dungeon" and mantle.drop.name == "The Deadmines")
check("an item on the AH stays an AH row and knows where it drops",
  staff and staff.source == "AH" and staff.drop and staff.drop.boss == "Edwin VanCleef")
check("a dungeon drop that is not gear is not listed", letter == nil)
ns.cycle("from")
check("From: AH only", ns.db().opts.from == "AH" and row("Cave Mantle") == nil and row("Oak Staff") ~= nil)
ns.cycle("from")
local onlyDungeon = #ns.view.list > 0
for _, r in ipairs(ns.view.list) do onlyDungeon = onlyDungeon and r.source == "dungeon" end
check("From: Dungeons", ns.db().opts.from == "dungeon" and onlyDungeon)
ns.cycle("from")
check("From: Bags only", ns.db().opts.from == "bags" and row("Opal Ring") ~= nil and row("Cave Mantle") == nil)
ns.cycle("from")
check("From goes back to all sources", ns.db().opts.from == nil and row("Cave Mantle") ~= nil)
SlashCmdList.UPGRADEFINDER("dungeons")
runTimers()
check("/uf dungeons turns them off", ns.db().opts.dungeons == false and row("Cave Mantle") == nil
  and lastSay():find("off") ~= nil)
SlashCmdList.UPGRADEFINDER("dungeons")
runTimers()
check("/uf dungeons turns them on again", ns.db().opts.dungeons == true and row("Cave Mantle") ~= nil)

-- Stat changes, offense and defense (Stats.lua) ----------------------------
local St = ns.stats
local d = St.diff({ int = 11, sta = 11, sp = 34, dps = 18.4 }, { { int = 5, spi = 3, dps = 12 } })
check("diff: new minus old", d.int == 6 and d.sta == 11 and d.spi == -3 and d.sp == 34 and math.abs(d.dps - 6.4) < 1e-9)
check("diff drops zeros", St.diff({ int = 2 }, { { int = 2 } }).int == nil)
check("diff: a two-hander minus both hands", St.diff({ int = 10 }, { { int = 3 }, { int = 4 } }).int == 3)
check("role: mage is a caster", St.role("MAGE", S.weightsFor("MAGE")) == "caster")
check("role: holy priest heals", St.role("PRIEST", S.weightsFor("PRIEST", nil, 2)) == "healer")
check("role: protection warrior tanks", St.role("WARRIOR", S.weightsFor("WARRIOR", nil, 3)) == "tank")
check("role: hunter is ranged", St.role("HUNTER", S.weightsFor("HUNTER")) == "ranged")
check("role: rogue is melee", St.role("ROGUE", S.weightsFor("ROGUE")) == "melee")
check("fmt", St.fmt(12.4) == "+12" and St.fmt(-3) == "-3" and St.fmt(1.5) == "+1.5" and St.fmt(0.42, true) == "+0.4%")
local function find(list, label) for _, e in ipairs(list) do if e[1] == label then return e end end end
local mw = S.weightsFor("MAGE")
local off, def = St.derive({ int = 24, sta = 2, sp = 10 }, { class = "MAGE", level = 24, sp = 20, spcrit = 5, armor = 300 }, mw,
  "INVTYPE_HEAD")
check("caster: spell damage", find(off, "Spell damage") and find(off, "Spell damage")[2] == "+10")
check("caster: Int gives spell crit (24 Int at 24 = about 1%)", find(off, "Spell crit") and find(off, "Spell crit")[2] == "+1.0%")
check("caster: an estimated DPS gain", find(off, "Est. DPS") and find(off, "Est. DPS")[3] == true)
check("caster: health and mana", find(def, "Health")[2] == "+20" and find(def, "Mana")[2] == "+360")
off, def = St.derive({ int = -10, sta = -5 }, { class = "MAGE", level = 24 }, mw, "INVTYPE_HEAD")
check("a loss is red (not good)", find(off, "Est. DPS")[3] == false and find(def, "Health")[3] == false)
local ww = S.weightsFor("WARRIOR")
off, def = St.derive({ str = 10, agi = 4, dps = 3, armor = 100 }, { class = "WARRIOR", level = 30, ap = 200, crit = 5,
  armor = 1000, weaponDps = 20 }, ww, "INVTYPE_2HWEAPON")
check("melee: Str gives AP", find(off, "Attack power")[2] == "+20")
check("melee: a weapon shows its DPS change", find(off, "Weapon DPS")[2] == "+3")
check("melee: armor (with Agi) shows less damage taken",
  find(def, "Armor") and find(def, "Armor")[2]:match("^%+108 %(%+[%d%.]+%% less damage%)$") ~= nil)
check("melee: no mana line for a warrior", find(def, "Mana") == nil)
off = St.derive({ str = 10, dps = 3 }, { class = "WARRIOR", level = 30 }, ww, "INVTYPE_HEAD")
check("melee: weapon DPS only for a weapon", find(off, "Weapon DPS") == nil)
check("stat line is colored and ordered", strip(St.statLine({ sta = -2, int = 5 })) == "-2 Sta  +5 Int")
-- A real row: Silk Hood over Worn Cap (+3 Int) in the mock game.
P.level = 22
local hoodRow = { id = 101, loc = "INVTYPE_HEAD" }
local wasHead = WORN[1]
WORN[1] = 100
ns.scan.readWorn()
local rd, roff = St.forRow(hoodRow)
WORN[1] = wasHead
ns.scan.readWorn()
check("forRow: Silk Hood vs Worn Cap", rd and rd.int == 3 and rd.sta == 4 and find(roff, "Est. DPS") ~= nil)

-- eHP --------------------------------------------------------------------------
off, def = St.derive({ sta = 10, armor = 200 }, { class = "WARRIOR", level = 30, health = 1000, armor = 1000 }, ww, "INVTYPE_CHEST")
local ehp = find(def, "eHP")
-- 1000 / (1 - 1000/3950) = 1338.98; 1100 / (1 - 1200/4150) = 1547.46
check("eHP from health and armor", ehp and ehp[2] == "+208 (+15.6%)" and ehp[3] == true)

-- Calibration (Calib.lua) ----------------------------------------------------
local Cal = ns.calib
check("calib: the combat log is not registered by default (Forever forbids it)",
  not (Cal.frame.events or {}).COMBAT_LOG_EVENT_UNFILTERED and not Cal.logOn())
SlashCmdList.UPGRADEFINDER("calib log")
check("/uf calib log turns it on", Cal.logOn() and Cal.frame.events.COMBAT_LOG_EVENT_UNFILTERED == true)
ns.handlers.ADDON_ACTION_FORBIDDEN("UpgradeFinder", "UNKNOWN()")
check("a forbidden call turns the combat log off", not Cal.logOn() and UpgradeFinderDB.blocked[1].fn == "UNKNOWN()")
SlashCmdList.UPGRADEFINDER("calib log")
SlashCmdList.UPGRADEFINDER("calib log")
check("/uf calib log again turns it off", not Cal.logOn())
ns.db().opts.combatLog = true -- saved by a 0.1.6 test build
Cal.handlers.PLAYER_LOGIN()
check("a saved combat log setting is cleared at login, not registered",
  not Cal.logOn() and ns.db().opts.combatLog == nil and not Cal.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
Cal.reset()
local snaps = Cal.store().snaps
-- Level 24: 24 Int per 1% crit, 10 health per Sta (+ 50), 15 mana per Int.
for _, int in ipairs({ 40, 52, 64 }) do
  table.insert(snaps, { level = 24, int = int, agi = 20, sta = 30, spcrit = 2 + int / 24, hp = 50 + 30 * 10,
    mana = 100 + int * 15 })
end
table.insert(snaps, { level = 24, int = 64, agi = 20, sta = 41, spcrit = 2 + 64 / 24, hp = 50 + 41 * 10, mana = 100 + 64 * 15 })
local r = Cal.ratios(24, ns.class())
check("calib: Int per crit measured", r.intPerCrit and math.abs(r.intPerCrit[1] - 24) < 1e-6 and r.intPerCrit.n == 4)
check("calib: health per Sta measured", r.hpPerSta and math.abs(r.hpPerSta[1] - 10) < 1e-6)
check("calib: mana per Int measured", r.manaPerInt and math.abs(r.manaPerInt[1] - 15) < 1e-6)
check("calib: no Agi spread, no Agi ratio", r.agiPerCrit == nil)
local r30 = Cal.ratios(30, ns.class())
check("calib: another level scales the crit ratio", r30.intPerCrit and math.abs(r30.intPerCrit[1] - 30) < 1e-6)
check("calib: a small spread does not count", Cal.slope({ { level = 5, int = 10, spcrit = 1 }, { level = 5, int = 12, spcrit = 2 } },
  5, "int", "spcrit") == nil)
off = St.derive({ int = 12 }, { class = "MAGE", level = 24, intPerCrit = 12 }, mw, "INVTYPE_HEAD")
check("derive uses a measured ratio", find(off, "Spell crit")[2] == "+1.0%")
-- Spells: Frostbolt hits 100 + 0.8 x sp, crits 150, at sp 0..40.
UnitGUID = function() return "me" end
local curSP = 0
GetSpellBonusDamage = function() return curSP end
for i = 1, 40 do
  local sp = i
  curSP = sp
  Cal.combat(0, "SPELL_DAMAGE", false, "me", "Ded", 0, 0, "mob", "Boar", 0, 0, 116, "Frostbolt", 16,
    math.floor(100 + 0.8 * sp + 0.5), 0, 16, nil, nil, nil, false)
  if i % 4 == 0 then
    Cal.combat(0, "SPELL_DAMAGE", false, "me", "Ded", 0, 0, "mob", "Boar", 0, 0, 116, "Frostbolt", 16, 150, 0, 16, nil, nil, nil, true)
  end
end
Cal.combat(0, "SPELL_DAMAGE", false, "someone", "X", 0, 0, "mob", "Boar", 0, 0, 116, "Frostbolt", 16, 9999, 0, 16, nil, nil, nil, false)
Cal.combat(0, "SPELL_MISSED", false, "me", "Ded", 0, 0, "mob", "Boar", 0, 0, 116, "Frostbolt", 16, "RESIST")
local model = Cal.model()
check("calib: a spell with enough hits", #model == 1 and model[1].name == "Frostbolt")
check("calib: others' damage is not counted", Cal.store().spells[116].dmg < 9999)
check("calib: coefficient fitted from varied spell damage", model[1].fitted and math.abs(model[1].coef - 0.8) < 0.02)
check("calib: crit rate", math.abs(model[1].critRate - 10 / 50) < 1e-9)
check("calib: misses counted", Cal.store().spells[116].misses == 1)
local dc = Cal.dpsChange(20, 0, 20.5)
-- hit at 20.5 sp: 116.4; +20 sp: +16 -> (132.4 / 116.4) - 1 = 0.1375
check("calib: DPS change from your spells", dc and math.abs(dc - 0.1375) < 0.005)
local report = table.concat(Cal.report(), "\n")
check("calib: report lists the spell and the ratio", report:find("Frostbolt %(116%)") ~= nil and report:find("Int per 1%% spell crit: 22%.0 %(measured at level 24") ~= nil)
GetSpellBonusDamage = nil
SlashCmdList.UPGRADEFINDER("calib reset")
UnitStat = function(_, i) return 0, ({ 10, 20, 30, 40, 50 })[i] end
GetSpellCritChance = function() return 4.5 end
UnitHealthMax = function() return 400 end
check("calib: a snapshot from the game", Cal.snap() == true and Cal.store().snaps[1].int == 40
  and Cal.store().snaps[1].spcrit == 4.5 and Cal.store().snaps[1].hp == 400)
check("calib: the same snapshot is not saved twice", Cal.snap() == false and #Cal.store().snaps == 1)
UnitStat, GetSpellCritChance, UnitHealthMax = nil, nil, nil
Cal.reset()
check("/uf calib reset clears", #Cal.store().snaps == 0 and next(Cal.store().spells) == nil)

-- Spells from the action bars (Spells.lua) ----------------------------------
local SPL = ns.spells
local dl, dd = SPL.parseText("Launches a bolt of frost at the enemy, causing 79 to 87 Frost damage and slowing movement.")
check("spell text: direct range", dl == 83 and dd == nil)
local _, dot, dur = SPL.parseText("Corrupts the target, causing 222 Shadow damage over 18 sec.")
check("spell text: damage over time", dot == 222 and dur == 18)
check("spell text: single number", SPL.parseText("Blasts the enemy for 60 Fire damage.") == 60)
check("spell text: no damage", SPL.parseText("Increases your Intellect by 10.") == nil)
local BAR = { [1] = 116, [2] = 2136, [3] = 99, [5] = 205 }
local SPELLS = {
  [116] = { "Frostbolt", 2500, "causing 79 to 87 Frost damage", 0, 50 },
  [205] = { "Frostbolt", 2200, "causing 40 to 46 Frost damage", 0, 30 }, -- a lower rank
  [2136] = { "Fire Blast", 0, "Blasts the enemy for 60 to 72 Fire damage.", 8000, 60 },
  [99] = { "Frost Armor", 0, "Increases armor.", 0, 60 },
}
GetActionInfo = function(slot) if BAR[slot] then return "spell", BAR[slot] end end
GetSpellInfo = function(id) local t = SPELLS[id] if t then return t[1], nil, nil, t[2] end end
GetSpellDescription = function(id) return SPELLS[id] and SPELLS[id][3] end
GetSpellBaseCooldown = function(id) return SPELLS[id] and SPELLS[id][4] end
GetSpellPowerCost = function(id) return SPELLS[id] and { { type = 0, cost = SPELLS[id][5] } } end
local bars = SPL.calibrate(SPL.fromBars())
check("bars: the damage spells, one per name, highest rank", #bars == 2 and bars[1].name == "Fire Blast"
  and bars[2].name == "Frostbolt" and bars[2].id == 116)
check("bars: cast time and cooldown", bars[2].cast == 2.5 and bars[1].cast == 1.5 and bars[1].cd == 8)
-- Frostbolt: 83 + 2.5/3.5 x 0 = 83 per 2.5 s = 33.2/s (filler).
-- Fire Blast: 66 + 1.5/3.5 x 0 = 66 every 8 s; uses 1.5/8 of the time.
local rot = SPL.rotation(bars, 0, 0, 1)
check("rotation: filler plus cooldown", rot and math.abs(rot.dps - (66 / 8 + (1 - 1.5 / 8) * 83 / 2.5)) < 1e-6)
check("rotation: shares add up", math.abs(rot.parts[1][3] + rot.parts[2][3] - 1) < 1e-9 and rot.parts[1][1].name == "Frostbolt")
check("rotation: mana per second", math.abs(rot.mps - (60 / 8 + (1 - 1.5 / 8) * 50 / 2.5)) < 1e-6)
local more = SPL.rotation(bars, 50, 0, 1)
check("rotation: more spell damage, more DPS", more.dps > rot.dps)
local ch = SPL.change(50, 0, { sp = 0, spcrit = 0 })
check("bars: DPS change", ch and math.abs(ch - (more.dps / rot.dps - 1)) < 1e-6)
off = St.derive({ sp = 50 }, { class = "MAGE", level = 24, sp = 0, spcrit = 0,
  barsFn = function(...) return (SPL.change(...)) end }, mw, "INVTYPE_HEAD")
check("derive uses the bars", find(off, "Est. DPS")[2] == string.format("%+.1f%%", (more.dps / rot.dps - 1) * 100))

-- Build (Build.lua, BuildUI.lua) ---------------------------------------------
local Bd = ns.build
Bd.reset()
WORN[1] = 100
check("build: starts as what you wear", Bd.items()[1] == "item:100" and Bd.items()[11] == "item:200")
Bd.set(1, "item:101")
local sh = Bd.sheet(Bd.items())
check("build: the sheet sees the change", sh.diff.int == 3 and sh.diff.sta == 4 and sh.loading == 0)
local function srow(label) for _, r in ipairs(sh.rows) do if r[1] == label then return r end end end
check("build: sheet rows for a caster", srow("eHP (physical)") ~= nil and srow("DPS (your bars)") ~= nil)
check("build: health row now and with", srow("Health") and srow("Health")[4] == "+40")
Bd.save("hood")
Bd.reset()
check("build: saved and reset", Bd.names()[1] == "hood" and Bd.items()[1] == "item:100")
check("build: load", Bd.load("hood") and Bd.items()[1] == "item:101")
Bd.clear(11)
check("build: an empty slot", Bd.items()[11] == nil)
Bd.unset(11)
check("build: back to worn", Bd.items()[11] == "item:200")
local vs = Bd.sheet(Bd.items(), Bd.get("hood"))
check("build: compare with a saved build (same: no change)", next(vs.diff) == nil)
-- Dropping an item: it must fit the slot.
GetCursorInfo = function() return "item", 109, "item:109" end
ClearCursor = function() end
Bd.reset()
check("build: drop a neck item on the head slot is refused", Bd.dropOn(1) == true and Bd.work[1] == nil)
check("build: drop it on the neck slot", Bd.dropOn(2) == true and Bd.work[2] == "item:109")
GetCursorInfo = nil
-- An Upgrades row (Alt-click) goes to the slot it replaces.
check("build: row to build", ns.rowToBuild({ id = 103, loc = "INVTYPE_HEAD" }) and Bd.work[1] == "item:103")
local okPaint = pcall(ns.paintBuild)
check("build: the window paints", okPaint and ns.buildFrame and ns.buildFrame:IsShown())
SlashCmdList.UPGRADEFINDER("build")
check("/uf build opens it", ns.buildFrame:IsShown())
Bd.delete("hood")
check("build: delete", #Bd.names() == 0)
Bd.reset()
GetActionInfo, GetSpellInfo, GetSpellDescription, GetSpellBaseCooldown, GetSpellPowerCost = nil, nil, nil, nil, nil

-- Resizable window --------------------------------------------------------------
local F = UpgradeFinderFrame
local fh = 92 + 14 * 20
F.GetHeight = function() return fh end
F.GetWidth = function() return 600 end
check("window: 14 rows at the start size", ns.visibleRows() == 14)
fh = 92 + 25 * 20
F.grip.scripts.OnMouseUp(F.grip)
check("window: a taller window shows more rows, and the size is saved", ns.visibleRows() == 25
  and UpgradeFinderDB.opts.size[1] == 600 and UpgradeFinderDB.opts.size[2] == fh)
fh = 10000
check("window: at most 40 rows", ns.visibleRows() == 40)
F.GetHeight, F.GetWidth, UpgradeFinderDB.opts.size = nil, nil, nil

-- Recipes: a pattern scores as the item it makes ------------------------------
local Sc = ns.scan
ITEMS[114] = { loc = "", class = 9, lines = { "Pattern: Frost Circlet", "Frost Circlet", "Binds when picked up",
  "Head", "+9 Intellect", "Requires Level 20", "Use: Teaches you how to craft Frost Circlet.",
  "Bolt of Silk Cloth (8), Fine Thread (4), Bleach", { "Requires Tailoring (125)", red = true } } }
ITEMS[115] = { loc = "", class = 9, lines = { "Plans: Iron Helm", "Iron Helm", "Head", { "Plate", red = true },
  "+8 Strength", { "Requires Blacksmithing (100)", red = true } } }
ITEMS[116] = { loc = "", class = 9, lines = { "Recipe: Fish Stew", "Use: Teaches you how to cook Fish Stew." } }
ITEMS[117] = { loc = "INVTYPE_CHEST", lines = { "Silk Robe", "Chest", "+4 Intellect" } }
ITEMS[118] = { loc = "", class = 9, lines = { "Pattern: Silk Robe", "Silk Robe", "Chest", "+4 Intellect",
  "Use: Teaches you how to craft Silk Robe.", "Fine Thread (2)", "Requires Tailoring (60)" } }
-- Reagents by name (C_Item.GetItemInfo), priced from the AH or the vendor.
local NAMES = { ["Bolt of Silk Cloth"] = 900, ["Fine Thread"] = 901, ["Silk Robe"] = 117 }
C_Item.GetItemInfo = function(name) local id = NAMES[name] if id then return name, "item:" .. id end end
local ahPrice = Auctionator.API.v1.GetAuctionPriceByItemID
Auctionator.API.v1.GetAuctionPriceByItemID = function(c, id)
  return ({ [900] = 5000, [901] = 300, [117] = 20000 })[id] or ahPrice(c, id) end
Auctionator.API.v1.GetVendorPriceByItemID = function(_, id) return id == 901 and 100 or nil end
Sc.item(114) Sc.item(115) Sc.item(116) Sc.item(118)
local c114 = Sc.cache[114]
check("recipe: scores the item it makes", c114 and c114.name == "Frost Circlet" and c114.loc == "INVTYPE_HEAD"
  and c114.value > 0 and c114.recipe == "Pattern: Frost Circlet" and c114.craft == "Tailoring (125)")
check("recipe: a missing profession is not unusable", c114 and c114.unusable == false and c114.reqLevel == 20)
check("recipe: plate you cannot wear is unusable", Sc.cache[115] and Sc.cache[115].unusable == true)
check("recipe: no gear inside is skipped", Sc.cache[116] == false)
local rr = Sc.rows({ [114] = "AH" })
check("recipe: the row carries the pattern", rr[1] and rr[1].recipe == "Pattern: Frost Circlet" and rr[1].gain > 0)
local cost = rr[1].cost
-- Pattern 0 (no AH price) + 8 x 50s + 4 x 1s (vendor, cheaper than the AH) + Bleach unknown.
check("recipe: reagents read from the tooltip", c114.reagents and #c114.reagents == 3
  and c114.reagents[1][1] == "Bolt of Silk Cloth" and c114.reagents[1][2] == 8 and c114.reagents[3][2] == 1)
check("recipe: craft cost from AH and vendor prices", cost and cost.total == 40400 and cost.missing == 1
  and cost.parts[2][4] == "vendor" and rr[1].price == 40400)
check("recipe: a bind on pickup item cannot be bought made", cost.bop and cost.buy == nil)
local rb = Sc.rows({ [118] = "AH" })[1]
check("recipe: buy the made item instead", rb and rb.cost.buy == 20000 and rb.cost.total == 200 and not rb.cost.bop)

-- Row tooltip: one stat per line, label left, number right -------------------
local doubles, singles = {}, {}
local gt = GameTooltip
local oldAdd, oldDouble = gt.AddLine, gt.AddDoubleLine
gt.AddLine = function(_, l) table.insert(singles, l) end
gt.AddDoubleLine = function(_, l, r) table.insert(doubles, { l, r }) end
ns.showDetails({ data = rr[1] })
gt.AddLine, gt.AddDoubleLine = oldAdd, oldDouble
local function hasDouble(l) for _, d in ipairs(doubles) do if d[1]:match(l) then return d end end end
local function hasSingle(l) for _, t in ipairs(singles) do if t == l then return true end end end
check("tooltip: an Upgrade line and a Crafted line", hasDouble("^Upgrade %+") ~= nil
  and hasSingle("Crafted: Pattern: Frost Circlet (Tailoring (125))"))
local intLine = hasDouble("^  Intellect$")
check("tooltip: one stat per line, the item number then the change", hasSingle("Stats: this item (change vs worn)")
  and intLine and intLine[2]:match("^%+9  %(%+%d+%)$") ~= nil)
local sl = ns.stats.statList({ frost = 4, sp = -8 }, { frost = 14, sta = 5 })
local function sline(l) for _, e in ipairs(sl) do if e[1] == l then return e end end end
check("stat list: own number, then the change", sline("Frost damage")[2] == "+14  (+4)" and sline("Frost damage")[3] == true
  and sline("Spell damage")[2] == "none  (-8)" and sline("Spell damage")[3] == false
  and sline("Stamina")[2] == "+5  (same)" and sline("Stamina")[3] == nil)
check("tooltip: no run-on Changes line", not hasSingle("Changes:"))
local cl, bl = hasDouble("^Craft$"), hasDouble("^Buy it made$")
check("tooltip: craft cost and buy line", cl and cl[2] == "4g 04s +?" and bl and bl[2] == "binds on pickup"
  and hasDouble("^  Fine Thread x4$")[2] == "4s 00c (vendor)")


-- Crafting lines on recipes ------------------------------------------------
local Cr = ns.craft
-- A tooltip that keeps its lines, with TextLeft globals like the game's.
local function fakeTooltip(name, link)
  local t = { lines = {} }
  function t:GetName() return name end
  function t:GetItem() return "x", link end
  function t:NumLines() return #self.lines end
  function t:AddLine(l) table.insert(self.lines, { l }) rawset(_G, name .. "TextLeft" .. #self.lines, { GetText = function() return l end }) end
  function t:AddDoubleLine(l, r) self:AddLine(l) self.lines[#self.lines][2] = r end
  function t:Show() end
  function t:find(label) for _, l in ipairs(self.lines) do if l[1] == label then return l[2] or true end end end
  return t
end
-- name, link, quality, ilvl, _, _, _, _, loc, _, sell, classID, _, bind
local INFO = { ["Silk Robe"] = { 117, 2, 25, "INVTYPE_CHEST", 900, 4, 2 }, ["Frost Circlet"] = { 119, 2, 25, "INVTYPE_HEAD", 600, 4, 1 },
  ["Bolt of Silk Cloth"] = { 900, 1, 1, "", 0, 7 }, ["Fine Thread"] = { 901, 1, 1, "", 0, 7 } }
local byId = {}
for n, v in pairs(INFO) do byId[v[1]] = n end
local oldInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(x)
  local name = INFO[x] and x or byId[tonumber(tostring(x):match("item:(%d+)"))]
  local v = INFO[name]
  if not v then return nil end
  return name, "item:" .. v[1], v[2], v[3], 1, "", "", 1, v[4], 0, v[5], v[6], 0, v[7]
end
local tt = fakeTooltip("FakeTipA", "item:118")
Cr.onTooltip(tt)
-- Silk Robe: 2 x Fine Thread at 1s (vendor) = 2s; sells on the AH for 2g less 5%.
check("craft: cost to craft line", tt:find("Cost to craft") == "2s 00c")
check("craft: sells for the best of AH and vendor", tt:find("Sells for") == "~1g 90s AH")
check("craft: profit", tt:find("Profit") == "+1g 88s")
check("craft: score of the made item vs what you wear", tostring(tt:find("Score of the made item")):match("^%d+%.%d %([%+%-]%d+%.%d vs your chest%)$") ~= nil)
local n = #tt.lines
Cr.onTooltip(tt)
check("craft: a second item hook adds nothing", #tt.lines == n)
-- Frost Circlet: Bleach has no price; the circlet binds on pickup, so only the vendor buys it.
tt = fakeTooltip("FakeTipB", "item:114")
Cr.onTooltip(tt)
check("craft: a reagent without a price", tt:find("Cost to craft") == "4g 04s +?" and tt:find("  No price: Bleach"))
check("craft: bind on pickup sells to the vendor only", tt:find("Sells for") == "6s 00c vendor" and tt:find("Loss") == "-3g 98s ?")
tt = fakeTooltip("FakeTipC", "item:106")
Cr.onTooltip(tt)
check("craft: not a recipe, no lines", #tt.lines == 0)
-- The profession window: 2 x Fine Thread makes one Silk Robe.
GetTradeSkillItemLink = function(i) return i == 1 and "|Hitem:117::|h[Silk Robe]|h" or nil end
GetTradeSkillNumReagents = function(i) return i == 1 and 1 or 0 end
GetTradeSkillReagentInfo = function() return "Fine Thread", "icon", 2, 5 end
GetTradeSkillReagentItemLink = function() return "|Hitem:901::|h[Fine Thread]|h" end
GetTradeSkillNumMade = function() return 2, 2 end
local ts = Cr.forTradeSkill(1)
local function lineOf(lines, label) for _, l in ipairs(lines) do if l[1] == label then return l[2] end end end
check("trade skill: cost, two made and the profit", lineOf(ts, "Cost to craft") == "2s 00c"
  and lineOf(ts, "Sells for (x2)") == "~3g 80s AH" and lineOf(ts, "Profit") == "+3g 78s"
  and lineOf(ts, "Score of the made item") ~= nil)
check("trade skill: no reagents, no lines", Cr.forTradeSkill(2) == nil)
-- The game's recipe tooltip: GetItem gives the made item, the first line names the pattern.
INFO["Pattern: Silk Robe"] = { 118, 2, 25, "", 400, 9 }
byId[118] = "Pattern: Silk Robe"
tt = fakeTooltip("FakeTipE", "|Hitem:117::|h[Silk Robe]|h")
tt:AddLine("Pattern: Silk Robe")
Cr.onTooltip(tt)
check("craft: GetItem gives the made item, the first line finds the pattern", tt:find("Profit") == "+1g 88s")
tt = fakeTooltip("FakeTipF", "item:117")
Cr.onTooltip(tt, { id = 118 })
check("craft: the tooltip data id finds the pattern", tt:find("Cost to craft") == "2s 00c")
tt = fakeTooltip("FakeTipG", "|Hitem:117::|h[Silk Robe]|h")
tt:AddLine("Silk Robe")
Cr.onTooltip(tt)
check("craft: the made item itself gets no lines", #tt.lines == 1)
-- The made item from the game's recipe tooltip, when its name is unknown to the client.
ITEMS[120] = { loc = "", class = 9, lines = { "Pattern: Earthen Hood", "Earthen Hood", "Binds when equipped", "Head",
  "+10 Spirit", "Use: Teaches you how to craft Earthen Hood.", "Fine Thread (2), Elemental Earth (2)",
  "Requires Tailoring (150)" } }
INFO["Pattern: Earthen Hood"] = { 120, 2, 30, "", 300, 9 }
byId[120] = "Pattern: Earthen Hood"
byId[121] = "Earthen Hood"
INFO["Earthen Hood"] = { 121, 2, 30, "INVTYPE_HEAD", 500, 4, 2 }
local hoodInfo = INFO["Earthen Hood"]
INFO["Earthen Hood"] = nil -- not seen by name
local ahById = Auctionator.API.v1.GetAuctionPriceByItemID
Auctionator.API.v1.GetAuctionPriceByItemID = function(c, id)
  return ({ [121] = 9000, [7067] = 2000 })[id] or ahById(c, id) end
local function byIdInfo(id) local n = byId[id] return n and (INFO[n] or (id == 121 and hoodInfo)) and n end
local infoNow = C_Item.GetItemInfo
local earthSeen = false
C_Item.GetItemInfo = function(x)
  local id = tonumber(tostring(x):match("^item:(%d+)$"))
  if id == 121 then local v = hoodInfo return "Earthen Hood", "item:121", v[2], v[3], 1, "", "", 1, v[4], 0, v[5], v[6], 0, v[7] end
  if id == 7067 and earthSeen then return "Elemental Earth", "item:7067", 1, 25, 1, "", "", 10, "", 0, 100, 7 end
  return infoNow(x)
end
C_Item.RequestLoadItemDataByID = function(id) if id == 7067 then earthSeen = true end end
runTimers() -- the name pass started by earlier tests ends
Cr.NAME_COOLDOWN = 0
Auctionator.Database.db["7067"] = {}
tt = fakeTooltip("FakeTipH", "|Hitem:121::|h[Earthen Hood]|h")
tt:AddLine("Pattern: Earthen Hood")
Cr.onTooltip(tt)
check("craft: the made item from the recipe tooltip", tt:find("Sells for") == "~85s 50c AH")
check("craft: an unseen reagent name has no price at first", tt:find("  No price: Elemental Earth"))
runTimers()
check("craft: reagent names are learned from the Auctionator scan", UpgradeFinderDB.names["Elemental Earth"] == 7067)
tt = fakeTooltip("FakeTipI", "|Hitem:121::|h[Earthen Hood]|h")
tt:AddLine("Pattern: Earthen Hood")
Cr.onTooltip(tt)
check("craft: the learned name gives the price", tt:find("Cost to craft") == "42s 00c" and tt:find("Profit") == "+43s 50c")
SlashCmdList.UPGRADEFINDER("craft names")
check("/uf craft names says how many names it knows", chat[#chat]:match("item names: %d+ learned") ~= nil)
C_Item.GetItemInfo = infoNow
-- Transformations: Silk Cloth -> Bolt of Silk Cloth (built in), Copper Ore -> Copper Bar (learned).
local infoT = C_Item.GetItemInfo
local TNAMES = { [4306] = "Silk Cloth", [4305] = "Bolt of Silk Cloth", [2770] = "Copper Ore", [2840] = "Copper Bar" }
C_Item.GetItemInfo = function(x)
  local id = tonumber(tostring(x):match("^item:(%d+)$"))
  if id and TNAMES[id] then return TNAMES[id], "item:" .. id, 1, 10, 1, "", "", 20, "", 0, 50, 7 end
  return infoT(x)
end
local ahT = Auctionator.API.v1.GetAuctionPriceByItemID
Auctionator.API.v1.GetAuctionPriceByItemID = function(c, id)
  return ({ [4306] = 1000, [4305] = 5000, [2770] = 100, [2840] = 50 })[id] or ahT(c, id) end
tt = fakeTooltip("FakeTipJ", "item:4306")
Cr.onTooltip(tt)
-- 4 x 10s = 40s in; the bolt sells for 50s less 5% = 47s 50c.
check("transform: built-in bolt on the cloth tooltip", tt:find("Make into Bolt of Silk Cloth (4 each)") == "+7s 50c (40s 00c -> ~47s 50c)")
GetNumTradeSkills = function() return 2 end
GetTradeSkillInfo = function(i) return i == 1 and "Smelting" or "Copper Bar", i == 1 and "header" or "optimal" end
GetTradeSkillItemLink = function(i) return i == 2 and "|Hitem:2840::|h[Copper Bar]|h" or nil end
GetTradeSkillNumReagents = function(i) return i == 2 and 1 or 0 end
GetTradeSkillReagentInfo = function() return "Copper Ore", "icon", 1, 5 end
GetTradeSkillReagentItemLink = function() return "|Hitem:2770::|h[Copper Ore]|h" end
GetTradeSkillNumMade = function() return 1, 1 end
Cr.readTradeSkills()
check("transform: recipes learned from the profession window", UpgradeFinderDB.recipes[2840]
  and UpgradeFinderDB.recipes[2840].reagents[1][1] == 2770)
tt = fakeTooltip("FakeTipK", "item:2770")
Cr.onTooltip(tt)
check("transform: a loss shows red", tt:find("Make into Copper Bar (1 each)") == "-50c (1s 00c -> 50c)")
local n2 = #tt.lines
Cr.onTooltip(tt)
check("transform: added once", #tt.lines == n2)
-- Shopping for several crafts: 4 Silk Cloth and 1 Fine Thread per bolt.
local BAGS = { [4306] = 6, [901] = 10 }
GetItemCount = function(id, bank) return bank and BAGS[id] or 0 end
local made, conv = nil, {}
Auctionator.API.v1.ConvertToSearchString = function(_, t)
  table.insert(conv, t)
  return '"' .. t.searchString .. '";;;;;;;;;;;;;;' .. tostring(t.quantity)
end
Auctionator.API.v1.CreateShoppingList = function(_, name, terms) made = { name = name, terms = terms } end
GetTradeSkillSelectionIndex = function() return 3 end
GetTradeSkillInfo = function(i) return ({ "Smelting", "Copper Bar", "Bolt of Silk Cloth" })[i], i == 1 and "header" or "optimal" end
GetTradeSkillNumReagents = function(i) return i == 3 and 2 or (i == 2 and 1 or 0) end
GetTradeSkillReagentInfo = function(i, r)
  if i == 3 then return r == 1 and "Silk Cloth" or "Fine Thread", "icon", r == 1 and 4 or 1, 0 end
  return "Copper Ore", "icon", 1, 0
end
GetTradeSkillReagentItemLink = function(i, r)
  if i == 3 then return r == 1 and "|Hitem:4306::|h[Silk Cloth]|h" or "|Hitem:901::|h[Fine Thread]|h" end
  return "|Hitem:2770::|h[Copper Ore]|h"
end
TradeSkillInputBox = widget("TradeSkillInputBox")
function TradeSkillInputBox:GetNumber() return 3 end
local nChat = #chat
SlashCmdList.UPGRADEFINDER("shop")
local said = table.concat(chat, "\n", nChat + 1)
check("shop: the Create box count and what to buy", said:find("Shopping for 3x Bolt of Silk Cloth", 1, true)
  and said:find("Silk Cloth: buy 6 (need 12, have 6), 10s 00c each", 1, true) ~= nil)
check("shop: a reagent you have enough of", said:find("You have enough Fine Thread", 1, true) ~= nil)
check("shop: the estimated cost", said:find("Cost: about 60s 00c at the AH.", 1, true) ~= nil)
check("shop: the Auctionator list has the amount to buy", made and made.name == "UpgradeFinder crafts"
  and #made.terms == 1 and made.terms[1]:find('^"Silk Cloth"') and conv[1].quantity == 6 and conv[1].isExact)
check("shop: the bank is not counted before a visit", said:find("open your bank once", 1, true) ~= nil)
-- Shift: add 2 copper bars; the bank was seen.
Cr.bankSeen(true)
GetTradeSkillSelectionIndex = function() return 2 end
nChat = #chat
SlashCmdList.UPGRADEFINDER("shop add 2")
said = table.concat(chat, "\n", nChat + 1)
check("shop add: both recipes in one list", said:find("Shopping for 3x Bolt of Silk Cloth, 2x Copper Bar (less your bags and bank)", 1, true)
  and said:find("Copper Ore: buy 2 (need 2, have 0)", 1, true) and #made.terms == 2
  and said:find("Cost: about 62s 00c at the AH.", 1, true) ~= nil)
BAGS[4306], BAGS[2770] = 20, 5
nChat = #chat
local rows = Cr.shop(3, false, 3)
said = table.concat(chat, "\n", nChat + 1)
check("shop: nothing to buy", said:find("You have every reagent.", 1, true) ~= nil and rows[1].buy == 0)
GetTradeSkillSelectionIndex = function() return 1 end
nChat = #chat
SlashCmdList.UPGRADEFINDER("shop")
check("shop: a header is not a recipe", chat[#chat]:find("pick a recipe", 1, true) ~= nil)
SlashCmdList.UPGRADEFINDER("shop clear")
check("/uf shop clear", UpgradeFinderDB.shop == nil)
TradeSkillFrame, TradeSkillReagentLabel = widget("TradeSkillFrame"), widget("TradeSkillReagentLabel")
local sb = Cr.shopButton()
check("shop: a Shop button with the Create box count", sb and sb:GetText() == "Shop x3" and Cr.shopButton() == sb)
GetTradeSkillSelectionIndex = function() return 3 end
sb.scripts.OnClick(sb)
check("shop: the button shops for the selected recipe", UpgradeFinderDB.shop and UpgradeFinderDB.shop.crafts[1] == "3x Bolt of Silk Cloth")
nChat = #chat
SlashCmdList.UPGRADEFINDER("shop debug")
check("/uf shop debug says where the button is", tostring(chat[nChat + 1]):find("UpgradeFinderShopButton: shown", 1, true) ~= nil
  and tostring(chat[#chat]):find("last error", 1, true) ~= nil)
TradeSkillFrame, TradeSkillReagentLabel = nil, nil
-- Forever's modern profession window: ProfessionsFrame and C_TradeSkillUI.
GetTradeSkillSelectionIndex, GetTradeSkillInfo = nil, nil
Cr.forgetShopButton()
UpgradeFinderDB.shop = nil
BAGS[4306], BAGS[901] = 6, 10
local form = widget("SchematicForm")
form.Reagents = widget("Reagents")
form.Reagents.Label = widget("ReagentsLabel")
function form:GetRecipeInfo() return { recipeID = 3914, name = "Earthen Silk Hood" } end
function form:GetCurrentRecipeLevel() return 1 end
local inits = {}
function form:Init() end
hooksecurefunc = hooksecurefunc or function(t, k, fn) inits[#inits + 1] = fn end
local multi = widget("CreateMultipleInputBox")
function multi:GetValue() return 3 end
ProfessionsFrame = { CraftingPage = { SchematicForm = form, CreateMultipleInputBox = multi } }
Enum = Enum or {}
Enum.CraftingReagentType = { Basic = 0, Optional = 1 }
C_TradeSkillUI = { GetRecipeSchematic = function(id)
  if id ~= 3914 then return nil end
  return { reagentSlotSchematics = {
    { reagentType = 0, quantityRequired = 4, reagents = { { itemID = 4306 } } },
    { reagentType = 0, quantityRequired = 1, reagents = { { itemID = 901 } } },
    { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2770 } } }, -- optional: not bought
  } }
end }
local rn, rr = Cr.selectedRecipe()
check("professions: the selected recipe and its basic reagents", rn == "Earthen Silk Hood" and #rr == 2
  and rr[1][1] == 4306 and rr[1][2] == 4 and rr[1][3] == "Silk Cloth")
local pb = Cr.shopButton()
check("professions: the Shop button on the recipe pane", pb and pb:GetText() == "Shop x3")
nChat = #chat
pb.scripts.OnClick(pb)
said = table.concat(chat, "\n", nChat + 1)
check("professions: shop for 3 crafts", said:find("Shopping for 3x Earthen Silk Hood", 1, true)
  and said:find("Silk Cloth: buy 6 (need 12, have 6)", 1, true) ~= nil)
ProfessionsFrame, C_TradeSkillUI = nil, nil
Cr.forgetShopButton()
Cr.bankSeen(false)
Auctionator.API.v1.CreateShoppingList, Auctionator.API.v1.ConvertToSearchString = nil, nil
GetItemCount, TradeSkillInputBox = nil, nil
C_Item.GetItemInfo, Auctionator.API.v1.GetAuctionPriceByItemID = infoT, ahT
SlashCmdList.UPGRADEFINDER("craft")
tt = fakeTooltip("FakeTipD", "item:118")
Cr.onTooltip(tt)
check("/uf craft turns the lines off", #tt.lines == 0 and UpgradeFinderDB.opts.craft == false)
SlashCmdList.UPGRADEFINDER("craft")
C_Item.GetItemInfo = oldInfo

print(failures == 0 and "all UpgradeFinder tests passed" or (failures .. " UpgradeFinder test(s) failed"))
os.exit(failures == 0 and 0 or 1)
