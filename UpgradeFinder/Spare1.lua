-- UpgradeFinder Grind: score gear by leveling speed, not by burst damage.
-- (In Spare1.lua so it loads with /reload; rename before a release.)
--
-- The hand-set weights (Score.lua) say how much damage a stat adds. Leveling
-- speed is damage times the share of the time you cast: a caster stops to
-- drink. The model here is one mana pool, emptied and filled again:
--
--   cast time  = pool / (mana per second of your rotation - regen)
--   drink time = pool / (mana per second of water + Spirit regen)
--   speed      = DPS x cast time / (cast time + drink time + overhead)
--
-- The rotation comes from the spells on your action bars (Spells.lua). The
-- weight of a stat is how much one point raises the speed, in units of one
-- point of spell damage on your single-target rotation. So the weights follow
-- your level, your gear and your spells, and they are worked out again when
-- you pick a mode or gain a level.
--
-- Modes (/uf mode, or the Mode button):
--   weights  the hand-set weights, as before
--   grind    one target at a time (Frostbolt)
--   aoe      pulls of several mobs with your area spell (Blizzard): damage
--            over time does not crit, the pull must fit in one mana pool, and
--            Stamina and armor count double (you take the hits of the pull)
--
-- Stamina, armor and the stats the model does not know keep their hand-set
-- weights. The numbers are Classic rules; where the game gives its own
-- (mana costs, regen, your spell text) those are used.
local _, ns = ...
local G = {}
ns.grind = G
local S, St, SP, Scan = ns.score, ns.stats, ns.spells, ns.scan
local call = ns.call

G.MODES = { "weights", "grind", "aoe" }
G.LABEL = { weights = "Weights", grind = "Single", aoe = "AoE" }
-- Water by the level that can drink it: mana per second (Classic conjured
-- and vendor water: 151 mana in 18 s at level 1 up to 4200 in 30 s at 55).
G.WATER = { { 1, 151 / 18 }, { 5, 436 / 21 }, { 15, 835 / 24 }, { 25, 1344 / 27 }, { 35, 1992 / 30 },
  { 45, 2934 / 30 }, { 55, 4200 / 30 } }
-- Seconds per mana pool that are neither casting nor drinking: sit down and
-- stand up, loot; for AoE also the time to gather the pull.
G.OVERHEAD = { grind = 5, aoe = 20 }
G.MOBS = 4          -- mobs in an AoE pull (/uf mobs N)
G.AOE_SURVIVAL = 2  -- Stamina and armor count this much more in AoE mode
-- Mana per second from one point of Spirit while you do not cast.
G.SPI_REGEN = { MAGE = 0.125, PRIEST = 0.125 }
G.SPI_REGEN_OTHER = 0.1
-- The stats the model works out, and the step used to measure each.
G.DERIVED = { { "sp", 10 }, { "int", 10 }, { "spi", 10 }, { "mp5", 5 }, { "spcrit", 1 }, { "sphit", 1 },
  { "mana", 50 } }

function G.drinkRate(level)
  local rate = G.WATER[1][2]
  for _, w in ipairs(G.WATER) do if (level or 1) >= w[1] then rate = w[2] end end
  return rate
end

local function opts() return ns.db().opts end
function G.mode()
  local m = opts().mode
  return (m == "grind" or m == "aoe") and m or "weights"
end
function G.mobs() return math.max(1, math.min(20, tonumber(opts().mobs) or G.MOBS)) end
-- The extra damage of a crit (0.5 = +50%); /uf critbonus PERCENT sets it.
function G.critBonus()
  local b = tonumber(opts().critBonus)
  return b and math.max(0, math.min(2, b)) or SP.CRIT_BONUS
end

---------------------------------------------------------------------------
-- The model. st is a plain table (G.state() reads it from the game; tests
-- pass their own), d a stat change.
---------------------------------------------------------------------------
-- The area spell of an AoE pull: a channel (Blizzard) when you have one on
-- your bars, else the area spell with the most damage per second.
function G.areaSpell(list, sp, crit, hit, o)
  local best, rate
  for _, s in ipairs(list or {}) do
    if s.area and s.cd <= s.cast then
      local r = SP.perCast(s, sp, crit, hit, o) / s.cast
      if s.channel then r = r + 1e9 end
      if not rate or r > rate then best, rate = s, r end
    end
  end
  return best
end

