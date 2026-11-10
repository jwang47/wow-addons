-- Offline tests for Omni with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/omni.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/omni%.lua$") or ""
local failures, chat, calls = 0, {}, {}
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function log(name, ...) table.insert(calls, { name = name, ... }) end
local function lastCall(name)
  for i = #calls, 1, -1 do if calls[i].name == name then return calls[i] end end
end

-- Generic widget: any unknown method is a no-op; scripts and text are kept.
local function widget(name)
  local w = { scripts = {}, text = "", shown = false, name = name }
  function w:SetScript(what, fn) self.scripts[what] = fn end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:IsShown() return self.shown end
  function w:SetText(t) self.text = t or "" if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, true) end end
  function w:GetText() return self.text end
  function w:RegisterEvent(e) self.events = self.events or {} self.events[e] = true end
  function w:CreateTexture() return widget() end
  function w:CreateFontString() local fs = widget() fs.SetText = function(s, t) s.text = t end return fs end
  -- Only method names (capitalised) fall back to a no-op.
  return setmetatable(w, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end
local frames = {}
function CreateFrame(kind, name)
  local f = widget(name)
  f.kind = kind
  if name then _G[name] = f end
  table.insert(frames, f)
  return f
end
UIParent = widget("UIParent")
UISpecialFrames = {}
BackdropTemplateMixin = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, strip(m)) end }
SlashCmdList = {}
GameTooltip = widget("GameTooltip")
function GameTooltip:SetHyperlink(l) self.link = l end
function GameTooltip:SetSpellByID(id) self.spell = id end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetOwner(o) self.owner = o end

local P = { level = 22, combat = false, shift = false, time = 1000, mapHere = 1436 }
function time() return P.time end
function UnitName(u) if u == "player" then return "Ded" end if u == "party1" then return "Ann", "Otherrealm" end end
function GetRealmName() return "Forever" end
function UnitLevel(u) return u == "player" and P.level or 20 end
function UnitClass() return "Priest", "PRIEST" end
function UnitFactionGroup() return "Alliance" end
function InCombatLockdown() return P.combat end
function IsShiftKeyDown() return P.shift end
local timers = {}
C_Timer = { After = function(_, f) table.insert(timers, f) end }
local function runTimers() while #timers > 0 do table.remove(timers, 1)() end end

-- Bags: bag 0 has Silk Cloth x12 and Linen Cloth x3. Bank (-1) and bank bag 5.
NUM_BAG_SLOTS = 4
local BAGS = {
  [0] = { { itemID = 4306, stackCount = 12, hyperlink = "|cffffffff|Hitem:4306|h[Silk Cloth]|h|r" },
    { itemID = 2589, stackCount = 3, hyperlink = "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r" } },
  [-1] = { { itemID = 4306, stackCount = 20, hyperlink = "|cffffffff|Hitem:4306|h[Silk Cloth]|h|r" } },
  [5] = { { itemID = 6948, stackCount = 1, hyperlink = "|cffffffff|Hitem:6948|h[Hearthstone]|h|r" } },
}
local bankVisible = false
C_Container = {
  GetContainerNumSlots = function(bag)
    if (bag == -1 or bag >= 5) and not bankVisible then return 0 end
    return BAGS[bag] and #BAGS[bag] or 0
  end,
  GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
}
Enum = { BagIndex = { Backpack = 0, Bank = -1 }, UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 },
  SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 } }
-- Mail: one letter with Wool Cloth x5.
function GetInboxNumItems() return 1 end
function GetInboxItem(i, a) if i == 1 and a == 1 then return "Wool Cloth", 2592, nil, 5 end end
function GetInboxItemLink() return nil end

local NAMES = { [4306] = "Silk Cloth", [2589] = "Linen Cloth", [2592] = "Wool Cloth", [6948] = "Hearthstone",
  [4338] = "Mageweave Cloth", [14047] = "Runecloth", [1179] = "Ice Cold Milk" }
C_Item = {
  GetItemNameByID = function(id) return NAMES[id] end,
  GetItemInfo = function(id) return NAMES[id], "|cffffffff|Hitem:" .. id .. "|h[" .. (NAMES[id] or "?") .. "]|h|r" end,
  GetItemIconByID = function() return 134400 end,
  RequestLoadItemDataByID = function(id) log("request", id) end,
}
-- Auctionator: price DB keys, a price API, an exact search.
local ahShown = false
AuctionHouseFrame = { IsShown = function() return ahShown end }
Auctionator = { Database = { db = { ["4338"] = {}, ["99999"] = {}, ["g:14047:20"] = {} } },
  API = { v1 = {
    GetAuctionPriceByItemID = function(_, id) return ({ [4306] = 2500, [4338] = 12000 })[id] end,
    GetAuctionAgeByItemID = function(_, id) return ({ [4338] = 3 })[id] end,
    MultiSearchExact = function(caller, names) log("ahsearch", caller, names[1]) end,
  } } }
MageMentorDB = { itemNames = { [1179] = "Ice Cold Milk" } }

