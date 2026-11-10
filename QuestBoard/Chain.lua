-- QuestBoard chains: what a quest leads to. Questie's quests know the next
-- quest in their chain (nextQuestInChain); its items know which quests
-- reward them (questRewards). The board reads every item once (a slice per
-- frame) to turn that round, then walks each quest's chain to its end and
-- keeps the best reward: gear before other items, then item quality.
local addonName, ns = ...
local D = ns.data
local call, api, plain = D.call, D.api, D.plain

D.CHAIN_MAX = 20                 -- longest chain walked
D.rewardsByQuest = nil           -- questID -> { itemID, ... } once built
D.rewardBuild = { state = "idle", i = 1, ids = nil }

-- A Questie pointer table as a list of ids (id -> data, or a list).
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

-- Builds the reward index; tick() may yield (it runs inside collect).
-- Returns true when the index is ready.
function D.buildRewards(tick)
  local b = D.rewardBuild
  if b.state == "done" then return true end
  if b.state == "none" then return false end
  local qdb = D.module("QuestieDB")
  if not (qdb and type(qdb.QueryItemSingle) == "function" and qdb.ItemPointers) then
    return false
  end
  if not b.ids then b.ids, b.map, b.names = ids(qdb.ItemPointers), {}, {} end
  while b.i <= #b.ids do
    local item = b.ids[b.i]
    local quests = call(qdb.QueryItemSingle, item, "questRewards")
    -- Quest items by name too, for objectives Questie has no place for.
    if call(qdb.QueryItemSingle, item, "class") == 12 then
      local name = call(qdb.QueryItemSingle, item, "name")
      if type(name) == "string" then b.names[name] = b.names[name] or item end
    end
    if type(quests) == "table" then
      for _, q in ipairs(quests) do
        b.map[q] = b.map[q] or {}
        table.insert(b.map[q], item)
      end
    end
    b.i = b.i + 1
    if tick and b.i % 200 == 0 then tick() end
  end
  D.rewardsByQuest, D.itemsByName, b.state, b.ids = b.map, b.names, "done", nil
  return true
end

-- The quests from id to the end of its chain.
function D.chain(id)
  local qdb = D.module("QuestieDB")
  local list, seen, q = { id }, { [id] = true }, id
  for _ = 1, D.CHAIN_MAX do
    local nxt = qdb and call(qdb.QueryQuestSingle, q, "nextQuestInChain")
    if type(nxt) ~= "number" or nxt <= 0 or seen[nxt] then break end
    seen[nxt] = true
    table.insert(list, nxt)
    q = nxt
  end
  return list
end

-- The quest before id: Questie's preQuestSingle (one of them is enough),
-- else the first of preQuestGroup (all of them are needed).
local function firstOf(v)
  if type(v) == "number" and v > 0 then return v end
  if type(v) == "table" then
    for _, x in ipairs(v) do if type(x) == "number" and x > 0 then return x end end
  end
  return nil
end
function D.preQuest(id)
  local qdb = D.module("QuestieDB")
  if not qdb then return nil end
  return firstOf(call(qdb.QueryQuestSingle, id, "preQuestSingle")) or firstOf(call(qdb.QueryQuestSingle, id, "preQuestGroup"))
end

-- The whole chain around id: the quests before it (walked back) and after
-- it. Returns the list and the place of id in it.
function D.fullChain(id)
  local before, seen, q = {}, { [id] = true }, id
  for _ = 1, D.CHAIN_MAX do
    local pre = D.preQuest(q)
    if not pre or seen[pre] then break end
    seen[pre] = true
    table.insert(before, 1, pre)
    q = pre
  end
  local list = {}
  for _, x in ipairs(before) do table.insert(list, x) end
  for _, x in ipairs(D.chain(id)) do
    if x == id or not seen[x] then seen[x] = true table.insert(list, x) end
  end
  return list, #before + 1
end

local function completed(id)
  local f = api("C_QuestLog.IsQuestFlaggedCompleted") or rawget(_G, "IsQuestFlaggedCompleted")
  return f and call(f, id) == true or false
end

-- Each step of the chain: { id, name, level, state } with state "done"
-- (handed in), "here" (this quest), "log" (in your log), or "later".
-- inLog: questID -> true. Nil when the quest has no chain.
function D.chainSteps(id, inLog)
  local qdb = D.module("QuestieDB")
  if not qdb then return nil end
  local list, at = D.fullChain(id)
  if #list < 2 then return nil end
  local steps = {}
  for i, q in ipairs(list) do
    local state = i == at and "here" or (inLog and inLog[q]) and "log" or completed(q) and "done" or (i < at and "done" or "later")
    local name = call(qdb.QueryQuestSingle, q, "name")
    table.insert(steps, { id = q, name = type(name) == "string" and name or ("quest " .. q),
      level = plain(call(qdb.QueryQuestSingle, q, "questLevel")), state = state })
  end
  return steps, at
