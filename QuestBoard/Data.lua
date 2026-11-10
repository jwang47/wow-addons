-- QuestBoard data: the quests in your log and the quests you can pick up,
-- with level fit, XP, distance and an XP-per-minute estimate. It reads
-- Questie's modules when Questie is loaded (positions, XP, available quests)
-- and the game's quest log otherwise. Questie has no public API and its
-- internals change between versions, so every Questie call is guarded.
local addonName, ns = ...
local D = {}
ns.data = D

-- Time model for the XP-per-minute estimate (seconds). Plain guesses, kept
-- in one place: a run to the place, a fixed cost per unfinished objective,
-- and a fixed cost for the way back to the quest giver.
D.RUN_SPEED = 7          -- yards per second on foot
D.OBJECTIVE_SECS = 90    -- one objective of a quest you do not have yet
D.UNIT_SECS = 30         -- one kill or loot, until the board knows your pace
D.RETURN_SECS = 60       -- back to the finisher after the objectives
D.PICKUP_SECS = 30       -- talk to the giver
D.FAR = 500000           -- Questie's distance for another continent or instance
D.BUDGET_MS = 3          -- work per frame when reading the available quests
D.ACTIVE_SECS = 300      -- a quest whose count went up this recently is "active"
D.NEAR_YARDS, D.MID_YARDS = 300, 1000   -- distance colours; past MID the XP sorts
D.HERE_YARDS = 300       -- "Nearby": a log quest whose open objective is this close
-- Once active, a quest stays: while you are within STAY_YARDS of its open
-- objective or make progress, and for GRACE_SECS after the last of either.
-- Hunting for the right mobs often takes you out of the entry range.
D.STAY_YARDS = 600
D.GRACE_SECS = 600

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end
D.call = call

-- A number the addon may compare (the Forever client hides some values).
local function plain(v)
  if type(v) ~= "number" then return nil end
  local secret = rawget(_G, "issecretvalue")
  if secret and secret(v) then return nil end
  return v
end
D.plain = plain

