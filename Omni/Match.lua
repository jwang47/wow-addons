-- Omni matching and ranking. No game calls here, so tests/omni.lua tests it
-- offline. An entry is { kind, key, name, lname, ... } (lname = M.norm(name)).
local _, ns = ...
local M = {}
ns.match = M

M.PER_GROUP = 8
M.RECENT_MAX = 8

-- Group order when two groups have equal best scores, and the titles.
-- Nearby is always first when it has hits.
M.GROUPS = { "command", "near", "log", "spell", "item", "place", "person", "npc", "quest" }
M.TITLES = { command = "Commands", spell = "Spells", item = "Items", place = "Places",
  person = "People", log = "Your quest log", npc = "NPCs (Questie)", near = "Nearby", quest = "Quests (Questie)", recent = "Recent" }
local ORDER = {}
for i, k in ipairs(M.GROUPS) do ORDER[k] = i end

-- "i:silk" searches items only. "@ann" searches people. "q:" also finds
-- quests in your log (their entries have also = "quest").
M.FILTERS = { i = "item", item = "item", s = "spell", spell = "spell", p = "place", z = "place",
  place = "place", w = "person", person = "person", n = "npc", npc = "npc", q = "quest", quest = "quest", l = "log", log = "log",
  c = "command", cmd = "command", near = "near", nb = "near" }

function M.norm(s)
  s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return s
end

-- Splits "i: Silk Cloth" into ("item", "silk cloth").
function M.parse(text)
  local q = M.norm(text)
  local tag, rest = q:match("^(%a+):%s*(.*)$")
  if tag and M.FILTERS[tag] then return M.FILTERS[tag], rest end
  if q:sub(1, 1) == "@" then return "person", M.norm(q:sub(2)) end
  return nil, q
end

local function words(q)
  local list = {}
  for w in q:gmatch("%S+") do table.insert(list, w) end
  return list
end

-- True when `w` starts a word in `s`: at the start, or after a character
-- that is not a letter or digit ("ironforge" in "the ironforge-gate").
local function startsWord(s, w)
  local from = 1
  while true do
    local at = s:find(w, from, true)
    if not at then return false end
    if at == 1 or not s:sub(at - 1, at - 1):match("[%w']") then return true end
    from = at + 1
  end
end

-- 3 = the name starts with the query; 2 = each query word starts a word of
-- the name; 1 = each query word is somewhere in the name; 0 = no match.
function M.score(lname, q, qwords)
  if q == "" then return 0 end
  local at = lname:find(q, 1, true)
  if at == 1 then return 3 end
  qwords = qwords or words(q)
  if #qwords == 1 then
    if not at then return 0 end
    return (lname:byte(at - 1) == 32 or startsWord(lname, q)) and 2 or 1
  end
  local tier = 2
  for _, w in ipairs(qwords) do
    if not lname:find(w, 1, true) then return 0 end
    if tier == 2 and not startsWord(lname, w) then tier = 1 end
  end
  return tier
end

-- Fuzzy matching ------------------------------------------------------------
M.FUZZY_MIN = 3 -- shorter queries match too much

-- The letters of w in order inside x, starting at x's first letter
-- ("rdg" in "redridge").
local function inOrder(w, x)
  if w:byte(1) ~= x:byte(1) then return false end
  local at = 1
  for i = 2, #w do
    at = x:find(w:sub(i, i), at + 1, true)
    if not at then return false end
  end
  return true
end

-- Edit distance of at most one (a wrong, missing, extra or swapped letter).
local function oneEdit(a, b)
  local la, lb = #a, #b
  if math.abs(la - lb) > 1 then return false end
  local i = 1
  while i <= la and i <= lb and a:byte(i) == b:byte(i) do i = i + 1 end
  if i > la and i > lb then return true end
  local ra, rb = a:sub(i + 1), b:sub(i + 1)
  if la == lb then
    return ra == rb or (a:sub(i, i) == b:sub(i + 1, i + 1) and a:sub(i + 1, i + 1) == b:sub(i, i) and a:sub(i + 2) == b:sub(i + 2))
  end
  if la > lb then return ra == b:sub(i) end
  return a:sub(i) == rb
end
M.oneEdit = oneEdit

local function nameWords(e)
  local list = e.lwords
  if not list then
    list = {}
    for w in e.lname:gmatch("[%w']+") do table.insert(list, w) end
    e.lwords = list
  end
  return list
end

