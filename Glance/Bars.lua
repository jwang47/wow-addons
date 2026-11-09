-- Glance bars: hide the action bars the keyboard bar replaces (Bartender4's
-- and Blizzard's), and draw a thin XP bar along the bottom edge instead of
-- the old one. Off until /glance bars hide; /glance bars show undoes it.
local addonName, ns = ...

local bars = {}
ns.bars = bars

-- Bartender4 names its bars BT4Bar<id>; Blizzard art and XP are bars too.
-- The bag bar, micro menu, pet and stance bars stay.
local function targets()
  local list = {}
  for i = 1, 10 do table.insert(list, _G["BT4Bar" .. i]) end
  for _, name in ipairs({ "BT4BarBlizzardArt", "BT4BarStatusTrackingBar",
      "MainActionBar", "MainMenuBar", "MainMenuBarArtFrame", "MultiBarBottomLeft",
      "MultiBarBottomRight", "StatusTrackingBarManager" }) do
    table.insert(list, _G[name])
  end
  return list
end
bars.targets = targets

function bars.hide()
  for _, f in ipairs(targets()) do
    ns.safe("hide bar", function()
      if RegisterStateDriver and f.IsProtected and f:IsProtected() then
        -- Secure bars: the game's own state driver keeps them hidden.
        RegisterStateDriver(f, "visibility", "hide")
      else
        f:Hide()
        if not f.glanceHook then
          f.glanceHook = true
          f:HookScript("OnShow", function(self) if ns.db.hideBars then self:Hide() end end)
        end
      end
    end)
  end
end

ns.module("bars", function()
  if ns.db.hideBars then ns.outOfCombat("hide bars", bars.hide) end

  -- XP: a 4 px line along the bottom edge, purple, with rested XP lighter.
  local xp = CreateFrame("StatusBar", "GlanceXP", UIParent)
  bars.xp = xp
  xp:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  xp:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
  xp:SetHeight(4)
  xp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  xp:SetStatusBarColor(0.64, 0.35, 0.85)
  xp.bg = xp:CreateTexture(nil, "BACKGROUND")
  xp.bg:SetAllPoints()
  xp.bg:SetColorTexture(0, 0, 0, 0.5)
  xp.rest = xp:CreateTexture(nil, "BORDER")
  xp.rest:SetPoint("TOPLEFT")
  xp.rest:SetPoint("BOTTOMLEFT")
  xp.rest:SetColorTexture(0.3, 0.5, 0.9, 0.6)
  xp:SetShown(ns.db.hideBars and true or false)
  local function update()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    xp:SetMinMaxValues(0, max)
    xp:SetValue(cur)
    local c, m, r = ns.plain(cur), ns.plain(max), ns.plain(GetXPExhaustion and GetXPExhaustion() or 0)
    if c and m and r and m > 0 and r > 0 then
      local w = (xp:GetWidth() or 0) * math.min(1, (c + r) / m)
      xp.rest:SetWidth(math.max(1, w))
      xp.rest:Show()
    else
      xp.rest:Hide()
    end
  end
  for _, ev in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
    ns.on(ev, update)
  end
  update()
end)

ns.commands.bars = function(rest)
  rest = (rest or ""):lower()
  if rest == "hide" then
    if InCombatLockdown() then return ns.print("Not in combat.") end
    ns.db.hideBars = true
    bars.hide()
    if bars.xp then bars.xp:Show() end
    ns.print("Hid the Bartender and Blizzard action bars, the gryphon art and the old XP bar. Bags and menu stay. /glance bars show brings them back.")
  elseif rest == "show" then
    ns.db.hideBars = false
    ns.print("Bringing the bars back. Reloading.")
    if ReloadUI then ReloadUI() end
  else
    ns.print("/glance bars hide - hide the old action bars, gryphons and XP bar; /glance bars show - bring them back")
  end
end
