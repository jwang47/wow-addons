-- BuffCheck logic: which buffs your group can give, who has them, and who to
-- buff next. No frames here, so the offline tests can load this file alone.
--
-- Values that the Forever client hides from addons ("secret" values) count
-- as unknown: a hidden aura is never shown as missing.
local addonName, ns = ...
local M = {}
ns.logic = M

M.LOW = 180       -- a buff with less than this many seconds left shows yellow
M.REFRESH = 60    -- the Next button also renews a buff of yours under this
M.OWED_SECS = 180 -- a stranger who buffed you stays on the list this long
M.PRESS_SECS = 6  -- after a press, wait this long for the aura to show

-- The buffs a class gives to others. A column shows only when a member of
-- that class is in your group (you included). `names` are every aura that
-- counts (the group versions too); `cast` is the spell BuffCheck casts when
-- the giver is you. `mana` = only mana users need it.
M.BUFFS = {
  { key = "int", label = "Int", class = "MAGE", cast = "Arcane Intellect",
    names = { "Arcane Intellect", "Arcane Brilliance" }, mana = true },
  { key = "fort", label = "Fort", class = "PRIEST", cast = "Power Word: Fortitude",
    names = { "Power Word: Fortitude", "Prayer of Fortitude" } },
  { key = "wild", label = "Wild", class = "DRUID", cast = "Mark of the Wild",
    names = { "Mark of the Wild", "Gift of the Wild" } },
  { key = "bless", label = "Bless", class = "PALADIN", pattern = "Blessing of " },
}

-- Your own buffs that only go on you, best first. The one you cast last
-- wins (a mage may prefer Mage Armor).
M.SELF = {
  MAGE = { "Ice Armor", "Frost Armor", "Mage Armor", "Molten Armor" },
  PRIEST = { "Inner Fire" },
  WARLOCK = { "Demon Armor", "Demon Skin" },
}

-- Stat scrolls in your bags. `buff` is the aura a scroll gives; `covers`
-- are class buffs that do not stack with it (the scroll is then wasted).
-- `classes` limits a scroll to the classes that use the stat.
local MELEE = { WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true, DRUID = true, HUNTER = true }
M.SCROLLS = {
  { stat = "Intellect", buff = "Intellect", covers = { "Arcane Intellect", "Arcane Brilliance" }, mana = true },
  { stat = "Stamina", buff = "Stamina", covers = { "Power Word: Fortitude", "Prayer of Fortitude" } },
  { stat = "Spirit", buff = "Spirit", covers = { "Divine Spirit", "Prayer of Spirit" }, mana = true },
  { stat = "Protection", buff = "Armor" },
  { stat = "Strength", buff = "Strength", classes = { WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true, DRUID = true } },
  { stat = "Agility", buff = "Agility", classes = MELEE },
}
local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6, VII = 7, VIII = 8 }

-- The scroll def and rank for an item name ("Scroll of Stamina III"), or nil.
function M.scrollOf(name)
  if type(name) ~= "string" then return nil end
  local stat, rest = name:match("^Scroll of (%a+)(.*)$")
  if not stat then return nil end
  for _, def in ipairs(M.SCROLLS) do
    if def.stat == stat then
      local roman = rest:match("^ (%u+)$")
      if rest ~= "" and not (roman and ROMAN[roman]) then return nil end
      return def, roman and ROMAN[roman] or 1
    end
  end
  return nil
end

-- The best scroll of each stat in `items` (a list of item names), for a
-- member of `class`: stat -> { def, name, rank }.
function M.bagScrolls(items, class)
  local best = {}
  for _, name in ipairs(items or {}) do
    local def, rank = M.scrollOf(name)
    if def and not (def.mana and M.NO_MANA[class]) and not (def.classes and not def.classes[class]) then
      local b = best[def.stat]
      if not b or rank > b.rank then best[def.stat] = { def = def, name = name, rank = rank } end
    end
  end
  return best
end

