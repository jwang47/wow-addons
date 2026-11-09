-- Glance units: small player and target bars that float under your
-- character, and a cast bar below them. Values go straight to the status
-- bars (no maths on them), so the newer clients' hidden numbers still work.
local addonName, ns = ...

local W, HP_H, MP_H = 170, 9, 5
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
  return b
end

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
  if UnitIsTapDenied and UnitIsTapDenied(unit) then return 0.55, 0.55, 0.55 end
  local r = UnitReaction(unit, "player")
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
  f.level:SetText((lvl and lvl > 0) and lvl or "??")
  f.hp:SetMinMaxValues(0, UnitHealthMax(u))
  f.hp:SetValue(UnitHealth(u))
  f.hp:SetStatusBarColor(ns.units.healthColor(u))
  local maxp = UnitPowerMax(u)
  f.mp:SetMinMaxValues(0, maxp)
  f.mp:SetValue(UnitPower(u))
  f.mp:SetStatusBarColor(powerColor(u))
  f.mp:SetShown(not (maxp == 0))
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
-- Cast bar
---------------------------------------------------------------------------
local cast
local function castInfo()
  local name, _, _, startMS, endMS = UnitCastingInfo("player")
  if name then return name, startMS, endMS, false end
  name, _, _, startMS, endMS = UnitChannelInfo("player")
  if name then return name, startMS, endMS, true end
end

local function castUpdate()
  local name, startMS, endMS, channel = castInfo()
  if not name then cast:Hide() return end
  cast.text:SetText(name)
  cast.bar:SetMinMaxValues(startMS, endMS)
  cast.channel = channel
  cast.startMS, cast.endMS = startMS, endMS
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
  ns.on("PLAYER_TARGET_CHANGED", function() refresh("target") end)
  ns.on("PLAYER_ENTERING_WORLD", function() refresh() end)
  for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
      "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
      "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
    ns.on(ev, function(unit) if unit == "player" then castUpdate() end end)
  end
end)