end

D.CHAIN_SHOW = 8   -- chain lines in a tooltip
D.STEP_MARK = { done = "|cff60d060done|r", here = "|cffffd200>>|r", log = "|cffffd200log|r", later = "|cff909090...|r" }
-- Tooltip lines for a chain: "Chain: 3 of 5", then one line per step
-- ("done", ">>" for this quest, "log", "..." for later ones), at most
-- CHAIN_SHOW around this quest.
function D.chainLines(steps, at)
  if not steps then return {} end
  local lines = { string.format("Chain: quest %d of %d", at, #steps) }
  local back = math.min(2, D.CHAIN_SHOW - 1)   -- steps shown before this one
  local first = math.max(1, math.min(at - back, #steps - D.CHAIN_SHOW + 1))
  local last = math.min(#steps, first + D.CHAIN_SHOW - 1)
  if first > 1 then table.insert(lines, string.format("  (%d earlier)", first - 1)) end
  for i = first, last do
    local s = steps[i]
    local lvl = s.level and ("[" .. s.level .. "] ") or ""
    table.insert(lines, "  " .. D.STEP_MARK[s.state] .. "  " .. lvl .. s.name)
  end
  if last < #steps then table.insert(lines, string.format("  (%d more)", #steps - last)) end
  return lines
end

local function itemFacts(item)
  local qdb = D.module("QuestieDB")
  local class = qdb and call(qdb.QueryItemSingle, item, "class")
  local name, _, quality = call(api("C_Item.GetItemInfo"), item)
  if not quality then call(api("C_Item.RequestLoadItemDataByID"), item) end
  name = name or (qdb and call(qdb.QueryItemSingle, item, "name"))
  return { id = item, name = name, quality = plain(quality), gear = class == 2 or class == 4 }
end

local cache = {}
function D.resetChains() cache = {} end

-- { steps (quests after this one), best = item facts or nil, at = quest of
-- the best reward, here = best is this quest's own reward, own = the best of
-- this quest's own rewards (any item), count = how many it offers }, or nil while
-- the reward index is not ready.
function D.chainInfo(id)
  if not D.rewardsByQuest then return nil end
  if cache[id] then return cache[id] end
  local chain = D.chain(id)
  local best, at, own, unknown = nil, nil, nil, false
  local function score(f) return f and ((f.gear and 10 or 0) + (f.quality or 1)) or -1 end
  for _, q in ipairs(chain) do
    for _, item in ipairs(D.rewardsByQuest[q] or {}) do
      local f = itemFacts(item)
      if not f.quality then unknown = true end
      if score(f) > score(best) then best, at = f, q end
      if q == id and score(f) > score(own) then own = f end
    end
  end
  local info = { steps = #chain - 1, best = best, at = at, here = at == id, own = own,
    count = #(D.rewardsByQuest[id] or {}) }
  if not unknown then cache[id] = info end   -- ask again once item data loads
  return info
end

D.QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }

-- A short tag: "-> [Item]" in the item's colour ("chain" when it is further
-- down the chain), or "XP only". Nil when nothing is known.
function D.chainTag(info)
  if not info then return nil end
  local b = info.best
  if b and b.gear and (b.quality or 2) >= 2 then
    local hex = D.QUALITY_HEX[b.quality or 2] or "1eff00"
    local where = info.here and "" or ("chain " .. (info.steps > 0 and ("+" .. info.steps .. " ") or ""))
    return where .. "-> |cff" .. hex .. "[" .. (b.name or ("item " .. b.id)) .. "]|r"
  end
  if info.steps > 0 then return "chain +" .. info.steps .. ", XP only" end
  return "XP only"
end

local function itemText(f)
  local hex = D.QUALITY_HEX[f.quality or 1] or "ffffff"
  return "|cff" .. hex .. "[" .. (f.name or ("item " .. f.id)) .. "]|r"
end
D.itemText = itemText

-- What handing a quest in gives: "[Item]" (best of its own rewards, "or 2
-- more" when it is a choice), then where the chain goes if it leads to
-- better gear. "no item" when it gives only XP. Nil when nothing is known.
function D.rewardTag(info)
  if not info then return nil end
  local text = info.own and (itemText(info.own) .. (info.count > 1 and (" +" .. (info.count - 1)) or "")) or "no item"
  local b = info.best
  if b and not info.here and b.gear and (b.quality or 2) >= 2 then
    text = text .. ", chain -> " .. itemText(b)
  end
  return text
end
