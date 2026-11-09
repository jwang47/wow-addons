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
  green = { 0.35, 0.8, 0.35 }, grey = { 0.55, 0.55, 0.55 },
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
function D.bearing(spawn, zone)
  local lib, zdb = hbd(), D.module("ZoneDB")
  if not (lib and zdb and spawn and spawn[1] and spawn[1] >= 0) then return nil end
  local px, py, pi = call(lib.GetPlayerWorldPosition, lib)
  local uiMap = call(zdb.GetUiMapIdByAreaId, zdb, zone)
  if not (px and uiMap) then return nil end
  local dx, dy, di = call(lib.GetWorldCoordinatesFromZone, lib, spawn[1] / 100, spawn[2] / 100, uiMap)
  if not dx or di ~= pi then return nil end
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
-- Objectives left: { text, have, need } for each unfinished objective.
local function objectivesLeft(id)
  local list = call(api("C_QuestLog.GetQuestObjectives"), id)
  local left, all = {}, 0
  for _, o in ipairs(type(list) == "table" and list or {}) do
    all = all + 1
    if not o.finished then
      table.insert(left, { text = o.text, have = plain(o.numFulfilled), need = plain(o.numRequired) })
    end
  end
  return left, all
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
      local left, all = objectivesLeft(id)
      -- A quest with objectives and none left is ready even if the flag lags.
      if all > 0 and #left == 0 then done = true end
      table.insert(list, { id = id, name = name, level = plain(level), header = zone, done = done,
        left = left, objectives = all, index = i, kind = done and "turnin" or "log" })
    end
  end
  return list
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
    if quest.Finisher then place(e, call(du.GetNearestFinisherOrStarter, quest.Finisher)) end
  elseif quest.Objectives then
    place(e, call(du.GetNearestSpawnForQuest, quest))
  end
  return e
end

function D.logSecs(e)
  if e.done then return D.travelSecs(e.dist) + D.PICKUP_SECS end
  return D.travelSecs(e.dist) + math.max(1, #e.left) * D.OBJECTIVE_SECS + D.RETURN_SECS
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
function D.pickup(id, level, maxAbove)
  local qdb, du = D.module("QuestieDB"), D.module("DistanceUtils")
  local quest = qdb and call(qdb.GetQuest, id)
  if type(quest) ~= "table" or quest.isHidden then return nil end
  if not D.fits(quest.level, quest.requiredLevel, level, maxAbove) then return nil end
  local e = { id = id, name = quest.name or ("Quest " .. id), level = quest.level, req = quest.requiredLevel,
    kind = "pickup", objectives = 0, left = {} }
  -- Raw objectives: [1] creatures, [2] objects, [3] items (lists of entries).
  local raw = type(quest.objectives) == "table" and quest.objectives or {}
  for k = 1, 3 do
    if type(raw[k]) == "table" then e.objectives = e.objectives + #raw[k] end
  end
  e.xp = D.questXP(id)
  if du and quest.Starts then place(e, call(du.GetNearestFinisherOrStarter, quest.Starts)) end
  -- Started by an item that drops: no giver to walk to.
  if not e.spawn and quest.Starts and quest.Starts.Item then e.fromItem = true end
  return e
end

function D.pickupSecs(e)
  return D.travelSecs(e.dist) + D.PICKUP_SECS + math.max(1, e.objectives) * D.OBJECTIVE_SECS + D.RETURN_SECS
end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------
-- near: nearest first (unknown and far last); xp: best XP per minute first.
function D.sort(list, by)
  table.sort(list, function(a, b)
    if by == "xp" then
      local ra, rb = a.rate or -1, b.rate or -1
      if ra ~= rb then return ra > rb end
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
  local secs = e.kind == "pickup" and D.pickupSecs(e) or D.logSecs(e)
  e.secs = e.far and nil or secs
  e.rate = (not e.far) and D.rate(e.xp, secs) or nil
  e.angle = e.dist and D.bearing(e.spawn, e.zone) or nil
  return e
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
  local out = { turnin = {}, log = {}, pickup = {}, questie = D.hasQuestie(), level = level }
  local inLog = {}
  for _, e in ipairs(D.logQuests()) do
    inLog[e.id] = true
    D.finish(D.placeLog(e), level)
    table.insert(e.done and out.turnin or out.log, e)
    tick()
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
  D.sort(out.turnin, "near")
  D.sort(out.log, opts.sortLog or "near")
  D.sort(out.pickup, opts.sortPickup or "xp")
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
