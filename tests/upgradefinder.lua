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
function CreateFrame(kind, name)
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
    return id, nil, nil, ITEMS[id] and ITEMS[id].loc
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

for _, file in ipairs({ "Score.lua", "Scan.lua", "Where.lua", "UI.lua", "Weights.lua" }) do
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
SlashCmdList.UPGRADEFINDER("weight reset")

-- Slot column -------------------------------------------------------------------
check("slot name for a ring", S.groupName("INVTYPE_FINGER") == "Ring")
check("slot name for a robe", S.groupName("INVTYPE_ROBE") == "Chest")
check("slot name for a wand", S.groupName("INVTYPE_WAND") == "Ranged")
check("no slot name for a non-slot", S.groupName("INVTYPE_BAG") == nil)
local sawSlot = false
for _, t in ipairs(slotTexts) do if t == "Head" or t == "Ring" or t == "Weapon" then sawSlot = true end end
check("rows show their slot", sawSlot)

print(failures == 0 and "all UpgradeFinder tests passed" or (failures .. " UpgradeFinder test(s) failed"))
os.exit(failures == 0 and 0 or 1)
