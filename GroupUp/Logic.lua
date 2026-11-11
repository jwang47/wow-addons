-- GroupUp logic: what a group changes for you, in numbers you can check.
--
--  1. Your quests: which ones a group speeds up (kill objectives count for
--     everyone in the group), which ones need a group (elite, group or
--     dungeon quests), and which party members have them too.
--  2. Your measured XP per hour, solo and in each group size, at about your
--     level (this character only).
--  3. How kill XP is split: the Classic group bonus and the share by level.
--
-- Questie is optional. Every game and Questie call is guarded, and values
-- the Forever client hides ("secret" numbers) count as unknown.
local addonName, ns = ...
local M = {}
ns.logic = M

M.BREAK_SECS = 600   -- a gap with no XP longer than this is a break: not counted
M.MIN_SECS = 300     -- show an XP-per-hour number only after this much time
M.LEVELS_BACK = 2    -- the XP-per-hour numbers use your level and this many below
M.MAX_SIZE = 5       -- raids count as 5

-- Classic group XP: the kill XP times this bonus is split by level among the
-- members near the kill.
M.BONUS = { 1, 1, 1.166, 1.3, 1.4 }

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h end
end
M.call = call

local function plain(v)
  if type(v) ~= "number" then return nil end
  local secret = rawget(_G, "issecretvalue")
  if secret and secret(v) then return nil end
  return v
end
M.plain = plain

