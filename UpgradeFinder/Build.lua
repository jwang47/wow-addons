-- UpgradeFinder Build: a gear planner in the style of Path of Building.
-- A build is one item per slot (1-18). The working build starts as what you
-- wear; put other items in its slots and the sheet shows your totals now and
-- with the build: health, mana, armor, eHP, spell damage or attack power,
-- crit, hit and DPS (for a caster, from the spells on your action bars).
-- Builds are saved per class by name; any two can be compared.
local _, ns = ...
local B = {}
ns.build = B
local call, api = ns.call, ns.api

B.SLOT_ORDER = { 1, 2, 3, 15, 5, 4, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

function B.store()
  local db = ns.db()
  db.builds = db.builds or {}
  local class = ns.class()
  db.builds[class] = db.builds[class] or {}
  return db.builds[class]
end

local function idOf(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or tonumber(link)
end
B.idOf = idOf

-- What you wear: slot -> item link (keeps enchants), or nil.
function B.worn()
  local out = {}
  for slot = 1, 18 do out[slot] = call(rawget(_G, "GetInventoryItemLink"), "player", slot) end
  return out
end

-- The working build: slot -> link, false (empty on purpose) or nil (worn).
B.work = {}
function B.reset() B.work = {} end
function B.set(slot, link) B.work[slot] = link end
function B.clear(slot) B.work[slot] = false end
function B.unset(slot) B.work[slot] = nil end

-- The full build: worn items with the working changes on top.
function B.items(build)
  local out, worn = {}, B.worn()
  for slot = 1, 18 do
    local v = (build or B.work)[slot]
    if v == nil then out[slot] = worn[slot] elseif v then out[slot] = v end
  end
  return out
end

-- Stats of one item link, cached; nil while the game loads it.
local cache = {}
function B.statsOf(link)
  if cache[link] then return cache[link] end
  local lines = ns.scan.read(function(tt) tt:SetHyperlink(link) end)
  if not lines then
    call(api("C_Item.RequestLoadItemDataByID"), idOf(link))
    return nil
  end
  local s = ns.score.parse(lines)
  cache[link] = s
  return s
end
function B.forget() for k in pairs(cache) do cache[k] = nil end end

-- Summed stats of a full build, and how many items are still loading.
function B.total(items)
  local t, missing = {}, 0
  for slot = 1, 18 do
    local link = items[slot]
    if link then
      local s = B.statsOf(link)
      if s then for k, v in pairs(s) do t[k] = (t[k] or 0) + v end else missing = missing + 1 end
    end
  end
  return t, missing
end

-- The sheet for build b against base a (both full item tables; a defaults
-- to what you wear). Rows: { label, now, with, delta text, good } with
-- numbers rounded for show; plus the derive() lists and the rotation.
function B.sheet(b, a)
  local St, SP = ns.stats, ns.spells
  a = a or B.worn()
  local ta, ma = B.total(a)
  local tb, mb = B.total(b)
  local d = St.diff(tb, { ta })
  local class, w = ns.class(), ns.weights()
  local ctx = St.context(class, w)
  -- The weapon you would hold, for the melee DPS formula.
  local main = b[16] and B.statsOf(b[16]) or nil
  local mainA = a[16] and B.statsOf(a[16]) or nil
  ctx.weaponDps = mainA and mainA.dps or ctx.weaponDps
  local loc = b[16] and ns.scan.equipLoc(idOf(b[16])) or nil
  if not (main and mainA and main.dps ~= mainA.dps) then loc = nil end
  local off, def, role, n = St.derive(d, ctx, w, loc)
  local rows = {}
  local function row(label, now, with, pct, fmtv)
    if now == nil then return end
    fmtv = fmtv or (pct and "%.1f%%" or "%d")
    local delta = with - now
    table.insert(rows, { label, string.format(fmtv, now), string.format(fmtv, with),
      math.abs(delta) >= (pct and 0.05 or 0.5) and St.fmt(delta, pct) or "", delta >= 0 })
  end
  row("Health", n.hpNow, n.hpNow + n.hp)
  local mana = call(rawget(_G, "UnitPowerMax"), "player", 0)
  if n.mana and mana and mana > 0 then row("Mana", mana, mana + n.mana) end
  row("Armor", n.armorNow, n.armorNow + n.armor)
  row("eHP (physical)", n.ehp0, n.ehp1)
  local rotA, rotB
  if role == "caster" or role == "healer" then
    local now = role == "healer" and (ctx.heal or 0) or (ctx.sp or 0)
    row(role == "healer" and "Healing" or "Spell damage", now, now + n.power)
    if ctx.spcrit then row("Spell crit", ctx.spcrit, ctx.spcrit + n.crit, true) end
    if n.hit ~= 0 then row("Spell hit", 0, n.hit, true) end
    if role == "caster" and SP then
      local list = SP.calibrate(SP.fromBars())
      local c0 = (ctx.spcrit or 5) / 100
      rotA = SP.rotation(list, ctx.sp or 0, c0, 0.96)
      rotB = SP.rotation(list, (ctx.sp or 0) + n.power, c0 + n.crit / 100, math.min(0.99, 0.96 + n.hit / 100))
      if rotA and rotB then
        row("DPS (your bars)", rotA.dps, rotB.dps, false, "%.1f")
        if rotA.mps > 0 then row("Mana / sec", rotA.mps, rotB.mps, false, "%.1f") end
        if mana and rotA.mps > 0 then
          row("Time to OOM (s)", (mana) / rotA.mps, (mana + (n.mana or 0)) / rotB.mps, false, "%d")
        end
      end
    end
  else
    local ap = role == "ranged" and ctx.rap or ctx.ap
    if ap then row("Attack power", ap, ap + n.ap) end
    local c = role == "ranged" and ctx.rangedCrit or ctx.crit
    if c then row("Crit", c, c + n.crit, true) end
  end
  if n.est and not (rotA and rotB) then
    table.insert(rows, { "Est. DPS", "", "", ns.stats.fmt(n.est * 100, true), n.est >= 0 })
  end
  return { rows = rows, diff = d, off = off, def = def, role = role, loading = ma + mb, rotation = rotB or rotA }
end

-- Saved builds -------------------------------------------------------------
function B.save(name)
  local items = B.items()
  local keep = {}
  for slot, link in pairs(items) do keep[slot] = link end
  B.store()[name] = keep
end
function B.load(name)
  local saved = B.store()[name]
  if not saved then return false end
  local worn = B.worn()
  B.work = {}
  for slot = 1, 18 do
    if saved[slot] ~= worn[slot] then B.work[slot] = saved[slot] or false end
  end
  return true
end
function B.delete(name) B.store()[name] = nil end
function B.names()
  local out = {}
  for name in pairs(B.store()) do table.insert(out, name) end
  table.sort(out)
  return out
end
-- Full item table of a saved build (nil: unknown name).
function B.get(name)
  local saved = B.store()[name]
  if not saved then return nil end
  local out = {}
  for slot = 1, 18 do out[slot] = saved[slot] end
  return out
end