-- The scrolls worth reading now: in your bags, and neither their buff nor
-- a class buff that covers it is on you. `canGive` is the key of your own
-- class buff ("int" for a mage: you cast Arcane Intellect, not a scroll).
-- Returns the list (sorted by stat), or nil when the auras are hidden.
function M.scrollsDue(best, auras, canGive)
  if not auras then return nil end
  local due, unknown = {}, false
  for _, def in ipairs(M.SCROLLS) do
    local b = best[def.stat]
    local mineCovers = canGive == "int" and def.stat == "Intellect" or canGive == "fort" and def.stat == "Stamina"
    if b and not mineCovers then
      local on = auras[def.buff] ~= nil
      for _, n in ipairs(def.covers or {}) do if auras[n] then on = true end end
      if not on then
        if auras.partial then unknown = true else due[#due + 1] = b end
      end
    end
  end
  if unknown and #due == 0 then return nil end
  return due
end

-- Classes with no mana in Classic.
M.NO_MANA = { WARRIOR = true, ROGUE = true }

-- Auras from others that are not a favour to return: shouts and paladin
-- auras reach you without anybody choosing you.
M.NOT_A_FAVOUR = {
  ["Battle Shout"] = true, ["Commanding Shout"] = true,
  ["Devotion Aura"] = true, ["Retribution Aura"] = true,
  ["Concentration Aura"] = true, ["Fire Resistance Aura"] = true,
  ["Frost Resistance Aura"] = true, ["Shadow Resistance Aura"] = true,
  ["Sanctity Aura"] = true, ["Trueshot Aura"] = true,
  ["Aspect of the Pack"] = true, ["Aspect of the Wild"] = true,
}

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h end
end
M.call = call

-- A value the client hides is nil here.
local function plain(v)
  local secret = rawget(_G, "issecretvalue")
  if secret and secret(v) then return nil end
  return v
end
M.plain = plain

-- UnitName's two returns as one name. On Forever the second is the
-- surname ("Ded", "Rats"), so the full name is "Ded Rats", which /target
-- finds. Elsewhere it is a realm, or nil.
function M.joinName(first, second)
  first, second = plain(first), plain(second)
  if type(first) ~= "string" or first == "" then return nil end
  if type(second) == "string" and second ~= "" then return first .. " " .. second end
  return first
end

-- The buff columns for a group whose classes are `present` (a set).
function M.columns(present)
  local out = {}
  for _, def in ipairs(M.BUFFS) do
    if present[def.class] then out[#out + 1] = def end
  end
  return out
end

-- Whether `def` matters for a member of `class`.
function M.applies(def, class)
  if def.mana and M.NO_MANA[class] then return false end
  return true
end

-- The aura in `auras` (name -> { expires, duration }) that counts for
-- `def`, or nil.
function M.find(auras, def)
  if not auras then return nil end
  if def.names then
    for _, n in ipairs(def.names) do
      if auras[n] then return auras[n], n end
    end
  elseif def.pattern then
    for n, a in pairs(auras) do
      if n:find(def.pattern, 1, true) then return a, n end
    end
  end
  return nil
end

-- The state of one cell: "on", "low" (ends soon), "off" (missing) or "unknown"
-- (the client hid something, or the member is too far to read), and the
-- seconds left (nil for a buff with no timer).
function M.state(auras, def, now)
  if not auras then return "unknown" end
  local a = M.find(auras, def)
  if not a then return auras.partial and "unknown" or "off" end
  local exp = a.expires or 0
  if exp <= 0 then return "on" end
  local left = exp - now
  if left < M.LOW then return "low", left end
  return "on", left
end

-- "2m" or "45s" for a cell.
function M.short(left)
  if not left then return "" end
  if left >= 60 then return math.floor(left / 60 + 0.5) .. "m" end
  return math.max(0, math.floor(left)) .. "s"
end

-- Which of your self buffs to cast: the one you cast last if you still
-- know it, else the first you know. `known(name)` says if you know it.
function M.selfBuff(class, last, known)
  local list = M.SELF[class]
  if not list then return nil end
  if last then
    for _, n in ipairs(list) do
      if n == last and known(n) then return n end
    end
  end
  for _, n in ipairs(list) do
    if known(n) then return n end
  end
  return nil
end

-- Whether any of your self buffs is on you.
function M.hasSelfBuff(class, auras)
  local list = M.SELF[class]
  if not list or not auras then return nil end
  for _, n in ipairs(list) do
    if auras[n] then return true end
  end
  if auras.partial then return nil end
  return false
end

-- The macro for one cast. `who` is a unit token for you and your group
-- (no target change), or a full name for anybody else: target them, cast,
-- and give your target back (or clear it when you had none).
function M.macro(spell, unit, name, hadTarget, item)
  if item then
    if item:find("[\n;%[%]]") then return "" end
    return "/use " .. item
  end
  if not spell then return "" end
  if unit then return "/cast [@" .. unit .. "] " .. spell end
  if not name or name:find("[\n;%[%]]") then return "" end
  return "/target " .. name .. "\n/cast " .. spell .. "\n" ..
    (hadTarget and "/targetlasttarget" or "/cleartarget")
end

-- Who to buff next. `c` holds what the caller read:
--   rows: { unit, name, class, auras, ok } for you and your group (ok =
--         connected, alive and seen), you first
--   mine: your buff def (or nil), selfSpell: your self buff to cast (or nil)
--   owed: list of { name, at, class?, auras? } (newest first; never a unit:
--         /cast [@nameplateN] does not work, so strangers are targeted by name)
--   scrolls: M.scrollsDue's list (scrolls to read)
--   nearby: list of { name, unit, class, auras }
--   skip: key -> until, now
-- Returns { key, spell or item, unit?, name, reason } or nil.
function M.nextBuff(c)
  local now, skip = c.now or 0, c.skip or {}
  local function free(key) return not skip[key] or skip[key] <= now end
  local mine = c.mine

  -- 1. Someone outside your group buffed you: return the favour.
  if mine then
    for _, o in ipairs(c.owed or {}) do
      local key = "owed:" .. o.name
      local st = o.auras and M.state(o.auras, mine, now)
      if free(key) and now - (o.at or 0) < M.OWED_SECS and st ~= "on" and st ~= "low"
          and (not o.class or M.applies(mine, o.class)) then
        return { key = key, spell = mine.cast, name = o.name, reason = "returns a favour" }
      end
    end
  end

  -- 2. Your group, you included: missing first, then ending soon.
  if mine then
    for pass = 1, 2 do
      for _, r in ipairs(c.rows or {}) do
        local key = "row:" .. (r.name or r.unit)
        if r.ok and free(key) and M.applies(mine, r.class) then
          local st, left = M.state(r.auras, mine, now)
          if (pass == 1 and st == "off") or (pass == 2 and st == "low" and left and left < M.REFRESH) then
            return { key = key, spell = mine.cast, unit = r.unit, name = r.name,
                     reason = r.unit == "player" and "you" or "group" }
          end
        end
      end
    end
  end

  -- 3. Your own armor.
  local you = c.rows and c.rows[1]
  if c.selfSpell and you and free("self") and M.hasSelfBuff(c.class, you.auras) == false then
    return { key = "self", spell = c.selfSpell, unit = "player", name = you.name, reason = "you" }
  end

  -- 4. A scroll in your bags whose buff is not on you.
  for _, sc in ipairs(c.scrolls or {}) do
    local key = "scroll:" .. sc.def.stat
    if free(key) then
      return { key = key, item = sc.name, unit = "player", name = you and you.name, reason = "scroll" }
    end
  end

  -- 5. Players near you without your buff.
  if mine then
    for _, n in ipairs(c.nearby or {}) do
      local key = "near:" .. n.name
      if free(key) and M.applies(mine, n.class) and M.state(n.auras, mine, now) == "off" then
        return { key = key, spell = mine.cast, name = n.name, reason = "nearby" }
      end
    end
  end
  return nil
end