-- Map: Azeroth 947 -> continents -> zones, a dungeon, a micro map, and a
-- duplicate "Stormwind City" as a micro map (dropped).
local MAPS = {
  { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
  { mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 947 },
  { mapID = 1436, name = "Westfall", mapType = 3, parentMapID = 1415 },
  { mapID = 1431, name = "Duskwood", mapType = 3, parentMapID = 1415 },
  { mapID = 1453, name = "Stormwind City", mapType = 3, parentMapID = 1415 },
  { mapID = 9001, name = "Stormwind City", mapType = 5, parentMapID = 1453 },
  { mapID = 9002, name = "The Deadmines", mapType = 4, parentMapID = 1436 },
  { mapID = 9003, name = "Moonbrook Inn", mapType = 5, parentMapID = 1436 },
}
local MAPINFO = {}
for _, m in ipairs(MAPS) do MAPINFO[m.mapID] = m end
C_Map = {
  GetFallbackWorldMapID = function() return 947 end,
  GetMapChildrenInfo = function(id, _, all) assert(id == 947 and all) return MAPS end,
  GetMapInfo = function(id) return MAPINFO[id] end,
  OpenWorldMap = function(id) log("map", id) end,
  GetBestMapForUnit = function() return P.mapHere end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(pt) log("waypoint", pt.mapID, pt.x, pt.y) return true end,
  GetMapRectOnMap = function(id, parent) if id == 1436 and parent == 1415 then return 0.4, 0.6, 0.5, 0.7 end end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) log("track", on) end }
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { mapID = m, x = x, y = y } end }
MageMentorZones = {
  { 10, 20, "Westfall", "A", "Sentinel Hill; finish before Deadmines" },
  { 18, 30, "Duskwood", "A", "Darkshire; a long, good quest hub" },
}

-- People: a friend (online), a guild member who is also a friend, a group
-- member from another realm.
C_FriendList = {
  GetNumFriends = function() return 2 end,
  GetFriendInfoByIndex = function(i)
    if i == 1 then return { name = "Bob", connected = true, level = 24, className = "Warrior", area = "Duskwood" } end
    return { name = "Cara", connected = false }
  end,
}
function IsInGuild() return true end
C_GuildInfo = { GuildRoster = function() end }
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(i)
  if i == 1 then return "Bob-Forever", "Member", 1, 24, "Warrior", "Duskwood", "", "", true end
  return "Dave-Forever", "Member", 1, 30, "Rogue", "Stranglethorn Vale", "", "", false
end
function GetNumGroupMembers() return 2 end
function IsInRaid() return false end
C_PartyInfo = { InviteUnit = function(n) log("invite", n) end }
function ChatFrame_SendTell(n) log("tell", n) end
function ChatEdit_InsertLink(l) log("insert", l) return false end
function ChatFrame_OpenChat(t) log("openchat", t) end

-- Spell book: one skill line with Frostbolt (two ranks), a passive, a future spell.
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { name = "Frost", itemIndexOffset = 0, numSpellBookItems = 4 } end,
  GetSpellBookItemInfo = function(slot)
    return ({
      { name = "Frostbolt", spellID = 116, subName = "Rank 3", itemType = 1, iconID = 1 },
      { name = "Frostbolt", spellID = 205, subName = "Rank 4", itemType = 1, iconID = 1 },
      { name = "Frost Armor", spellID = 168, isPassive = true, itemType = 1 },
      { name = "Frost Nova", spellID = 122, itemType = 2 },
    })[slot]
  end,
}
C_Spell = {
  PickupSpell = function(id) log("pickup", id) end,
  GetSpellLink = function(id) return "|Hspell:" .. id .. "|h[spell]|h" end,
}
SlashCmdList.MAGEMENTOR = function(msg) log("mm", msg) end

-- Questie (loaded after first open): pointer tables and single queries.
local questieReady = false
local NPC = { [234] = { name = "Gryan Stoutmantle", subName = "The People's Militia", spawns = { [40] = { { 56.3, 47.5 } } } },
  [235] = { name = "Salma Saldean", spawns = { [40] = { { 56.0, 31.2 } }, [10] = { { 1, 1 } } } },
  [639] = { name = "Edwin VanCleef", spawns = { [1581] = { { -1, -1 } } } } }
local QUEST = { [65] = { name = "The Defias Brotherhood", startedBy = { { 234 } }, questLevel = 18 } }
local ITEM = { [3307] = { name = "Gnoll Paw", npcDrops = { 235 } }, [4306] = { name = "Silk Cloth" } }
local AREA = { [40] = 1436, [10] = 1431, [1581] = 9002 }
local QuestieDB = {
  QueryNPCSingle = function(id, key) return NPC[id] and NPC[id][key] end,
  QueryQuestSingle = function(id, key) return QUEST[id] and QUEST[id][key] end,
  QueryItemSingle = function(id, key) return ITEM[id] and ITEM[id][key] end,
}
-- Questie's manual icons: ShowNPC adds frames, ResetManualFrames clears a type.
QuestieMapMock = { frames = {} }
function QuestieMapMock:ShowNPC(id, _, _, _, _, _, typ)
  log("qpin", id, typ)
  self.frames[typ] = self.frames[typ] or {}
  table.insert(self.frames[typ], id)
end
function QuestieMapMock:ResetManualFrames(typ) self.frames[typ] = nil end
local ZoneDB = { GetUiMapIdByAreaId = function(_, area) return AREA[area] end }
QuestieLoader = { ImportModule = function(_, name)
  if name == "QuestieDB" then
    if questieReady then
      QuestieDB.NPCPointers = { [234] = 1, [235] = 1, [639] = 1 }
      QuestieDB.QuestPointers = { 65 }
      QuestieDB.ItemPointers = { [3307] = 1, [4306] = 1 }
    end
    return QuestieDB
  end
  if name == "ZoneDB" then return ZoneDB end
  if name == "QuestieMap" then return QuestieMapMock end
end }

local bindings, saved = {}, nil
function GetBindingKey(action) for k, a in pairs(bindings) do if a == action then return k end end end
function GetBindingAction(key) return bindings[key] or "" end
function SetBinding(key, action) bindings[key] = action return true end
function GetCurrentBindingSet() return 2 end
function SaveBindings(set) saved = set end

-- Load the addon -----------------------------------------------------------
local ns = {}
for _, file in ipairs({ "Match.lua", "Sources.lua", "Actions.lua", "Omni.lua" }) do
  assert(loadfile(root .. "Omni/" .. file))("Omni", ns)
