-- UpgradeFinder: where an item comes from, read from Questie's database
-- when Questie is on: quest rewards, drops (and the dungeon), vendors,
-- objects and containers. Items Questie does not know get nothing.
local _, ns = ...
local W = {}
ns.where = W
local call, api = ns.call, ns.api

W.MAX_DROPS = 3   -- more NPCs than this drop it: a "world drop"
W.LOOK = 10       -- droppers checked to see if they are all in one dungeon

local function qdb()
  local loader = rawget(_G, "QuestieLoader")
  if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
  local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
  if ok and type(db) == "table" and type(db.QueryItemSingle) == "function" then return db, loader end
end
W.qdb = qdb

-- A query that errors marks the lookup as failed, so W.of does not cache
-- a result that is only empty because Questie was not ready.
local failed = false
local function q(kind, id, key)
  local db = qdb()
  if not db then failed = true return nil end
  local fn = ({ npc = db.QueryNPCSingle, quest = db.QueryQuestSingle, item = db.QueryItemSingle })[kind]
  if type(fn) ~= "function" then failed = true return nil end
  local ok, v = pcall(fn, id, key)
  if not ok then failed = true return nil end
  return v
end

local function list(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for _, v in ipairs(t) do if type(v) == "number" then table.insert(out, v) end end
  return out
end

local zoneNames = {}
local function areaName(area)
  if zoneNames[area] then return zoneNames[area] end
  local name = call(api("C_Map.GetAreaInfo"), area)
  if type(name) ~= "string" or name == "" then
    local _, loader = qdb()
    local ok, zdb = pcall(loader and loader.ImportModule or error, loader, "ZoneDB")
    local mapID = ok and type(zdb) == "table" and call(zdb.GetUiMapIdByAreaId, zdb, area)
    local info = mapID and call(api("C_Map.GetMapInfo"), mapID)
    name = type(info) == "table" and info.name or nil
  end
  zoneNames[area] = name or false
  return name
end

-- Where an NPC is: a zone name, and the instance area when every spawn
-- it has is in that one instance (Questie gives instance spawns as -1, -1).
local function npcPlace(id)
  local spawns = q("npc", id, "spawns")
  if type(spawns) == "table" then
    local first, inside, outside = nil, nil, false
    for area, points in pairs(spawns) do
      first = first or area
      local p = type(points) == "table" and points[1]
      if type(p) == "table" and p[1] == -1 then
        if inside and inside ~= area then outside = true end
        inside = inside or area
      else
        outside = true
      end
    end
    if inside and not outside then return areaName(inside), inside end
    if first then return areaName(first), nil end
  end
  local zone = q("npc", id, "zoneID")
  return type(zone) == "number" and zone > 0 and areaName(zone) or nil, nil
end

local cache = {}
function W.forget() for k in pairs(cache) do cache[k] = nil end end

-- { quests = {name...}, drops = {{name, zone, dungeon}...}, world = bool,
--   dungeon = zone name (it drops in that dungeon), vendors = {{name, zone}},
--   objects = n, containers = n }, or nil when Questie has nothing.
function W.of(id)
  if cache[id] ~= nil then return cache[id] or nil end
  if not qdb() then return nil end -- not cached: Questie may load later
  failed = false
  local r, any = { quests = {}, drops = {}, vendors = {} }, false
  for _, qid in ipairs(list(q("item", id, "questRewards"))) do
    local name = q("quest", qid, "name")
    if type(name) == "string" then table.insert(r.quests, name) any = true end
  end
  local npcs = list(q("item", id, "npcDrops"))
  -- A dungeon drop: every dropper (all checked, so at most LOOK of them)
  -- spawns only in one and the same instance.
  local area, same = nil, #npcs > 0 and #npcs <= W.LOOK
  for i = 1, math.min(#npcs, W.LOOK) do
    local name = q("npc", npcs[i], "name")
    local zone, instance = npcPlace(npcs[i])
    if not instance or (area and area ~= instance) then same = false end
    area = area or instance
    if type(name) == "string" and #npcs <= W.MAX_DROPS then
      table.insert(r.drops, { name = name, zone = zone, dungeon = instance ~= nil })
    end
  end
  if #npcs > W.MAX_DROPS then r.world = true end
  if same and area then r.dungeon = areaName(area) end
  any = any or #npcs > 0
  for _, v in ipairs(list(q("item", id, "vendors"))) do
    local name = q("npc", v, "name")
    if type(name) == "string" then
      table.insert(r.vendors, { name = name, zone = (npcPlace(v)) })
      any = true
      if #r.vendors >= 2 then break end
    end
  end
  r.objects = #list(q("item", id, "objectDrops"))
  r.containers = #list(q("item", id, "itemDrops"))
  any = any or r.objects > 0 or r.containers > 0
  if not failed then cache[id] = any and r or false end
  return any and r or nil
end

-- A short tag for a list row: the item is free to get without the AH.
function W.tag(r)
  if not r then return nil end
  if r.quests[1] then return "quest" end
  if r.dungeon then return r.dungeon end
  if r.vendors[1] then return "vendor" end
end

local function place(name, zone) return zone and (name .. " (" .. zone .. ")") or name end

-- Tooltip lines, one per kind of source.
function W.lines(r)
  local out = {}
  if not r then return out end
  if r.quests[1] then
    table.insert(out, "Quest reward: " .. table.concat(r.quests, ", ", 1, math.min(#r.quests, 2)))
  end
  if #r.drops > 0 then
    local parts = {}
    for _, d in ipairs(r.drops) do table.insert(parts, place(d.name, d.zone)) end
    table.insert(out, "Drops from " .. table.concat(parts, ", "))
  elseif r.dungeon then
    table.insert(out, "Drops in " .. r.dungeon)
  elseif r.world then
    table.insert(out, "World drop")
  end
  if r.vendors[1] then
    local parts = {}
    for _, v in ipairs(r.vendors) do table.insert(parts, place(v.name, v.zone)) end
    table.insert(out, "Sold by " .. table.concat(parts, ", "))
  end
  if r.objects > 0 then table.insert(out, "From a chest or other object") end
  if r.containers > 0 then table.insert(out, "Inside a container item") end
  return out
end

-- Adds "Get it:" lines to an item tooltip (gear only, and only when on).
function W.addToTooltip(tt, id)
  if not (tt and id) or ns.db().opts.where == false then return end
  local loc = ns.scan.equipLoc(id)
  if not (loc and ns.score.SLOTS[loc]) then return end
  local lines = W.lines(W.of(id))
  for i, l in ipairs(lines) do tt:AddLine((i == 1 and "Get it: " or "  ") .. l, 0.55, 0.78, 1) end
end

local function onTooltip(tt)
  if not (tt and tt.GetItem) then return end
  local _, link = tt:GetItem()
  local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
  if id and tt ~= rawget(_G, "UpgradeFinderScanTooltip") then W.addToTooltip(tt, id) end
end
local function guarded(tt) pcall(onTooltip, tt) end
W.onTooltip = guarded

local hooked = false
function W.hook()
  if hooked then return end
  hooked = true
  local proc, enum = rawget(_G, "TooltipDataProcessor"), api("Enum.TooltipDataType.Item")
  if type(proc) == "table" and proc.AddTooltipPostCall and enum then
    proc.AddTooltipPostCall(enum, guarded)
  else
    local gt = rawget(_G, "GameTooltip")
    if gt and gt.HookScript then gt:HookScript("OnTooltipSetItem", guarded) end
    local ref = rawget(_G, "ItemRefTooltip")
    if ref and ref.HookScript then ref:HookScript("OnTooltipSetItem", guarded) end
  end
end
W.hook()