local function api(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end
D.api = api

---------------------------------------------------------------------------
-- Questie modules (nil when Questie is not loaded or has changed)
---------------------------------------------------------------------------
local cache = {}
function D.module(name)
  if cache[name] then return cache[name] end
  local loader = rawget(_G, "QuestieLoader")
  if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
  local ok, m = pcall(loader.ImportModule, loader, name)
  if ok and type(m) == "table" then cache[name] = m return m end
end
function D.resetModules() cache = {} end

function D.hasQuestie()
  return D.module("QuestieDB") ~= nil and D.module("DistanceUtils") ~= nil
end

---------------------------------------------------------------------------
-- Level fit
---------------------------------------------------------------------------
function D.playerLevel() return plain(call(rawget(_G, "UnitLevel"), "player")) or 1 end

-- How many levels below you a quest still gives full XP (green).
function D.greenRange(level)
  local fn = rawget(_G, "GetQuestGreenRange")
  local r = plain(call(fn, "player")) or plain(call(fn))
  if r then return r end
  if level <= 5 then return 5 end
  if level <= 39 then return 5 + math.floor(level / 10) end
  return 1 + math.floor(level / 5)
end

-- "red", "orange", "yellow", "green" or "grey", as the quest log colours it.
function D.difficulty(questLevel, level)
  level = level or D.playerLevel()
  if not questLevel or questLevel <= 0 then return "yellow" end
  local diff = questLevel - level
  if diff >= 5 then return "red" end
  if diff >= 3 then return "orange" end
  if diff >= -2 then return "yellow" end
  if -diff <= D.greenRange(level) then return "green" end
  return "grey"
end

D.COLORS = {
  red = { 1, 0.25, 0.2 }, orange = { 1, 0.55, 0.2 }, yellow = { 1, 0.85, 0.25 },
  green = { 0.35, 0.8, 0.35 }, grey = { 0.55, 0.55, 0.55 }, white = { 0.95, 0.95, 0.95 },
}

---------------------------------------------------------------------------
-- XP and distance
---------------------------------------------------------------------------
function D.questXP(id)
  local qxp = D.module("QuestXP")
  if qxp and type(qxp.GetQuestLogRewardXP) == "function" then
    local xp = plain(call(qxp.GetQuestLogRewardXP, qxp, id, false))
    if xp and xp > 0 then return xp end
  end
end

local HBD
local function hbd()
  if HBD == nil then
    local stub = rawget(_G, "LibStub")
    HBD = stub and select(2, pcall(stub, "HereBeDragonsQuestie-2.0", true)) or false
    if type(HBD) ~= "table" then HBD = false end
  end
  return HBD or nil
end
function D.resetHBD() HBD = nil end

-- Direction from the player to spawn = { x, y } (0-100) in Questie area zone:
-- radians, 0 = north, counter-clockwise (the same as GetPlayerFacing).
-- World position (yards) of a spawn: x, y, instance; nil if unknown.
function D.world(spawn, zone)
  local lib, zdb = hbd(), D.module("ZoneDB")
  if not (lib and zdb and spawn and spawn[1] and spawn[1] >= 0) then return nil end
  local uiMap = call(zdb.GetUiMapIdByAreaId, zdb, zone)
  if not uiMap then return nil end
  return call(lib.GetWorldCoordinatesFromZone, lib, spawn[1] / 100, spawn[2] / 100, uiMap)
end

-- The zone's name for a Questie area id, or nil.
function D.zoneName(zone)
  local zdb = D.module("ZoneDB")
  local uiMap = zdb and zone and call(zdb.GetUiMapIdByAreaId, zdb, zone)
  local info = uiMap and call(api("C_Map.GetMapInfo"), uiMap)
  return type(info) == "table" and type(info.name) == "string" and info.name or nil
end

function D.bearing(spawn, zone)
  local lib = hbd()
  local dx, dy, di = D.world(spawn, zone)
  if not (lib and dx) then return nil end
  local px, py, pi = call(lib.GetPlayerWorldPosition, lib)
  if not px or di ~= pi then return nil end
  return (call(lib.GetWorldVector, lib, pi, px, py, dx, dy))
end

-- Fills e.dist, e.target, e.spawn, e.zone from a Questie result.
local function place(e, spawn, zone, name, dist)
  dist = plain(dist)
  if spawn and dist and dist < 999999999 then
    e.spawn, e.zone, e.target = spawn, zone, name
    e.far = dist >= D.FAR
    e.dist = (not e.far) and dist or nil
  end
end

-- Estimated XP per minute. secs: the time model above.
function D.rate(xp, secs)
  if not xp or not secs or secs <= 0 then return nil end
  return xp / (secs / 60)
end

function D.travelSecs(dist)
  local speed = plain(call(rawget(_G, "GetUnitSpeed"), "player")) or 0
  if speed < D.RUN_SPEED then speed = D.RUN_SPEED end
  return (dist or 0) / speed
end

---------------------------------------------------------------------------
-- Your quest log
---------------------------------------------------------------------------
-- Objectives left: { text, have, need } for each unfinished objective,
-- then how many there are, the summed count, and how far along the quest
-- is (0-1, each objective weighs the same).
local function objectivesLeft(id)
  local list = call(api("C_QuestLog.GetQuestObjectives"), id)
  local left, all, count, sum = {}, 0, 0, 0
  for _, o in ipairs(type(list) == "table" and list or {}) do
    all = all + 1
    count = count + (plain(o.numFulfilled) or 0) + (o.finished and 1 or 0)
    local have, need = plain(o.numFulfilled) or 0, plain(o.numRequired) or 0
    sum = sum + ((o.finished and 1) or (need > 0 and math.min(1, have / need)) or 0)
    if not o.finished then
      table.insert(left, { text = o.text, have = plain(o.numFulfilled), need = plain(o.numRequired) })
    end
  end
  return left, all, count, all > 0 and sum / all or nil
end

-- A quest's tag: "D" dungeon, "R" raid, "G" group or elite, or nil. From the
-- game (GetQuestTagInfo), else Questie, else the suggested group size.
D.TAG_IDS = { [1] = "G", [62] = "R", [81] = "D", [85] = "D", [88] = "R", [89] = "R" }
D.TAG_NAMES = { Group = "G", Elite = "G", Dungeon = "D", Heroic = "D", Raid = "R" }
local tagCache = {}
function D.questTag(id, suggested)
  if not id then return nil end
  if tagCache[id] ~= nil then return tagCache[id] or nil end
  local tagID, tagName = call(rawget(_G, "GetQuestTagInfo"), id)
  tagID, tagName = plain(tagID), plain(tagName)
  if not tagID and not tagName then
    local qdb = D.module("QuestieDB")
    if qdb then
      tagID, tagName = call(qdb.GetQuestTagInfo, id)
      tagID, tagName = plain(tagID), plain(tagName)
    end
  end
  local tag = (type(tagID) == "number" and D.TAG_IDS[tagID]) or (type(tagName) == "string" and D.TAG_NAMES[tagName]) or nil
  suggested = plain(suggested)
  if not tag and type(suggested) == "number" and suggested > 1 then tag = "G" end
  tagCache[id] = tag or false
  return tag
end
function D.resetTags() tagCache = {} end
D.TAG_TEXT = { D = "dungeon quest", R = "raid quest", G = "group or elite quest" }
-- Dungeon and raid quests (not plain group quests).
function D.isDungeon(e) return e.tag == "D" or e.tag == "R" end

-- One entry per quest in the log, headers skipped.
function D.logQuests()
  local list, zone = {}, nil
  local n = call(api("C_QuestLog.GetNumQuestLogEntries")) or 0
  local title = rawget(_G, "GetQuestLogTitle")
  for i = 1, n do
    local name, level, header, id, done, suggested
    local info = call(api("C_QuestLog.GetInfo"), i)
    if type(info) == "table" then
      name, level, header, id, suggested = info.title, info.level, info.isHeader, info.questID, info.suggestedGroup
    elseif title then
      local t, l, g, h, _, c, _, q = call(title, i)
      name, level, header, id, done, suggested = t, l, h, q, c == 1, g
    end
    if header then zone = name
    elseif id and type(name) == "string" and name ~= "" and not (info and info.isHidden) then
      if done == nil then
        done = (call(api("C_QuestLog.ReadyForTurnIn"), id) or call(api("C_QuestLog.IsComplete"), id)) and true or false
      end
      local left, all, count, frac = objectivesLeft(id)
      -- A quest with objectives and none left is ready even if the flag lags.
      if all > 0 and #left == 0 then done = true end
      table.insert(list, { id = id, name = name, level = plain(level), header = zone, done = done, tag = D.questTag(id, suggested),
        left = left, objectives = all, count = count, frac = frac, index = i, kind = done and "turnin" or "log" })
    end
  end
  return list
end

-- The NPC in ids whose name is name (the nearest one Questie picked), or
-- the first one.
function D.npcNamed(ids, name)
  if type(ids) ~= "table" or not ids[1] then return nil end
  local qdb = D.module("QuestieDB")
  if name and qdb and type(qdb.QueryNPCSingle) == "function" then
    for _, id in ipairs(ids) do
      if call(qdb.QueryNPCSingle, id, "name") == name then return id end
    end
  end
  return ids[1]
end

-- Adds Questie's XP and nearest place to a log entry.
function D.placeLog(e)
  e.xp = D.questXP(e.id)
  local du, aq = D.module("DistanceUtils"), D.module("ActiveQuests")
  if not du then return e end
  local quest = aq and type(aq.Get) == "function" and call(aq.Get, e.id)
  quest = type(quest) == "table" and quest.quest
  if type(quest) ~= "table" then
    local qdb = D.module("QuestieDB")
    quest = qdb and call(qdb.GetQuest, e.id)
  end
  if type(quest) ~= "table" then return e end
  e.req = quest.requiredLevel
  if e.done then
    if quest.Finisher then
      place(e, call(du.GetNearestFinisherOrStarter, quest.Finisher))
      e.npc = D.npcNamed(quest.Finisher.NPC, e.target)
    end
  elseif quest.Objectives then
    place(e, call(du.GetNearestSpawnForQuest, quest))
  end
  -- No spawn for the quest: where its items come from.
  if not e.spawn and not e.done then D.placeObjectiveItem(e, quest) end
  -- No place for the objectives (a letter or item to deliver, or Questie
  -- has no spawns for them): the place is the NPC who takes it in.
  -- Only when there is nothing left to get: an open count (8/12 eggs)
  -- whose source Questie does not know gets no place, not the turn-in.
  if not e.spawn and quest.Finisher then
    local toGet = false
    for _, o in ipairs(e.left or {}) do
      if o.need and o.need > 0 and (o.have or 0) < o.need then toGet = true end
    end
    if e.done or not toGet then
      place(e, call(du.GetNearestFinisherOrStarter, quest.Finisher))
      if e.spawn then
        e.npc = D.npcNamed(quest.Finisher.NPC, e.target)
        e.deliver = true
      end
    else
      local _, _, name = call(du.GetNearestFinisherOrStarter, quest.Finisher)
      e.finisher, e.unknownPlace = name, true
      D.placeSpot(e)
    end
  end
  return e
end

-- Where the item that starts a quest drops: the nearest spawn of a
-- monster that drops it. Fills e.item, e.dropFrom and the place.
-- Where an item comes from: the nearest mob that drops it, object (chest,
-- crate, nest) that holds it, or vendor that sells it. Nil if unknown.
function D.itemSource(itemID)
  local qdb, du = D.module("QuestieDB"), D.module("DistanceUtils")
  if not (qdb and du and itemID) then return nil end
  local item = call(qdb.GetItem, qdb, itemID)
  if type(item) ~= "table" then return nil end
  local best
  local function try(thing, id, how)
    if type(thing) == "table" and type(thing.spawns) == "table" then
      local spawn, zone, dist = call(du.GetNearestSpawn, thing.spawns)
      dist = plain(dist)
      if spawn and dist and (not best or dist < best.dist) then
        best = { spawn = spawn, zone = zone, dist = dist, name = thing.name, id = id, how = how }
      end
    end
  end
  local function list(t) return type(t) == "table" and t or {} end
  for _, id in ipairs(list(item.npcDrops)) do try(call(qdb.GetNPC, qdb, id), id, "drop") end
  for _, id in ipairs(list(item.objectDrops)) do try(call(qdb.GetObject, qdb, id), id, "object") end
  for _, id in ipairs(list(item.vendors)) do try(call(qdb.GetNPC, qdb, id), id, "vendor") end
  return best, item
end

function D.placeItemStart(e, quest)
  local itemID = quest.Starts and quest.Starts.Item and quest.Starts.Item[1]
  local best, item = D.itemSource(itemID)
  if item then e.startItem = item.name end
  if best then
    e.dropFrom, e.dropHow = best.name, best.how
    place(e, best.spawn, best.zone, best.name, best.dist)
  end
end

-- The item name in an objective text: "Perfect Razormaw Egg: 8/12" or
-- "8/12 Perfect Razormaw Egg".
function D.objectiveName(text)
  if type(text) ~= "string" then return nil end
  local name = text:gsub(":%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%s*%d+%s*/%s*%d+%s+", "")
  return name ~= "" and name or nil
end

-- An open item objective's source, when Questie has no spawn for the quest
-- itself: by the quest's item ids, else by the item's name.
function D.placeObjectiveItem(e, quest)
  local ids = {}
  local raw = type(quest.objectives) == "table" and quest.objectives[3]
  for _, o in ipairs(type(raw) == "table" and raw or {}) do
    if type(o) == "table" and type(o[1]) == "number" then table.insert(ids, o[1]) end
  end
  for _, o in ipairs(e.left or {}) do
    local id = D.itemsByName and D.itemsByName[D.objectiveName(o.text) or ""]
    if id then table.insert(ids, id) end
  end
  local best
  for _, id in ipairs(ids) do
    local src = D.itemSource(id)
    if src and (not best or src.dist < best.dist) then best = src end
  end
  if best then
    e.getFrom, e.getHow = best.name, best.how
    place(e, best.spawn, best.zone, best.name, best.dist)
    e.npc = best.how ~= "object" and best.id or nil
  end
end

-- Kills or loots still to do: need - have for each open objective (1 for
-- one with no count).
function D.unitsLeft(e)
  local n = 0
  for _, o in ipairs(e.left or {}) do
    if o.need and o.have and o.need > 0 then n = n + math.max(0, o.need - o.have) else n = n + 1 end
  end
  return n
end

-- How much slower a quest over your level goes: tougher mobs, more deaths
-- and rests. 5 or more over (red) counts as close to not doable alone. A
-- quest 3 or more under goes a bit faster.
D.LEVEL_SLOW = { [1] = 1.25, [2] = 1.6, [3] = 2.2, [4] = 3.2 }
D.RED_SLOW, D.LOW_FAST = 6, 0.85
function D.levelFactor(questLevel, level)
  level = level or D.playerLevel()
  if not (questLevel and level) or questLevel <= 0 then return 1 end
  local diff = questLevel - level
  if diff >= 5 then return D.RED_SLOW end
  if diff >= 1 then return D.LEVEL_SLOW[diff] end
  if diff <= -3 then return D.LOW_FAST end
  return 1
end

-- The work left on a quest: kills or loot left at your pace on it (it
-- already shows how hard the quest is for you), else at your pace over
-- all quests (or a guess) times the level factor. Second value: a guess.
function D.workSecs(e)
  local own = D.pace[e.id]
  if own then return D.unitsLeft(e) * own, false end
  local pace = math.max(D.anyPace or 0, D.UNIT_SECS)
  return D.unitsLeft(e) * pace * D.levelFactor(e.level), true
end

function D.logSecs(e)
  if e.done then return D.travelSecs(e.dist) + D.PICKUP_SECS end
  return D.travelSecs(e.dist) + D.workSecs(e) + D.RETURN_SECS
end

---------------------------------------------------------------------------
-- Quests you can pick up (Questie's "!" quests)
---------------------------------------------------------------------------
-- Whether a quest's level fits: it gives XP (not grey) and is at most
-- maxAbove levels over you. Quests you cannot take yet are left out.
function D.fits(questLevel, req, level, maxAbove)
  level = level or D.playerLevel()
  if req and req > level then return false end
  local d = D.difficulty(questLevel, level)
  if d == "grey" then return false end
  return (questLevel or level) - level <= (maxAbove or 3)
end

-- The ids Questie shows as available, in any order.
function D.availableIDs()
  local aq = D.module("AvailableQuests")
  local set = aq and rawget(aq, "__availableQuests")
  local ids = {}
  if type(set) ~= "table" then return ids end
  for id, on in pairs(set) do
    if on and type(id) == "number" then table.insert(ids, id) end
  end
  table.sort(ids)
  return ids
end

-- Why a quest you can take is not on the board: nil when it fits, else
-- a short reason.
function D.unfitReason(quest, level, maxAbove)
  level = level or D.playerLevel()
  if quest.isHidden then return "Questie marks it hidden" end
  if quest.requiredLevel and quest.requiredLevel > level then return "it needs level " .. quest.requiredLevel end
  if D.difficulty(quest.level, level) == "grey" then return "it is grey for you (no XP), so Pick up leaves it out" end
  if (quest.level or level) - level > (maxAbove or 3) then
    return string.format("it is level %d, more than %d over you (/qb range %d shows it)", quest.level, maxAbove or 3, quest.level - level)
  end
  return nil
end

-- Finds a quest by name (part of it, any case) and says where it is on the
-- board or why it is not there. st: the last pass; where: kind -> where
-- the board shows it; maxAbove: the /qb range.
function D.whyQuest(query, st, where, maxAbove)
  local q = (query or ""):lower()
  if q == "" then return "name a quest: /qb why Stopping the Cycle" end
  local function hit(name) return type(name) == "string" and name:lower():find(q, 1, true) ~= nil end
  for _, kind in ipairs({ "active", "nearby", "turnin", "log", "party", "pickup", "farPickup" }) do
    for _, e in ipairs(st and st[kind] or {}) do
      if hit(e.name) then
        local place = e.dist and (", " .. D.yards(e.dist)) or (kind ~= "farPickup" and kind ~= "pickup" and ", no known place" or "")
        return e.name .. place .. ": " .. ((where and where[kind]) or kind)
      end
    end
  end
  for _, e in ipairs(D.logQuests()) do
    if hit(e.name) then return e.name .. " is in your log; the board shows it after its next update (a few seconds)" end
  end
  local qdb = D.module("QuestieDB")
  if not qdb then return "no quest named \"" .. query .. "\" in your log, and Questie is not loaded to look for pick-ups" end
  local level = D.playerLevel()
  for _, id in ipairs(D.availableIDs()) do
    local quest = call(qdb.GetQuest, id)
    if type(quest) == "table" and hit(quest.name) then
      local why = D.unfitReason(quest, level, maxAbove)
      if why then return quest.name .. " is available, but " .. why end
      local e = D.pickup(id, level, maxAbove)
      if e and e.far then return quest.name .. " is available, but its giver is far away (another continent), so Pick up leaves it out" end
      return quest.name .. " is available; it should show in Pick up after the next update"
    end
  end
  for _, id in ipairs(D.ids and D.ids(qdb.QuestPointers) or {}) do
    local name = call(qdb.QueryQuestSingle, id, "name")
    if hit(name) then
      local pre = D.preQuest and D.preQuest(id)
      local f = api("C_QuestLog.IsQuestFlaggedCompleted") or rawget(_G, "IsQuestFlaggedCompleted")
      if f and call(f, id) == true then return name .. ": you have done it already" end
      if pre and not (f and call(f, pre) == true) then
        local preName = call(qdb.QueryQuestSingle, pre, "name")
        return name .. ": Questie says you cannot take it yet; do " .. (type(preName) == "string" and preName or ("quest " .. pre)) .. " first"
      end
      return name .. ": Questie does not show it as available to you (done, your class, race or faction, or the level)"
    end
  end
  return "Questie has no quest named \"" .. query .. "\" (a quest new on Forever?); the board can show it only once it is in your log"
end

-- An entry for one available quest, or nil when it does not fit.
-- kind "party": a quest a party member has; any level you can take.
function D.pickup(id, level, maxAbove, kind)
  local qdb, du = D.module("QuestieDB"), D.module("DistanceUtils")
  local quest = qdb and call(qdb.GetQuest, id)
  if type(quest) ~= "table" or quest.isHidden then return nil end
  if kind == "party" then
    if quest.requiredLevel and quest.requiredLevel > (level or D.playerLevel()) then return nil end
  elseif not D.fits(quest.level, quest.requiredLevel, level, maxAbove) then
    return nil
  end
  local e = { id = id, name = quest.name or ("Quest " .. id), level = quest.level, req = quest.requiredLevel, tag = D.questTag(id),
    kind = kind or "pickup", objectives = 0, left = {} }
  -- Raw objectives: [1] creatures, [2] objects, [3] items (lists of entries).
  local raw = type(quest.objectives) == "table" and quest.objectives or {}
  for k = 1, 3 do
    if type(raw[k]) == "table" then e.objectives = e.objectives + #raw[k] end
  end
  e.xp = D.questXP(id)
  if du and quest.Starts then
    place(e, call(du.GetNearestFinisherOrStarter, quest.Starts))
    e.npc = D.npcNamed(quest.Starts.NPC, e.target)
  end
  -- Started by an item that drops: no giver to walk to. The place is where
  -- the item drops; the hand-in NPC goes in the tooltip.
  if not e.spawn and quest.Starts and quest.Starts.Item then
    e.fromItem = true
    D.placeItemStart(e, quest)
    if du and quest.Finisher then
      local spawn, zone, name, dist = call(du.GetNearestFinisherOrStarter, quest.Finisher)
      e.finisher = name
      -- Questie does not know where the item comes from (a world drop):
      -- the distance is to the one who takes it in.
      if not e.spawn then
        place(e, spawn, zone, name, dist)
        e.toFinisher = e.spawn and true or nil
      end
    end
  end
  return e
end

---------------------------------------------------------------------------
-- Party
---------------------------------------------------------------------------
-- { { name, unit } } for each party member.
function D.partyMembers()
  local list = {}
  for i = 1, 4 do
    local unit = "party" .. i
    local name = call(rawget(_G, "UnitName"), unit)
    if type(name) == "string" and name ~= "" then table.insert(list, { name = name, unit = unit }) end
  end
  return list
end

-- Questie's copy of the party's quest logs: questID -> { player -> objectives }.
function D.remoteLogs()
  local comms = D.module("QuestieComms")
  local logs = comms and rawget(comms, "remoteQuestLogs")
  return type(logs) == "table" and logs or {}
end

local function shortName(n) return type(n) == "string" and (n:match("^([^%-]+)") or n) or nil end

-- "3/8" from Questie's objectives for one player, or "done" or "".
function D.partyProgress(objectives)
  if type(objectives) ~= "table" then return "" end
  local any, all = false, true
  for _, o in pairs(objectives) do
    if type(o) == "table" then
      any = true
      if not o.finished then
        all = false
        if o.fulfilled and o.required and o.required > 1 then return o.fulfilled .. "/" .. o.required end
      end
    end
  end
  return (any and all) and "done" or ""
end

-- Party members with a quest from Questie's data: { { name, progress } }.
function D.partyHas(players, members)
  local who = {}
  for _, m in ipairs(members) do
    for pname, obj in pairs(type(players) == "table" and players or {}) do
      if shortName(pname) == m.name then
        table.insert(who, { name = m.name, progress = D.partyProgress(obj) })
        break
      end
    end
  end
  return who
end

-- Party members on a quest in your log: the game knows (IsUnitOnQuest),
-- and Questie adds their progress when it has it.
function D.partyOn(id, members)
  local on = api("C_QuestLog.IsUnitOnQuest") or rawget(_G, "IsUnitOnQuest")
  local remote = D.remoteLogs()[id]
  local who = {}
  for _, m in ipairs(members) do
    local has = call(on, m.unit, id)
    local mine = D.partyHas(remote, { m })[1]
    if has or mine then table.insert(who, { name = m.name, progress = mine and mine.progress or "" }) end
  end
  return who
end

-- "Ann 3/8, Bo" for a row.
function D.partyText(who)
  local parts = {}
  for _, w in ipairs(who or {}) do
    table.insert(parts, w.progress ~= "" and (w.name .. " " .. w.progress) or w.name)
  end
  return table.concat(parts, ", ")
end

-- Where a party member is: map position (for a pin) and world position
-- (for yards and the arrow). Nil when the game does not say (a dungeon,
-- another continent, out of range).
function D.unitPlace(unit)
  local mapID = call(api("C_Map.GetBestMapForUnit"), unit)
  local pos = mapID and call(api("C_Map.GetPlayerMapPosition"), mapID, unit)
  if type(pos) ~= "table" or not pos.GetXY then return nil, mapID end
  local ok, x, y = pcall(pos.GetXY, pos)
  if not (ok and x and y) or (x == 0 and y == 0) then return nil, mapID end
  local place = { mapID = mapID, x = x, y = y }
  local lib = hbd()
  if lib then place.wx, place.wy, place.inst = call(lib.GetWorldCoordinatesFromZone, lib, x, y, mapID) end
  return place, mapID
end

-- Health in percent, or nil when the client hides it (secret values).
local function healthPct(unit)
  local h, m = D.plain(call(rawget(_G, "UnitHealth"), unit)), D.plain(call(rawget(_G, "UnitHealthMax"), unit))
  if type(h) ~= "number" or type(m) ~= "number" or m <= 0 then return nil end
  return math.floor(h / m * 100 + 0.5)
end

-- One row per party member: level, class colour, how they are (offline,
-- dead, AFK, health), where (yards and arrow, or the zone), and the quests
-- of yours they have with their progress. out: the pass so far (log lists
-- and party pick-ups).
function D.memberList(out, members, level)
  local list = {}
  local lib = hbd()
  local px, py, pi
  if lib then px, py, pi = call(lib.GetPlayerWorldPosition, lib) end
  local myMap = call(api("C_Map.GetBestMapForUnit"), "player")
  for i, m in ipairs(members) do
    local u = m.unit
    local lvl = D.plain(call(rawget(_G, "UnitLevel"), u))
    local _, class = call(rawget(_G, "UnitClass"), u)
    local colors = rawget(_G, "RAID_CLASS_COLORS")
    local cc = type(class) == "string" and type(colors) == "table" and colors[class]
    local e = { kind = "member", id = -1000 - i, unit = u, name = m.name, level = type(lvl) == "number" and lvl > 0 and lvl or nil, left = {},
      classColor = type(cc) == "table" and { cc.r, cc.g, cc.b } or nil }
    e.color = e.level and D.difficulty(e.level, level) or "white"
    if call(rawget(_G, "UnitIsConnected"), u) == false then e.status = "Offline"
    elseif call(rawget(_G, "UnitIsGhost"), u) then e.status = "Ghost"
    elseif call(rawget(_G, "UnitIsDeadOrGhost"), u) then e.status = "Dead"
    else
      e.hp = healthPct(u)
      e.status = (call(rawget(_G, "UnitIsAFK"), u) and "AFK" or nil)
    end
    local place, mapID = D.unitPlace(u)
    if place then
      e.spot = place
      if px and place.wx and place.inst == pi then
        local dx, dy = place.wx - px, place.wy - py
        e.dist = math.sqrt(dx * dx + dy * dy)
        e.wx, e.wy, e.inst = place.wx, place.wy, place.inst
        e.angle = (call(lib.GetWorldVector, lib, pi, px, py, place.wx, place.wy))
      end
    end
    if not e.dist then
      local ok, d2, checked = pcall(rawget(_G, "UnitDistanceSquared") or error, u)
      if ok and checked and type(d2) == "number" then e.dist = math.sqrt(d2) end
    end
    if mapID and mapID ~= myMap then
      local info = call(api("C_Map.GetMapInfo"), mapID)
      e.zoneName = type(info) == "table" and type(info.name) == "string" and info.name or nil
    end
    -- Your quests they have, and how far they are on each.
    e.shared, e.behind = {}, 0
    for _, kind in ipairs({ "active", "nearby", "turnin", "log" }) do
      for _, q in ipairs(out[kind] or {}) do
        for _, w in ipairs(q.party or {}) do
          if w.name == m.name then
            table.insert(e.shared, { id = q.id, name = q.name, progress = w.progress, mine = q.done and "done" or D.progress(q) })
            if q.done and w.progress ~= "" and w.progress ~= "done" then e.behind = e.behind + 1 end
          end
        end
      end
    end
    e.theirs = 0
    for _, q in ipairs(out.party or {}) do
      for _, w in ipairs(q.party or {}) do if w.name == m.name then e.theirs = e.theirs + 1 end end
    end
    table.insert(list, e)
  end
  return list
end

-- The status line of a member row: "92% hp, in Westfall, 3 quests with
-- you (1 behind)". Behind: you can hand it in, they are not done.
function D.memberText(e)
  local parts = {}
  if e.status then table.insert(parts, e.status) end
  if e.hp and e.status ~= "Offline" then table.insert(parts, e.hp .. "% hp") end
  if e.zoneName then table.insert(parts, "in " .. e.zoneName) end
  local n = #(e.shared or {})
  if n > 0 then
    table.insert(parts, n .. " quest" .. (n == 1 and "" or "s") .. " with you" .. ((e.behind or 0) > 0 and (" (" .. e.behind .. " behind)") or ""))
  end
  if (e.theirs or 0) > 0 then table.insert(parts, e.theirs .. " you lack") end
  return table.concat(parts, ", ")
end

function D.pickupSecs(e)
  return D.travelSecs(e.dist) + D.PICKUP_SECS + math.max(1, e.objectives) * D.OBJECTIVE_SECS * D.levelFactor(e.level) + D.RETURN_SECS
end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------
-- near: nearest first up to D.MID_YARDS; past that (and for far or unknown
-- places) the travel guess counts for little, so the biggest XP comes
-- first. xp: best XP per minute first, then the same.
function D.sort(list, by)
  local function far(e) return not e.dist or e.dist > D.MID_YARDS end
  table.sort(list, function(a, b)
    if by == "xp" then
      local ra, rb = a.rate or -1, b.rate or -1
      if ra ~= rb then return ra > rb end
    end
    local fa, fb = far(a), far(b)
    if fa ~= fb then return fb end
    if fa then
      local xa, xb = a.xp or 0, b.xp or 0
      if xa ~= xb then return xa > xb end
    end
    local da, db = a.dist or math.huge, b.dist or math.huge
    if da ~= db then return da < db end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return a.name < b.name
  end)
  return list
end

-- Finishes one entry: colour, estimate, direction.
function D.finish(e, level)
  e.color = D.difficulty(e.level, level)
  local secs = (e.kind == "pickup" or e.kind == "party") and D.pickupSecs(e) or D.logSecs(e)
  e.secs = e.far and nil or secs
  e.rate = (not e.far) and D.rate(e.xp, secs) or nil
  if e.spot then
    -- Placed by where you last made progress: world position already known.
    local lib = hbd()
    local px, py, pi
    if lib then px, py, pi = call(lib.GetPlayerWorldPosition, lib) end
    e.wx, e.wy, e.inst = e.spot.wx, e.spot.wy, e.spot.inst
    e.angle = (px and pi == e.inst) and (call(lib.GetWorldVector, lib, pi, px, py, e.wx, e.wy)) or nil
    return e
  end
  e.angle = e.dist and D.bearing(e.spawn, e.zone) or nil
  if e.dist then e.wx, e.wy, e.inst = D.world(e.spawn, e.zone) end
  return e
end

-- Where you last made progress on each quest: { wx, wy, inst, mapID, x, y }.
-- The board uses it when Questie does not know where the objective is.
-- QuestBoard.lua points this at the saved variables.
D.lastSpot = {}
function D.noteSpot(id)
  local lib = hbd()
  local px, py, pi
  if lib then px, py, pi = call(lib.GetPlayerWorldPosition, lib) end
  if not px then return end
  local spot = { wx = px, wy = py, inst = pi }
  local mapID = call(api("C_Map.GetBestMapForUnit"), "player")
  local pos = mapID and call(api("C_Map.GetPlayerMapPosition"), mapID, "player")
  if type(pos) == "table" and pos.GetXY then
    local ok, x, y = pcall(pos.GetXY, pos)
    if ok and x then spot.mapID, spot.x, spot.y = mapID, x, y end
  end
  D.lastSpot[id] = spot
end

-- Places e at the spot where you last made progress, if there is one on
-- this continent.
function D.placeSpot(e)
  local spot = D.lastSpot[e.id]
  local lib = hbd()
  local px, py, pi
  if lib then px, py, pi = call(lib.GetPlayerWorldPosition, lib) end
  if not (spot and px and pi == spot.inst) then return end
  local dx, dy = spot.wx - px, spot.wy - py
  e.spot, e.dist, e.target = spot, math.sqrt(dx * dx + dy * dy), "where you last got one"
end

---------------------------------------------------------------------------
-- Areas: places where several quest stops (objectives, hand-ins, givers)
-- are close together, so one trip does several quests. Travel is the big
-- cost, so an area is scored by the XP you can earn there per minute of
-- getting there and doing it.
---------------------------------------------------------------------------
D.AREA_YARDS = 250       -- stops this close to an area's first stop join it
D.AREA_KINDS = { "active", "nearby", "turnin", "log", "party", "pickup" }

local function stopSecs(e)
  if e.kind == "turnin" then return D.PICKUP_SECS end
  if e.kind == "pickup" or e.kind == "party" then return D.PICKUP_SECS end
  return (D.workSecs(e))
end

-- XP you earn at the stop itself (a pick-up earns it later, elsewhere).
local function stopXP(e)
  if e.kind == "pickup" or e.kind == "party" then return 0 end
  return e.xp or 0
end

function D.areas(out)
  if D.AREA_YARDS <= 0 then return {} end   -- 0 turns areas off
  local pts = {}
  for _, kind in ipairs(D.AREA_KINDS) do
    for _, e in ipairs(out[kind] or {}) do
      -- Only real stops: not an item-started quest (no giver to visit; its
      -- place is a drop or the finisher), not a party quest you cannot take.
      local stop = not e.hiddenTag and not (e.fromItem and (e.kind == "pickup" or e.kind == "party"))
        and not (e.kind == "party" and not e.canTake)
      if stop and e.wx and e.dist then table.insert(pts, e) end
    end
  end
  table.sort(pts, function(a, b) return a.dist < b.dist end)
  local used, list = {}, {}
  for _, seed in ipairs(pts) do
    if not used[seed] then
      local a = { kind = "area", color = "white", stops = {}, counts = {}, xp = 0, work = 0, spawn = seed.spawn, zone = seed.zone,
        dist = seed.dist, angle = seed.angle, target = seed.target, npc = seed.npc, id = "area" .. #list }
      for _, e in ipairs(pts) do
        if not used[e] and e.inst == seed.inst then
          local dx, dy = e.wx - seed.wx, e.wy - seed.wy
          if dx * dx + dy * dy <= D.AREA_YARDS * D.AREA_YARDS then
            used[e] = true
            table.insert(a.stops, e)
            a.counts[e.kind] = (a.counts[e.kind] or 0) + 1
            a.xp = a.xp + stopXP(e)
            a.work = a.work + stopSecs(e)
          end
        end
      end
      if #a.stops >= 2 then
        a.secs = D.travelSecs(a.dist) + a.work
        a.rate = a.xp > 0 and D.rate(a.xp, a.secs) or nil
        -- Inside it: say so, the stops can be anywhere within AREA_YARDS.
        a.name = (a.dist <= D.AREA_YARDS and "Around you, by " or "Near ") .. (seed.target or seed.name)
        table.insert(list, a)
      end
    end
  end
  table.sort(list, function(x, y)
    if (x.rate or 0) ~= (y.rate or 0) then return (x.rate or 0) > (y.rate or 0) end
    return #x.stops > #y.stops
  end)
  return list
end

---------------------------------------------------------------------------
-- Zones: where to go next or swap to. Every stop you know of (your log,
-- hand-ins, pick-ups near and far) by zone, scored by the XP there per
-- minute of the trip and the work.
---------------------------------------------------------------------------
local function zoneWork(e)
  if e.kind == "pickup" or e.kind == "party" then
    return D.PICKUP_SECS + math.max(1, e.objectives or 0) * D.OBJECTIVE_SECS * D.levelFactor(e.level) + D.RETURN_SECS
  end
  return stopSecs(e)
end

function D.zones(out)
  local by, list = {}, {}
  for _, kind in ipairs({ "active", "nearby", "turnin", "log", "pickup", "farPickup" }) do
    for _, e in ipairs(out[kind] or {}) do
      local name = D.zoneName(e.zone) or (e.kind ~= "pickup" and e.header) or nil
      if name and not e.hiddenTag then
        local z = by[name]
        if not z then
          z = { kind = "zone", name = name, color = "white", stops = {}, counts = {}, xp = 0, work = 0, left = {}, id = "zone:" .. name }
          by[name] = z
          table.insert(list, z)
        end
        table.insert(z.stops, e)
        local k = kind == "farPickup" and "pickup" or e.kind
        z.counts[k] = (z.counts[k] or 0) + 1
        z.xp = z.xp + (e.xp or 0)
        z.work = z.work + zoneWork(e)
        if e.dist and (not z.dist or e.dist < z.dist) then
          z.dist, z.angle, z.spawn, z.zone, z.target, z.near = e.dist, e.angle, e.spawn, e.zone, e.target, e
        end
        z.zone = z.zone or e.zone
      end
    end
  end
  for _, z in ipairs(list) do
    z.secs = (z.dist and D.travelSecs(z.dist) or 0) + z.work
    z.rate = z.xp > 0 and D.rate(z.xp, z.secs) or nil
    z.far = not z.dist
  end
  -- Zones you can reach first, best XP per minute; far ones after, most XP.
  table.sort(list, function(a, b)
    if a.far ~= b.far then return not a.far end
    if a.far then return a.xp > b.xp end
    return (a.rate or 0) > (b.rate or 0)
  end)
  return list
end

-- "3 in your log, 1 hand in, 4 pick up" for a zone.
function D.zoneText(z)
  local c, parts = z.counts, {}
  local logN = (c.active or 0) + (c.nearby or 0) + (c.log or 0)
  if logN > 0 then table.insert(parts, logN .. " in your log") end
  if (c.turnin or 0) > 0 then table.insert(parts, c.turnin .. " hand in") end
  if (c.pickup or 0) > 0 then table.insert(parts, c.pickup .. " pick up") end
  return table.concat(parts, ", ")
end

-- "2 hand in, 1 objective, 1 pick up" for an area.
function D.areaText(a)
  local c, parts = a.counts, {}
  local hand = c.turnin or 0
  local obj = (c.active or 0) + (c.nearby or 0) + (c.log or 0)
  local pick = (c.pickup or 0) + (c.party or 0)
  if hand > 0 then table.insert(parts, hand .. " hand in") end
  if obj > 0 then table.insert(parts, obj .. (obj == 1 and " objective" or " objectives")) end
  if pick > 0 then table.insert(parts, pick .. " pick up") end
  return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Active quests: a quest whose objective count went up in the last
-- ACTIVE_SECS (you killed or looted for it), or that you marked yourself. The first look at a quest only
-- records its count, so nothing is active right after login.
D.seen, D.activeAt, D.heldAt = {}, {}, {}
-- Your pace: seconds per kill or loot, per quest and over all quests. A gap
-- longer than PACE_GAP_SECS (you went off to do something else) is not
-- counted.
D.pace, D.anyPace, D.lastGain = {}, nil, {}
D.PACE_GAP_SECS = 300
local function blend(old, new) return old and (old * 0.6 + new * 0.4) or new end

-- Whether a log quest is active now (recent: its count just went up).
-- Only progress (or your own mark, pinned) makes a quest active; being
-- near only keeps an active quest there.
function D.isActive(e, recent, clock, pinned)
  local held = D.heldAt[e.id]
  local wasActive = held and clock - held <= D.GRACE_SECS
  local near = wasActive and e.dist and e.dist <= D.STAY_YARDS
  if recent or near or pinned then D.heldAt[e.id] = clock return true end
  if wasActive then return true end
  D.heldAt[e.id] = nil
  return false
end
function D.noteProgress(e, clock)
  local before = D.seen[e.id]
  D.seen[e.id] = e.count
  if before and e.count and e.count > before then
    D.activeAt[e.id] = clock
    D.noteSpot(e.id)
    local last = D.lastGain[e.id]
    if last and clock - last <= D.PACE_GAP_SECS and clock > last then
      local per = (clock - last) / (e.count - before)
      D.pace[e.id] = blend(D.pace[e.id], per)
      D.anyPace = blend(D.anyPace, per)
    end
    D.lastGain[e.id] = clock
  end
  local at = D.activeAt[e.id]
  if at and clock - at <= D.ACTIVE_SECS then
    e.activeAt = at
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- One full pass. It is a coroutine body: it yields when the frame budget is
-- spent, so a long list of available quests never stalls the game.
-- opts: { sortLog, sortPickup, maxAbove, yield = function or nil }
---------------------------------------------------------------------------
function D.collect(opts)
  opts = opts or {}
  local level = D.playerLevel()
  local now = rawget(_G, "debugprofilestop")
  local start = now and now() or 0
  local function tick()
    if opts.yield and now and now() - start > D.BUDGET_MS then
      opts.yield()
      start = now()
    end
  end
  local out = { active = {}, nearby = {}, turnin = {}, log = {}, party = {}, pickup = {}, farPickup = {}, questie = D.hasQuestie(), level = level }
  local inLog = {}
  local clock = opts.time or call(rawget(_G, "GetTime")) or 0
  for _, e in ipairs(D.logQuests()) do
    inLog[e.id] = true
    D.finish(D.placeLog(e), level)
    -- /qb dungeons off: a dungeon quest stays in the Log tab only.
    e.hiddenTag = opts.dungeons == false and D.isDungeon(e) or nil
    if D.questItem then e.item = D.questItem(e) end
    local pinned = opts.doing and opts.doing[e.id]
    e.pinned = pinned and true or nil
    local recent = D.noteProgress(e, clock)
    -- A hand-in you pinned, or one you were just working on, stays in Active
    -- (Doing) until you hand it in: the next step is to take it back.
    local held = D.heldAt[e.id]
    if e.done and (pinned or (held and clock - held <= D.GRACE_SECS)) then
      table.insert(out.active, e)
    elseif not e.done and D.isActive(e, recent, clock, pinned) then
      table.insert(out.active, e)
    elseif not e.done and e.dist and e.dist <= D.HERE_YARDS then
      table.insert(out.nearby, e)
    else
      table.insert(e.done and out.turnin or out.log, e)
    end
    tick()
  end
  -- Spots of quests no longer in your log go.
  for id in pairs(D.lastSpot) do if not inLog[id] then D.lastSpot[id] = nil end end
  -- Your party: who shares each quest in your log, and the quests they have
  -- that you do not (Questie's party data), nearest giver first.
  local members = opts.party == false and {} or D.partyMembers()
  out.members = {}
  if #members > 0 then
    for _, list in ipairs({ out.active, out.nearby, out.turnin, out.log }) do
      for _, e in ipairs(list) do e.party = D.partyOn(e.id, members) end
    end
    if out.questie then
      for id, players in pairs(D.remoteLogs()) do
        if not inLog[id] then
          local who = D.partyHas(players, members)
          if #who > 0 then
            local e = D.pickup(id, level, nil, "party")
            if e and not e.far then
              e.party = who
              e.pinned = opts.doing and opts.doing[id] and true or nil
              table.insert(e.pinned and out.active or out.party, D.finish(e, level))
            end
          end
        end
        tick()
      end
    end
  end
  if out.questie then
    local avail = {}
    for _, id in ipairs(D.availableIDs()) do avail[id] = true end
    for _, e in ipairs(out.party) do e.canTake = avail[e.id] or nil end
    for _, e in ipairs(out.active) do if e.kind == "party" then e.canTake = avail[e.id] or nil end end
    for _, id in ipairs(D.availableIDs()) do
      if not inLog[id] then
        local e = D.pickup(id, level, opts.maxAbove)
        if e and opts.dungeons == false and D.isDungeon(e) then e = nil end
        if e and e.far then
          -- Far away: for Areas, or Doing when you pinned it (a zone you swap to).
          e.pinned = opts.doing and opts.doing[id] and true or nil
          table.insert(e.pinned and out.active or out.farPickup, D.finish(e, level))
        end
        if e and not e.far then
          -- A pick-up you pinned waits in Active until you take it.
          e.pinned = opts.doing and opts.doing[id] and true or nil
          table.insert(e.pinned and out.active or out.pickup, D.finish(e, level))
        end
      end
      tick()
    end
    -- Pins of quests you handed in (or can no longer take) go.
    if opts.doing then
      local party = {}
      for _, e in ipairs(out.active) do if e.kind == "party" then party[e.id] = true end end
      for _, e in ipairs(out.party) do party[e.id] = true end
      for id in pairs(opts.doing) do
        if not (inLog[id] or avail[id] or party[id]) then opts.doing[id] = nil end
      end
    end
  end
  -- Recent progress first (newest first), then the ones you stand in.
  table.sort(out.active, function(a, b)
    if (a.activeAt or -1) ~= (b.activeAt or -1) then return (a.activeAt or -1) > (b.activeAt or -1) end
    return (a.dist or math.huge) < (b.dist or math.huge)
  end)
  D.sort(out.turnin, "near")
  D.sort(out.nearby, "near")
  D.sort(out.party, "near")
  D.sort(out.log, opts.sortLog or "near")
  D.sort(out.pickup, opts.sortPickup or "xp")
  out.area = D.areas(out)
  out.zones = D.zones(out)
  -- Your party: how each member is, where, and how far on your quests.
  out.members = D.memberList(out, members, level)
  -- XP colours: each group's best third green, worst third grey.
  D.tier(out.turnin, "xp")
  D.tier(out.pickup, "rate")
  D.tier(out.party, "rate")
  D.tier(out.area, "rate")
  -- Chains: the reward index is read once (spread over frames), then each
  -- quest gets what its chain leads to.
  -- Town: the nearest innkeeper and flight master of your side.
  out.town = out.questie and D.townList(opts.yield and tick) or {}
  if out.questie and D.buildRewards and D.buildRewards(opts.yield and tick) then
    for _, kind in ipairs({ "active", "nearby", "turnin", "log", "party", "pickup" }) do
      for _, e in ipairs(out[kind]) do e.chain = D.chainInfo(e.id) end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
function D.yards(d)
  if not d then return "" end
  if d >= 1000 then return string.format("%.1fk yd", d / 1000) end
  return string.format("%d yd", math.floor(d / 10 + 0.5) * 10)
end

-- Marks each entry's value (field) against the others in its group:
-- e.tier "good" (top third), "low" (bottom third) or nil. Needs 3 values.
function D.tier(list, field)
  local vals = {}
  for _, e in ipairs(list or {}) do e.tier = nil if e[field] then table.insert(vals, e[field]) end end
  if #vals < 3 then return end
  table.sort(vals)
  local lowCut = vals[math.max(1, math.floor(#vals / 3))]
  local highCut = vals[#vals - math.max(1, math.floor(#vals / 3)) + 1]
  for _, e in ipairs(list) do
    local v = e[field]
    if v and v >= highCut and v > lowCut then e.tier = "good"
    elseif v and v <= lowCut and v < highCut then e.tier = "low" end
  end
end

D.TIER_HEX = { good = "60d060", low = "909090" }
function D.tierText(e, text)
  local hex = e.tier and D.TIER_HEX[e.tier]
  return hex and ("|cff" .. hex .. text .. "|r") or text
end

-- Travel time in a few characters: "<1 min", "4 min".
function D.mins(secs)
  if not secs then return "" end
  if secs < 60 then return "<1 min" end
  return string.format("%d min", math.floor(secs / 60 + 0.5))
end

-- Distance in a colour by how far: green within the Nearby range, yellow
-- up to a short ride, grey beyond.
function D.yardsText(d)
  if not d then return "" end
  local hex = d <= D.NEAR_YARDS and "60d060" or d <= D.MID_YARDS and "e0c040" or "909090"
  return "|cff" .. hex .. D.yards(d) .. "|r"
end

function D.short(n)
  if not n then return "" end
  if n >= 10000 then return string.format("%dk", math.floor(n / 1000 + 0.5)) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n + 0.5))
end

-- Compass point for an angle (0 = north, counter-clockwise).
local POINTS = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }
function D.compass(angle)
  if not angle then return "" end
  local i = math.floor((angle % (2 * math.pi)) / (math.pi / 4) + 0.5) % 8
  return POINTS[i + 1]
end

-- Progress of the first unfinished objective, "4/10", or "" .
function D.progress(e)
  local o = e.left and e.left[1]
  if o and o.have and o.need and o.need > 1 then return o.have .. "/" .. o.need end
  return ""
end

---------------------------------------------------------------------------
-- Town: the nearest innkeeper and flight master friendly to your side, from
-- Questie's NPC data (read once, a slice per frame). Addons cannot walk you
-- there; the row gives the map pin, the arrow and the distance.
---------------------------------------------------------------------------
D.NPC_FLAGS = { inn = 65536, flight = 8192 }   -- UNIT_NPC_FLAG_INNKEEPER, _FLIGHTMASTER
D.townBuild = { state = "idle", i = 1 }
D.townNPCs = nil                -- { inn = { ids }, flight = { ids } } once read

local function hasFlag(flags, bit)
  flags = tonumber(flags) or 0
  return math.floor(flags / bit) % 2 == 1
end

local function mySide()
  local f = call(rawget(_G, "UnitFactionGroup"), "player")
  return f == "Horde" and "H" or f == "Alliance" and "A" or nil
end

function D.buildTown(tick)
  local b = D.townBuild
  if b.state == "done" then return true end
  local qdb = D.module("QuestieDB")
  if not (qdb and type(qdb.QueryNPCSingle) == "function" and type(qdb.NPCPointers) == "table") then return false end
  if not b.ids then
    b.ids, b.found = {}, { inn = {}, flight = {} }
    for id in pairs(qdb.NPCPointers) do if type(id) == "number" then table.insert(b.ids, id) end end
    table.sort(b.ids)
  end
  local side = mySide()
  while b.i <= #b.ids do
    local id = b.ids[b.i]
    local flags = call(qdb.QueryNPCSingle, id, "npcFlags")
    if flags and (hasFlag(flags, D.NPC_FLAGS.inn) or hasFlag(flags, D.NPC_FLAGS.flight)) then
      local friend = call(qdb.QueryNPCSingle, id, "friendlyToFaction")
      if not side or not friend or friend == "AH" or friend == side then
        if hasFlag(flags, D.NPC_FLAGS.inn) then table.insert(b.found.inn, id) end
        if hasFlag(flags, D.NPC_FLAGS.flight) then table.insert(b.found.flight, id) end
      end
    end
    b.i = b.i + 1
    if tick and b.i % 200 == 0 then tick() end
  end
  D.townNPCs, b.state, b.ids = b.found, "done", nil
  return true
end

local function nearestOf(ids)
  local qdb, du = D.module("QuestieDB"), D.module("DistanceUtils")
  if not (qdb and du) then return nil end
  local best
  for _, id in ipairs(ids or {}) do
    local spawns = call(qdb.QueryNPCSingle, id, "spawns")
    if type(spawns) == "table" then
      local spawn, zone, dist = call(du.GetNearestSpawn, spawns)
      dist = plain(dist)
      if spawn and dist and dist < D.FAR and (not best or dist < best.dist) then
        best = { id = id, spawn = spawn, zone = zone, dist = dist }
      end
    end
  end
  return best
end

-- Rows for the Town group: the nearest inn and flight master.
function D.townList(tick)
  if not D.buildTown(tick) then return {} end
  local qdb, out = D.module("QuestieDB"), {}
  for _, what in ipairs({ "inn", "flight" }) do
    local n = nearestOf(D.townNPCs[what])
    if n then
      local name = call(qdb.QueryNPCSingle, n.id, "name") or ("NPC " .. n.id)
      local e = { kind = "town", id = -n.id, npc = n.id, name = name, role = what, color = "white", left = {} }
      e.spawn, e.zone, e.target, e.dist = n.spawn, n.zone, name, n.dist
      e.angle = D.bearing(n.spawn, n.zone)
      e.wx, e.wy, e.inst = D.world(n.spawn, n.zone)
      table.insert(out, e)
    end
  end
  D.sort(out, "near")
  return out
end
