-- Glance minimap: square, top-right, with the zone, coordinates and clock
-- under it. Addon buttons (LibDBIcon) fold into a drawer behind one tab.
local addonName, ns = ...

local SIZE = 190          -- default; /glance map or the edit-mode corner changes it
local MIN, MAX = 120, 400
local mm = {}
ns.minimap = mm

-- LibDBIcon and HereBeDragons (Questie) ask this to place buttons and pins.
function GetMinimapShape() return "SQUARE" end

local function hide(f)
  if type(f) == "table" then
    ns.safe("hide minimap part", function()
      f:Hide()
      f:SetAlpha(0)
      if f.EnableMouse then f:EnableMouse(false) end
    end)
  end
end

function mm.coords()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then return nil end
  return string.format("%.1f, %.1f", x * 100, y * 100)
end

function mm.clock()
  local h, m = GetGameTime()
  return string.format("%d:%02d", h, m)
end

-- Addon buttons: every LibDBIcon button, wherever it sits.
function mm.addonButtons()
  local list = {}
  local function scan(parent)
    if not parent or not parent.GetChildren then return end
    for _, child in ipairs({ parent:GetChildren() }) do
      local name = child.GetName and child:GetName()
      if name and name:match("^LibDBIcon10_") then table.insert(list, child) end
    end
  end
  scan(Minimap)
  scan(MinimapBackdrop)
  scan(mm.drawer)
  table.sort(list, function(a, b) return a:GetName() < b:GetName() end)
  return list
end