-- Each query word fits some word of the name: inside it, its letters in
-- order from the first, or (4+ letters) one typo off the word or the start
-- of a longer word, for a name you are still typing.
-- A cheap filter first (C-speed string.find): each query word's first two
-- letters appear in that order somewhere in the name. Both fuzzy kinds
-- keep them, unless the typo is in the first two letters.
local function esc(c) return c:match("%w") and c or ("%" .. c) end
local heads = {}
local function headPattern(w)
  local p = heads[w]
  if not p then
    p = esc(w:sub(1, 1)) .. (#w > 1 and (".-" .. esc(w:sub(2, 2))) or "")
    heads[w] = p
  end
  return p
end

function M.fuzzy(e, qwords)
  for _, w in ipairs(qwords) do
    if not e.lname:find(headPattern(w)) then return false end
  end
  local names = nameWords(e)
  for _, w in ipairs(qwords) do
    local ok = false
    local first = w:byte(1)
    for _, x in ipairs(names) do
      if x:find(w, 1, true) then ok = true
      elseif x:byte(1) == first and (inOrder(w, x)
        or (#w >= 4 and (oneEdit(w, x) or (#x > #w and oneEdit(w, x:sub(1, #w)))))) then ok = true end
      if ok then break end
    end
    if not ok then return false end
  end
  return true
end

local function better(recent)
  return function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    local ra, rb = recent[a.entry.key] or 0, recent[b.entry.key] or 0
    if ra ~= rb then return ra > rb end
    local oa, ob = a.entry.boost or 0, b.entry.boost or 0
    if oa ~= ob then return oa > ob end
    if #a.entry.lname ~= #b.entry.lname then return #a.entry.lname < #b.entry.lname end
    return a.entry.lname < b.entry.lname
  end
end

-- lists: an array of entry arrays (one per source). recent: key -> time.
-- Returns groups { { kind, title, entries = {...} }, ... }, best first, with
-- at most M.PER_GROUP entries each. The first source to give a key wins.
-- opts (all optional):
--   tick()       called every M.TICK entries; may coroutine.yield to spread
--                the search over frames
--   narrow       the matched list of a shorter query this one extends: the
--                exact pass then looks only at those entries
--   onExact(g)   the exact groups, before a fuzzy pass runs
-- Also returns matched: every exact hit, in source order (for narrow).
M.TICK = 400
M.NEAR_EMPTY = 5 -- nearest NPCs shown above Recent for an empty query

-- The Nearby group with the max nearest entries, or nil.
local function nearest(lists, max)
  local list = {}
  for _, src in ipairs(lists) do
    for _, e in ipairs(src) do if e.kind == "near" then table.insert(list, e) end end
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return (a.boost or 0) > (b.boost or 0) end)
  local g = { kind = "near", title = M.TITLES.near, entries = {}, more = math.max(0, #list - max) }
  for i = 1, math.min(#list, max) do g.entries[i] = list[i] end
  return g
end

function M.search(lists, text, recent, opts)
  recent = recent or {}
  opts = opts or {}
  local only, q = M.parse(text)
  local seen, hits = {}, {}
  if q == "" and only == "near" then
    -- "near:" alone lists everything nearby, nearest first.
    local g = nearest(lists, M.PER_GROUP * 3)
    return g and { g } or {}
  end
  if q == "" then
    if only then return {} end
    -- Nearby first, then what you used last.
    local groups = {}
    local near = nearest(lists, M.NEAR_EMPTY)
    if near then
      table.insert(groups, near)
      for _, e in ipairs(near.entries) do seen[e.key] = true end
    end
    local list = {}
    for _, src in ipairs(lists) do
      for _, e in ipairs(src) do
        if recent[e.key] and not seen[e.key] then
          seen[e.key] = true
          table.insert(list, e)
        end
      end
    end
    table.sort(list, function(a, b) return recent[a.key] > recent[b.key] end)
    while #list > M.RECENT_MAX do table.remove(list) end
    if #list > 0 then table.insert(groups, { kind = "recent", title = M.TITLES.recent, entries = list }) end
    return groups
  end
  -- Keep only the best M.PER_GROUP hits of each kind (insertion into a
  -- short sorted list), so a one-letter query over 40k entries stays fast.
  local qwords = words(q)
  local before = better(recent)
  local cap = M.PER_GROUP
  local total, n, tick, matched = 0, 0, opts.tick, {}
  local function pass(from, scoreOf, record)
    for _, src in ipairs(from) do
      for _, e in ipairs(src) do
        n = n + 1
        if tick and n % M.TICK == 0 then tick() end
        -- record: every exact candidate goes into matched, even one whose
        -- key an earlier source already gave (another name for the same
        -- thing can match a longer query that the first name does not).
        if (not only or e.kind == only or e.also == only) and (record or not seen[e.key]) then
          local s = scoreOf(e)
          if s > 0 and record then matched[#matched + 1] = e end
          if s > 0 and not seen[e.key] then
            seen[e.key], total = true, total + 1
            local h = hits[e.kind]
            if not h then h = { top = {}, n = 0 } hits[e.kind] = h end
            h.n = h.n + 1
            local top, hit = h.top, { entry = e, score = s }
            if #top < cap or before(hit, top[#top]) then
              local i = #top + 1
              while i > 1 and before(hit, top[i - 1]) do top[i] = top[i - 1] i = i - 1 end
              top[i] = hit
              if #top > cap then top[#top] = nil end
            end
          end
        end
      end
    end
  end
  pass(opts.narrow and { opts.narrow } or lists, function(e) return M.score(e.lname, q, qwords) end, true)
  -- Few exact hits: look again with fuzzy matching (initials, skipped
  -- letters, one typo). It ranks below every exact hit.
  local fuzzy = total < cap and #q >= M.FUZZY_MIN
  local function groupsNow()
    local groups = {}
    for kind, h in pairs(hits) do
      local g = { kind = kind, title = M.TITLES[kind] or kind, entries = {}, best = h.top[1].score,
        recent = recent[h.top[1].entry.key] or 0 }
      for _, hit in ipairs(h.top) do table.insert(g.entries, hit.entry) end
      g.more = h.n - #g.entries
      table.insert(groups, g)
    end
    table.sort(groups, function(a, b)
      if (a.kind == "near") ~= (b.kind == "near") then return a.kind == "near" end
      if a.best ~= b.best then return a.best > b.best end
      if a.recent ~= b.recent then return a.recent > b.recent end
      return (ORDER[a.kind] or 99) < (ORDER[b.kind] or 99)
    end)
    return groups
  end
  if fuzzy then
    if opts.onExact then opts.onExact(groupsNow(), matched) end
    pass(lists, function(e) return M.fuzzy(e, qwords) and 0.5 or 0 end, false)
  end
  return groupsNow(), matched
end
