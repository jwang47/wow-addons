-- QuestBoard chain plan (in a spare file so it loads with /reload; rename it
-- ChainPlan.lua before a release, AGENTS.md).
--
-- The Chain lines of a quest's tooltip show what each step gives and how
-- long it takes: the XP, a "+gear" mark when the step rewards gear, and the
-- minutes (the trip plus the work). The heading sums what is left of the
-- chain. D.chainLines here replaces the plain list in Chain.lua.
--
-- The minutes are a guess, made the same way as the board's own: the trip
-- from where the step before ends (you, for the first step) to the giver,
-- the objectives (D.OBJECTIVE_SECS each, slower above your level), back,
-- and on to the one who takes it in. The step you hover uses the board's
-- own time. XP is at your level now.
local _, ns = ...
local D = ns.data
local call = D.call

-- Where the NPC or object of a Questie Starts or Finisher table stands:
-- wx, wy, instance (its first spawn), or nil.
local QUERY = { { "NPC", "QueryNPCSingle" }, { "GameObject", "QueryObjectSingle" } }
local function spotOf(who)
  local qdb = D.module("QuestieDB")
  if type(who) ~= "table" or not qdb then return nil end
  for _, k in ipairs(QUERY) do
    local list, query = who[k[1]], qdb[k[2]]
    if type(list) == "table" and type(query) == "function" then
      for _, id in ipairs(list) do
        local spawns = call(query, id, "spawns")
        for zone, spots in pairs(type(spawns) == "table" and spawns or {}) do
          local s = type(spots) == "table" and spots[1]
          if type(s) == "table" then
            local wx, wy, inst = D.world(s, zone)
            if wx then return { wx = wx, wy = wy, inst = inst } end
          end
        end
      end
    end
  end
  return nil
end
D.spotOf = spotOf

local function nearestNode(nodes, wx, wy, inst)
  local best, bd
  for _, n in ipairs(nodes) do
    if n.inst == inst then
      local dx, dy = n.wx - wx, n.wy - wy
      local d = math.sqrt(dx * dx + dy * dy)
      if not bd or d < bd then best, bd = n, d end
    end
  end
  return best, bd
end

-- Seconds from spot a to spot b: on foot, by flight when that is shorter,
-- or the flat boat guess for another continent. Nil if a place is unknown.
function D.tripBetween(a, b)
  if not (a and b) then return nil end
  if a.inst ~= b.inst then return D.FAR_TRIP_SECS or 15 * 60 end
  local dx, dy = a.wx - b.wx, a.wy - b.wy
  local dist = math.sqrt(dx * dx + dy * dy)
  local speed = D.plain(call(rawget(_G, "GetUnitSpeed"), "player")) or 0
  if speed < D.RUN_SPEED then speed = D.RUN_SPEED end
  local secs = dist / speed
  local nodes = D.FLY_MIN_YARDS and dist >= D.FLY_MIN_YARDS and D.flyNodes and D.flyNodes()
  if nodes then
    local na, da = nearestNode(nodes, a.wx, a.wy, a.inst)
    local nb, db = nearestNode(nodes, b.wx, b.wy, b.inst)
    if na and nb and na ~= nb then
      local hx, hy = na.wx - nb.wx, na.wy - nb.wy
      local fly = (da + db) / speed + D.FLY_BOARD_SECS + math.sqrt(hx * hx + hy * hy) / D.FLY_SPEED
      if fly < secs then secs = fly end
    end
  end
  return secs
end

-- The work of a quest you have not done: talk to the giver, the
-- objectives and back, hand it in (a dungeon run for a dungeon quest).
local function workSecs(quest, id)
  local n = 0
  local raw = type(quest.objectives) == "table" and quest.objectives or {}
  for k = 1, 3 do if type(raw[k]) == "table" then n = n + #raw[k] end end
  local run = D.runSecs and D.questTag and D.runSecs({ tag = D.questTag(id) })
  return D.PICKUP_SECS * 2 + (run or (math.max(1, n) * D.OBJECTIVE_SECS * D.levelFactor(quest.level) + D.RETURN_SECS))
end

-- The best gear a quest rewards (item facts), or nil.
local function gearOf(id)
  local items = D.rewardsByQuest and D.rewardsByQuest[id]
  if not items then return nil end
  local qdb = D.module("QuestieDB")
  local best
  for _, item in ipairs(items) do
    local class = qdb and call(qdb.QueryItemSingle, item, "class")
    if class == 2 or class == 4 then
      local _, _, quality = call(D.api("C_Item.GetItemInfo"), item)
      quality = D.plain(quality) or 2
      if not best or quality > best.quality then best = { id = item, quality = quality } end
    end
  end
  return best
end