local function api(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end
M.api = api

local function text(v)
  if type(v) ~= "string" then return nil end
  local secret = rawget(_G, "issecretvalue")
  if secret and secret(v) then return nil end
  return v
end

---------------------------------------------------------------------------
-- Kill XP split
---------------------------------------------------------------------------
-- Your share of the solo kill XP in a group: levels lists every member near
-- the kill, you included. 1 means the same XP as solo.
function M.share(myLevel, levels)
  local n = math.min(#levels, M.MAX_SIZE)
  if n <= 1 then return 1 end
  local sum = 0
  for i = 1, n do sum = sum + (levels[i] or myLevel) end
  if sum <= 0 then return 1 / n end
  return M.BONUS[n] * myLevel / sum
end

-- The highest mob level that gives no XP (grey) at this level.
function M.greyLevel(level)
  if level <= 5 then return 0 end
  if level <= 39 then return level - math.floor(level / 10) - 5 end
  return level - math.floor(level / 5) - 1
end

-- Kill XP is worked out from the highest level in the group, so mobs that are
-- grey to that member give nobody XP. True when mobs of your level are grey
-- to the highest member.
function M.highMemberGreys(myLevel, levels)
  local top = myLevel
  for _, l in ipairs(levels) do if l > top then top = l end end
  return myLevel <= M.greyLevel(top), top
end

---------------------------------------------------------------------------
-- XP tracking
---------------------------------------------------------------------------
-- st: the tracker state { last, size, level, xp, max }. buckets:
-- levels[level][size] = { secs, xp, quest, kills, killxp, rested }.
local function bucket(levels, level, size)
  levels[level] = levels[level] or {}
  local b = levels[level][size]
  if not b then
    b = { secs = 0, xp = 0, quest = 0, kills = 0, killxp = 0, rested = 0 }
    levels[level][size] = b
  end
  return b
end
M.bucket = bucket

function M.clampSize(n)
  n = n or 1
  if n < 1 then return 1 end
  if n > M.MAX_SIZE then return M.MAX_SIZE end
  return n
end

-- Credits the time since the last event to the group size and level of that
-- time, then starts a new stretch at now with size and level.
function M.tick(st, levels, now, size, level)
  if st.last and st.level and st.size then
    local dt = now - st.last
    if dt > 0 and dt <= M.BREAK_SECS then
      local b = bucket(levels, st.level, st.size)
      b.secs = b.secs + dt
    end
  end
  st.last, st.size, st.level = now, M.clampSize(size), level
end

-- XP gained since the last reading, across a level-up.
function M.xpDelta(st, xp, max)
  if not (xp and max) then return 0 end
  local d = 0
  if st.xp then
    if xp >= st.xp then d = xp - st.xp
    elseif st.max then d = (st.max - st.xp) + xp end
  end
  st.xp, st.max = xp, max
  return d
end

-- The numbers in a kill XP message: "Kobold dies, you gain 300 experience.
-- (+150 exp Rested bonus)". Returns xp, rested (rested is part of xp), or
-- nil when it is not a kill message.
function M.parseKill(msg)
  msg = text(msg)
  if not msg then return nil end
  local xp = tonumber(msg:match("dies, you gain (%d+)") or msg:match("gain (%d+) experience"))
  if not xp then return nil end
  if not msg:find("dies", 1, true) and not msg:find("slain", 1, true) then return nil end
  local rested = tonumber(msg:match("%+(%d+) exp Rested")) or 0
  return xp, rested
end

---------------------------------------------------------------------------
-- XP per hour
---------------------------------------------------------------------------
-- Adds every bucket for sizes in `sizes` at levels level-back .. level.
function M.sum(levels, level, sizes, back)
  local t = { secs = 0, xp = 0, quest = 0, kills = 0, killxp = 0, rested = 0 }
  for l = level - (back or M.LEVELS_BACK), level do
    local row = levels[l]
    if row then
      for _, s in ipairs(sizes) do
        local b = row[s]
        if b then for k in pairs(t) do t[k] = t[k] + (b[k] or 0) end end
      end
    end
  end
  return t
end

-- XP per hour without rested bonus XP, or nil with too little time.
function M.perHour(t)
  if t.secs < M.MIN_SECS then return nil end
  return (t.xp - t.rested) / t.secs * 3600
end

function M.perKill(t)
  if t.kills <= 0 then return nil end
  return (t.killxp - t.rested) / t.kills
end

function M.killsPerMin(t)
  if t.secs < M.MIN_SECS or t.kills <= 0 then return nil end
  return t.kills / t.secs * 60
end

function M.questShare(t)
  if t.xp <= 0 then return nil end
  return t.quest / t.xp
end

---------------------------------------------------------------------------
-- Your quests
---------------------------------------------------------------------------
local GROUP_TAGS = { [1] = true, [62] = true, [81] = true, [88] = true, [89] = true }
local GROUP_NAMES = { Group = true, Elite = true, Dungeon = true, Raid = true, Heroic = true }

function M.module(name)
  local loader = rawget(_G, "QuestieLoader")
  if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
  local ok, m = pcall(loader.ImportModule, loader, name)
  if ok and type(m) == "table" then return m end
end

-- The tag of a quest: "Elite", "Dungeon", ... or nil.
function M.tag(id, suggested)
  local tagID, tagName = call(rawget(_G, "GetQuestTagInfo"), id)
  tagID, tagName = plain(tagID), text(tagName)
  if not tagID and not tagName then
    local qdb = M.module("QuestieDB")
    if qdb then tagID, tagName = call(qdb.GetQuestTagInfo, id) end
    tagID, tagName = plain(tagID), text(tagName)
  end
  if (tagID and GROUP_TAGS[tagID]) or (tagName and GROUP_NAMES[tagName]) then
    return tagName or "Group"
  end
  suggested = plain(suggested)
  if suggested and suggested > 1 then return "Group " .. suggested end
end

-- Unfinished objectives by type: kills (monster), drops (item), clicks
-- (object), other (talk, explore, event).
local function objectives(id, index)
  local o = { kills = 0, drops = 0, clicks = 0, other = 0, total = 0, lines = {} }
  local list = call(api("C_QuestLog.GetQuestObjectives"), id)
  if type(list) ~= "table" then
    list = {}
    local lb, num = rawget(_G, "GetQuestLogLeaderBoard"), rawget(_G, "GetNumQuestLeaderBoards")
    for i = 1, plain(call(num, index)) or 0 do
      local t, kind, done = call(lb, i, index)
      table.insert(list, { text = t, type = kind, finished = done })
    end
  end
  for _, ob in ipairs(list) do
    o.total = o.total + 1
    if not ob.finished then
      local k = ob.type == "monster" and "kills" or ob.type == "item" and "drops"
        or ob.type == "object" and "clicks" or "other"
      o[k] = o[k] + 1
      table.insert(o.lines, { text = text(ob.text), kind = k })
    end
  end
  return o
end

-- Party members (names) who have the quest too.
function M.sharedWith(id, index, units)
  local names = {}
  local cq = api("C_QuestLog.IsUnitOnQuest")
  local old = rawget(_G, "IsUnitOnQuest")
  for _, u in ipairs(units) do
    local on = call(cq, u, id)
    if on == nil and old then on = call(old, index, u) end
    if on == true or on == 1 then
      local name = text(call(rawget(_G, "UnitName"), u))
      table.insert(names, name or u)
    end
  end
  return names
end

-- What a group does for a quest: "need" (tagged group, elite, dungeon),
-- "faster" (kill objectives left: kills count for everyone), "maybe"
-- (drops or clicks left: it depends whether each of you gets a copy),
-- "same" (talk, explore) or "done".
function M.verdict(q)
  if q.done then return "done" end
  if q.tag then return "need" end
  if q.obj.kills > 0 then return "faster" end
  if q.obj.drops > 0 or q.obj.clicks > 0 then return "maybe" end
  return "same"
end

M.RANK = { need = 1, faster = 2, maybe = 3, same = 4, pickup = 5, done = 6 }

-- Every quest in your log, best reason to group first.
function M.quests(units)
  local out = {}
  local n = plain(call(api("C_QuestLog.GetNumQuestLogEntries"))) or 0
  local title = rawget(_G, "GetQuestLogTitle")
  for i = 1, n do
    local name, level, suggested, header, done, id
    local info = call(api("C_QuestLog.GetInfo"), i)
    if type(info) == "table" then
      name, level, suggested, header, id = info.title, info.level, info.suggestedGroup, info.isHeader, info.questID
    elseif title then
      local t, l, s, h, _, c, _, q = call(title, i)
      name, level, suggested, header, id, done = t, l, s, h, q, (c == 1 or c == true)
    end
    if not header and id and text(name) and not (info and info.isHidden) then
      if done == nil then
        done = (call(api("C_QuestLog.ReadyForTurnIn"), id) or call(api("C_QuestLog.IsComplete"), id)) and true or false
      end
      local q = { id = id, name = name, level = plain(level), index = i, done = done }
      q.obj = objectives(id, i)
      if q.obj.total > 0 and #q.obj.lines == 0 then q.done = true end
      q.tag = M.tag(id, suggested)
      q.shared = M.sharedWith(id, i, units or {})
      q.verdict = M.verdict(q)
      table.insert(out, q)
    end
  end
  table.sort(out, function(a, b)
    local ra, rb = M.RANK[a.verdict], M.RANK[b.verdict]
    if ra ~= rb then return ra < rb end
    if #a.shared ~= #b.shared then return #a.shared > #b.shared end
    return a.name < b.name
  end)
  return out
end

---------------------------------------------------------------------------
-- QuestBoard pins
---------------------------------------------------------------------------
-- The quests you pinned in QuestBoard (Alt-click, "I'm doing this"), as a
-- set of quest IDs, or nil when QuestBoard is not there or nothing is
-- pinned. QuestBoard keeps them in QuestBoardDB.doing.
function M.pins()
  local db = rawget(_G, "QuestBoardDB")
  local doing = type(db) == "table" and db.doing
  if type(doing) ~= "table" then return nil end
  local set, n = {}, 0
  for id, on in pairs(doing) do
    if on and type(id) == "number" then set[id] = true n = n + 1 end
  end
  if n == 0 then return nil end
  return set
end

-- The name of a quest you do not have yet (a pinned pick-up).
function M.questName(id)
  local name = text(call(api("C_QuestLog.GetTitleForQuestID"), id))
  if name then return name end
  local qdb = M.module("QuestieDB")
  if qdb and type(qdb.QueryQuestSingle) == "function" then
    name = text(call(qdb.QueryQuestSingle, id, "name"))
  end
  return name or ("Quest " .. id)
end

-- Splits your log by the pins: the pinned quests in your log, pinned quests
-- you have not taken yet (verdict "need" when tagged for a group, else
-- "pickup"), and the rest of your log. Without pins, every quest is in
-- `focus` and `pinned` is false.
function M.focus(quests, pins)
  if not pins then return { focus = quests, rest = {}, pinned = false } end
  local out = { focus = {}, rest = {}, pinned = true }
  local seen = {}
  for _, q in ipairs(quests) do
    if pins[q.id] then table.insert(out.focus, q) seen[q.id] = true
    else table.insert(out.rest, q) end
  end
  local later = {}
  for id in pairs(pins) do
    if not seen[id] then
      local q = { id = id, name = M.questName(id), notTaken = true, shared = {},
        obj = { kills = 0, drops = 0, clicks = 0, other = 0, total = 0, lines = {} } }
      q.tag = M.tag(id)
      q.verdict = q.tag and "need" or "pickup"
      table.insert(later, q)
    end
  end
  table.sort(later, function(a, b) return a.name < b.name end)
  for _, q in ipairs(later) do table.insert(out.focus, q) end
  return out
end

function M.count(quests)
  local c = { need = 0, faster = 0, maybe = 0, same = 0, pickup = 0, done = 0, shared = 0 }
  for _, q in ipairs(quests) do
    c[q.verdict] = c[q.verdict] + 1
    if #q.shared > 0 and q.verdict ~= "done" then c.shared = c.shared + 1 end
  end
  return c
end

-- Which way the numbers lean: "group", "solo" or "even", and the reasons.
-- A quest that needs a group counts 2, a quest with kills left 1, a quest
-- with only drops or clicks left -0.5; measured XP per hour that differs by
-- 10% or more counts 2 for the faster way.
function M.lean(c, soloRate, groupRate)
  local score, why = 0, {}
  if c.need > 0 then score = score + 2 * c.need table.insert(why, c.need .. " need a group") end
  if c.faster > 0 then score = score + c.faster table.insert(why, c.faster .. " with kills to share") end
  if c.maybe > 0 then score = score - 0.5 * c.maybe end
  if soloRate and groupRate then
    if groupRate >= soloRate * 1.1 then score = score + 2 table.insert(why, "grouped XP/h is higher")
    elseif soloRate >= groupRate * 1.1 then score = score - 2 table.insert(why, "solo XP/h is higher") end
  end
  if c.maybe > 0 and score <= 0 then table.insert(why, c.maybe .. " with only drops or clicks") end
  local way = score >= 1 and "group" or score <= -1 and "solo" or "even"
  return way, why
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
function M.short(n)
  if not n then return "?" end
  if n >= 10000 then return string.format("%dk", math.floor(n / 1000 + 0.5)) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n + 0.5))
