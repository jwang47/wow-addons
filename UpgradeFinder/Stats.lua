-- UpgradeFinder: what an upgrade changes, in the style of Path of Building.
-- The row tooltip shows the stat changes against what it replaces, then
-- offense (spell damage, crit, attack power, an estimated DPS change) and
-- defense (health, armor, mana). The derived numbers use simple Classic
-- rules and your current totals from the game; they are estimates.
local _, ns = ...
local St = {}
ns.stats = St
local call, api = ns.call, ns.api

St.NAMES = {
  str = "Str", agi = "Agi", sta = "Sta", int = "Int", spi = "Spi", ap = "AP", sp = "Spell dmg", heal = "Healing",
  frost = "Frost dmg", fire = "Fire dmg", arcane = "Arcane dmg", shadow = "Shadow dmg", nature = "Nature dmg",
  holy = "Holy dmg", crit = "Crit", hit = "Hit", spcrit = "Spell crit", sphit = "Spell hit", mp5 = "Mp5",
  armor = "Armor", def = "Defense", block = "Block", dps = "Weapon DPS",
}
St.ORDER = { "str", "agi", "sta", "int", "spi", "ap", "sp", "heal", "frost", "fire", "arcane", "shadow", "nature",
  "holy", "crit", "hit", "spcrit", "sphit", "mp5", "dps", "armor", "def", "block" }
St.PCT = { crit = true, hit = true, spcrit = true, sphit = true }
local SCHOOLS = { "frost", "fire", "arcane", "shadow", "nature", "holy" }
-- Spell school index for GetSpellBonusDamage / GetSpellCritChance.
local SCHOOL_INDEX = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }

-- Stat points for 1% crit at level 60; lower levels need fewer (scaled by
-- level). Intellect for spell crit, Agility for melee and ranged crit.
St.INT_PER_CRIT = { MAGE = 59.5, PRIEST = 59.2, WARLOCK = 60.6, DRUID = 60, SHAMAN = 59.5, PALADIN = 54 }
St.AGI_PER_CRIT = { ROGUE = 29, HUNTER = 53, WARRIOR = 20, PALADIN = 20, SHAMAN = 20, DRUID = 20 }

-- new minus the sum of olds (a two-hander replaces both hands).
function St.diff(new, olds)
  local d = {}
  for k, v in pairs(new or {}) do d[k] = (d[k] or 0) + v end
  for _, old in ipairs(olds or {}) do
    for k, v in pairs(old) do d[k] = (d[k] or 0) - v end
  end
  for k, v in pairs(d) do if math.abs(v) < 0.001 then d[k] = nil end end
  return d
end

-- caster, healer, tank, ranged or melee, from the weights in use.
function St.role(class, w)
  w = w or {}
  if (w.def or 0) >= 1 then return "tank" end
  if (w.heal or 0) >= 1 then return "healer" end
  if class == "HUNTER" then return "ranged" end
  if (w.sp or 0) >= 0.8 and (w.sp or 0) >= (w.str or 0) and (w.sp or 0) >= (w.agi or 0) then return "caster" end
  return "melee"
end

-- The school that counts most for you (by weight), or nil.
function St.school(w)
  local best, bw
  for _, s in ipairs(SCHOOLS) do
    if (w[s] or 0) > (bw or 0) then best, bw = s, w[s] end
  end
  return best
end

-- Melee weapon equip locations (a hunter's ranged slot is separate).
local MELEE = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_2HWEAPON = true,
  INVTYPE_WEAPONOFFHAND = true }
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

local function per(level, at60)
  return at60 * math.max(10, level or 60) / 60
end

-- Attack power from strength and agility (melee; ranged for a hunter).
function St.apFrom(class, d, ranged)
  local str, agi = d.str or 0, d.agi or 0
  if ranged then return agi * 2 end
  if class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN" or class == "DRUID" then return str * 2 end
  if class == "ROGUE" or class == "HUNTER" then return str + agi end
  return str
end

-- Armor reduction (0..0.75) against a mob of your level.
function St.reduction(armor, level)
  armor = math.max(0, armor or 0)
  local r = armor / (armor + 400 + 85 * (level or 60))
  return math.min(0.75, r)
end

