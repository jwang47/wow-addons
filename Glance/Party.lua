-- Glance party: make party members easy to find in the world. While you
-- are in a group, friendly player nameplates are on (class colours), and
-- each party member gets a large class-coloured name above their nameplate.
-- Your own nameplate settings come back when you leave the group.
-- /glance party on|off.
local addonName, ns = ...
local party = { labels = {} }
ns.party = party

-- CVars Glance sets in a group, and their values there.
local CVARS = {
  nameplateShowFriendlyPlayers = "1",
  nameplateShowFriendlyClassColor = "1",
  UnitNameFriendlyPlayerName = "1",
}

local function inGroup() return IsInGroup and IsInGroup() and true or false end

local function isPartyUnit(unit)
  if not (UnitExists(unit) and UnitIsPlayer and UnitIsPlayer(unit)) then return false end
  if UnitIsUnit(unit, "player") then return false end
  local ok, yes = pcall(function()
    return (UnitInParty and UnitInParty(unit)) or (UnitInRaid and UnitInRaid(unit)) or UnitPlayerOrPetInParty and UnitPlayerOrPetInParty(unit)
  end)
  return ok and ns.plain(yes) and true or false
end

-- Turn the group CVars on (saving yours) or put yours back. Out of combat.
function party.applyCVars()
  if not SetCVar then return end
  ns.outOfCombat("partycvars", function()
    local want = ns.db.party ~= false and inGroup()
    if want and not ns.db.partySaved then
      local saved = {}
      for k in pairs(CVARS) do saved[k] = GetCVar and GetCVar(k) end
      ns.db.partySaved = saved
      for k, v in pairs(CVARS) do pcall(SetCVar, k, v) end
    elseif not want and ns.db.partySaved then
      for k, v in pairs(ns.db.partySaved) do
        if v ~= nil then pcall(SetCVar, k, v) end
      end
      ns.db.partySaved = nil
    end
  end)
end

local function label(unit)
  local l = party.labels[unit]
  if l then return l end
  l = CreateFrame("Frame", nil, UIParent)
  l:SetSize(1, 1)
  l:SetFrameStrata("LOW")
  l.text = l:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  l.text:SetPoint("BOTTOM", l, "TOP", 0, 0)
  if l.text.SetFont and STANDARD_TEXT_FONT then l.text:SetFont(STANDARD_TEXT_FONT, 15, "THICKOUTLINE") end
  l.bar = l:CreateTexture(nil, "OVERLAY")
  l.bar:SetSize(30, 3)
  l.bar:SetPoint("TOP", l.text, "BOTTOM", 0, -1)
  l:Hide()
  party.labels[unit] = l
  return l
end

function party.show(unit)
  if ns.db.party == false or not isPartyUnit(unit) then return end
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then return end
  local l = label(unit)
  local r, g, b = 0.4, 0.9, 1
  local _, class = UnitClass(unit)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then r, g, b = c.r, c.g, c.b end
  l.text:SetText(UnitName(unit))
  l.text:SetTextColor(r, g, b)
  l.bar:SetColorTexture(r, g, b, 0.9)
  l:ClearAllPoints()
  l:SetPoint("BOTTOM", plate, "TOP", 0, 6)
  l:Show()
end

function party.hide(unit)
  local l = party.labels[unit]
  if l then l:Hide() end
end

function party.refreshAll()
  for unit, l in pairs(party.labels) do l:Hide() end
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then party.show(unit) end
  end
end

ns.commands.party = function(rest)
  rest = (rest or ""):lower()
  if rest == "on" then ns.db.party = true
  elseif rest == "off" then ns.db.party = false
  else
    return ns.print("/glance party on|off - large names over party members (now " .. (ns.db.party == false and "off" or "on") .. ")")
  end
  party.applyCVars()
  party.refreshAll()
  ns.print("Party names " .. rest .. ".")
end

ns.module("party", function()
  ns.on("NAME_PLATE_UNIT_ADDED", function(unit) party.show(unit) end)
  ns.on("NAME_PLATE_UNIT_REMOVED", function(unit) party.hide(unit) end)
  ns.on("GROUP_ROSTER_UPDATE", function() party.applyCVars(); party.refreshAll() end)
  ns.on("PLAYER_ENTERING_WORLD", function() party.applyCVars(); party.refreshAll() end)
  party.applyCVars()
end)
