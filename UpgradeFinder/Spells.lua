-- UpgradeFinder: a caster DPS estimate from the spells on your action bars.
-- Each damage spell on a bar gives its damage (from the spell text, or your
-- measured average hit from Calib.lua), cast time, cooldown and mana cost.
-- The rotation: spells with a cooldown whenever ready, and the rest of the
-- time the filler with the most damage per second of casting. Melee classes
-- keep the formula in Stats.lua (white hits do most of their damage).
local _, ns = ...
local SP = {}
ns.spells = SP
local call, api = ns.call, ns.api

SP.GCD = 1.5
SP.SLOTS = 120
SP.CRIT_BONUS = 0.5 -- a spell crit does +50% (more with a talent: /uf critbonus)

-- An area spell, from its text ("the target area", "all enemies within 10
-- yards", "in a cone in front of the caster"). The single-target rotation
-- leaves these out; the AoE score (Spare1.lua) uses only these.
local AREA = { "target area", "selected area", "all enemies", "all targets", "enemies within", "targets within",
  "nearby enemies", "in a cone", "in front of the caster", "enemies in front" }
function SP.isArea(text)
  if type(text) ~= "string" then return false end
  local t = text:lower()
  for _, p in ipairs(AREA) do if t:find(p, 1, true) then return true end end
  return false
end

-- Damage numbers from a spell's text: direct ("causing 79 to 87 Frost
-- damage", "for 30 Fire damage") and over time ("135 Shadow damage over
-- 18 sec"). Returns direct average, dot total, dot seconds.
function SP.parseText(text)
  if type(text) ~= "string" then return nil end
  local dot, dur = text:match("(%d+) %a+ damage over (%d+) sec")
  local lo, hi = text:match("(%d+) to (%d+) %a+ damage")
  local direct
  if lo then direct = (tonumber(lo) + tonumber(hi)) / 2
  else
    local one = text:match("(%d+) %a+ damage")
    if one and not (dot and one == dot) then direct = tonumber(one) end
  end
  if not direct and not dot then return nil end
  return direct, dot and tonumber(dot) or nil, dur and tonumber(dur) or nil
end

local function spellText(id)
  local f = rawget(_G, "GetSpellDescription") or api("C_Spell.GetSpellDescription")
  return call(f, id)
end

local function cost(id)
  local costs = call(rawget(_G, "GetSpellPowerCost"), id) or call(api("C_Spell.GetSpellPowerCost"), id)
  if type(costs) == "table" then
    for _, c in ipairs(costs) do if c.type == 0 or c.name == "MANA" then return c.cost or 0 end end
  end
  return 0
end

-- The damage spells on your bars: { id, name, direct, dot, dur, cast, cd,
-- mana, coef, measured }. Each spell once (the highest rank of a name).
function SP.fromBars()
  local byName, list = {}, {}
  for slot = 1, SP.SLOTS do
    local kind, id = call(rawget(_G, "GetActionInfo"), slot)
    if kind == "spell" and id then
      local name, _, _, castMs = call(rawget(_G, "GetSpellInfo"), id)
      local text = spellText(id)
      local direct, dot, dur = SP.parseText(text)
      if name and (direct or dot) then
        local s = { id = id, name = name, direct = direct or 0, dot = dot or 0, dur = dur or 0,
          cast = math.max(SP.GCD, (castMs or 0) / 1000), castRaw = (castMs or 0) / 1000,
          cd = (call(rawget(_G, "GetSpellBaseCooldown"), id) or 0) / 1000, mana = cost(id),
          area = SP.isArea(text) }
        -- An area spell with no cast time and only damage over time is a
        -- channel (Blizzard): it takes its whole duration, not one GCD.
        if s.area and s.castRaw == 0 and s.direct == 0 and s.dur > 0 then
          s.channel, s.cast = true, math.max(SP.GCD, s.dur)
        end
        local old = byName[name]
        if not old or (s.direct + s.dot) > (old.direct + old.dot) then byName[name] = s end
      end
    end
  end
  for _, s in pairs(byName) do table.insert(list, s) end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- Fills each spell's coefficient and measured hit (Calib.lua), if any.
function SP.calibrate(list)
  local spells = ns.calib and ns.calib.store().spells or {}
  for _, s in ipairs(list) do
    local t = spells[s.id]
    if t and t.n >= (ns.calib.MIN_HITS or 20) then
      local coef, fitted = ns.calib.coef(s.id, t)
      s.coef, s.fitted = coef, fitted
      s.measured = { avg = t.d / t.n, sp0 = t.sp / t.n, crit = (t.hits + t.crits) > 0 and t.crits / (t.hits + t.crits) or nil,
        bonus = ns.calib.critBonus and ns.calib.critBonus(t) or nil }
    else
      -- Classic rule: cast time / 3.5 s (1.5 s for instants), at most 1;
      -- damage over time: duration / 15 s.
      s.coef = math.min(1, math.max(SP.GCD, s.castRaw) / 3.5)
      s.dotCoef = math.min(1, (s.dur or 0) / 15)
      -- Classic area rule: a third of the single-target coefficient; a
      -- channel counts as its channel time (at most 3.5 s).
      if s.area then
        s.coef = s.coef / 3
        s.dotCoef = s.channel and math.min(1, s.dur / 3.5) / 3 or s.dotCoef / 3
      end
    end
  end
  return list
end

-- Damage of one cast at spell damage sp, crit (fraction), hit (fraction).
-- o (optional): crit0, your crit now (a measured crit rate then moves by
-- crit - crit0, so more crit on gear still counts); bonus, the extra damage
-- of a crit (0.5 = +50%).
function SP.perCast(s, sp, crit, hit, o)
  local direct
  if s.measured then
    -- Measured direct hits only: ticks come as SPELL_PERIODIC_DAMAGE.
    direct = s.measured.avg + (s.coef or 0) * (sp - s.measured.sp0)
  else
    direct = s.direct + (s.direct > 0 and (s.coef or 0) * sp or 0)
  end
  local dot = s.dot > 0 and (s.dot + (s.dotCoef or 0) * sp) or 0
  local c = crit
  if s.measured and s.measured.crit then
    c = math.max(0, math.min(1, s.measured.crit + (o and o.crit0 and (crit - o.crit0) or 0)))
  end
  local bonus = s.measured and s.measured.bonus or (o and o.bonus) or SP.CRIT_BONUS
  return (math.max(0, direct) * (1 + bonus * c) + dot) * hit
end

-- The rotation at spell damage sp, crit and hit (fractions):
-- { dps, mps (mana per second), parts = { {spell, dps, share} } }.
-- One target: area spells (Blizzard, Frost Nova) are left out. o: see
-- SP.perCast.
function SP.rotation(all, sp, crit, hit, o)
  local list = {}
  for _, s in ipairs(all or {}) do if not s.area then table.insert(list, s) end end
  if #list == 0 then return nil end
  local filler, best, used = nil, 0, 0
  local parts, dps, mps = {}, 0, 0
  for _, s in ipairs(list) do
    if s.cd <= s.cast then
      local rate = SP.perCast(s, sp, crit, hit, o) / s.cast
      if rate > best then filler, best = s, rate end
    end
  end
  for _, s in ipairs(list) do
    if s.cd > s.cast then
      local per = SP.perCast(s, sp, crit, hit, o)
      if per > 0 and (not filler or per / s.cast > best) then
        local every = math.max(s.cd, s.cast, s.dur or 0)
        used = used + s.cast / every
        table.insert(parts, { s, per / every })
        dps, mps = dps + per / every, mps + s.mana / every
      end
    end
  end
  if filler then
    local left = math.max(0, 1 - used)
    local d = left * best
    table.insert(parts, { filler, d })
    dps, mps = dps + d, mps + left * filler.mana / filler.cast
  end
  for _, p in ipairs(parts) do p[3] = dps > 0 and p[2] / dps or 0 end
  table.sort(parts, function(a, b) return a[2] > b[2] end)
  return { dps = dps, mps = mps, parts = parts }
end

-- The DPS change for +power and +crit (fraction) with your bars, or nil.
function SP.change(power, crit, ctx)
  local list = SP.calibrate(SP.fromBars())
  local sp, c0 = ctx.sp or 0, (ctx.spcrit or 5) / 100
  local o = { crit0 = c0, bonus = ns.grind and ns.grind.critBonus() or nil }
  local a = SP.rotation(list, sp, c0, 0.96, o)
  local b = SP.rotation(list, sp + power, c0 + crit, 0.96, o)
  if not (a and b) or a.dps <= 0 then return nil end
  return b.dps / a.dps - 1, a, b
end
