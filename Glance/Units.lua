-- Glance units: small player and target bars that float under your
-- character, and a cast bar below them. Values go straight to the status
-- bars (no maths on them), so the newer clients' hidden numbers still work.
local addonName, ns = ...

local W, HP_H, MP_H = 170, 13, 9
local FONT = "GameFontHighlightSmall"
local frames = {}
ns.units = { frames = frames }

local function bar(parent, h)
  local b = CreateFrame("StatusBar", nil, parent)
  b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  b:SetHeight(h)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0, 0, 0, 0.45)
  b.text = b:CreateFontString(nil, "OVERLAY", FONT)
  b.text:SetPoint("CENTER", 0, 0)
  if b.text.SetFont and STANDARD_TEXT_FONT then b.text:SetFont(STANDARD_TEXT_FONT, h >= 12 and 10 or 8, "OUTLINE") end
  return b
end

-- "1,234 / 1,500". The values may be secret: the game's number formatters
-- and string joins take them, maths does not. Anything else falls back to
-- the bare current value, then to no text.
local function num(v)
  local f = AbbreviateLargeNumbers or tostring
  local ok, s = pcall(f, v)
  return ok and s or nil
end
local function setNumbers(b, cur, max)
  if pcall(function() b.text:SetText(num(cur) .. " / " .. num(max)) end) then return end
  if not pcall(function() b.text:SetText(num(cur)) end) then b.text:SetText("") end
end
ns.units.setNumbers = setNumbers

local function classColor(unit)
  local _, class = UnitClass(unit)
  local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class)
    or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
  if c then return c.r, c.g, c.b end
  return 0.4, 0.8, 0.95
end

-- Health colour: green for you (so it stands apart from mana), class for
-- other players, reaction for the rest, grey if tapped.
function ns.units.healthColor(unit)
  if UnitIsUnit and UnitIsUnit(unit, "player") then return 0.3, 0.78, 0.35 end
  if UnitIsPlayer(unit) then return classColor(unit) end
  if UnitIsTapDenied and ns.plain(UnitIsTapDenied(unit)) then return 0.55, 0.55, 0.55 end
  local r = ns.plain(UnitReaction(unit, "player"))
  if r and r <= 3 then return 0.88, 0.32, 0.27 end
  if r == 4 then return 0.95, 0.8, 0.3 end
  return 0.35, 0.8, 0.35
end

local function powerColor(unit)
  local _, token = UnitPowerType(unit)
  local c = PowerBarColor and token and PowerBarColor[token]
  if c then return c.r, c.g, c.b end
  return 0.25, 0.45, 0.95
end

local function update(f)
  local u = f.unit
  if not UnitExists(u) then return end
  f.name:SetText(UnitName(u))
  local lvl = UnitLevel(u)
  local known = ns.plain(lvl)
  if known and known <= 0 then f.level:SetText("??") else f.level:SetText(lvl) end
  local hmax, h = UnitHealthMax(u), UnitHealth(u)
  f.hp:SetMinMaxValues(0, hmax)
  f.hp:SetValue(h)
  setNumbers(f.hp, h, hmax)
  f.hp:SetStatusBarColor(ns.units.healthColor(u))
  local maxp = UnitPowerMax(u)
  f.mp:SetMinMaxValues(0, maxp)
  local p = UnitPower(u)
  f.mp:SetValue(p)
  setNumbers(f.mp, p, maxp)
  f.mp:SetStatusBarColor(powerColor(u))
  local m = ns.plain(maxp)
  f.mp:SetShown(m == nil or m > 0)   -- a hidden maximum: keep the bar
end
ns.units.update = update

local function makeUnit(unit, x)
  local f = CreateFrame("Button", "Glance" .. unit:gsub("^%l", string.upper), UIParent, "SecureUnitButtonTemplate")
  f.unit = unit
  f:SetSize(W, 30)
  f:SetPoint("TOP", UIParent, "CENTER", x, -110)
  f:SetAttribute("unit", unit)
  f:SetAttribute("type1", "target")
  f:SetAttribute("type2", "togglemenu")
  f:RegisterForClicks("AnyUp")
  f.name = f:CreateFontString(nil, "OVERLAY", FONT)
  f.name:SetPoint("TOPLEFT", 1, 0)
  f.name:SetPoint("TOPRIGHT", -22, 0)
  f.name:SetJustifyH("LEFT")
  f.level = f:CreateFontString(nil, "OVERLAY", FONT)
  f.level:SetPoint("TOPRIGHT", -1, 0)
  f.level:SetTextColor(0.8, 0.8, 0.8)
  f.hp = bar(f, HP_H)
  f.hp:SetPoint("TOPLEFT", 0, -14)
  f.hp:SetPoint("TOPRIGHT", 0, -14)
  f.mp = bar(f, MP_H)
  f.mp:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -1)
  f.mp:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -1)
  frames[unit] = f
  return f
