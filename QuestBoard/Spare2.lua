-- QuestBoard trips (in a spare file so it loads with /reload; rename it
-- Trips.lua before a release, AGENTS.md).
--
-- How long the trip to a quest takes when a run in a straight line is the
-- wrong guess: a flight for a long way on your continent, and a flat guess
-- for another continent. D.travelSecs (Data.lua) asks D.flySecs here.
--
-- These are estimates, not measured: the flight is a straight line between
-- the two flight masters at FLY_SPEED, and the board does not know which
-- flight paths you have. The tooltip says when a time counts a flight.
local _, ns = ...
local D = ns.data
local call = D.call

D.FLY_MIN_YARDS = 1500       -- nearer than this: no flight is considered
D.FLY_SPEED = 30             -- yards per second on a flight
D.FLY_BOARD_SECS = 20        -- talk to the flight master, take off, land
D.FAR_TRIP_SECS = 15 * 60    -- another continent: boat or zeppelin, a guess

-- Every flight master of your side with a place: { wx, wy, inst, id }.
-- From Questie's NPC data, once the Town list has read it.
function D.flyNodes()
  if D.flyNodeList then return D.flyNodeList end
  local ids = D.townNPCs and D.townNPCs.flight
  local qdb = D.module("QuestieDB")
  if not (ids and qdb and type(qdb.QueryNPCSingle) == "function") then return nil end
  local list = {}
  for _, id in ipairs(ids) do
    local spawns = call(qdb.QueryNPCSingle, id, "spawns")
    if type(spawns) == "table" then
      for zone, spots in pairs(spawns) do
        local spot = type(spots) == "table" and spots[1]
        if type(spot) == "table" then
          local wx, wy, inst = D.world(spot, zone)
          if wx and wy then table.insert(list, { wx = wx, wy = wy, inst = inst, id = id }) end
        end
      end
    end
  end
  if #list == 0 then return nil end   -- no map data yet: try again later
  D.flyNodeList = list
  return list
end

local function nearestNode(nodes, wx, wy, inst)
  local best, bestD
  for _, n in ipairs(nodes) do
    if n.inst == inst then
      local dx, dy = n.wx - wx, n.wy - wy
      local d = dx * dx + dy * dy
      if not bestD or d < bestD then best, bestD = n, d end
    end
  end
  return best, bestD and math.sqrt(bestD)
end

-- The trip to e by flight, in seconds: the run to the flight master
-- nearest you, the flight, and the run from the one nearest the place.
-- nil when there is no flight to consider.
function D.flySecs(e, speed)
  if not (e.wx and e.wy and e.dist and e.dist >= D.FLY_MIN_YARDS) then return nil end
  local nodes = D.flyNodes()
  if not nodes then return nil end
  local px, py, pi = D.playerWorld()
  if not px or pi ~= e.inst then return nil end
  local a, da = nearestNode(nodes, px, py, pi)
  local b, db = nearestNode(nodes, e.wx, e.wy, e.inst)
  if not (a and b) or a == b then return nil end
  local dx, dy = a.wx - b.wx, a.wy - b.wy
  local hop = math.sqrt(dx * dx + dy * dy)
  return (da + db) / (speed or D.RUN_SPEED) + D.FLY_BOARD_SECS + hop / D.FLY_SPEED
end
