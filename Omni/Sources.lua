-- Omni sources: each builds a list of entries for Match.lua from the game.
-- Every game call goes through call(), so a function Forever lacks gives an
-- empty source, not an error.
local _, ns = ...
local S = {}
ns.sources = S
local norm = ns.match.norm

local function pass(ok, ...) if ok then return ... end end
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  return pass(pcall(fn, ...))
end
ns.call = call

local function api(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = rawget(t, part)
  end
  return t
end
ns.api = api

function ns.db()
  if type(OmniDB) ~= "table" then OmniDB = {} end
  local db = OmniDB
  db.chars = db.chars or {}
  db.itemNames = db.itemNames or {}
  db.recent = db.recent or {}
  db.whispers = db.whispers or {}
  return db
end

function ns.charKey()
  return (call(UnitName, "player") or "?") .. "-" .. (call(GetRealmName) or "?")
end

function ns.char()
  local db = ns.db()
  local key = ns.charKey()
  db.chars[key] = db.chars[key] or { bank = {}, mail = {} }
  return db.chars[key]
end

local function entry(kind, id, name, fields)
  local e = fields or {}
  e.kind, e.id, e.name = kind, id, name
  e.key = kind .. ":" .. tostring(id)
  e.lname = e.lname or norm(name)
  return e
end
S.entry = entry

function ns.money(copper)
  copper = math.floor(copper or 0)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return string.format("%dg %ds", g, s) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return c .. "c"
end

---------------------------------------------------------------------------
-- Items: bags (live), bank and mail (saved when you last opened them), and
-- every item name the game, Auctionator's scan or MageMentor knows.
---------------------------------------------------------------------------
local function linkName(link) return type(link) == "string" and link:match("%[(.-)%]") or nil end

-- { [itemID] = count } of one container.
local function readBag(bag, into, names)
  local slots = call(api("C_Container.GetContainerNumSlots"), bag) or 0
  for slot = 1, slots do
    local info = call(api("C_Container.GetContainerItemInfo"), bag, slot)
    if type(info) == "table" and info.itemID then
      into[info.itemID] = (into[info.itemID] or 0) + (info.stackCount or 1)
      local name = info.itemName or linkName(info.hyperlink)
      if name and names then names[info.itemID] = name end
    end
  end
  return slots
end

function S.bagCounts()
  local counts, names = {}, ns.db().itemNames
  for bag = 0, (rawget(_G, "NUM_BAG_SLOTS") or 4) + (rawget(_G, "NUM_REAGENTBAG_SLOTS") or 0) do
    readBag(bag, counts, names)
  end
  return counts
end

-- Bank container IDs: the main bank, the bank bags after your own bags, and
-- any Enum.BagIndex value with "bank" in its name (not the account bank).
function S.bankBags()
  local list, seen = {}, {}
  local function add(id) if type(id) == "number" and not seen[id] then seen[id] = true table.insert(list, id) end end
  local idx = api("Enum.BagIndex")
  add(type(idx) == "table" and idx.Bank or -1)
  local first = (rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS") or rawget(_G, "NUM_BAG_SLOTS") or 4) + 1
  for id = first, first + (rawget(_G, "NUM_BANKBAGSLOTS") or 7) - 1 do add(id) end
  if type(idx) == "table" then
    for name, id in pairs(idx) do
      local l = tostring(name):lower()
      if l:find("bank") and not l:find("account") then add(id) end
    end
  end
  table.sort(list)
  return list
end

function S.scanBank()
  local counts, names, any = {}, ns.db().itemNames, false
  for _, bag in ipairs(S.bankBags()) do
    if readBag(bag, counts, names) > 0 then any = true end
  end
  if not any then return false end
  local c = ns.char()
  c.bank, c.bankAt = counts, call(time)
  return true
end

function S.scanMail()
  local n = call(GetInboxNumItems) or 0
  local counts, names = {}, ns.db().itemNames
  for i = 1, n do
    for a = 1, rawget(_G, "ATTACHMENTS_MAX_RECEIVE") or 16 do
      local name, itemID, _, count = call(GetInboxItem, i, a)
      if not itemID then
        local link = call(GetInboxItemLink, i, a)
        itemID = link and tonumber(link:match("item:(%d+)"))
        name = name or linkName(link)
      end
      if itemID then
        counts[itemID] = (counts[itemID] or 0) + (count or 1)
        if name then names[itemID] = name end
      end
    end
  end
  local c = ns.char()
  c.mail, c.mailAt = counts, call(time)
end

local function itemName(id)
  local db = ns.db()
  local name = db.itemNames[id]
  if name then return name end
  name = call(api("C_Item.GetItemNameByID"), id)
  if type(name) == "string" and name ~= "" then
    db.itemNames[id] = name
    return name
  end
end

-- Item IDs in Auctionator's price database (keys are "12345" strings).
local function auctionatorIDs()
  local dbt = api("Auctionator.Database.db")
  local ids = {}
  if type(dbt) ~= "table" then return ids end
  for key in pairs(dbt) do
    -- Gear can be keyed with a prefix and item level ("g:12345:20").
    local id = tonumber(type(key) == "string" and key:match("(%d+)") or key)
    if id then table.insert(ids, id) end
  end
  return ids
end

S.ASK_PER_OPEN = 300

-- questieItems: Questie's item entries; their IDs keep e.questie on the
-- merged entry, so a quest item you no longer carry still shows its drops.
function S.items(questieItems)
  local db, c = ns.db(), ns.char()
  local mm = rawget(_G, "MageMentorDB")
  if type(mm) == "table" and type(mm.itemNames) == "table" then
    for id, name in pairs(mm.itemNames) do
      if type(id) == "number" and type(name) == "string" and not db.itemNames[id] then db.itemNames[id] = name end
    end
  end
  local bags = S.bagCounts()
  local byID, list = {}, {}
  local function get(id)
    if byID[id] then return byID[id] end
    local name = itemName(id)
    if not name then return nil end
    local e = entry("item", id, name, { where = {} })
    byID[id] = e
    table.insert(list, e)
    return e
  end
  for _, src in ipairs({ { "bags", bags }, { "bank", c.bank or {} }, { "mail", c.mail or {} } }) do
    for id, n in pairs(src[2]) do
      local e = type(n) == "number" and n > 0 and get(id)
      if e then
        e.where[src[1]] = n
        e.owned, e.boost = true, 1
      end
    end
  end
  local asked, request = 0, api("C_Item.RequestLoadItemDataByID")
  for _, id in ipairs(auctionatorIDs()) do
    local e = get(id)
    if e then e.ah = true
    elseif request and asked < S.ASK_PER_OPEN then
      call(request, id)
      asked = asked + 1
    end
  end
  for id in pairs(db.itemNames) do get(id) end
  for _, q in ipairs(questieItems or {}) do
    if byID[q.id] then byID[q.id].questie = true end
  end
  return list
end

---------------------------------------------------------------------------
-- Places: every continent, zone, city and dungeon map below the world map.
---------------------------------------------------------------------------
local function zoneNotes()
  local notes = {}
  local z = rawget(_G, "MageMentorZones")
  if type(z) == "table" then
    for _, row in ipairs(z) do
      if type(row) == "table" and row[3] then notes[row[3]] = row end
    end
  end
  return notes
end

-- The map walk is cached; the level advice is worked out again on each
-- call, so it follows your level after a level-up.
local placeCache
function S.places()
  if placeCache then return S.placeAdvice(placeCache) end
  local list, byName = {}, {}
  local mt = api("Enum.UIMapType") or {}
  local keep = { [mt.Continent or 2] = "continent", [mt.Zone or 3] = "zone", [mt.Dungeon or 4] = "dungeon" }
  local root = call(api("C_Map.GetFallbackWorldMapID")) or 947
  local maps = call(api("C_Map.GetMapChildrenInfo"), root, nil, true) or {}
  local function parentName(id)
    local info = id and call(api("C_Map.GetMapInfo"), id)
    return info and info.name
  end
  for _, m in ipairs(maps) do
    local what = keep[m.mapType]
    if what and m.name and m.name ~= "" then
      local old = byName[m.name]
      if not old or m.mapType < old.mapType then
        local e = entry("place", m.mapID, m.name, { mapType = m.mapType, what = what })
        local parent = m.mapType ~= (mt.Continent or 2) and parentName(m.parentMapID)
        e.detail = parent and (what .. ", " .. parent) or what
        if old then
          for i, x in ipairs(list) do if x == old then list[i] = e end end
        else
          table.insert(list, e)
        end
        byName[m.name] = e
      end
    end
  end
  if #list > 0 then placeCache = list end
  return S.placeAdvice(list)
end

function S.placeAdvice(list)
  local notes, level = zoneNotes(), call(UnitLevel, "player") or 0
  local faction = (call(UnitFactionGroup, "player") == "Horde") and "H" or "A"
  for _, e in ipairs(list) do
    local row = notes[e.name]
    if row then
      e.levels = string.format("%d-%d", row[1], row[2])
      e.note = row[5]
      e.fits = level >= row[1] - 1 and level <= row[2] and (row[4] == "both" or row[4] == faction)
      e.boost = e.fits and 1 or 0
    end
  end
  return list
end

---------------------------------------------------------------------------
-- People: friends, guild, group and the people you whispered with.
---------------------------------------------------------------------------
local function short(name) return (tostring(name):gsub("%-.*$", "")) end

function S.people()
  local list, byName = {}, {}
  local function add(full, tag, info)
    if type(full) ~= "string" or full == "" then return end
    local name = short(full)
    local k = name:lower()
    local e = byName[k]
    if not e then
      e = entry("person", k, name, { full = full, tags = {} })
      byName[k] = e
      table.insert(list, e)
    end
    -- Keep the name with a realm when any source gives one.
    if full:find("-", 1, true) and not e.full:find("-", 1, true) then e.full = full end
    table.insert(e.tags, tag)
    if info then
      if info.online then e.online, e.boost = true, 1 end
      e.level = e.level or info.level
      e.class = e.class or info.class
      e.area = e.area or info.area
    end
  end
  local friends = api("C_FriendList")
  for i = 1, call(friends and friends.GetNumFriends) or 0 do
    local f = call(friends.GetFriendInfoByIndex, i)
    if type(f) == "table" then
      add(f.name, "friend", { online = f.connected, level = f.level, class = f.className, area = f.area })
    end
  end
  if call(IsInGuild) then
    call(api("C_GuildInfo.GuildRoster"))
    for i = 1, call(GetNumGuildMembers) or 0 do
      local name, _, _, lvl, class, zone, _, _, online = call(GetGuildRosterInfo, i)
      add(name, "guild", { online = online, level = lvl, class = class, area = zone })
    end
  end
  local n = call(GetNumGroupMembers) or 0
  local raid = call(IsInRaid)
  for i = 1, raid and n or n - 1 do
    local unit = (raid and "raid" or "party") .. i
    local name, realm = call(UnitName, unit)
    if name and realm and realm ~= "" then name = name .. "-" .. realm end
    add(name, "group", { online = true, level = call(UnitLevel, unit), class = call(UnitClass, unit) })
  end
  for _, w in ipairs(ns.db().whispers) do add(w.name, "whisper") end
  for _, e in ipairs(list) do
    local d = table.concat(e.tags, ", ")
    if e.level and e.level > 0 then d = d .. "  " .. e.level .. (e.class and (" " .. e.class) or "") end
    if e.online and e.area then d = d .. "  " .. e.area end
    e.detail = d
  end
  return list
end

S.WHISPERS_KEPT = 30
function S.noteWhisper(name)
  if type(name) ~= "string" or name == "" then return end
  local w = ns.db().whispers
  for i = #w, 1, -1 do if w[i].name == name then table.remove(w, i) end end
  table.insert(w, 1, { name = name, at = call(time) })
  while #w > S.WHISPERS_KEPT do table.remove(w) end
end

---------------------------------------------------------------------------
-- Spells: the player's spell book (no passives), one entry per name.
---------------------------------------------------------------------------
function S.spells()
  local list, byName = {}, {}
  local book = api("C_SpellBook")
  local bank = api("Enum.SpellBookSpellBank.Player") or 0
  local spellType = api("Enum.SpellBookItemType.Spell") or 1
  local lines = call(book and book.GetNumSpellBookSkillLines) or 0
  for l = 1, lines do
    local line = call(book.GetSpellBookSkillLineInfo, l)
    if type(line) == "table" then
      local first = (line.itemIndexOffset or 0) + 1
      for slot = first, first + (line.numSpellBookItems or 0) - 1 do
        local info = call(book.GetSpellBookItemInfo, slot, bank)
        if type(info) == "table" and info.name and info.spellID and not info.isPassive
          and (info.itemType == nil or info.itemType == spellType) then
          local e = byName[info.name]
          if not e then
            e = entry("spell", info.name:lower(), info.name, {})
            byName[info.name] = e
            table.insert(list, e)
          end
          e.spellID, e.slot, e.icon = info.spellID, slot, info.iconID
          e.detail = (info.subName and info.subName ~= "") and info.subName or line.name
        end
      end
    end
  end
  return list
end

---------------------------------------------------------------------------
-- MageMentor commands (only when MageMentor is loaded).
---------------------------------------------------------------------------
S.MM_COMMANDS = {
  { "next", "trainer spells for now and the next two levels" },
  { "zone", "where to quest, and dungeons for your level" },
  { "dungeons", "dungeons for your level" },
  { "talents", "frost leveling plan vs your tree" },
  { "tailoring", "your next Tailoring step" },
  { "shop", "Auctionator shopping list of Tailoring materials" },
  { "gold", "what to keep for training" },
  { "gear", "how item scores work" },
  { "notes", "notes Claude Code left you" },
  { "panel", "show or hide the info panel" },
  { "sync", "send your status for Claude Code" },
  { "errors", "errors the addon caught" },
}

function S.commands()
  local list = {}
  if type(api("SlashCmdList.MAGEMENTOR")) ~= "function" then return list end
  for _, c in ipairs(S.MM_COMMANDS) do
    local name = "/mm " .. c[1]
    table.insert(list, entry("command", c[1], name, { args = c[1], detail = c[2], lname = norm(name .. " " .. c[2]) }))
  end
  return list
end

---------------------------------------------------------------------------
-- Quests in your log, headers skipped (a quest under a collapsed header is
-- not listed by the game). The key is Questie's "quest:ID", so the log
-- entry wins over Questie's copy of the same quest.
function S.questLog()
  local list, zone = {}, nil
  local title = rawget(_G, "GetQuestLogTitle")
  local n = call(rawget(_G, "GetNumQuestLogEntries")) or call(api("C_QuestLog.GetNumQuestLogEntries")) or 0
  for i = 1, n do
    local name, level, header, done, qid
    if title then
      local t, l, _, h, _, c, _, id = call(title, i)
      name, level, header, done, qid = t, l, h, c == 1, id
    else
      local info = call(api("C_QuestLog.GetInfo"), i)
      if type(info) == "table" then
        name, level, header, qid = info.title, info.level, info.isHeader, info.questID
        done = qid and call(api("C_QuestLog.IsComplete"), qid) and true or false
      end
    end
    if header then zone = name
    elseif type(name) == "string" and name ~= "" then
      local e = entry("log", qid or ("#" .. i), name,
        { index = i, questID = qid, level = level, zone = zone, done = done, also = "quest" })
      if qid then e.key = "quest:" .. qid end
      table.insert(list, e)
    end
  end
  return list
end

-- Questie: NPCs, quests and quest items from its database. There are tens
-- of thousands, so the index is built a slice per frame on the first open.
---------------------------------------------------------------------------
S.QUESTIE_SLICE = 2000
local questie = { state = "idle", npc = {}, quest = {}, item = {} }
S.questieState = questie

function S.questieDB()
  local loader = rawget(_G, "QuestieLoader")
  if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
  local ok, qdb = pcall(loader.ImportModule, loader, "QuestieDB")
  if ok and type(qdb) == "table" and type(qdb.QueryNPCSingle) == "function" then return qdb, loader end
end

-- Pointer tables are id -> data (older Questie) or a list of ids. A table
-- whose keys are exactly 1..n is a list: real ids are never 1..n in a row.
local function ids(t)
  local list = {}
  if type(t) ~= "table" then return list end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n > 0 and n == #t then
    for _, id in ipairs(t) do if type(id) == "number" then table.insert(list, id) end end
  else
    for id in pairs(t) do if type(id) == "number" then table.insert(list, id) end end
  end
  return list
end
S.ids = ids

-- Starts (or continues) the Questie index. onDone runs when it finishes.
function S.buildQuestie(onDone)
  if questie.state == "done" or questie.state == "busy" then return questie.state end
  local qdb = S.questieDB()
  if not qdb or not (qdb.NPCPointers or qdb.QuestPointers) then
    questie.state = qdb and "waiting" or "none"
    return questie.state
  end
  questie.state = "busy"
  local jobs = {
    { "npc", ids(qdb.NPCPointers), qdb.QueryNPCSingle },
    { "quest", ids(qdb.QuestPointers), qdb.QueryQuestSingle },
    { "item", ids(qdb.ItemPointers), qdb.QueryItemSingle },
  }
  local j, i = 1, 1
  -- A timer callback has no error guard: one bad row must not leave the
  -- state "busy" forever.
  local step
  local function body()
    local budget = S.QUESTIE_SLICE
    while budget > 0 and j <= #jobs do
      local kind, list, query = jobs[j][1], jobs[j][2], jobs[j][3]
      if i > #list or type(query) ~= "function" then
        j, i = j + 1, 1
      else
        local id = list[i]
        local name = call(query, id, "name")
        if type(name) == "string" and name ~= "" then
          local e = entry(kind, id, name, { questie = true })
          table.insert(questie[kind], e)
        end
        i, budget = i + 1, budget - 1
      end
    end
    if j <= #jobs then
      call(api("C_Timer.After"), 0, step)
    else
      questie.state = "done"
      if onDone then onDone() end
    end
  end
  step = function()
    local ok, err = pcall(body)
    if not ok then
      questie.state = "none"
      print("|cffffd100Omni|r: Questie read stopped: " .. tostring(err))
    end
  end
  step()
  return questie.state
end

function S.questieLists() return questie.npc, questie.quest, questie.item end

---------------------------------------------------------------------------
-- Nearby: Questie NPCs with a spawn on the map you stand on, matched by name
-- and title ("tailor" finds "Artisan Tailor"), nearest first. The map index
-- (uiMapID -> NPCs with their nearest spawn point there) is built once, a
-- slice per frame, after the Questie index.
---------------------------------------------------------------------------
S.NEARBY_SLICE = 1500
local near = { state = "idle", byMap = {} }
S.nearState = near

function S.buildNearby(onDone)
  if near.state ~= "idle" then return near.state end
  if questie.state ~= "done" then return "waiting" end
  local qdb, loader = S.questieDB()
  local ok, zdb = pcall(loader and loader.ImportModule or error, loader, "ZoneDB")
  if not (qdb and ok and type(zdb) == "table" and type(zdb.GetUiMapIdByAreaId) == "function") then
    near.state = "none"
    return near.state
  end
  near.state = "busy"
  local mapOf, list, i = {}, questie.npc, 1
  -- A timer callback has no error guard: one bad row must not leave the
  -- state "busy" forever.
  local step
  local function body()
    local budget = S.NEARBY_SLICE
    while budget > 0 and i <= #list do
      local e = list[i]
      local spawns = call(qdb.QueryNPCSingle, e.id, "spawns")
      local cost = 1
      if type(spawns) == "table" then
        for area, points in pairs(spawns) do
          if mapOf[area] == nil then mapOf[area] = call(zdb.GetUiMapIdByAreaId, zdb, area) or false end
          local mapID = mapOf[area]
          if mapID and type(points) == "table" then
            local pts = {}
            for _, p in ipairs(points) do
              if type(p) == "table" and type(p[1]) == "number" and p[1] >= 0 and type(p[2]) == "number" then table.insert(pts, { p[1] / 100, p[2] / 100 }) end
            end
            cost = cost + #points / 4 -- the slice budget counts spawn points too
            if #pts > 0 then
              near.byMap[mapID] = near.byMap[mapID] or {}
              table.insert(near.byMap[mapID], { id = e.id, name = e.name, points = pts })
            end
          end
        end
      end
      i, budget = i + 1, budget - cost
    end
    if i <= #list then
      call(api("C_Timer.After"), 0, step)
    else
      near.state = "done"
      if onDone then onDone() end
    end
  end
  step = function()
    local ok, err = pcall(body)
    if not ok then
      near.state = "none"
      print("|cffffd100Omni|r: Nearby read stopped: " .. tostring(err))
    end
  end
  step()
  return near.state
end

-- Where you stand: map ID, x and y (0 to 1), or nil.
function S.playerPos()
  local mapID = call(api("C_Map.GetBestMapForUnit"), "player")
  if not mapID then return nil end
  local pos = call(api("C_Map.GetPlayerMapPosition"), mapID, "player")
  if type(pos) ~= "table" then return mapID end
  local x, y
  if pos.GetXY then x, y = call(pos.GetXY, pos) else x, y = pos.x, pos.y end
  return mapID, x, y
end

-- Yards between two points on one map, or nil when the map size is unknown.
function S.yards(mapID, x1, y1, x2, y2)
  local w, h = call(api("C_Map.GetMapWorldSize"), mapID)
  if not (w and h and w > 0 and h > 0) then return nil end
  local dx, dy = (x2 - x1) * w, (y2 - y1) * h
  return math.sqrt(dx * dx + dy * dy)
end

-- Entries for the map you stand on. Each keeps its nearest spawn there; the
-- key is the NPC's own, so the Nearby row wins over the plain NPC row.
function S.nearby()
  local list = {}
  local mapID, px, py = S.playerPos()
  local npcs = mapID and near.byMap[mapID]
  if not npcs then return list end
  local qdb = S.questieDB()
  -- Rank in yards when the map size is known (maps are not square).
  local w, h = call(api("C_Map.GetMapWorldSize"), mapID)
  if not (w and h and w > 0 and h > 0) then w, h = 1, 1 end
  for _, n in ipairs(npcs) do
    local best, bx, by = nil, n.points[1][1], n.points[1][2]
    if px and py then
      for _, p in ipairs(n.points) do
        local d = ((p[1] - px) * w) ^ 2 + ((p[2] - py) * h) ^ 2
        if not best or d < best then best, bx, by = d, p[1], p[2] end
      end
    end
    local sub = n.sub
    if sub == nil then
      sub = qdb and call(qdb.QueryNPCSingle, n.id, "subName")
      n.sub = type(sub) == "string" and sub or false
      sub = n.sub
    end
    local e = entry("near", n.id, n.name, { also = "npc", mapID = mapID, x = bx, y = by, sub = sub or nil,
      lname = norm(n.name .. (sub and (" " .. sub) or "")) })
    e.key = "npc:" .. n.id
    e.boost = best and -best or 0 -- nearer first among equal matches
    table.insert(list, e)
  end
  return list
end
