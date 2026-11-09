-- UpgradeFinder calibration: measures the Forever formulas from your own
-- client instead of the Classic guesses in Stats.lua.
--
-- 1. Stat snapshots. When your gear, level or stats change, it saves your
--    stats next to what the game reports (spell crit, crit, max health, max
--    mana, armor). Within one level, the slope of crit against Intellect
--    gives the Int per 1% spell crit (gear crit lines are taken out first);
--    the same for Agility, Stamina (health) and Intellect (mana).
-- 2. Your spells (only with /uf calib log on: Forever forbids addons the
--    combat log). From the combat log (your own damage only), each spell ID
--    keeps running sums: hits and crits, damage, and non-crit damage against
--    your spell damage at that moment. That gives the average hit, the crit
--    rate, each spell's share of your damage and, once your spell damage has
--    varied enough, the spell damage coefficient.
-- Stats.lua uses a measured value when there is enough data, else its guess.
local _, ns = ...
local C = {}
ns.calib = C
local call, api = ns.call, ns.api

C.MAX_SNAPS = 60        -- per class, oldest dropped first
C.MIN_SPREAD = 4        -- stat points of spread at one level before a slope counts
C.MIN_HITS = 20         -- non-crit hits of a spell before it joins the DPS model
C.MIN_SP_SPREAD = 15    -- spell damage spread before the coefficient is fitted
local SCHOOL_INDEX = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }

function C.store(class)
  local db = ns.db()
  db.calib = db.calib or {}
  class = class or ns.class()
  db.calib[class] = db.calib[class] or { snaps = {}, spells = {} }
  return db.calib[class]
end

local function stat(i)
  local _, eff = call(rawget(_G, "UnitStat"), "player", i)
  return eff
end

-- Crit lines on your worn gear (they are not from Int or Agi).
local function gearCrit()
  local S, Scan = ns.score, ns.scan
  local sp, melee = 0, 0
  for slot = 1, 18 do
    if call(rawget(_G, "GetInventoryItemLink"), "player", slot) then
      local lines = Scan.read(function(tt) tt:SetInventoryItem("player", slot) end)
      if not lines then return nil end -- not loaded: no snapshot this time
      local s = S.parse(lines)
      sp, melee = sp + (s.spcrit or 0), melee + (s.crit or 0)
    end
  end
  return sp, melee
end

-- The snapshot of now, or nil when the game cannot tell yet.
function C.read()
  local level = call(rawget(_G, "UnitLevel"), "player")
  local int, agi, sta = stat(4), stat(2), stat(3)
  if not (level and int and agi and sta) then return nil end
  local gsp, gmelee = gearCrit()
  if not gsp then return nil end
  local school = ns.stats.school(ns.weights()) or "frost"
  local spcrit = call(rawget(_G, "GetSpellCritChance"), SCHOOL_INDEX[school] or 2)
  local crit = call(rawget(_G, "GetCritChance"))
  local _, armor = call(rawget(_G, "UnitArmor"), "player")
  return { level = level, int = int, agi = agi, sta = sta,
    spcrit = spcrit and (spcrit - gsp) or nil, crit = crit and (crit - gmelee) or nil,
    hp = call(rawget(_G, "UnitHealthMax"), "player"),
    mana = call(rawget(_G, "UnitPowerMax"), "player", 0), armor = armor }
end

local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Saves the snapshot of now (a copy of the last one is not saved again).
function C.snap()
  local s = C.read()
  if not s then return false end
  local snaps = C.store().snaps
  for _, old in ipairs(snaps) do if same(old, s) then return false end end
  table.insert(snaps, s)
  while #snaps > C.MAX_SNAPS do table.remove(snaps, 1) end
  return true
end

-- Least squares slope of y on x for the snapshots at one level, or nil when
-- x does not spread by at least MIN_SPREAD (or y is missing).
function C.slope(snaps, level, x, y)
  local n, sx, sy, sxx, sxy, lo, hi = 0, 0, 0, 0, 0, nil, nil
  for _, s in ipairs(snaps) do
    if s.level == level and s[x] and s[y] then
      n, sx, sy = n + 1, sx + s[x], sy + s[y]
      sxx, sxy = sxx + s[x] * s[x], sxy + s[x] * s[y]
      lo, hi = math.min(lo or s[x], s[x]), math.max(hi or s[x], s[x])
    end
  end
  if n < 2 or hi - lo < C.MIN_SPREAD then return nil end
  local d = n * sxx - sx * sx
  if d == 0 then return nil end
  return (n * sxy - sx * sy) / d, n
end