end

function M.mins(secs) return string.format("%d min", math.floor((secs or 0) / 60 + 0.5)) end

function M.pct(f) return string.format("%d%%", math.floor(f * 100 + 0.5)) end

-- "solo 11k/h vs grouped 14k/h": the measured line, or what is missing.
function M.rateLine(solo, grouped)
  local a, b = M.perHour(solo), M.perHour(grouped)
  local function one(label, t, r)
    if r then return label .. " " .. M.short(r) .. "/h" end
    return label .. " ? (" .. M.mins(t.secs) .. " of " .. M.mins(M.MIN_SECS) .. ")"
  end
  return one("solo", solo, a) .. "   " .. one("grouped", grouped, b)
end

-- The kill-split line for a group of these levels (you first).
function M.splitLine(myLevel, levels)
  local s = M.share(myLevel, levels)
  return string.format("you get %s of the solo kill XP; kill %.1fx as fast to keep up", M.pct(s), 1 / s)
end

-- A short summary for chat: the quest counts and the measured rates.
-- pinned: the quests are your QuestBoard pins.
function M.summary(quests, solo, grouped, pinned)
  local c = M.count(quests)
  local parts = {}
  if c.need > 0 then table.insert(parts, c.need .. " need a group") end
  if c.faster > 0 then table.insert(parts, c.faster .. " go faster (shared kills)") end
  if c.maybe > 0 then table.insert(parts, c.maybe .. " drops or clicks") end
  if c.pickup > 0 then table.insert(parts, c.pickup .. " not taken yet") end
  if c.shared > 0 then table.insert(parts, c.shared .. " shared with your group") end
  local q = #parts > 0 and table.concat(parts, ", ") or "no open quests"
  return (pinned and "Pinned quests: " or "Quests: ") .. q .. ".", "XP: " .. M.rateLine(solo, grouped) .. "."
end

return M
