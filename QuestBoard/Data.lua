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
D.OBJECTIVE_SECS = 90    -- one unfinished objective (kill or collect)
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

-- One entry per quest in the log, headers skipped.
function D.logQuests()
  local list, zone = {}, nil
  local n = call(api("C_QuestLog.GetNumQuestLogEntries")) or 0
  local title = rawget(_G, "GetQuestLogTitle")
  for i = 1, n do
    local name, level, header, id, done
    local info = call(api("C_QuestLog.GetInfo"), i)
    if type(info) == "table" then
      name, level, header, id = info.title, info.level, info.isHeader, info.questID
    elseif title then
      local t, l, _, h, _, c, _, q = call(title, i)
      name, level, header, id, done = t, l, h, q, c == 1
    end
    if header then zone = name
    elseif id and type(name) == "string" and name ~= "" and not (info and info.isHidden) then
      if done == nil then
        done = (call(api("C_QuestLog.ReadyForTurnIn"), id) or call(api("C_QuestLog.IsComplete"), id)) and true or false
      end
      local left, all, count, frac = objectivesLeft(id)
      -- A quest with objectives and none left is ready even if the flag lags.
      if all > 0 and #left == 0 then done = true end
      table.insert(list, { id = id, name = name, level = plain(level), header = zone, done = done,
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
  -- No place for the objectives (a letter or item to deliver, or Questie
  -- has no spawns for them): the place is the NPC who takes it in.
  if not e.spawn and quest.Finisher then
    place(e, call(du.GetNearestFinisherOrStarter, quest.Finisher))
    if e.spawn then
      e.npc = D.npcNamed(quest.Finisher.NPC, e.target)
      e.deliver = true
    end
  end
  return e
end

-- Where the item that starts a quest drops: the nearest spawn of a
-- monster that drops it. Fills e.item, e.dropFrom and the place.
function D.placeItemStart(e, quest)
  local qdb, du = D.module("QuestieDB"), D.module("DistanceUtils")
  local itemID = quest.Starts and quest.Starts.Item and quest.Starts.Item[1]
  if not (qdb and du and itemID) then return end
  local item = call(qdb.GetItem, qdb, itemID)
  if type(item) ~= "table" then return end
  e.item = item.name
  -- Where the item comes from: mobs that drop it, objects (chests, crates)
  -- that hold it, or vendors that sell it. The nearest of all of them.
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
  if best then
    e.dropFrom, e.dropHow = best.name, best.how
    place(e, best.spawn, best.zone, best.name, best.dist)
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

-- Time for the work left on a quest. Once you have made progress, it uses
-- your own pace (seconds per kill or loot, on this quest, else on any
-- quest); before that, OBJECTIVE_SECS per open objective.
function D.workSecs(e)
  local pace = D.pace[e.id] or D.anyPace
  if pace then return D.unitsLeft(e) * pace end
  return math.max(1, #(e.left or {})) * D.OBJECTIVE_SECS
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
  local e = { id = id, name = quest.name or ("Quest " .. id), level = quest.level, req = quest.requiredLevel,
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

function D.pickupSecs(e)
  return D.travelSecs(e.dist) + D.PICKUP_SECS + math.max(1, e.objectives) * D.OBJECTIVE_SECS + D.RETURN_SECS
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
  e.angle = e.dist and D.bearing(e.spawn, e.zone) or nil
  if e.dist then e.wx, e.wy, e.inst = D.world(e.spawn, e.zone) end
  return e
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
  return math.max(1, #(e.left or {})) * D.OBJECTIVE_SECS
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
      if e.wx and e.dist then table.insert(pts, e) end
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
        a.name = "Near " .. (seed.target or seed.name)
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
  local out = { active = {}, nearby = {}, turnin = {}, log = {}, party = {}, pickup = {}, questie = D.hasQuestie(), level = level }
  local inLog = {}
  local clock = opts.time or call(rawget(_G, "GetTime")) or 0
  for _, e in ipairs(D.logQuests()) do
    inLog[e.id] = true
    D.finish(D.placeLog(e), level)
    if D.questItem then e.item = D.questItem(e) end
    local pinned = opts.doing and opts.doing[e.id]
    e.pinned = pinned and true or nil
    if not e.done and D.isActive(e, D.noteProgress(e, clock), clock, pinned) then
      table.insert(out.active, e)
    elseif not e.done and e.dist and e.dist <= D.HERE_YARDS then
      table.insert(out.nearby, e)
    else
      table.insert(e.done and out.turnin or out.log, e)
    end
    tick()
  end
  -- Your party: who shares each quest in your log, and the quests they have
  -- that you do not (Questie's party data), nearest giver first.
  local members = D.partyMembers()
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
              table.insert(out.party, D.finish(e, level))
            end
          end
        end
        tick()
      end
    end
  end
  if out.questie then
    for _, id in ipairs(D.availableIDs()) do
      if not inLog[id] then
        local e = D.pickup(id, level, opts.maxAbove)
        if e and not e.far then table.insert(out.pickup, D.finish(e, level)) end
      end
      tick()
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
  -- Chains: the reward index is read once (spread over frames), then each
  -- quest gets what its chain leads to.
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