-- Measured ratios for a level: { intPerCrit, agiPerCrit, hpPerSta,
-- manaPerInt, from = level measured, n = snapshots }. The nearest measured
-- level is used (crit ratios scaled by level, as in Stats.lua).
function C.ratios(level, class)
  local snaps = C.store(class).snaps
  local levels, seen = {}, {}
  for _, s in ipairs(snaps) do
    if not seen[s.level] then seen[s.level] = true table.insert(levels, s.level) end
  end
  table.sort(levels, function(a, b) return math.abs(a - level) < math.abs(b - level) end)
  local out = {}
  local function take(key, x, y, invert, scale)
    for _, lv in ipairs(levels) do
      local m, n = C.slope(snaps, lv, x, y)
      if m and m > 0 then
        local v = invert and (1 / m) or m
        if scale then v = v * math.max(10, level) / math.max(10, lv) end
        out[key] = { v, from = lv, n = n }
        return
      end
    end
  end
  take("intPerCrit", "int", "spcrit", true, true)
  take("agiPerCrit", "agi", "crit", true, true)
  take("hpPerSta", "sta", "hp")
  take("manaPerInt", "int", "mana")
  return out
end

---------------------------------------------------------------------------
-- Spells from the combat log
---------------------------------------------------------------------------
-- spells[id] = { name, hits, crits, misses, dmg (all), n, sp, d, spsp, spd }
-- (n and the sums are over non-crit, unresisted hits, for the fit).
function C.spellPower()
  local school = ns.stats.school(ns.weights()) or "frost"
  return call(rawget(_G, "GetSpellBonusDamage"), SCHOOL_INDEX[school] or 2) or 0
end

function C.record(id, name, amount, crit, resisted, absorbed, sp)
  local spells = C.store().spells
  local t = spells[id]
  if not t then
    t = { name = name, hits = 0, crits = 0, misses = 0, dmg = 0, n = 0, sp = 0, d = 0, spsp = 0, spd = 0 }
    spells[id] = t
  end
  t.dmg = t.dmg + amount
  if crit then t.crits = t.crits + 1 return end
  t.hits = t.hits + 1
  if (resisted or 0) > 0 or (absorbed or 0) > 0 then return end
  t.n, t.sp, t.d = t.n + 1, t.sp + sp, t.d + amount
  t.spsp, t.spd = t.spsp + sp * sp, t.spd + sp * amount
end

function C.miss(id, name)
  local spells = C.store().spells
  spells[id] = spells[id] or { name = name, hits = 0, crits = 0, misses = 0, dmg = 0, n = 0, sp = 0, d = 0, spsp = 0, spd = 0 }
  spells[id].misses = spells[id].misses + 1
end

-- The spell damage coefficient: fitted when spell damage varied enough,
-- else from the cast time (cast / 3.5 s, 1.5 s for instants, at most 1).
function C.coef(id, t)
  local spread = t.n > 1 and (t.spsp / t.n - (t.sp / t.n) ^ 2) or 0
  if t.n >= C.MIN_HITS and spread >= (C.MIN_SP_SPREAD / 2) ^ 2 then
    local d = t.n * t.spsp - t.sp * t.sp
    if d ~= 0 then
      local m = (t.n * t.spd - t.sp * t.d) / d
      if m > 0 and m < 2 then return m, true end
    end
  end
  local cast = select(4, call(rawget(_G, "GetSpellInfo"), id))
  cast = (type(cast) == "number" and cast > 0) and cast / 1000 or 1.5
  return math.min(1, cast / 3.5), false
end

-- The spells with enough hits: { id, name, avg (non-crit hit at sp0), sp0,
-- coef, fitted, critRate, share (of your damage) }, biggest share first.
function C.model()
  local spells, list, total = C.store().spells, {}, 0
  for _, t in pairs(spells) do total = total + t.dmg end
  for id, t in pairs(spells) do
    if t.n >= C.MIN_HITS and total > 0 then
      local coef, fitted = C.coef(id, t)
      local landed = t.hits + t.crits
      table.insert(list, { id = id, name = t.name, avg = t.d / t.n, sp0 = t.sp / t.n, coef = coef, fitted = fitted,
        critRate = landed > 0 and t.crits / landed or 0, missRate = t.misses / math.max(1, landed + t.misses),
        share = t.dmg / total })
    end
  end
  table.sort(list, function(a, b) return a.share > b.share end)
  return list
end