-- Damage and mana per second while casting: { dps, mps, spell (aoe) }.
function G.rotation(st, sp, crit, hit)
  local o = { crit0 = st.crit, bonus = st.critBonus }
  if st.mode == "aoe" then
    local s = G.areaSpell(st.list, sp, crit, hit, o)
    if not s then return nil end
    return { dps = (st.mobs or G.MOBS) * SP.perCast(s, sp, crit, hit, o) / s.cast, mps = s.mana / s.cast, spell = s }
  end
  return SP.rotation(st.list, sp, crit, hit, o)
end

-- Sustained damage per second with the stat change d, or nil with no spells.
-- Also returns the parts { dps, mps, cast, drink, uptime }.
function G.speed(st, d)
  d = d or {}
  local power = (d.sp or 0) + (st.school and d[st.school] or 0)
  local crit = st.crit + ((d.spcrit or 0) + (d.int or 0) / st.intPerCrit) / 100
  crit = math.max(0, math.min(1, crit))
  -- 4% of spells miss a mob of your level; 1% always misses.
  local hit = math.min(0.99, 0.96 + ((st.hit or 0) + (d.sphit or 0)) / 100)
  local rot = G.rotation(st, st.sp + power, crit, hit)
  if not rot or rot.dps <= 0 then return nil end
  local pool = math.max(1, st.mana + (d.int or 0) * st.manaPerInt + (d.mana or 0))
  local mp5 = ((st.mp5 or 0) + (d.mp5 or 0)) / 5
  local spirit = math.max(0, (st.spi or 0) + (d.spi or 0)) * st.spiRegen
  local drain = rot.mps - mp5 - (st.regenCast or 0)
  local parts = { dps = rot.dps, mps = rot.mps, uptime = 1, spell = rot.spell }
  if drain <= 0 then return rot.dps, parts end -- never out of mana
  parts.cast = pool / drain
  parts.drink = pool / (st.drink + spirit + mp5)
  parts.uptime = parts.cast / (parts.cast + parts.drink + st.overhead)
  return rot.dps * parts.uptime, parts
end

-- The speed change of a stat change, as a fraction (0.02 = +2%), or nil.
function G.change(st, d)
  local base = G.speed(st)
  local with = base and G.speed(st, d)
  if not with or base <= 0 then return nil end
  return with / base - 1
end

local function round(v) return math.floor(v * 1000 + 0.5) / 1000 end

-- Weights from the model. base: the hand-set weights (they give Stamina,
-- armor and the rest). Returns weights and info { unit, parts }, or nil
-- when your bars have no spell for the mode.
function G.derive(st, base)
  local speed, parts = G.speed(st)
  if not speed then return nil end
  -- The unit: 1 spell damage on the single-target rotation.
  local unit
  if st.mode ~= "grind" then
    local single = {}
    for k, v in pairs(st) do single[k] = v end
    single.mode, single.overhead = "grind", G.OVERHEAD.grind
    unit = G.change(single, { sp = 10 })
  end
  unit = unit or G.change(st, { sp = 10 })
  if not unit or unit <= 0 then return nil end
  unit = unit / 10
  local w = {}
  for k, v in pairs(base or {}) do w[k] = v end
  for _, e in ipairs(G.DERIVED) do
    local stat, step = e[1], e[2]
    w[stat] = round(math.max(0, (G.change(st, { [stat] = step }) or 0) / step / unit))
  end
  -- One-school damage: your school is spell damage; the others keep their
  -- share of it.
  local baseSp = base and base.sp or 0
  for _, school in ipairs({ "frost", "fire", "arcane", "shadow", "nature", "holy" }) do
    if school == st.school then w[school] = w.sp
    elseif base and base[school] and baseSp > 0 then w[school] = round(w.sp * base[school] / baseSp) end
  end
  if base and base.slay and baseSp > 0 then w.slay = round(w.sp * base.slay / baseSp) end
  if st.mode == "aoe" then
    for _, k in ipairs({ "sta", "armor" }) do if w[k] then w[k] = round(w[k] * G.AOE_SURVIVAL) end end
  end
  w.hp = round((w.sta or 0) / 10) -- flat health: a tenth of Stamina
  return w, { unit = unit, parts = parts }
end