-- Your current totals, read from the game when it can tell (each guarded:
-- the Forever client lacks some calls). Missing ones are estimated.
function St.context(class, w)
  local ctx = { class = class, level = call(rawget(_G, "UnitLevel"), "player") or 60 }
  local school = St.school(w or {})
  local idx = SCHOOL_INDEX[school or "frost"] or 2
  ctx.sp = call(rawget(_G, "GetSpellBonusDamage"), idx)
  ctx.heal = call(rawget(_G, "GetSpellBonusHealing"))
  ctx.spcrit = call(rawget(_G, "GetSpellCritChance"), idx)
  ctx.crit = call(rawget(_G, "GetCritChance"))
  ctx.rangedCrit = call(rawget(_G, "GetRangedCritChance"))
  local base, pos, neg = call(rawget(_G, "UnitAttackPower"), "player")
  ctx.ap = base and (base + (pos or 0) + (neg or 0)) or nil
  base, pos, neg = call(rawget(_G, "UnitRangedAttackPower"), "player")
  ctx.rap = base and (base + (pos or 0) + (neg or 0)) or nil
  local _, effective = call(rawget(_G, "UnitArmor"), "player")
  ctx.armor = effective
  ctx.health = call(rawget(_G, "UnitHealthMax"), "player")
  -- Measured Forever ratios (Calib.lua), where there is enough data.
  local calib = ns.calib and ns.calib.ratios(ctx.level, class) or {}
  for _, k in ipairs({ "intPerCrit", "agiPerCrit", "hpPerSta", "manaPerInt" }) do
    if calib[k] then ctx[k] = calib[k][1] end
  end
  if ns.calib then ctx.dpsFn = ns.calib.dpsChange end
  return ctx
end

-- "+12", "-3", "+1.5" (a fraction below 10), "+0.4%" for a percent.
local function fmt(n, pct)
  if pct then return string.format("%+.1f%%", n) end
  local r = n >= 0 and math.floor(n + 0.5) or -math.floor(-n + 0.5)
  if math.abs(n) >= 10 or math.abs(n - r) < 0.05 then return string.format("%+d", r) end
  return string.format("%+.1f", n)
end
St.fmt = fmt

-- Colored "+11 Int" pieces for the stat changes, in a fixed order.
function St.statLine(d)
  local parts = {}
  for _, k in ipairs(St.ORDER) do
    local v = d[k]
    if v then
      local text = fmt(v, St.PCT[k]) .. " " .. St.NAMES[k]
      table.insert(parts, (v > 0 and "|cff40ff40" or "|cffff6060") .. text .. "|r")
    end
  end
  return table.concat(parts, "  ")
end

