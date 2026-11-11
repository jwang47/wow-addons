-- BuffCheck ready check: what you are short of when you leave town.
--
-- When you leave a rest area (an inn or a city) or enter a dungeon, one
-- line says what is missing: reagents for the spells you know, conjured
-- water and food (mages), worn gear, full bags, unspent talent points.
-- Nothing is said when all is well. /buffs ready runs it by hand.
--
-- The reagent table is from Classic. A reagent counts only when you know
-- one of its spells, so a wrong row on Forever stays quiet.
local addonName, ns = ...
local M = ns.logic
local call, plain = M.call, M.plain
local R = {}
ns.ready = R

R.MIN_FREE = 5        -- fewer free bag slots than this is worth a word
R.MIN_DURABILITY = 0.3 -- the most worn item at or under 30%
R.MIN_WATER = 20      -- one stack of conjured water
R.MIN_FOOD = 10
R.REPEAT_SECS = 300   -- the same line is not said twice within this time

-- Reagents by class: the items that count (any of them), how many to
-- carry, and the spells that use them.
R.REAGENTS = {
  MAGE = {
    { name = "Rune of Teleportation", items = { 17031 }, min = 2,
      spells = { "Teleport: Stormwind", "Teleport: Ironforge", "Teleport: Darnassus", "Teleport: Orgrimmar",
        "Teleport: Undercity", "Teleport: Thunder Bluff" } },
    { name = "Rune of Portals", items = { 17032 }, min = 2,
      spells = { "Portal: Stormwind", "Portal: Ironforge", "Portal: Darnassus", "Portal: Orgrimmar",
        "Portal: Undercity", "Portal: Thunder Bluff" } },
    { name = "Arcane Powder", items = { 17020 }, min = 2, spells = { "Arcane Brilliance" } },
    { name = "Light Feather", items = { 17056 }, min = 2, spells = { "Slow Fall" } },
  },
  PRIEST = {
    { name = "Candle", items = { 17028, 17029 }, min = 2, spells = { "Prayer of Fortitude", "Prayer of Spirit" } },
    { name = "Light Feather", items = { 17056 }, min = 2, spells = { "Levitate" } },
  },
  DRUID = {
    { name = "Wild Berries or Thornroot", items = { 17021, 17026 }, min = 2, spells = { "Gift of the Wild" } },
    { name = "Rebirth seed", items = { 17034, 17035, 17036, 17037, 17038 }, min = 1, spells = { "Rebirth" } },
  },
  PALADIN = {
    { name = "Symbol of Kings", items = { 21177 }, min = 5,
      spells = { "Greater Blessing of Might", "Greater Blessing of Wisdom", "Greater Blessing of Kings" } },
    { name = "Symbol of Divinity", items = { 17033 }, min = 1, spells = { "Divine Intervention" } },
  },
  SHAMAN = { { name = "Ankh", items = { 17030 }, min = 1, spells = { "Reincarnation" } } },
  ROGUE = { { name = "Flash Powder", items = { 5140 }, min = 2, spells = { "Vanish" } } },
  WARLOCK = { { name = "Soul Shard", items = { 6265 }, min = 2, spells = { "Summon Voidwalker", "Create Healthstone" } } },
}

-- Conjured water and food by item ID (every rank).
R.WATER = { 5350, 2288, 2136, 3772, 8077, 8078, 8079, 30703, 22018 }
R.FOOD = { 5349, 1113, 1114, 1487, 8075, 8076, 22895, 22019 }

local function sum(counts, ids)
  local n = 0
  for _, id in ipairs(ids) do n = n + (counts[id] or 0) end
  return n
end

local function amount(n, name) return (n == 0 and "no " or (n .. " ")) .. name end