---------------------------------------------------------------------------
-- Reading the game
---------------------------------------------------------------------------
-- The hand-set weights; for a mage with MageMentor, its weights (it names
-- spell crit and hit "crit" and "hit").
function G.baseWeights()
  local w = {}
  for k, v in pairs(ns.weights()) do w[k] = v end
  local mm = rawget(_G, "MageMentorAPI")
  if ns.class() == "MAGE" and type(mm) == "table" and type(mm.score) == "function" then
    for _, k in ipairs({ "sp", "frost", "fire", "arcane", "shadow", "nature", "holy", "int", "spi", "mp5", "sta",
      "armor", "slay" }) do
      local ok, v = pcall(mm.score, { [k] = 1 })
      if ok and type(v) == "number" then w[k] = v end
    end
    for mine, theirs in pairs({ spcrit = "crit", sphit = "hit" }) do
      local ok, v = pcall(mm.score, { [theirs] = 1 })
      if ok and type(v) == "number" then w[mine] = v end
    end
  end
  return w
end

-- Spell hit and mana per 5 s on what you wear (the game has no call for them).
function G.wornTotals()
  local hit, mp5 = 0, 0
  for slot = 1, 18 do
    if call(rawget(_G, "GetInventoryItemLink"), "player", slot) then
      local lines = Scan.read(function(tt) tt:SetInventoryItem("player", slot) end)
      local s = lines and S.parse(lines) or {}
      hit, mp5 = hit + (s.sphit or 0), mp5 + (s.mp5 or 0)
    end
  end
  return hit, mp5
end

function G.state(mode)
  local class, base = ns.class(), G.baseWeights()
  local ctx = St.context(class, base)
  local level = ctx.level or 60
  local st = { mode = mode or G.mode(), class = class, level = level, school = St.school(base) }
  st.role = St.role(class, base)
  st.sp, st.crit = ctx.sp or 0, (ctx.spcrit or 5) / 100
  st.intPerCrit = ctx.intPerCrit or (St.INT_PER_CRIT[class] or 60) * math.max(10, level) / 60
  st.manaPerInt = ctx.manaPerInt or 15
  st.mana = call(rawget(_G, "UnitPowerMax"), "player", 0) or call(rawget(_G, "UnitManaMax"), "player") or (level * 30)
  local _, spi = call(rawget(_G, "UnitStat"), "player", 5)
  st.spi = spi or level
  st.spiRegen = G.SPI_REGEN[class] or G.SPI_REGEN_OTHER
  st.hit, st.mp5 = G.wornTotals()
  st.drink = G.drinkRate(level)
  st.overhead = G.OVERHEAD[st.mode] or G.OVERHEAD.grind
  st.mobs, st.critBonus = G.mobs(), G.critBonus()
  st.list = SP.calibrate(SP.fromBars())
  return st, base
end

---------------------------------------------------------------------------
-- The weights in use
---------------------------------------------------------------------------
local function storeKey(mode) return ns.weightKey() .. ":" .. mode end

-- The saved weights of the mode in use, or nil (the hand-set weights).
function G.weights()
  local mode = G.mode()
  if mode == "weights" then return nil end
  local saved = (ns.db().grind or {})[storeKey(mode)]
  return saved and saved.w or nil
end

-- Works the weights of a mode out again and saves them. Returns the saved
-- entry, or nil and why not.
function G.refresh(mode)
  mode = mode or G.mode()
  if mode == "weights" then return nil end
  local st, base = G.state(mode)
  if st.role ~= "caster" then return nil, "the leveling-speed score is for damage casters; the hand-set weights stay" end
  local w, info = G.derive(st, base)
  if not w then
    return nil, mode == "aoe" and "no area damage spell (Blizzard, Arcane Explosion) found on your action bars"
      or "no damage spell found on your action bars"
  end
  local db = ns.db()
  db.grind = db.grind or {}
  local p = info.parts
  local entry = { w = w, level = st.level, mobs = st.mobs, uptime = p.uptime, dps = p.dps, mps = p.mps,
    spell = p.spell and p.spell.name or nil }
  db.grind[storeKey(mode)] = entry
  return entry
end

-- "spell damage 1, Intellect 0.15, ..." for the chat.
local SHOW = { "sp", "int", "spi", "mp5", "spcrit", "sphit", "sta", "armor" }
function G.describe(entry)
  local parts = {}
  for _, k in ipairs(SHOW) do
    local v = entry.w[k]
    if v then
      local s = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
      table.insert(parts, (St.LONG[k] or St.NAMES[k] or k) .. " " .. s)
    end
  end
  return table.concat(parts, ", ")
end