local laying = false
function mm.layoutDrawer()
  if laying or not mm.drawer then return end
  laying = true
  local list = mm.addonButtons()
  local per = 6
  for i, b in ipairs(list) do
    b:SetParent(mm.drawer)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", mm.drawer, "TOPLEFT", 4 + ((i - 1) % per) * 31, -4 - math.floor((i - 1) / per) * 31)
    b:SetScript("OnDragStart", nil)
    b:SetScript("OnDragStop", nil)
    if not b.glanceHooked then
      b.glanceHooked = true
      hooksecurefunc(b, "SetPoint", function()
        if not laying then C_Timer.After(0, mm.layoutDrawer) end
      end)
    end
  end
  local rows = math.max(1, math.ceil(#list / per))
  mm.drawer:SetSize(8 + math.min(#list, per) * 31, 8 + rows * 31)
  mm.tab.text:SetText(#list > 0 and ("Addons " .. #list) or "Addons")
  laying = false
end

local function chip(parent, text)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(16)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0, 0, 0, 0.4)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER")
  b.text:SetText(text)
  b:SetWidth(64)
  return b
end

function mm.setSize(size)
  size = math.floor(math.max(MIN, math.min(MAX, size)) + 0.5)
  ns.db.mapSize = size
  if not mm.holder then return size end
  mm.holder:SetSize(size, size)
  Minimap:SetSize(size, size)
  -- Nudge the zoom so the game redraws the map at the new size.
  local z = Minimap:GetZoom()
  Minimap:SetZoom(z > 0 and z - 1 or z + 1)
  Minimap:SetZoom(z)
  return size
end

ns.commands.map = function(rest)
  local n = tonumber(rest)
  if not n then return ns.print("/glance map SIZE, " .. MIN .. " to " .. MAX .. " (now " .. (ns.db.mapSize or SIZE) .. ")") end
  ns.print("Minimap " .. mm.setSize(n) .. " px.")
end

ns.module("minimap", function()
  local holder = CreateFrame("Frame", "GlanceMinimap", UIParent)
  mm.holder = holder
  holder:SetSize(ns.db.mapSize or SIZE, ns.db.mapSize or SIZE)
  holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -16)

  Minimap:SetParent(holder)
  Minimap:ClearAllPoints()
  Minimap:SetAllPoints(holder)
  Minimap:SetSize(ns.db.mapSize or SIZE, ns.db.mapSize or SIZE)

  -- Resizing: a grip on the bottom-left corner in /glance edit.
  local grip = CreateFrame("Button", "GlanceMinimapGrip", holder)
  mm.grip = grip
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
  grip:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 10)
  grip.tex = grip:CreateTexture(nil, "OVERLAY")
  grip.tex:SetAllPoints()
  grip.tex:SetColorTexture(1, 0.85, 0.3, 0.8)
  grip:Hide()
  grip:SetScript("OnMouseDown", function(self)
    local x, y = GetCursorPosition()
    self.from = { x = x, y = y, size = holder:GetWidth() }
  end)
  grip:SetScript("OnMouseUp", function(self) self.from = nil end)
  grip:SetScript("OnUpdate", function(self)
    if not self.from then return end
    local x, y = GetCursorPosition()
    local scale = holder:GetEffectiveScale()
    -- Dragging left or down grows the map (it hangs from the top-right).
    local grow = math.max(self.from.x - x, self.from.y - y) / scale
    mm.setSize(self.from.size + grow)
  end)
  table.insert(ns.editHooks, function(on) grip:SetShown(on) end)
  Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")
  Minimap:EnableMouseWheel(true)
  Minimap:SetScript("OnMouseWheel", function(self, d)
    local z = self:GetZoom() + (d > 0 and 1 or -1)
    if z >= 0 and z <= self:GetZoomLevels() - 1 then self:SetZoom(z) end
  end)
  -- Right-click opens tracking, as on the old round minimap.
  Minimap:HookScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      local t = MinimapCluster and MinimapCluster.Tracking
      if t and t.Button and t.Button.OpenMenu then t.Button:OpenMenu() end
    end
  end)

  local edge = holder:CreateTexture(nil, "BACKGROUND")
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(1, 1, 1, 0.25)

  hide(MinimapCompassTexture)
  hide(MinimapBorder)
  hide(MinimapBorderTop)
  hide(MinimapZoomIn)
  hide(MinimapZoomOut)
  hide(MiniMapWorldMapButton)
  hide(MinimapZoneTextButton)
  hide(GameTimeFrame)
  hide(TimeManagerClockButton)
  if MinimapCluster then
    hide(MinimapCluster.BorderTop)
    hide(MinimapCluster.ZoneTextButton)
    hide(MinimapCluster.Tracking)
    -- Blizzard's own coordinates; ours are in the line under the map.
    local box = MinimapCluster.MinimapContainer
    if type(box) == "table" then hide(box.PlayerCoords) end
  end
  hide(Minimap.ZoomIn)
  hide(Minimap.ZoomOut)
  hide(Minimap.ZoomHitArea)
  -- Mail and crafting-order icons: keep, in the bottom-left corner.
  local ind = MinimapCluster and MinimapCluster.IndicatorFrame
  if ind then
    ind:SetParent(holder)
    ind:ClearAllPoints()
    ind:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 2, 2)
  end
  if AddonCompartmentFrame then
    AddonCompartmentFrame:SetParent(holder)
    AddonCompartmentFrame:ClearAllPoints()
    AddonCompartmentFrame:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -2, -2)
  end

  -- Line 1: zone (full width). Line 2: Addons tab left, coords and clock right.
  local zone = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  zone:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -4)
  zone:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -4)
  zone:SetJustifyH("LEFT")
  zone:SetWordWrap(false)
  local info = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetPoint("TOPRIGHT", zone, "BOTTOMRIGHT", 0, -5)
  info:SetTextColor(0.78, 0.8, 0.82)
  mm.zone, mm.info = zone, info

  mm.tab = chip(holder, "Addons")
  mm.tab:SetPoint("TOPLEFT", zone, "BOTTOMLEFT", 0, -2)
  mm.drawer = CreateFrame("Frame", "GlanceAddonDrawer", holder)
  mm.drawer:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -44)
  mm.drawer.bg = mm.drawer:CreateTexture(nil, "BACKGROUND")
  mm.drawer.bg:SetAllPoints()
  mm.drawer.bg:SetColorTexture(0, 0, 0, 0.55)
  mm.drawer:SetFrameStrata("DIALOG")
  mm.drawer:Hide()
  mm.tab:SetScript("OnClick", function()
    mm.layoutDrawer()
    mm.drawer:SetShown(not mm.drawer:IsShown())
  end)

  local elapsed = 1
  holder:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    ns.safe("minimap text", function()
      zone:SetText(GetMinimapZoneText and GetMinimapZoneText() or "")
      local c = mm.coords()
      info:SetText((c and (c .. "  ") or "") .. mm.clock())
    end)
  end)

  -- Addon buttons appear as their addons load; fold them in a few times.
  ns.on("PLAYER_ENTERING_WORLD", function()
    for _, t in ipairs({ 1, 4, 10 }) do C_Timer.After(t, mm.layoutDrawer) end
  end)
end)