end
local events = ns.events
local function fire(ev, ...) events.scripts.OnEvent(events, ev, ...) end

local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end
local function names(groups, kind)
  for _, g in ipairs(groups) do
    if g.kind == kind then
      local list = {}
      for _, e in ipairs(g.entries) do table.insert(list, e.name) end
      return table.concat(list, ",")
    end
  end
  return ""
end

-- Matching -----------------------------------------------------------------
local M = ns.match
check("prefix scores 3", M.score("silk cloth", "sil") == 3)
check("word start scores 2", M.score("bolt of silk cloth", "silk") == 2)
check("words in any order score 2", M.score("bolt of silk cloth", "cloth silk") == 2)
check("substring scores 1", M.score("bolt of silk cloth", "ilk") == 1)
check("hyphen starts a word", M.score("ann-otherrealm", "other") == 2)
check("no match scores 0", M.score("silk cloth", "wool") == 0)
-- Fuzzy: initials or skipped letters, and one typo, below exact hits.
local function fz(name, q) return M.fuzzy({ lname = M.norm(name) }, (function()
  local t = {} for w in q:gmatch("%S+") do table.insert(t, w) end return t end)()) end
check("fuzzy: skipped letters", fz("Redridge Machete", "rdg mach"))
check("fuzzy: a typo", fz("Redridge Machete", "machette"))
check("fuzzy: a swapped pair", fz("Redridge Machete", "mahcete"))
check("fuzzy: a typo while still typing", fz("Redridge Machete", "redrid machx"))
check("fuzzy: not anything", not fz("Redridge Machete", "wool") and not fz("Silk Cloth", "slik wool"))
check("fuzzy: needs the first letter", not fz("Redridge Machete", "edrg"))
check("fuzzy: a swap of letters 2 and 3 is found", fz("Redridge Machete", "mcahete"))
check("fuzzy: a typo in the first two letters is not (README says so)", not fz("Redridge Machete", "mxchete"))
check("one edit: missing, extra, wrong", M.oneEdit("machete", "machte") and M.oneEdit("machete", "machette")
  and M.oneEdit("machete", "macxete") and not M.oneEdit("machete", "mxcxete"))