function G.status()
  local mode = G.mode()
  if mode == "weights" then return { "score mode: hand-set weights (/uf mode grind or /uf mode aoe for leveling speed)" } end
  local e = (ns.db().grind or {})[storeKey(mode)]
  if not e then return { "score mode: " .. G.LABEL[mode] .. ", but no weights yet (/uf mode " .. mode .. ")" } end
  local out = { string.format("score mode: %s, weights from level %d%s", mode == "aoe" and "AoE pulls" or "single target",
    e.level, mode == "aoe" and (", " .. (e.spell or "area spell") .. " on " .. e.mobs .. " mobs") or "") }
  if e.mps and e.mps > 0 then
    table.insert(out, string.format("you cast %d%% of the time and drink or walk the rest", e.uptime * 100 + 0.5))
  else
    table.insert(out, "the game gave no mana costs: the score is burst damage only")
  end
  table.insert(out, "1 point is worth: " .. G.describe(e))
  return out
end

-- Sets the mode, works its weights out and scores the items again.
function G.set(mode)
  if mode ~= "grind" and mode ~= "aoe" then mode = "weights" end
  local o = opts()
  if mode == "weights" then
    o.mode = nil
    ns.reweigh("score mode: hand-set weights")
    return true
  end
  local entry, why = G.refresh(mode)
  if not entry then ns.say(why) return false end
  o.mode = mode
  for _, l in ipairs(G.status()) do ns.say(l) end
  ns.reweigh()
  return true
end

-- The Mode button: the next mode that works.
function G.cycle()
  local now = G.mode()
  local i = 1
  for n, m in ipairs(G.MODES) do if m == now then i = n end end
  for step = 1, #G.MODES do
    local m = G.MODES[(i + step - 1) % #G.MODES + 1]
    if G.set(m) then return end
  end
end

-- /uf mode [weights|grind|aoe], /uf mobs N, /uf critbonus PERCENT.
function G.slash(cmd, a)
  if cmd == "mode" then
    if a == "" then for _, l in ipairs(G.status()) do ns.say(l) end return end
    if a == "single" then a = "grind" end
    if a ~= "weights" and a ~= "grind" and a ~= "aoe" then ns.say("modes: weights, grind, aoe") return end
    G.set(a)
  elseif cmd == "mobs" then
    local n = tonumber(a)
    if not n then ns.say("mobs in an AoE pull: " .. G.mobs() .. " (/uf mobs N)") return end
    opts().mobs = n
    ns.say("AoE pulls of " .. G.mobs() .. " mobs")
    if G.mode() == "aoe" then G.set("aoe") end
  elseif cmd == "critbonus" then
    local n = tonumber(a)
    if not n then
      ns.say(string.format("a spell crit does +%d%% damage (/uf critbonus PERCENT; 100 with a talent that doubles it)",
        G.critBonus() * 100 + 0.5))
      return
    end
    opts().critBonus = n / 100
    ns.say(string.format("a spell crit does +%d%% damage", G.critBonus() * 100 + 0.5))
    if G.mode() ~= "weights" then G.set(G.mode()) end
  end
end

---------------------------------------------------------------------------
-- The score mode section at the bottom of the Weights panel: a button per
-- mode, and boxes for the mobs in a pull and the crit bonus, so nothing
-- here needs a slash command.
---------------------------------------------------------------------------
G.PANEL_H = 96
local pui = { modes = {} }
G.panelUI = pui

function G.paintPanel()
  if not pui.mobs then return end
  local mode = G.mode()
  for m, b in pairs(pui.modes) do
    local label = m == "weights" and "Weights" or m == "grind" and "Single target" or "AoE pulls"
    b:SetText(m == mode and ("|cffffd100" .. label .. "|r") or label)
  end
  if not call(pui.mobs.HasFocus, pui.mobs) then pui.mobs:SetText(tostring(G.mobs())) end
  if not call(pui.crit.HasFocus, pui.crit) then pui.crit:SetText(tostring(math.floor(G.critBonus() * 100 + 0.5))) end
  local lines = G.status()
  pui.status:SetText(mode == "weights" and "Single target and AoE pulls rank gear by leveling speed."
    or (lines[3] or lines[1] or ""))
end

function G.buildPanel(panel)
  local function tip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
      local tt = rawget(_G, "GameTooltip")
      if not tt then return end
      tt:SetOwner(self, "ANCHOR_RIGHT")
      tt:AddLine(title)
      tt:AddLine(text, 0.8, 0.8, 0.8, true)
      tt:Show()
    end)
    frame:SetScript("OnLeave", function() local tt = rawget(_G, "GameTooltip") if tt then tt:Hide() end end)
  end
  local head = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, G.PANEL_H - 8)
  head:SetText("Score mode")
  local tips = {
    weights = "The hand-set weight of each stat, above.",
    grind = "Leveling speed with one target at a time: your damage times the share of the time you cast and do not drink. The weights come from the spells on your action bars, your mana and your level.",
    aoe = "Leveling speed with pulls of several mobs and your area spell (Blizzard). Damage over time does not crit; Intellect, Stamina and armor count for more.",
  }
  for i, m in ipairs(G.MODES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(88, 20)
    b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12 + (i - 1) * 92, G.PANEL_H - 34)
    b:SetScript("OnClick", function() G.set(m) if ns.paint then ns.paint() end G.paintPanel() end)
    tip(b, m == "weights" and "Weights" or m == "grind" and "Single target" or "AoE pulls", tips[m])
    pui.modes[m] = b
  end
  local function box(key, label, x, cmd, title, text)
    local l = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, G.PANEL_H - 56)
    l:SetText(label)
    local e = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    e:SetSize(36, 18)
    e:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x + 84, G.PANEL_H - 60)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    local function commit(self)
      local n = tonumber(((self:GetText() or ""):gsub("%s", "")))
      local now = key == "mobs" and G.mobs() or math.floor(G.critBonus() * 100 + 0.5)
      if n and n ~= now then G.slash(cmd, tostring(n)) if ns.paint then ns.paint() end end
      G.paintPanel()
    end
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() commit(self) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() G.paintPanel() end)
    e:SetScript("OnEditFocusLost", commit)
    tip(e, title, text)
    pui[key] = e
  end
  box("mobs", "Mobs per pull", 14, "mobs", "Mobs per pull", "How many mobs you gather for one AoE pull. More mobs: more damage for the same mana.")
  box("crit", "Crit bonus %", 152, "critbonus", "Crit bonus",
    "The extra damage of your spell crits: 50, or 100 with a talent that doubles them. It sets what crit on gear is worth.")
  pui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  pui.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 8)
  pui.status:SetWidth(272)
  pui.status:SetJustifyH("LEFT")