-- The problems, most urgent first, as short texts. s = {
--   class, knows = function(spell) -> bool, counts = { [itemID] = n },
--   durability = 0..1 or nil, free = free bag slots or nil, talents = n }
function R.problems(s)
  local out = {}
  local knows = s.knows or function() return false end
  local counts = s.counts or {}
  for _, r in ipairs(R.REAGENTS[s.class or ""] or {}) do
    local uses = false
    for _, spell in ipairs(r.spells) do
      if knows(spell) then uses = true break end
    end
    if uses then
      local n = sum(counts, r.items)
      if n < r.min then out[#out + 1] = amount(n, r.name) end
    end
  end
  if knows("Conjure Water") then
    local n = sum(counts, R.WATER)
    if n < R.MIN_WATER then out[#out + 1] = amount(n, "conjured water") end
  end
  if knows("Conjure Food") then
    local n = sum(counts, R.FOOD)
    if n < R.MIN_FOOD then out[#out + 1] = amount(n, "conjured food") end
  end
  if s.durability and s.durability <= R.MIN_DURABILITY then
    out[#out + 1] = string.format("gear at %d%% (repair)", math.floor(s.durability * 100 + 0.5))
  end
  if s.free and s.free < R.MIN_FREE then
    out[#out + 1] = s.free == 0 and "bags full" or (s.free .. " free bag slot" .. (s.free == 1 and "" or "s"))
  end
  if s.talents and s.talents > 0 then
    out[#out + 1] = s.talents .. " talent point" .. (s.talents == 1 and "" or "s") .. " to spend"
  end
  return out
end

-- "Before you go: no Rune of Teleportation, gear at 22% (repair)", or nil.
function R.line(s)
  local list = R.problems(s)
  if #list == 0 then return nil end
  return "Before you go: " .. table.concat(list, ", ")
end

---------------------------------------------------------------------------
-- Reading the game
---------------------------------------------------------------------------
local function G(name) return rawget(_G, name) end

local function knows(spell)
  local cs = G("C_Spell")
  if cs and cs.GetSpellInfo then return call(cs.GetSpellInfo, spell) ~= nil end
  return call(G("GetSpellInfo"), spell) ~= nil
end

-- Item counts and free general slots in bags 0-4.
local function bags()
  local counts, free = {}, nil
  local cc = G("C_Container")
  if not (cc and cc.GetContainerNumSlots and cc.GetContainerItemInfo) then return counts, free end
  for bag = 0, 4 do
    for slot = 1, plain(call(cc.GetContainerNumSlots, bag)) or 0 do
      local info = call(cc.GetContainerItemInfo, bag, slot)
      local id = type(plain(info)) == "table" and plain(info.itemID)
      if id then counts[id] = (counts[id] or 0) + (plain(info.stackCount) or 1) end
    end
    local n, family = call(cc.GetContainerNumFreeSlots, bag)
    n, family = plain(n), plain(family)
    if n and (family == nil or family == 0) then free = (free or 0) + n end
  end
  return counts, free
end

-- The most worn equipped item, 0..1, or nil when nothing has durability.
local function durability()
  local get = G("GetInventoryItemDurability")
  local low
  for slot = 1, 18 do
    local cur, max = call(get, slot)
    cur, max = plain(cur), plain(max)
    if cur and max and max > 0 and (not low or cur / max < low) then low = cur / max end
  end
  return low
end

local function talents()
  local n = plain(call(G("UnitCharacterPoints"), "player"))
  return type(n) == "number" and n or nil
end

function R.read()
  local _, class = call(G("UnitClass"), "player")
  local counts, free = bags()
  return { class = plain(class), knows = knows, counts = counts, free = free, durability = durability(),
    talents = talents() }
end

---------------------------------------------------------------------------
-- When to speak
---------------------------------------------------------------------------
local last = { text = nil, at = 0 }

local function now() return plain(call(G("GetTime"))) or 0 end

-- Say the line in chat and in the middle of the screen. force: also say
-- that all is well, and repeat a line said a moment ago.
function R.announce(force)
  local on = not ns.db or ns.db.ready ~= false
  if not on and not force then return nil end
  local text = R.line(R.read())
  if not text then
    if force then ns.say("Ready: nothing missing.") end
    return nil
  end
  local t = now()
  if not force and last.text == text and t - last.at < R.REPEAT_SECS then return nil end
  last.text, last.at = text, t
  ns.say(text)
  local errors = G("UIErrorsFrame")
  if errors and errors.AddMessage then call(errors.AddMessage, errors, text, 1, 0.82, 0) end
  return text
end

function R.slash(arg)
  if arg == "on" or arg == "off" then
    ns.db.ready = arg == "on"
    ns.say("Ready check when you leave town: " .. arg .. ".")
  else
    R.announce(true)
  end
end

local ev = CreateFrame("Frame")
R.ev = ev
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_UPDATE_RESTING")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
local resting
ev:SetScript("OnEvent", function(_, event)
  local ok, err = pcall(function()
    local rest = call(G("IsResting")) and true or false
    if event == "PLAYER_UPDATE_RESTING" then
      -- Left an inn or a city.
      if resting and not rest then R.announce(false) end
    elseif event == "PLAYER_ENTERING_WORLD" then
      local inside, kind = call(G("IsInInstance"))
      if inside and (kind == "party" or kind == "raid") then R.announce(false) end
    end
    resting = rest
  end)
  if not ok and not R.reported then
    R.reported = true
    ns.say("ready check error: " .. tostring(err))
  end
end)