-- The offense and defense entries for a stat change d. Each entry is
-- { label, value, good }; the estimated DPS change is d.est (a fraction).
-- ctx: St.context() or a test table; loc: the item's equip location.
function St.derive(d, ctx, w, loc)
  local class, level = ctx.class, ctx.level or 60
  local role = St.role(class, w)
  local off, def = {}, {}
  local function add(list, label, v, pct)
    if v and math.abs(v) >= (pct and 0.05 or 0.5) then table.insert(list, { label, fmt(v, pct), v > 0 }) end
  end
  local est
  -- Measured ratios (ctx, from Calib.lua) win over the Classic guesses.
  local intPer = ctx.intPerCrit or (St.INT_PER_CRIT[class] and per(level, St.INT_PER_CRIT[class]))
  local agiPer = ctx.agiPerCrit or (St.AGI_PER_CRIT[class] and per(level, St.AGI_PER_CRIT[class]))
  local intCrit = intPer and (d.int or 0) / intPer or 0
  local agiCrit = agiPer and (d.agi or 0) / agiPer or 0

  if role == "caster" or role == "healer" then
    local heal = role == "healer"
    local school = St.school(w or {})
    local power = heal and ((d.heal or 0) + (d.sp or 0)) or ((d.sp or 0) + (school and d[school] or 0))
    local crit = (d.spcrit or 0) + intCrit
    add(off, heal and "Healing" or "Spell damage", power)
    add(off, "Spell crit", crit, true)
    add(off, "Spell hit", d.sphit, true)
    -- One cast: base (B, by level) + 0.8 x power, crits for +50%.
    local B, now = 4 * level + 20, heal and (ctx.heal or 0) or (ctx.sp or 0)
    local c0 = (ctx.spcrit or 5) / 100
    local h0 = heal and 1 or 0.96
    local before = (B + 0.8 * now) * (1 + 0.5 * c0) * h0
    local after = (B + 0.8 * (now + power)) * (1 + 0.5 * (c0 + crit / 100))
      * (heal and 1 or math.min(0.99, h0 + (d.sphit or 0) / 100))
    est = after / before - 1
    -- Your own spells (Calib.lua), once enough hits are logged.
    local measured = not heal and ctx.dpsFn and ctx.dpsFn(power, crit / 100, ctx.sp)
    if measured then est = (1 + measured) * math.min(0.99, h0 + (d.sphit or 0) / 100) / h0 - 1 end
  else
    local ranged = role == "ranged"
    local apNow = ranged and ctx.rap or ctx.ap or (60 + level * 3)
    local ap = (d.ap or 0) + St.apFrom(class, d, ranged)
    local crit = (d.crit or 0) + agiCrit
    local weapon = (ranged and RANGED or MELEE)[loc or ""] or false
    add(off, "Attack power", ap)
    add(off, "Crit", crit, true)
    add(off, "Hit", d.hit, true)
    if weapon then add(off, "Weapon DPS", d.dps) end
    -- Damage per second: (weapon DPS + AP / 14) x crit (+100%) x hit.
    local w0 = ctx.weaponDps or (level * 0.9 + 3)
    local c0 = ((ranged and ctx.rangedCrit or ctx.crit) or 5) / 100
    local before = (w0 + apNow / 14) * (1 + c0) * 0.95
    local after = (w0 + (weapon and d.dps or 0) + (apNow + ap) / 14) * (1 + c0 + crit / 100)
      * math.min(1, 0.95 + (d.hit or 0) / 100)
    est = after / before - 1
  end
  if est and math.abs(est) >= 0.0005 then
    table.insert(off, { (role == "healer" and "Est. healing" or "Est. DPS"), fmt(est * 100, true), est > 0 })
  end

  local hp = (d.sta or 0) * (ctx.hpPerSta or 10)
  add(def, "Health", hp)
  local armor = (d.armor or 0) + (d.agi or 0) * 2
  local armorNow = ctx.armor or level * 20
  if math.abs(armor) >= 0.5 then
    local dr = (St.reduction(armorNow + armor, level) - St.reduction(armorNow, level)) * 100
    table.insert(def, { "Armor", fmt(armor) .. string.format(" (%+.1f%% less damage)", dr), armor > 0 })
  end
  -- Effective health against physical hits: health / (1 - armor reduction).
  local hpNow = ctx.health or (level * 15 + 40)
  local ehp0 = hpNow / (1 - St.reduction(armorNow, level))
  local ehp1 = (hpNow + hp) / (1 - St.reduction(armorNow + armor, level))
  if math.abs(ehp1 - ehp0) >= 0.5 then
    table.insert(def, { "eHP", fmt(ehp1 - ehp0) .. string.format(" (%+.1f%%)", (ehp1 / ehp0 - 1) * 100), ehp1 > ehp0 })
  end
  add(def, "Defense", d.def)
  add(def, "Block", d.block)
  if class ~= "WARRIOR" and class ~= "ROGUE" then add(def, "Mana", (d.int or 0) * (ctx.manaPerInt or 15)) end
  add(def, "Mp5", d.mp5)
  return off, def, role
end

-- "Label +N  Label +N%" with green gains and red losses.
function St.join(list)
  local parts = {}
  for _, e in ipairs(list) do
    table.insert(parts, e[1] .. " " .. (e[3] and "|cff40ff40" or "|cffff6060") .. e[2] .. "|r")
  end
  return table.concat(parts, "  ")
end

-- The stat change, offense and defense for a list row: reads the item and
-- the worn items it replaces through the hidden tooltip (only on hover).
-- Returns nil when a tooltip has not loaded yet.
function St.forRow(r)
  local S, Scan = ns.score, ns.scan
  local lines = Scan.read(function(tt) tt:SetHyperlink("item:" .. r.id) end)
  if not lines then return nil end
  local worn = Scan.worn()
  local slots = S.replacedSlots(r.loc, worn.value or {}, worn.twoHander, worn.dualWield) or {}
  local olds = {}
  local function slotStats(slot)
    if not call(rawget(_G, "GetInventoryItemLink"), "player", slot) then return {} end
    local l = Scan.read(function(tt) tt:SetInventoryItem("player", slot) end)
    return l and S.parse(l) or {}
  end
  for _, slot in ipairs(slots) do table.insert(olds, slotStats(slot)) end
  local class, w = ns.class(), ns.weights()
  local ctx = St.context(class, w)
  ctx.weaponDps = (St.role(class, w) == "ranged" and slotStats(18) or slotStats(16)).dps
  local d = St.diff(S.parse(lines), olds)
  local off, def = St.derive(d, ctx, w, r.loc)
  return d, off, def
end