end

---------------------------------------------------------------------------
-- Range to the target, from your own spells: each Glance key whose spell
-- has a range says in or out of range, and the spells' ranges bracket the
-- distance. The target frame edge turns green while your longest spell
-- reaches, red when it does not; the text gives the bracket ("< 30 yd").
---------------------------------------------------------------------------
local function spellRange(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    return info and ns.plain(info.maxRange)
  end
  if GetSpellInfo then return ns.plain(select(6, GetSpellInfo(id))) end
end

-- Returns reach (true/false/nil for unknown) and the distance text.
-- A party or raid member: the exact distance (UnitDistanceSquared). Anyone
-- else: the game gives addons no position, so the distance is bracketed by
-- every spellbook spell that has a range, plus the interact distances
-- (about 10, 11 and 28 yd) out of combat.
local INTERACT = { [3] = 10, [2] = 11, [4] = 28 }

local function exactYards(unit)
  if not UnitDistanceSquared then return nil end
  local ok, d2, checked = pcall(UnitDistanceSquared, unit)
  d2, checked = ok and ns.plain(d2), ok and ns.plain(checked)
  if checked and type(d2) == "number" and d2 >= 0 then return math.sqrt(d2) end
end

function ns.units.range()
  if not UnitExists("target") or UnitIsUnit("target", "player") then return nil end
  local inMin, outMax, longest, longestIn
  local function note(r, hit)
    if type(r) ~= "number" or r <= 0 or hit == nil then return end
    if hit then inMin = math.min(inMin or r, r) else outMax = math.max(outMax or r, r) end
    if not longest or r > longest then longest, longestIn = r, hit end
  end
  local seen = {}
  -- Spells: the spellbook if we have it, else the Glance keys.
  local book = ns.keybar and ns.keybar.bookSpells
  if book and #book > 0 and C_Spell and C_Spell.IsSpellInRange then
    for _, id in ipairs(book) do
      if not seen[id] then
        seen[id] = true
        local r = spellRange(id)
        if type(r) == "number" and r > 0 then
          local ok, hit = pcall(C_Spell.IsSpellInRange, id, "target")
          if ok then hit = ns.plain(hit) else hit = nil end
          if hit ~= nil then note(r, hit and true or false) end
        end
      end
    end
  elseif GetActionInfo then
    for _, b in pairs(ns.keybar and ns.keybar.buttons or {}) do
      for _, slot in ipairs({ b.plainSlot, b.shiftSlot }) do
        if slot and not seen[slot] then
          seen[slot] = true
          local kind, id = GetActionInfo(slot)
          kind, id = ns.plain(kind), ns.plain(id)
          local r = (kind == "spell" and type(id) == "number") and spellRange(id) or nil
          if type(r) == "number" and r > 0 then
            local hit = ns.plain(ns.api.IsActionInRange(slot))
            if hit ~= nil then note(r, hit and true or false) end
          end
        end
      end
    end
  end
  local exact = exactYards("target")
  if not longest and not exact then return nil end
  -- Interact distances refine the bracket (not in combat: blocked there).
  if CheckInteractDistance and not InCombatLockdown() then
    for idx, yd in pairs(INTERACT) do
      local ok, hit = pcall(CheckInteractDistance, "target", idx)
      if ok then hit = ns.plain(hit) else hit = nil end
      if hit ~= nil then
        if hit then inMin = math.min(inMin or yd, yd) else outMax = math.max(outMax or yd, yd) end
      end
    end
  end
  local text
  if exact then text = string.format("%d yd", exact + 0.5)
  elseif inMin and outMax and outMax < inMin then text = outMax .. "-" .. inMin .. " yd"
  elseif inMin then text = "< " .. inMin .. " yd"
  elseif outMax then text = "> " .. outMax .. " yd" end
  if longest == nil then return nil, text end
  return longestIn and true or false, text
end

local function paintRange()
  local f = frames.target
  if not (f and f.range) then return end
  local reach, text = ns.units.range()
  if reach == nil and text then
    f.range:SetText(text)
    f.range:SetTextColor(0.9, 0.9, 0.9)
    f.edge:Hide()
    return
  end
  if reach == nil then
    f.range:SetText("")
    f.edge:Hide()
    return
  end
  local r, g, b = 0.35, 0.9, 0.4
  if not reach then r, g, b = 1, 0.3, 0.25 end
  f.range:SetText(text)
  f.range:SetTextColor(r, g, b)
  f.edge:SetColorTexture(r, g, b, 0.8)
  f.edge:Show()
end
ns.units.paintRange = paintRange

local function addRange(f)
  f.edge = f:CreateTexture(nil, "BACKGROUND")
  f.edge:SetPoint("TOPLEFT", f.hp, "TOPLEFT", -2, 2)
  f.edge:SetPoint("BOTTOMRIGHT", f.mp, "BOTTOMRIGHT", 2, -2)
  f.edge:Hide()
  f.range = f:CreateFontString(nil, "OVERLAY", FONT)
  f.range:SetPoint("TOPRIGHT", f.mp, "BOTTOMRIGHT", 0, -3)
  if f.range.SetFont and STANDARD_TEXT_FONT then f.range:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE") end
end

---------------------------------------------------------------------------
-- Cast bar
---------------------------------------------------------------------------
local cast
-- Cast and channel times can be secret, so the bar runs on the game's own
-- timer (SetTimerDuration with UnitCastingDuration) where the client has
-- it, and on our own sums only where the times are plain numbers.
local function castUpdate()
  local channel = false
  local n = select("#", UnitCastingInfo("player"))
  local name, _, _, startMS, endMS = UnitCastingInfo("player")
  if n == 0 then
    n = select("#", UnitChannelInfo("player"))
    name, _, _, startMS, endMS = UnitChannelInfo("player")
    channel = true
  end
  if n == 0 then cast:Hide() return end
  cast.text:SetText(name)
  cast.channel = channel
  cast.startMS, cast.endMS = ns.plain(startMS), ns.plain(endMS)
  cast.timer = false
  local durFn = channel and UnitChannelDuration or UnitCastingDuration
  if cast.bar.SetTimerDuration and durFn and not (cast.startMS and cast.endMS) then
    local ok = pcall(function()
      local d = durFn("player")
      local E = Enum or {}
      local interp = E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate
      local dirs = E.StatusBarTimerDirection
      local dir = dirs and (channel and dirs.RemainingTime or dirs.ElapsedTime)
      cast.bar:SetTimerDuration(d, interp, dir)
    end)
    cast.timer = ok
  end
  if not cast.timer and cast.startMS and cast.endMS then
    cast.bar:SetMinMaxValues(cast.startMS, cast.endMS)
  end
  cast.time:SetText("")
  cast:Show()
end

local function makeCast()
  cast = CreateFrame("Frame", "GlanceCastBar", UIParent)
  cast:SetSize(260, 14)
  cast:SetPoint("TOP", UIParent, "CENTER", 0, -152)
  cast.bar = bar(cast, 14)
  cast.bar:SetAllPoints()
  cast.bar:SetStatusBarColor(0.45, 0.7, 1)
  cast.text = cast.bar:CreateFontString(nil, "OVERLAY", FONT)
  cast.text:SetPoint("LEFT", 5, 0)
  cast.time = cast.bar:CreateFontString(nil, "OVERLAY", FONT)
  cast.time:SetPoint("RIGHT", -5, 0)
  cast:Hide()
  cast:SetScript("OnUpdate", function(self)
    if self.timer or not (self.startMS and self.endMS) then return end
    ns.safe("cast bar", function()
      local now = GetTime() * 1000
      if self.channel then
        self.bar:SetValue(self.startMS + self.endMS - now)
      else
        self.bar:SetValue(now)
      end
      self.time:SetFormattedText("%.1f", math.max(0, (self.endMS - now) / 1000))
    end)
  end)
  ns.units.cast = cast
end

ns.module("units", function()
  if ns.db.hideBlizzard then
    ns.outOfCombat("hide unit frames", function()
      ns.hideFrame(PlayerFrame)
      ns.hideFrame(TargetFrame)
      ns.hideFrame(PlayerCastingBarFrame or CastingBarFrame)
    end)
  end
  ns.outOfCombat("unit frames", function()
    update(makeUnit("player", -(W / 2 + 8)))
    local t = makeUnit("target", W / 2 + 8)
    addRange(t)
    RegisterUnitWatch(t)
    update(t)
  end)
  makeCast()
  local function refresh(unit)
    if not unit or frames[unit] then
      for u, f in pairs(frames) do
        if not unit or u == unit then ns.safe("unit " .. u, update, f) end
      end
    end
  end
  for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
      "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE",
      "UNIT_LEVEL", "UNIT_FACTION" }) do
    ns.on(ev, refresh)
  end
  ns.on("PLAYER_TARGET_CHANGED", function() refresh("target"); ns.safe("range", paintRange) end)
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.2, function() ns.safe("range", paintRange) end)
  end
  ns.on("PLAYER_ENTERING_WORLD", function() refresh() end)
  for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
      "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
      "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
    ns.on(ev, function(unit) if unit == "player" then castUpdate() end end)
  end
end)