end

---------------------------------------------------------------------------
-- Hooks into the scan and the row tooltip
---------------------------------------------------------------------------
-- The score of an item: the mode's weights when a mode is on.
local valueOf = ns.valueOf
function ns.valueOf(lines, w)
  local gw = G.weights()
  if gw then return S.value(S.parse(lines), gw) end
  return valueOf(lines, w)
end

-- The saved item scores belong to one set of weights: the mode's weights
-- are part of the key.
local cacheKey = Scan.cacheKey
function Scan.cacheKey()
  local key = cacheKey()
  local gw = G.weights()
  if not gw then return key end
  local parts = {}
  for k, v in pairs(gw) do table.insert(parts, k .. "=" .. v) end
  table.sort(parts)
  return key .. "#" .. G.mode() .. ":" .. table.concat(parts, ",")
end

-- The row tooltip: "Leveling speed +1.2%" under the offense lines. The
-- state is read once and kept a few seconds (it reads your bars and gear).
local kept, keptAt, keptMode
local function state()
  local now = call(rawget(_G, "GetTime")) or 0
  local mode = G.mode()
  if not kept or keptMode ~= mode or now - keptAt > 5 or now < keptAt then
    kept, keptAt, keptMode = G.state(mode), now, mode
  end
  return kept
end
function G.forget() kept = nil end

local derive = St.derive
function St.derive(d, ctx, w, loc)
  local off, def, role, n = derive(d, ctx, w, loc)
  if G.mode() ~= "weights" and role == "caster" and G.weights() then
    local ok, ch = pcall(function() return G.change(ctx.grind or state(), d) end)
    if ok and ch and math.abs(ch) >= 0.0005 then
      n.grind = ch
      table.insert(off, { G.mode() == "aoe" and "AoE leveling speed" or "Leveling speed", St.fmt(ch * 100, true), ch > 0 })
    end
  end
  return off, def, role, n
end

-- A new level changes the model (water, spell ranks, crit per Intellect).
local frame = CreateFrame("Frame")
G.frame = frame
frame:SetScript("OnEvent", function()
  if G.mode() == "weights" then return end
  local after = ns.api("C_Timer.After")
  local function go()
    G.forget()
    if pcall(G.refresh) and ns.reweigh then ns.reweigh() end
  end
  if after then call(after, 2, go) else go() end
end)
pcall(frame.RegisterEvent, frame, "PLAYER_LEVEL_UP")