-- The DPS change for +power spell damage and +crit (a fraction) with your
-- measured spells, or nil without enough data. Each spell: its average hit
-- moves by coef x power (from your spell damage now), crits do +50%.
function C.dpsChange(power, crit, spNow)
  local m = C.model()
  if #m == 0 then return nil end
  local change, weight = 0, 0
  for _, s in ipairs(m) do
    local hitNow = s.avg + s.coef * ((spNow or s.sp0) - s.sp0)
    if hitNow > 0 then
      local before = hitNow * (1 + 0.5 * s.critRate)
      local after = (hitNow + s.coef * power) * (1 + 0.5 * math.min(1, s.critRate + crit))
      change, weight = change + s.share * (after / before - 1), weight + s.share
    end
  end
  return weight > 0 and change / weight or nil
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
C.frame = frame
local pending = false
function C.later()
  if pending then return end
  pending = true
  local after = api("C_Timer.After")
  local function go() pending = false pcall(C.snap) end
  if after then call(after, 1, go) else go() end
end

local me
function C.combat(...)
  local _, sub, _, source = ...
  me = me or call(rawget(_G, "UnitGUID"), "player")
  if source ~= me then return end
  if sub == "SPELL_DAMAGE" then
    local id, name, _, amount, _, _, resisted, _, absorbed, critical = select(12, ...)
    if id and amount then C.record(id, name, amount, critical, resisted, absorbed, C.spellPower()) end
  elseif sub == "SPELL_MISSED" then
    local id, name = select(12, ...)
    if id then C.miss(id, name) end
  end
end

local handlers = {
  PLAYER_ENTERING_WORLD = C.later, PLAYER_EQUIPMENT_CHANGED = C.later, PLAYER_LEVEL_UP = C.later,
  UNIT_STATS = function(unit) if unit == "player" then C.later() end end,
  COMBAT_LOG_EVENT_UNFILTERED = function()
    local info = rawget(_G, "CombatLogGetCurrentEventInfo")
    if info then C.combat(info()) end
  end,
}
C.handlers = handlers
-- The Forever client forbids addons the combat log: registering for it
-- brings up "blocked from an action only available to the Blizzard UI" at
-- login. So it is off unless you turn it on (/uf calib log), for a client
-- that allows it.
for ev in pairs(handlers) do
  if ev ~= "COMBAT_LOG_EVENT_UNFILTERED" then pcall(frame.RegisterEvent, frame, ev) end
end
-- On for this session only: it is never saved, so a client that forbids
-- it cannot bring the pop-up back at the next login. (0.1.6 test builds
-- saved it in opts.combatLog; that value is cleared here.)
local logOn = false
function C.logOn() return logOn end
function C.setLog(on)
  logOn = on and true or false
  if on then pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
  else pcall(frame.UnregisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED") end
end
handlers.PLAYER_LOGIN = function() ns.db().opts.combatLog = nil end
pcall(frame.RegisterEvent, frame, "PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, ev, ...) pcall(handlers[ev], ...) end)

-- /uf calib: what has been measured.
function C.report()
  local out, class = {}, ns.class()
  local level = call(rawget(_G, "UnitLevel"), "player") or 60
  local r = C.ratios(level, class)
  local function line(label, e, default)
    if e then
      table.insert(out, string.format("%s: %.1f (measured at level %d, %d snapshots)", label, e[1], e.from, e.n))
    else
      table.insert(out, label .. ": " .. default .. " (not measured yet)")
    end
  end
  local St = ns.stats
  line("Int per 1% spell crit", r.intPerCrit, St.INT_PER_CRIT[class]
    and string.format("%.1f", St.INT_PER_CRIT[class] * math.max(10, level) / 60) or "-")
  line("Agi per 1% crit", r.agiPerCrit, St.AGI_PER_CRIT[class]
    and string.format("%.1f", St.AGI_PER_CRIT[class] * math.max(10, level) / 60) or "-")
  line("Health per Sta", r.hpPerSta, "10")
  line("Mana per Int", r.manaPerInt, "15")
  table.insert(out, string.format("%d snapshots saved. Swap gear with different Int or Agi to measure more.",
    #C.store(class).snaps))
  local m = C.model()
  if not C.logOn() then
    table.insert(out, "Spells: the combat log is off (Forever forbids it to addons). The DPS uses your action bars.")
  elseif #m == 0 then
    table.insert(out, "Spells: none with " .. C.MIN_HITS .. " normal hits yet. Fight, and they appear here.")
  end
  for i = 1, math.min(5, #m) do
    local s = m[i]
    table.insert(out, string.format("%s (%d): %.0f avg hit at %.0f spell dmg, coef %.2f (%s), crit %d%%, %d%% of your damage",
      s.name or "?", s.id, s.avg, s.sp0, s.coef, s.fitted and "measured" or "from cast time",
      math.floor(s.critRate * 100 + 0.5), math.floor(s.share * 100 + 0.5)))
  end
  return out
end

function C.reset()
  local db = ns.db()
  if db.calib then db.calib[ns.class()] = nil end
end