do
  local lists = { { { kind = "item", key = "item:1", name = "Redridge Machete", lname = "redridge machete" },
    { kind = "item", key = "item:2", name = "Machete", lname = "machete" } } }
  local g = M.search(lists, "machette")
  check("search: a typo still finds it", g[1] and #g[1].entries == 2)
  g = M.search(lists, "mach")
  check("search: exact hits do not pull in fuzzy ones", g[1] and #g[1].entries == 2 and g[1].best == 3)
  g = M.search(lists, "rd")
  check("search: no fuzzy for short queries", #g == 0)
end
check("filter i:", select(1, M.parse("i: Silk")) == "item" and select(2, M.parse("i: Silk")) == "silk")
check("filter @", select(1, M.parse("@bo")) == "person" and select(2, M.parse("@bo")) == "bo")
check("unknown tag is text", select(1, M.parse("foo:bar")) == nil)

do
  local list = {}
  for i = 1, 12 do table.insert(list, ns.sources.entry("item", i, "Cloth " .. i)) end
  table.insert(list, ns.sources.entry("item", 50, "Bolt of Cloth"))
  local g = M.search({ list }, "cloth", {})
  check("at most 8 per group", #g[1].entries == 8 and g[1].more == 5)
  check("prefix before word start", g[1].entries[1].name:find("^Cloth") ~= nil)
  local g2 = M.search({ list }, "cloth", { ["item:12"] = 5 })
  check("recent use ranks first within a tier", g2[1].entries[1].name == "Cloth 12")
  local g3 = M.search({ list }, "", { ["item:3"] = 5, ["item:50"] = 9 })
  check("empty query lists recent", g3[1].kind == "recent" and g3[1].entries[1].name == "Bolt of Cloth")
  -- Nearby is the first group, even when another group scores better.
  local near = ns.sources.entry("near", 7, "Clothier Ann")
  near.key, near.boost = "npc:7", -4
  local far = ns.sources.entry("near", 8, "Cloth Merchant")
  far.key, far.boost = "npc:8", -9
  local g4 = M.search({ list, { far, near } }, "cloth", {})
  check("Nearby group comes first", g4[1].kind == "near" and g4[2].kind == "item")
  local g5 = M.search({ list, { far, near } }, "", { ["item:50"] = 9, ["npc:7"] = 3 })
  check("empty query: Nearby nearest first, then Recent without repeats",
    g5[1].kind == "near" and g5[1].entries[1].name == "Clothier Ann" and g5[2].kind == "recent" and #g5[2].entries == 1)
end

check("ids: a list of ids", table.concat(ns.sources.ids({ 65 }), ",") == "65")
check("ids: id -> pointer map", table.concat(ns.sources.ids({ [234] = 7 }), ",") == "234")

-- Sources ------------------------------------------------------------------
fire("PLAYER_LOGIN")
check("binds Ctrl+Space at first login", bindings["CTRL-SPACE"] == "OMNI_TOGGLE" and saved == 2)
bindings = { ["CTRL-SPACE"] = "OMNI_TOGGLE" }
OmniDB.boundOnce = nil
check("keeps an existing Omni key", ns.defaultBinding() == false)
bindings = { ["CTRL-SPACE"] = "TOGGLEMUSIC" }
OmniDB.boundOnce = nil
chat = {}
check("does not take a used key", ns.defaultBinding() == false and chat[1]:find("taken") ~= nil)

check("bank IDs include -1 and 5..11", (function()
  local l = table.concat(ns.sources.bankBags(), ",")
  return l:find("^%-1,5,6") ~= nil and l:find("11$") ~= nil
end)())
check("bank scan needs the bank open", ns.sources.scanBank() == false)
bankVisible = true
fire("BANKFRAME_OPENED")
fire("BANKFRAME_CLOSED")
bankVisible = false
fire("MAIL_SHOW")
fire("MAIL_INBOX_UPDATE")
fire("MAIL_CLOSED")
local c = OmniDB.chars["Ded-Forever"]
check("bank saved", c.bank[4306] == 20 and c.bank[6948] == 1)
check("mail saved", c.mail[2592] == 5)

local items = ns.sources.items()
local byName = {}
for _, e in ipairs(items) do byName[e.name] = e end
check("silk: bags 12, bank 20", byName["Silk Cloth"].where.bags == 12 and byName["Silk Cloth"].where.bank == 20)
check("wool from mail", byName["Wool Cloth"].where.mail == 5)
check("AH scan item named", byName["Mageweave Cloth"] and byName["Mageweave Cloth"].ah)
check("gear key g:ID:level read", byName["Runecloth"] and byName["Runecloth"].ah)
check("MageMentor names used", byName["Ice Cold Milk"] ~= nil)
check("unknown AH item requested", lastCall("request") and lastCall("request")[1] == 99999)
check("names saved for next time", OmniDB.itemNames[4338] == "Mageweave Cloth")

local places = ns.sources.places()
local pn = {}
for _, e in ipairs(places) do pn[e.name] = e end
check("zones, continents, dungeons", pn.Westfall and pn.Kalimdor and pn["The Deadmines"])
check("micro maps dropped", pn["Moonbrook Inn"] == nil and pn["Stormwind City"].id == 1453)
check("MageMentor range on a place", pn.Duskwood.levels == "18-30" and pn.Duskwood.fits and not pn.Westfall.fits)
check("place detail names the continent", pn.Westfall.detail == "zone, Eastern Kingdoms")

fire("CHAT_MSG_WHISPER", "hi", "Eve-Forever")
fire("CHAT_MSG_WHISPER_INFORM", "yo", "Bob-Forever")
local people = ns.sources.people()
local pp = {}
for _, e in ipairs(people) do pp[e.name] = e end
check("friend + guild + whisper merge", pp.Bob and pp.Bob.detail:find("friend, guild, whisper") == 1)
check("group member with realm", pp.Ann and pp.Ann.full == "Ann-Otherrealm")
check("whisper partner listed", pp.Eve and pp.Eve.full == "Eve-Forever")
check("online friend shows zone", pp.Bob.detail:find("Duskwood") ~= nil)

local spells = ns.sources.spells()
check("one Frostbolt, top rank, no passive or future", #spells == 1 and spells[1].spellID == 205)
check("commands from MageMentor", #ns.sources.commands() > 5)

-- Search box ---------------------------------------------------------------
ns.open()
local box = OmniSearchBox
check("box opens", OmniFrame:IsShown())
box:SetText(" ")
check("opening key's space is dropped", box:GetText() == "")
runTimers() -- clears justOpened; Questie is not ready yet
check("questie waits until its DB is ready", ns.sources.questieState.state == "waiting")

box:SetText("silk")
local g = ns.search("silk")
check("silk finds the item", names(g, "item") == "Silk Cloth")
check("detail shows where and AH", strip(ns.actions.detail(g[1].entries[1])) == "bags 12  bank 20  AH 25s 0c")
do
  local A = ns.actions
  local saved = time
  time = function() return 100000 end
  Auctionator.SavedState = { TimeOfLastBrowseScan = 100000 - 7200 }
  check("AH age: days old", A.ahAge(4338) == "3d old" and A.ahAge(4306) == nil)
  Auctionator.API.v1.GetAuctionAgeByItemID = function(_, id) return id == 4306 and 0 or nil end
  check("AH age in the row", strip(A.detail(g[1].entries[1])) == "bags 12  bank 20  AH 25s 0c  today")
  check("last scan: the newer stamp", A.lastScan() == 92800 and A.ago(A.lastScan()) == "2h ago")
  Auctionator.SavedState.TimeOfLastGetAllScan = 100000 - 120
  check("last scan: a newer full scan wins", A.ago(A.lastScan()) == "2m ago")
  local lines = {}
  local tt = { SetHyperlink = function() end, AddLine = function(_, l) table.insert(lines, l) end, Show = function() end }
  A.tooltip(tt, g[1].entries[1])
  check("tooltip: price age and last scan", lines[1] == "AH price seen today; AH scan 2m ago")
  LootValue = { scanText = function() return "AH scan 5m ago" end }
  check("LootValue's wording wins when loaded", A.scanText() == "AH scan 5m ago")
  LootValue.scanText = function() return nil end
  check("LootValue gives nil: our own text", A.scanText() == "AH scan 2m ago")
  LootValue.scanText = function() error("boom") end
  check("LootValue throws: our own text", A.scanText() == "AH scan 2m ago")
  LootValue = nil
  local ageApi = Auctionator.API.v1.GetAuctionAgeByItemID
  Auctionator.API.v1.GetAuctionAgeByItemID = nil
  lines = {}
  A.tooltip(tt, g[1].entries[1])
  check("no age API: no made-up age, scan time only", lines[1] == "AH scan 2m ago")
  Auctionator.API.v1.GetAuctionAgeByItemID = ageApi
  Auctionator.SavedState = nil
  check("no saved state: no scan time", A.lastScan() == nil and A.scanText() == nil)
  time = saved
end
box.scripts.OnEnterPressed(box)
check("Enter links the item", lastCall("openchat") and lastCall("openchat")[1]:find("item:4306") ~= nil)
check("recent saved", OmniDB.recent["item:4306"] == 1000)
check("box closes after an action", not OmniFrame:IsShown())

ns.open("i: mage")
ahShown = true
ns.refresh()
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("Enter at the AH runs Auctionator search", lastCall("ahsearch") and lastCall("ahsearch")[2] == "Mageweave Cloth")
ahShown = false

ns.open("dusk")
g = ns.search("dusk")
check("dusk: place and person (Bob's zone is not his name)", names(g, "place") == "Duskwood" and names(g, "person") == "")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("Enter opens the map", lastCall("map")[1] == 1431)

ns.open("@bo")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("Enter whispers the full name", lastCall("tell")[1] == "Bob-Forever")
ns.open("ann")
P.shift = true
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
P.shift = false
check("Shift+Enter invites", lastCall("invite")[1] == "Ann-Otherrealm")

ns.open("frostb")
P.combat = true
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("no spell pickup in combat", lastCall("pickup") == nil and OmniFrame:IsShown())
P.combat = false
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("Enter puts the spell on the cursor", lastCall("pickup")[1] == 205)

ns.open("tailoring")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("Enter runs the MageMentor command", lastCall("mm")[1] == "tailoring")

-- Arrow keys skip group headers.
ns.open("cloth")
local first = 0
for i, r in ipairs((function() local v = ns.layout(ns.search("cloth")) return v end)()) do
  if r.entry and first == 0 then first = i end
end
check("first pick is the first entry, not a header", first == 2)

-- Questie --------------------------------------------------------------------
questieReady = true
ns.close()
ns.sources.QUESTIE_SLICE = 2
ns.open("gry")
check("questie indexes over several frames", ns.sources.questieState.state == "busy")
runTimers()
check("questie index done", ns.sources.questieState.state == "done")
g = ns.search("gry")
check("NPC on your map found in Nearby", names(g, "near") == "Gryan Stoutmantle" and names(g, "npc") == "")
OmniSearchBox:SetText("gry")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
local wp = lastCall("waypoint")
check("NPC: map pin at the spawn", wp and wp[1] == 1436 and math.abs(wp[2] - 0.563) < 1e-6)
check("NPC: chat says where", chat[#chat]:find("Westfall %(56, 48%), map pin set") ~= nil)
check("NPC: the pin is tracked", lastCall("track") and lastCall("track")[1] == true)
check("NPC: Questie's own icon too", lastCall("qpin") ~= nil and lastCall("qpin")[2] == "omni")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("Enter twice: still one Questie icon", #QuestieMapMock.frames.omni == 1)

-- The game refuses the pin: no tracking, and chat says so.
local setter = C_Map.SetUserWaypoint
C_Map.SetUserWaypoint = function(pt) log("waypoint", pt.mapID) return false end
calls = {}
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("refused pin: not tracked", lastCall("track") == nil and chat[#chat]:find("no map pin here") ~= nil)
C_Map.SetUserWaypoint = setter

-- A map that takes no user pin: the pin goes on its parent, moved there.
calls = {}
C_Map.CanSetUserWaypointOnMap = function(id) return id ~= 1436 end
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
wp = lastCall("waypoint")
check("no pin on the zone: parent map instead", wp and wp[1] == 1415
  and math.abs(wp[2] - (0.4 + 0.563 * 0.2)) < 1e-6)
C_Map.CanSetUserWaypointOnMap = function() return false end
calls = {}
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("no map takes a pin: says so", lastCall("waypoint") == nil and chat[#chat]:find("no map pin here") ~= nil)
C_Map.CanSetUserWaypointOnMap = function() return true end

-- Another addon swallows OpenWorldMap: the map is toggled open.
WorldMapFrame = { shown = false, IsShown = function(self) return self.shown end,
  SetMapID = function(self, id) log("setmap", id) end }
ToggleWorldMap = function() WorldMapFrame.shown = true log("toggle") end
calls = {}
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("hidden map after OpenWorldMap is toggled open", lastCall("toggle") ~= nil and lastCall("setmap")[1] == 1436)
calls = {}
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("an open map is not toggled shut", lastCall("toggle") == nil)
WorldMapFrame, ToggleWorldMap = nil, nil

calls = {}
P.mapHere = 1431
ns.open("salma")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("spawn on your map is preferred", lastCall("waypoint")[1] == 1431)
P.mapHere = 1436

calls = {}
ns.open("vancleef")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("dungeon NPC opens the map, no pin", lastCall("map")[1] == 9002 and lastCall("waypoint") == nil)

-- Nearby: NPCs on the map you stand on, by name or title, nearest first,
-- with the distance in yards.
C_Map.GetPlayerMapPosition = function(m) return { GetXY = function() return 0.56, 0.25 end } end
C_Map.GetMapWorldSize = function(m) return 1000, 500 end
ns.close()
ns.open("")
g = ns.search("militia")
check("Nearby matches the NPC's title", names(g, "near") == "Gryan Stoutmantle")
g = ns.search("near:")
check("near: alone lists all nearby, nearest first", names(g, "near") == "Salma Saldean,Gryan Stoutmantle")
g = ns.search("")
check("empty query shows Nearby first, nearest first", g[1] and g[1].kind == "near" and names(g, "near") == "Salma Saldean,Gryan Stoutmantle")
check("off-map NPCs are not nearby", names(ns.search("vancleef"), "near") == "" and names(ns.search("vancleef"), "npc") == "Edwin VanCleef")
check("n: also finds nearby NPCs", names(ns.search("n: gryan"), "near") == "Gryan Stoutmantle")
local salma
for _, grp in ipairs(g) do if grp.kind == "near" then salma = grp.entries[1] end end
-- dx = 0 yd, dy = (0.312 - 0.25) * 500 = 31 yd
check("Nearby shows yards", strip(ns.actions.detail(salma)) == "31 yd")
calls = {}
ns.actions.run(salma)
wp = lastCall("waypoint")
check("Nearby Enter pins that spawn", wp and wp[1] == 1436 and math.abs(wp[3] - 0.312) < 1e-6)
-- Ranking uses yards: on a 1000 x 500 map, (0.08, 0) is 80 yd, (0, 0.10) is 50 yd.
NPC[236] = { name = "Twin Scout", spawns = { [40] = { { 64, 25 }, { 56, 35 } } } }
QuestieDB.NPCPointers[236] = 1
local twin
for _, en in ipairs(ns.sources.nearby()) do if en.id == 236 then twin = en end end
check("Nearby: none yet for an NPC added after the index", twin == nil)
NPC[236], QuestieDB.NPCPointers[236] = nil, nil
do
  local list = ns.sources.nearState.byMap[1436]
  table.insert(list, { id = 237, name = "Twin Scout", points = { { 0.64, 0.25 }, { 0.56, 0.35 } } })
  for _, en in ipairs(ns.sources.nearby()) do if en.id == 237 then twin = en end end
  check("Nearby: nearest spawn in yards, not map units", twin and twin.y == 0.35)
  table.remove(list)
end
C_Map.GetMapWorldSize = nil
check("no map size: no yards", strip(ns.actions.detail(salma)) == "")
C_Map.GetPlayerMapPosition = nil

ns.open("q: defias")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("quest shows its start NPC", lastCall("waypoint")[1] == 1436 and chat[#chat]:find("from Gryan") ~= nil)
local function questRow(q)
  for _, grp in ipairs(ns.search(q)) do if grp.kind == "quest" then return grp.entries[1] end end
end
check("quest detail: not taken", strip(ns.actions.detail(questRow("q: defias"))) == "not taken  level 18")
QUEST[65].requiredLevel = 25
check("quest detail: needs a higher level", strip(ns.actions.detail(questRow("q: defias"))) == "needs level 25  level 18")
QUEST[65].requiredLevel = nil
IsQuestFlaggedCompleted = function(id) return id == 65 end
check("quest detail: done (older API)", strip(ns.actions.detail(questRow("q: defias"))) == "done  level 18")
IsQuestFlaggedCompleted = nil

g = ns.search("gnoll")
check("quest item in Items", names(g, "item") == "Gnoll Paw")
ns.open("gnoll paw")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("quest item shows where it drops", chat[#chat]:find("drops from Salma") ~= nil)
g = ns.search("silk cloth")
check("Questie copy of an owned item is not listed twice", names(g, "item") == "Silk Cloth")

-- Your quest log ----------------------------------------------------------------
local QLOG = { { "Westfall", 0, nil, true }, { "The Forgotten Heirloom", 17, nil, false, nil, nil, nil, 64 },
  { "The Defias Brotherhood", 18, nil, false, nil, 1, nil, 65 } }
function GetNumQuestLogEntries() return #QLOG end
function GetQuestLogTitle(i) local q = QLOG[i] if q then return unpack(q, 1, 8) end end
function SelectQuestLogEntry(i) log("select", i) end
function QuestLog_SetSelection(i) log("setsel", i) end
function QuestLog_Update() log("qlupdate") end
function GetQuestLink(id) return "|Hquest:" .. id .. "|h[q]|h" end
QuestLogFrame = widget("QuestLogFrame")
QuestLogListScrollFrameScrollBar = { SetValue = function(_, v) log("scroll", v) end }
function ShowUIPanel(f) f:Show() log("showpanel") end
ns.close()
ns.open("") -- the index is rebuilt on open
g = ns.search("defias")
check("log quest is found", names(g, "log") == "The Defias Brotherhood")
check("Questie copy of a log quest is not listed twice", names(g, "quest") == "")
check("q: finds quests in your log", names(ns.search("q: heirloom"), "log") == "The Forgotten Heirloom")
local defias
for _, grp in ipairs(g) do if grp.kind == "log" then defias = grp.entries[1] end end
check("log detail: done, level, zone", strip(ns.actions.detail(defias)) == "done  level 18  Westfall")
calls = {}
ns.open("defias")
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("Enter opens the quest log at the quest", QuestLogFrame:IsShown() and lastCall("select")[1] == 3
  and lastCall("setsel")[1] == 3 and lastCall("scroll")[1] == 0)
table.insert(QLOG, 2, { "Elwynn Forest", 0, nil, true }) -- the log changed after the box opened
calls = {}
ns.actions.run(defias)
check("quest found again by ID when the log moves", lastCall("setsel")[1] == 4)
calls = {}
ns.actions.run(defias, true)
check("Shift+Enter links the quest", lastCall("openchat")[1]:find("quest:65") ~= nil)
QLOG = {}

-- A quest under a collapsed header: the game does not list it, so Omni
-- shows Questie's row, says it is in your log, and opens the log there.
QLOG = { { "Westfall", 0, nil, true } }
local expanded = false
function ExpandQuestHeader(i)
  log("expand", i)
  if not expanded then expanded = true table.insert(QLOG, { "The Defias Brotherhood", 18, nil, false, nil, nil, nil, 65 }) end
end
C_QuestLog = { IsOnQuest = function(id) return id == 65 end }
ns.close()
ns.open("")
local row = questRow("q: defias")
check("collapsed quest: Questie row says in your log", row and strip(ns.actions.detail(row)) == "in your log  level 18")
check("collapsed quest: hint says quest log", ns.actions.hint(row):find("open in the quest log") ~= nil)
calls = {}
ns.actions.run(row)
check("collapsed quest: Enter expands and opens the log at it", lastCall("expand")[1] == 0 and lastCall("setsel")[1] == 2)
calls = {}
ns.actions.run(row, true)
check("collapsed quest: Shift+Enter shows where it starts", lastCall("waypoint") ~= nil)
C_QuestLog.IsOnQuest = function() return false end
C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 65 end
check("quest detail: done", strip(ns.actions.detail(row)) == "done  level 18")
C_QuestLog, ExpandQuestHeader, QLOG = nil, nil, {}
-- Older clients: no C_QuestLog.IsOnQuest, so the log index decides, and
-- being in the log wins over a done flag.
local idx = 3
GetQuestLogIndexByID = function() return idx end
IsQuestFlaggedCompleted = function() return true end
check("old API: a log index means in your log", ns.actions.questStatus(65) == "log")
idx = 0
check("old API: index 0 is not in the log", ns.actions.questStatus(65) == "done")
idx = nil
IsQuestFlaggedCompleted = nil
check("old API: no index is not in the log", ns.actions.questStatus(65) == nil)
GetQuestLogIndexByID = nil

-- Astra round 1 regressions ---------------------------------------------------
-- A quest item whose name is cached but which you no longer carry still
-- shows where it drops; a zero count is not "owned".
OmniDB.itemNames[3307] = "Gnoll Paw"
OmniDB.chars["Ded-Forever"].mail[3307] = 0
ns.open("gnoll paw")
chat = {}
OmniSearchBox.scripts.OnEnterPressed(OmniSearchBox)
check("cached quest item still shows its drops", chat[#chat] and chat[#chat]:find("drops from Salma") ~= nil)

-- Every group is reachable with the arrow keys, and the view scrolls.
do
  local list = {}
  for _, kind in ipairs({ "item", "place", "person", "npc", "quest" }) do
    for i = 1, 8 do table.insert(list, ns.sources.entry(kind, i, "Zed " .. kind .. " " .. i)) end
  end
  local v = ns.view
  v.rows = ns.layout(M.search({ list }, "zed", {}))
  check("five full groups give 45 rows", #v.rows == 45)
  v.pick, v.top = 2, 1
  local seen, visible = {}, true
  for _ = 1, 40 do
    seen[v.rows[v.pick].entry.key] = true
    ns.move(1)
    if v.pick < v.top or v.pick > v.top + ns.MAX_ROWS - 1 then visible = false end
  end
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  check("arrows reach all 40 entries", count == 40)
  check("the picked row stays on screen", visible)
  v.pick, v.top = 2, 1
  local kinds = {}
  for _ = 1, 5 do table.insert(kinds, v.rows[v.pick].entry.kind) ns.nextGroup(1) end
  check("Tab steps through the groups", table.concat(kinds, ",") == "item,place,person,npc,quest")
  ns.nextGroup(-1)
  check("Shift+Tab goes back a group", v.rows[v.pick].entry.kind == "quest")
end

-- Place advice follows a level-up.
P.level = 31
local after = {}
for _, e in ipairs(ns.sources.places()) do after[e.name] = e end
check("Duskwood no longer fits at 31", after.Duskwood.fits == false)
P.level = 22

-- LootValue without Auctionator: one chat line at login.
do
  local loaded = { Auctionator = false }
  C_AddOns = { GetAddOnInfo = function(n) if n == "LootValue" then return "LootValue" end end,
    IsAddOnLoaded = function(n) return loaded[n] end }
  chat = {}
  check("warns when LootValue is there without Auctionator", ns.checkAuctionator() and chat[1]:find("needs the Auctionator") ~= nil)
  loaded.Auctionator = true
  check("no warning with Auctionator on", ns.checkAuctionator() == false)
  C_AddOns.GetAddOnInfo = function() return nil end
  loaded.Auctionator = false
  check("no warning without LootValue", ns.checkAuctionator() == false)
  C_AddOns = nil
end

-- The "Equipped" comparison: a layout whose whole box fits (right of the
-- item tooltip, a row below, a column below), each comparison anchored to
-- GameTooltip only. Only for Omni's own tooltip.
do
  local function shop(name, w, h)
    local t = widget(name)
    t.shown, t.GetWidth, t.GetHeight = true, function() return w end, function() return h end
    t.GetEffectiveScale = function() return t.scale or 1 end
    t.SetPoint = function(self, a, rel, b, x, y) self.at = { a, rel, b, x, y } end
    _G[name] = t
    return t
  end
  local s1, s2 = shop("ShoppingTooltip1", 300, 400), shop("ShoppingTooltip2", 300, 400)
  ns.open("silk")
  GameTooltip.owner = OmniFrame
  UIParent.GetRight = function() return 1700 end
  local tl, tr, tb = 700, 1000, 600
  GameTooltip.GetLeft = function() return tl end
  GameTooltip.GetRight = function() return tr end
  GameTooltip.GetBottom = function() return tb end
  local function place() s1.at, s2.at = nil, nil return ns.placeCompare() end
  check("compare: right of the item tooltip when the row fits",
    place() == "right" and s1.at[2] == GameTooltip and s1.at[3] == "TOPRIGHT" and s1.at[4] == 2
    and s2.at[2] == GameTooltip and s2.at[4] == 304)
  tr = 1500
  check("compare: no room right, a row below", place() == "row" and s1.at[3] == "BOTTOMLEFT"
    and s2.at[2] == GameTooltip and s2.at[4] == 302)
  tl, tb = 1200, 900
  check("compare: row too wide, a column below", place() == "column" and s2.at[3] == "BOTTOMLEFT" and s2.at[5] == -404)
  tb = 500
  check("compare: nothing fits, the game's layout stays", place() == nil and s1.at == nil)
  tl, tr, tb = 300, 400, 600
  s1.scale, s2.scale = 2, 2 -- 600 screen pixels wide each
  check("compare: offsets in the comparison's own scale", place() == "right" and s1.at[4] == 1 and s2.at[4] == 302)
  s1.scale, s2.scale = nil, nil
  GameTooltip.owner = UIParent
  check("compare: another addon's tooltip is left alone", place() == nil and s1.at == nil)
  ns.close()
  ShoppingTooltip1, ShoppingTooltip2 = nil, nil
  GameTooltip.GetLeft, GameTooltip.GetRight, GameTooltip.GetBottom = nil, nil, nil
end

-- Search spread over frames, narrowing, stale searches, Enter --------------
do
  -- M.search: narrow looks only at the given entries; matched lists exact hits.
  local list = {}
  for i = 1, 50 do table.insert(list, ns.sources.entry("item", i, (i <= 5 and "Silk " or "Wool ") .. i)) end
  local visits = 0
  local g, matched = M.search({ list }, "sil", {}, { tick = function() visits = visits + 1 end })
  check("matched holds every exact hit", #matched == 5)
  local scored = 0
  local score = M.score
  M.score = function(...) scored = scored + 1 return score(...) end
  g = M.search({ list }, "silk", {}, { narrow = matched })
  M.score = score
  check("narrow: only the last hits are scored", scored == 5 and #g[1].entries == 5)
  local exactFirst
  M.search({ list }, "woo", {}, { onExact = function(eg) exactFirst = #eg end })
  check("onExact runs only when a fuzzy pass follows", exactFirst == nil)
  M.search({ list }, "slik", {}, { onExact = function(eg) exactFirst = #eg end })
  check("onExact gets the exact groups before fuzzy", exactFirst == 0)

  -- In Omni: a fake clock that moves 1 ms per read makes the search yield.
  local big = {}
  for i = 1, 3000 do table.insert(big, ns.sources.entry("item", 10000 + i, "Zed thing " .. i)) end
  local t = 0
  debugprofilestop = function() t = t + 1 return t end
  local M_TICK = M.TICK
  M.TICK = 100
  ns.open("")
  local lists0 = ns.rebuild()
  table.insert(lists0, big)
  OmniSearchBox:SetText("zed")
  check("sliced: the first frame does not finish", ns.view.rows[1] == nil or ns.perf.text ~= "zed")
  runTimers()
  check("sliced: results after more frames", ns.perf.text == "zed" and ns.perf.frames > 1
    and ns.view.rows[2] and ns.view.rows[2].entry.name:find("Zed") ~= nil)
  OmniSearchBox:SetText("zed t")
  OmniSearchBox:SetText("zed th")
  runTimers()
  check("stale searches are dropped", ns.perf.text == "zed th")
  OmniSearchBox:SetText("zed thing 2999")
  ns.act(false) -- before any timer runs
  check("Enter finishes the search first", ns.perf.text == "zed thing 2999")

  -- Enter acts on the picked entry even when the fuzzy hits land first.
  for i = 1, 3000 do big[i].lname = "qqq " .. i big[i].name = "Qqq " .. i end
  big[1].lname, big[1].name = "zork alpha", "Zork Alpha"
  big[2].lname, big[2].name = "zork beta", "Zork Beta"
  big[3].lname, big[3].name = "zrok gamma", "Zrok Gamma" -- a fuzzy hit for "zork"
  OmniSearchBox:SetText("zork")
  local guard = 0
  local function nameAt(i) local r = ns.view.rows[i] return r and r.entry and r.entry.name or "" end
  while not nameAt(2):find("^Zork") and #timers > 0 and guard < 200 do table.remove(timers, 1)() guard = guard + 1 end
local second = nameAt(3)
  check("exact hits show before the fuzzy pass ends", ns.perf.text ~= "zork" and second:find("^Zork ") ~= nil)
  ns.view.pick = 3
  local ran
  local run = ns.actions.run
  ns.actions.run = function(e) ran = e.name return false end
  ns.act(false)
  check("Enter acts on the picked entry, not the first after fuzzy lands", ran == second)
  ns.actions.run = run

  -- Closing between slices stops the search: nothing paints afterwards.
  OmniSearchBox:SetText("qqq 299")
  GameTooltip:Hide()
  ns.close()
  runTimers()
  check("close cancels a running search", ns.perf.text ~= "qqq 299" and not GameTooltip:IsShown())
  debugprofilestop, M.TICK = nil, M_TICK
  ns.close()
  ns.rebuild()
end

-- Narrowing keeps every exact candidate, also other names for one key.
do
  local a = { kind = "item", key = "item:9", name = "Silk Cloth", lname = "silk cloth" }
  local b = { kind = "item", key = "item:9", name = "Silken Thread", lname = "silken thread" }
  local lists = { { a }, { b } }
  local _, matched = M.search(lists, "sil", {})
  check("matched keeps both names of one key", #matched == 2)
  local full = M.search(lists, "silken", {})
  local narrowed = M.search(lists, "silken", {}, { narrow = matched })
  check("narrowed equals full when names share a key", full[1].entries[1] == b and narrowed[1].entries[1] == b
    and narrowed[1].best == full[1].best)
end

-- A source that throws gives an empty group and one chat line, not an error.
do
  local S = ns.sources
  local real = S.people
  S.people = function() error("bad level") end
  local before = #chat
  local ok = pcall(ns.rebuild)
  check("a failing source does not break the box", ok and #chat == before + 1 and chat[#chat]:find("people error") ~= nil)
  pcall(ns.rebuild)
  check("a failing source is reported once", #chat == before + 1)
  S.people = real
end

-- Recent keys are trimmed to the newest ns.RECENT_KEPT.
do
  local recent = {}
  for k = 1, ns.RECENT_KEPT + 50 do recent["k" .. k] = k end
  ns.trimRecent(recent)
  local n = 0
  for _ in pairs(recent) do n = n + 1 end
  check("recent is trimmed", n == ns.RECENT_KEPT and recent["k" .. (ns.RECENT_KEPT + 50)] and not recent.k1)
end

print(failures == 0 and "all Omni tests passed" or (failures .. " Omni test(s) failed"))
os.exit(failures == 0 and 0 or 1)