-- Fills each step not done yet with xp, travel and work (seconds; nil when
-- a place is unknown) and gear. here: the board's entry for the hovered
-- quest (its secs and place), or nil. Returns the totals: { xp, travel,
-- work, quests, unknown = steps with no time }.
function D.chainPlan(steps, at, here)
  local qdb = D.module("QuestieDB")
  local total = { xp = 0, travel = 0, work = 0, quests = 0, unknown = 0 }
  if not (steps and qdb) then return total end
  local px, py, pi = D.playerWorld()
  local from = px and { wx = px, wy = py, inst = pi } or nil
  for i, s in ipairs(steps) do
    if s.state ~= "done" then
      local quest = call(qdb.GetQuest, s.id)
      quest = type(quest) == "table" and quest or {}
      s.xp = D.questXP(s.id)
      s.gear = gearOf(s.id)
      local finish = spotOf(quest.Finisher)
      if i == at and here and here.secs then
        s.travel = here.dist and (D.travelSecs(here.dist, here)) or 0
        if here.far then s.travel = s.travel + (D.FAR_TRIP_SECS or 0) end
        s.work = math.max(0, here.secs - s.travel)
      else
        local start = s.state ~= "log" and spotOf(quest.Starts) or nil
        local toStart = start and D.tripBetween(from, start) or 0
        local toEnd = D.tripBetween(start or from, finish)
        if (start and not from) or not toEnd then
          s.travel = nil
        else
          s.travel = toStart + toEnd
        end
        s.work = workSecs(quest, s.id)
        if s.state == "log" then s.work = s.work - D.PICKUP_SECS end
      end
      from = finish or from
      total.quests = total.quests + 1
      total.xp = total.xp + (s.xp or 0)
      total.work = total.work + (s.work or 0)
      if s.travel then total.travel = total.travel + s.travel else total.unknown = total.unknown + 1 end
    end
  end
  return total
end

local function mins(secs) return math.max(1, math.floor(secs / 60 + 0.5)) end

-- "1.7k xp  6 min" for a step, grey; "" when nothing is known.
function D.stepRight(s)
  local parts = {}
  if s.xp then table.insert(parts, D.short(s.xp) .. " xp") end
  if s.work then table.insert(parts, (s.travel and "" or "~") .. mins((s.travel or 0) + s.work) .. " min") end
  return table.concat(parts, "  ")
end

-- Sums of steps first..last that are not done: xp, seconds.
local function sum(steps, first, last)
  local xp, secs = 0, 0
  for i = first, last do
    local s = steps[i]
    if s.state ~= "done" then xp, secs = xp + (s.xp or 0), secs + (s.travel or 0) + (s.work or 0) end
  end
  return xp, secs
end

D.CHAIN_SHOW = 8   -- chain lines in a tooltip
D.STEP_MARK = { done = "|cff60d060done|r", here = "|cffffd200>>|r", log = "|cffffd200log|r", later = "|cff909090...|r" }
-- Tooltip lines for a chain. Each is a string, or { left, right } for a
-- line with a right column. "Chain: quest 3 of 5" with the totals of what
-- is left, then one line per step ("done", ">>" for this quest, "log",
-- "..." for later ones) with its XP and minutes, at most CHAIN_SHOW around
-- this quest; the steps cut off are summed.
function D.chainLines(steps, at, here)
  if not steps then return {} end
  local t = D.chainPlan(steps, at, here)
  local head = string.format("Chain: quest %d of %d", at, #steps)
  local lines
  if t.quests > 0 then
    local mins_ = mins(t.travel + t.work)
    lines = { { head, string.format("%d left: %s xp, %s%d min", t.quests, D.short(t.xp), t.unknown > 0 and "~" or "", mins_) } }
    table.insert(lines, { "", string.format("|cff909090%d min travel, %d min questing (a guess)|r", mins(t.travel), mins(t.work)) })
  else
    lines = { head }
  end
  local back = math.min(2, D.CHAIN_SHOW - 1)   -- steps shown before this one
  local first = math.max(1, math.min(at - back, #steps - D.CHAIN_SHOW + 1))
  local last = math.min(#steps, first + D.CHAIN_SHOW - 1)
  if first > 1 then table.insert(lines, string.format("  (%d earlier)", first - 1)) end
  for i = first, last do
    local s = steps[i]
    local lvl = s.level and ("[" .. s.level .. "] ") or ""
    local gear = s.gear and ("  |cff" .. (D.QUALITY_HEX[s.gear.quality] or "1eff00") .. "+gear|r") or ""
    local left = "  " .. D.STEP_MARK[s.state] .. "  " .. lvl .. s.name .. gear
    if s.state == "done" then table.insert(lines, left)
    else table.insert(lines, { left, D.stepRight(s) }) end
  end
  if last < #steps then
    local xp, secs = sum(steps, last + 1, #steps)
    local more = string.format("  (%d more", #steps - last)
    if xp > 0 or secs > 0 then table.insert(lines, { more .. ")", string.format("%s xp  %d min", D.short(xp), mins(secs)) })
    else table.insert(lines, more .. ")") end
  end
  return lines
end
