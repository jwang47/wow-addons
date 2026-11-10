-- Glance bars: hide the action bars the keyboard bar replaces (Bartender4's
-- and Blizzard's), and draw a thin XP bar along the bottom edge instead of
-- the old one. Off until /glance bars hide; /glance bars show undoes it.
local addonName, ns = ...

local bars = {}
ns.bars = bars

-- Bartender4 names its bars BT4Bar<id>; Blizzard art and XP are bars too.
-- The bag bar, micro menu, pet and stance bars stay, and so do the two
-- right-edge bars (Bartender 3 and 4): click bars that the keyboard bar does
-- not replace.
local KEEP = { [3] = true, [4] = true }
local function targets()
  local list = {}
  for i = 1, 10 do
    if not KEEP[i] then table.insert(list, _G["BT4Bar" .. i]) end
  end
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

local function big(n)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  return tostring(n)
end

-- Text for the XP bar; "" when the game keeps the numbers secret.
function bars.xpText(c, m, r)
  if type(c) ~= "number" or type(m) ~= "number" or m <= 0 then return "" end
  local t = string.format("%s / %s (%.1f%%)", big(c), big(m), c / m * 100)
  if type(r) == "number" and r > 0 then t = t .. string.format("  Rested %d%%", r / m * 100 + 0.5) end
  return t
end

ns.module("bars", function()
  if ns.db.hideBars then ns.outOfCombat("hide bars", bars.hide) end

  -- XP: a 12 px bar along the bottom edge, purple, with rested XP lighter
  -- and the numbers in it.
  local xp = CreateFrame("StatusBar", "GlanceXP", UIParent)
  bars.xp = xp
  xp:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  xp:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
  xp:SetHeight(12)
  xp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  xp:SetStatusBarColor(0.64, 0.35, 0.85)
  xp.bg = xp:CreateTexture(nil, "BACKGROUND")
  xp.bg:SetAllPoints()
  xp.bg:SetColorTexture(0, 0, 0, 0.5)
  xp.rest = xp:CreateTexture(nil, "BORDER")
  xp.rest:SetPoint("TOPLEFT")
  xp.rest:SetPoint("BOTTOMLEFT")
  xp.rest:SetColorTexture(0.3, 0.5, 0.9, 0.6)
  -- "12,345 / 20,000 (61.7%)" in the bar, plus rested XP when you have it.
  xp.text = xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  xp.text:SetPoint("CENTER", 0, 0)
  if xp.text.SetFont and STANDARD_TEXT_FONT then xp.text:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE") end
  xp:SetShown(ns.db.hideBars and true or false)
  local function update()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    xp:SetMinMaxValues(0, max)
    xp:SetValue(cur)
    local c, m, r = ns.plain(cur), ns.plain(max), ns.plain(GetXPExhaustion and GetXPExhaustion() or 0)
    xp.text:SetText(bars.xpText(c, m, r))
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
