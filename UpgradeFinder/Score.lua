-- UpgradeFinder scoring: stats from tooltip text, stat weights per class,
-- slots, and the ranking. No frames here, so tests/upgradefinder.lua tests it
-- offline.
local _, ns = ...
local S = {}
ns.score = S

-- Tooltip line patterns, first match wins per line. Values are summed.
-- Forever wording for spell power is from MageMentor (Core.lua PATTERNS).
S.PATTERNS = {
  { "str", "^%+(%d+) Strength" }, { "agi", "^%+(%d+) Agility" }, { "sta", "^%+(%d+) Stamina" },
  { "int", "^%+(%d+) Intellect" }, { "spi", "^%+(%d+) Spirit" },
  { "dps", "^%(([%d%.]+) damage per second%)" },
  { "armor", "^(%d+) Armor" },
  { "block", "^(%d+) Block" },
  -- Spell damage against one creature type ("Increases damage done to Undead
  -- by magical spells and effects by up to 12."): its own stat, worth little
  -- outside some zones and dungeons. Before "sp", which also matches it.
  { "slay", "damage done to [%a%s]+ by magical spells and effects by up to (%d+)" },
  -- One school only: its own stat, weighted per class (0 = not your school).
  { "frost", "by Frost spells and effects by up to (%d+)" },
  { "fire", "by Fire spells and effects by up to (%d+)" },
  { "arcane", "by Arcane spells and effects by up to (%d+)" },
  { "shadow", "by Shadow spells and effects by up to (%d+)" },
  { "nature", "by Nature spells and effects by up to (%d+)" },
  { "holy", "by Holy spells and effects by up to (%d+)" },
  { "heal", "healing done by up to (%d+) and damage done by up to %d+" },
  { "sp", "damage done by up to (%d+) for all magical spells" },
  { "heal", "[Ii]ncreases healing done by spells and effects by up to (%d+)" },
  { "sp", "spells and effects by up to (%d+)" },
  { "spcrit", "critical strike with spells by (%d+)%%" },
  { "sphit", "chance to hit with spells by (%d+)%%" },
  { "crit", "critical strike by (%d+)%%" },
  { "hit", "chance to hit by (%d+)%%" },
  { "ap", "%+(%d+) [Aa]ttack [Pp]ower" },
  { "ap", "[Aa]ttack [Pp]ower by (%d+)" },
  { "def", "[Dd]efense by (%d+)" },
  { "def", "^%+(%d+) Defense" },
  { "mp5", "[Rr]estores (%d+) [Mm]ana per 5 sec" },
  { "mp5", "%+(%d+) Mana Regeneration per 5 sec" },
  { "mp5", "^%+(%d+) [Mm]ana every 5 sec" },
  -- Flat health and mana (enchants, some green items): worth a tenth of
  -- Stamina and a twentieth of Intellect unless a weight says otherwise.
  { "hp", "^%+(%d+) Health$" }, { "mana", "^%+(%d+) Mana$" },
}

-- Set bonuses ("(3) Set: +10 Intellect.", "Set: ...") need other pieces:
-- they are not the item's own stats.
function S.isSetLine(line)
  return line:match("^%(%d+%) Set:") ~= nil or line:match("^Set:") ~= nil
end

function S.withoutSets(lines)
  local out = {}
  for _, line in ipairs(lines) do if not S.isSetLine(line) then table.insert(out, line) end end
  return out
end

function S.parse(lines)
  local s = {}
  lines = S.withoutSets(lines)
  for _, line in ipairs(lines) do
    for _, p in ipairs(S.PATTERNS) do
      local n = line:match(p[2])
      if n then s[p[1]] = (s[p[1]] or 0) + tonumber(n) break end
    end
  end
  -- A healing line in the Forever combined wording also carries damage.
  for _, line in ipairs(lines) do
    local h, d = line:match("healing done by up to (%d+) and damage done by up to (%d+)")
    if h then s.sp = (s.sp or 0) + tonumber(d) end
  end
  return s
end

-- Simple leveling weights per class (1 point of the main stat = 1). They are
-- a starting point, not theorycraft: /uf weight STAT N changes them.
S.WEIGHTS = {
  WARRIOR = { str = 1, agi = 0.6, sta = 0.4, ap = 0.5, crit = 14, hit = 14, dps = 5, armor = 0.01, def = 0.3, block = 0.05 },
  ROGUE = { agi = 1, str = 0.5, sta = 0.3, ap = 0.5, crit = 14, hit = 14, dps = 5, armor = 0.005 },
  HUNTER = { agi = 1, int = 0.3, sta = 0.3, spi = 0.1, ap = 0.4, crit = 14, hit = 14, dps = 4, armor = 0.005 },
  PALADIN = { str = 1, int = 0.5, sta = 0.4, agi = 0.4, spi = 0.2, ap = 0.5, sp = 0.4, holy = 0.3, heal = 0.3, crit = 12, hit = 10,
    dps = 5, armor = 0.01, mp5 = 1 },
  SHAMAN = { str = 0.8, agi = 0.5, int = 0.8, sta = 0.4, spi = 0.3, ap = 0.4, sp = 0.8, nature = 0.8, fire = 0.6, frost = 0.4, heal = 0.4, crit = 10, hit = 8,
    spcrit = 8, dps = 4, armor = 0.005, mp5 = 1.5 },
  DRUID = { str = 0.7, agi = 0.7, int = 0.7, sta = 0.4, spi = 0.4, ap = 0.4, sp = 0.7, nature = 0.7, arcane = 0.6, heal = 0.4, crit = 10, spcrit = 8,
    armor = 0.005, mp5 = 1.5 },
  PRIEST = { int = 0.7, spi = 0.6, sta = 0.4, sp = 1, shadow = 0.8, holy = 0.4, heal = 0.6, spcrit = 8, sphit = 8, mp5 = 1.5 },
  MAGE = { int = 0.5, spi = 0.4, sta = 0.3, sp = 1, frost = 1, fire = 1, arcane = 1, spcrit = 8, sphit = 8, mp5 = 1 },
  WARLOCK = { int = 0.4, spi = 0.4, sta = 0.6, sp = 1, shadow = 1, fire = 0.7, spcrit = 6, sphit = 8, mp5 = 1 },
}
S.DEFAULT_CLASS = "WARRIOR"

-- Talent trees (by tab order) that need other weights than the class row
-- above. The tree with the most points picks the weights.
local TANK = { sta = 1, def = 1.5, armor = 0.02, block = 0.3, str = 0.6, agi = 0.6, hit = 8, dps = 3 }
local HEAL = { int = 0.9, spi = 0.5, sta = 0.3, heal = 1, sp = 0.3, spcrit = 8, mp5 = 2 }
S.SPECS = {
  WARRIOR = { [3] = { "Protection", TANK } },
  PALADIN = { [1] = { "Holy", HEAL },
    [2] = { "Protection", { sta = 1, def = 1.5, armor = 0.02, block = 0.3, str = 0.6, agi = 0.4, int = 0.3, sp = 0.5,
      dps = 2 } } },
  PRIEST = { [1] = { "Discipline", HEAL }, [2] = { "Holy", HEAL },
    [3] = { "Shadow", { int = 0.5, spi = 0.5, sta = 0.5, sp = 1, shadow = 1, sphit = 10, spcrit = 6, mp5 = 1 } } },
  SHAMAN = { [1] = { "Elemental", { int = 0.6, spi = 0.3, sta = 0.3, sp = 1, nature = 1, fire = 0.8, frost = 0.5, spcrit = 10, sphit = 10, mp5 = 1.5 } },
    [2] = { "Enhancement", { str = 1, agi = 0.7, int = 0.3, sta = 0.4, ap = 0.5, crit = 14, hit = 14, dps = 6,
      armor = 0.005 } },
    [3] = { "Restoration", HEAL } },
  DRUID = { [1] = { "Balance", { int = 0.6, spi = 0.4, sta = 0.3, sp = 1, nature = 1, arcane = 0.9, spcrit = 10, sphit = 10, mp5 = 1 } },
    [2] = { "Feral", { agi = 1, str = 1, sta = 0.6, ap = 0.5, crit = 14, hit = 14, armor = 0.02, def = 0.5 } },
    [3] = { "Restoration", HEAL } },
}

-- Every stat a weight can name: the stats in the tables above.
S.STATS = {}
for _, t in pairs(S.WEIGHTS) do for k in pairs(t) do S.STATS[k] = true end end
for _, specs in pairs(S.SPECS) do for _, s in pairs(specs) do for k in pairs(s[2]) do S.STATS[k] = true end end end

-- Spec name for a class and talent tab, or nil (class weights).
function S.specName(class, tab)
  local s = S.SPECS[class] and S.SPECS[class][tab or 0]
  return s and s[1]
end

function S.weightsFor(class, custom, tab)
  local w = {}
  local spec = S.SPECS[class] and S.SPECS[class][tab or 0]
  for k, v in pairs(spec and spec[2] or S.WEIGHTS[class] or S.WEIGHTS[S.DEFAULT_CLASS]) do w[k] = v end
  for k, v in pairs(custom or {}) do w[k] = v end
  if w.hp == nil then w.hp = (w.sta or 0) / 10 end
  if w.mana == nil then w.mana = (w.int or 0) / 20 end
  return w
end

function S.value(stats, w)
  local total = 0
  for k, v in pairs(stats) do total = total + v * (w[k] or 0) end
  return total
end

-- Equip location -> inventory slots it can go in.
S.SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_2HWEAPON = { 16, 17, both = true }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_WAND = { 18 },
  INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
-- Slot groups for the filter buttons.
S.GROUPS = {
  { "All" },
  { "Head", INVTYPE_HEAD = true }, { "Neck", INVTYPE_NECK = true }, { "Shoulder", INVTYPE_SHOULDER = true },
  { "Back", INVTYPE_CLOAK = true }, { "Chest", INVTYPE_CHEST = true, INVTYPE_ROBE = true },
  { "Wrist", INVTYPE_WRIST = true }, { "Hands", INVTYPE_HAND = true }, { "Waist", INVTYPE_WAIST = true },
  { "Legs", INVTYPE_LEGS = true }, { "Feet", INVTYPE_FEET = true }, { "Ring", INVTYPE_FINGER = true },
  { "Trinket", INVTYPE_TRINKET = true },
  { "Weapon", INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_2HWEAPON = true },
  { "Off hand", INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true },
  { "Ranged", INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_WAND = true, INVTYPE_THROWN = true,
    INVTYPE_RELIC = true },
}

-- The slot group name for an equip location ("Ring" for INVTYPE_FINGER), or nil.
function S.groupName(loc)
  for i = 2, #S.GROUPS do
    if S.GROUPS[i][loc] then return S.GROUPS[i][1] end
  end
end

-- What an item with this equip location replaces, given the value of each
-- equipped slot (slotValue[slot], nil = empty) and whether the main hand
-- holds a two-hander. Returns the value replaced and a note.
local ONE_HAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OFF_HAND = { INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true }
function S.replaced(loc, slotValue, twoHander, dualWield)
  local slots, note = S.replacedSlots(loc, slotValue, twoHander, dualWield)
  if not slots then return nil end
  local v = 0
  for _, slot in ipairs(slots) do v = v + (slotValue[slot] or 0) end
  return v, note
end

-- The worn slots the item takes the place of (the weaker ring or trinket,
-- both hands for a two-hander), and a note; nil for a non-slot.
function S.replacedSlots(loc, slotValue, twoHander, dualWield)
  local slots = S.SLOTS[loc]
  if not slots then return nil end
  if slots.both then return { 16, 17 } end
  if (ONE_HAND[loc] or OFF_HAND[loc]) and twoHander then
    return { 16 }, "replaces your two-hander"
  end
  if loc == "INVTYPE_WEAPON" and not dualWield then return { 16 } end
  local worst, at
  for _, slot in ipairs(slots) do
    local v = slotValue[slot] or 0
    if not worst or v < worst then worst, at = v, slot end
  end
  return { at }
end

-- Filters and sorts candidate rows. A row is { id, name, loc, gain, price,
-- reqLevel, unusable, source }. opts: group (S.GROUPS entry), level,
-- from (only this source: "AH", "dungeon" or "bags"),
-- ahead (levels above yours still shown), money, affordable, sort ("gain" or
-- "pergold"), minGain.
function S.rank(rows, opts)
  local out = {}
  local level, ahead = opts.level or 1, opts.ahead or 0
  for _, r in ipairs(rows) do
    local ok = r.gain and r.gain > (opts.minGain or 0.05) and not r.unusable
      and (r.reqLevel or 0) <= level + ahead
      and (not opts.group or opts.group[1] == "All" or opts.group[r.loc])
      and (not opts.affordable or r.source ~= "AH" or (r.price ~= nil and r.price <= (opts.money or 0)))
      and (not opts.from or r.source == opts.from)
    if ok then
      r.perGold = (r.price and r.price > 0) and r.gain / (r.price / 10000) or nil
      table.insert(out, r)
    end
  end
  local byGold = opts.sort == "pergold"
  table.sort(out, function(a, b)
    local an, bn = (a.reqLevel or 0) <= level, (b.reqLevel or 0) <= level
    if an ~= bn then return an end
    if byGold then
      -- Owned items cost nothing, dungeon drops no gold (after the owned
      -- ones); an AH item with no price goes last.
      local function free(r) return r.source == "AH" and 0 or r.source == "dungeon" and 1e9 or math.huge end
      local ag = a.perGold or free(a)
      local bg = b.perGold or free(b)
      if ag ~= bg then return ag > bg end
    end
    if a.gain ~= b.gain then return a.gain > b.gain end
    if (a.price or 0) ~= (b.price or 0) then return (a.price or 0) < (b.price or 0) end
    return a.id < b.id
  end)
  return out
end
