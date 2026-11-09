-- UpgradeFinder Weights panel: one box per stat, and presets. It opens beside
-- the Upgrades window (the Weights button, or /uf config). The panel and the
-- slash commands share ns.setWeight, ns.resetWeights and the preset functions.
local _, ns = ...
local S = ns.score
local panel, boxes, ui = nil, {}, { presets = {} }
local COLS, CELL_H, PRESETS = 2, 21, 6

local function call(fn, ...) if type(fn) == "function" then return fn(...) end end
local function num(v)
  local s = string.format("%.3f", v or 0):gsub("0+$", ""):gsub("%.$", "")
  return s
end

-- The default weight of a stat for your spec (what "reset" goes back to).
local function default(stat)
  return S.weightsFor(ns.class(), nil, ns.talentTab())[stat] or 0
end

function ns.paintWeights()
  if not panel then return end
  local w, _, spec = ns.weights(), ns.weightKey()
  local name = ns.weightsName()
  ui.title:SetText("Weights |cff9d9d9d(" .. (spec or ns.class():lower()) .. ", " .. (name or "default") .. ")|r")
  for stat, box in pairs(boxes) do
    if not call(box.HasFocus, box) then box:SetText(num(w[stat])) end
    local changed = math.abs((w[stat] or 0) - default(stat)) > 1e-9
    if changed then box:SetTextColor(1, 0.82, 0) else box:SetTextColor(1, 1, 1) end
  end
  local names = ns.presetNames()
  local active = ns.db().active[ns.weightKey()]
  for i, b in ipairs(ui.presets) do
    local n = names[i]
    b.preset = n
    if n then
      b:SetText(n == active and ("|cffffd100" .. n .. "|r") or n)
      b:Show()
    else b:Hide() end
  end
  local more = #names - PRESETS
  ui.more:SetText(more > 0 and (more .. " more: /uf presets, /uf load NAME") or "")
  local mm = ns.class() == "MAGE" and type(rawget(_G, "MageMentorAPI")) == "table"
  ui.note:SetText(mm and "|cffff8040A mage with MageMentor uses MageMentor's weights (/mm weight).|r"
    or "Gold: changed from the default. Enter or click away to apply.")
end

-- A stat box was edited: an empty box is the default again.
local function commit(stat, box)
  local text = (box:GetText() or ""):gsub("%s", "")
  local v = tonumber(text)
  local cur = ns.weights()[stat] or 0
  if text == "" then ns.setWeight(stat, nil)
  elseif v and math.abs(v - cur) > 1e-9 then ns.setWeight(stat, v)
  else ns.paintWeights() return end
  ns.reweigh()
end

local function build()
  local main = ns.frame
  panel = CreateFrame("Frame", "UpgradeFinderWeights", main, rawget(_G, "BackdropTemplateMixin") and "BackdropTemplate" or nil)
  panel:SetSize(300, 430)
  panel:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
  panel:EnableMouse(true)
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
    panel:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
  end
  ui.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

  -- Stat boxes, two columns.
  local stats = ns.statList()
  local rowsPer = math.ceil(#stats / COLS)
  for i, stat in ipairs(stats) do
    local col, row = math.floor((i - 1) / rowsPer), (i - 1) % rowsPer
    local x, y = 14 + col * 140, -36 - row * CELL_H
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y - 3)
    label:SetText(stat)
    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(56, 18)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x + 62, y)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() commit(stat, self) end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() ns.paintWeights() end)
    box:SetScript("OnEditFocusLost", function(self) commit(stat, self) end)
    box:SetScript("OnEnter", function(self)
      local tt = rawget(_G, "GameTooltip")
      if not tt then return end
      tt:SetOwner(self, "ANCHOR_RIGHT")
      tt:AddLine(stat .. ": default " .. num(default(stat)))
      tt:AddLine("Empty the box for the default.", 0.7, 0.7, 0.7)
      tt:Show()
    end)
    box:SetScript("OnLeave", function() local tt = rawget(_G, "GameTooltip") if tt then tt:Hide() end end)
    boxes[stat] = box
  end

  -- Presets: a name box, Save, Defaults; then one button per preset.
  local y = -36 - rowsPer * CELL_H - 10
  local head = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
  head:SetText("Presets")
  y = y - 16
  ui.name = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  ui.name:SetSize(120, 20)
  ui.name:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y)
  ui.name:SetAutoFocus(false)
  local function save()
    local n = (ui.name:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-")
    if n == "" then ns.say("type a name for the preset first") return end
    ns.savePreset(n)
    ui.name:SetText("")
    ui.name:ClearFocus()
    ns.say("saved your weights as \"" .. n .. "\"")
    ns.paintWeights()
  end
  ui.name:SetScript("OnEnterPressed", save)
  ui.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  ui.save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  ui.save:SetSize(56, 20)
  ui.save:SetPoint("LEFT", ui.name, "RIGHT", 6, 0)
  ui.save:SetText("Save")
  ui.save:SetScript("OnClick", save)
  ui.reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  ui.reset:SetSize(70, 20)
  ui.reset:SetPoint("LEFT", ui.save, "RIGHT", 4, 0)
  ui.reset:SetText("Defaults")
  ui.reset:SetScript("OnClick", function()
    ns.resetWeights()
    ns.reweigh("weights back to the defaults")
  end)
  y = y - 26
  for i = 1, PRESETS do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(132, 20)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + ((i - 1) % 2) * 140, y - math.floor((i - 1) / 2) * 22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
      local n = self.preset
      if not n then return end
      if button == "RightButton" then
        if call(rawget(_G, "IsShiftKeyDown")) then
          ns.deletePreset(n)
          ns.say("deleted preset \"" .. n .. "\"")
          ns.paintWeights()
        else ns.say("shift-right-click deletes \"" .. n .. "\"") end
        return
      end
      ns.loadPreset(n)
      ns.reweigh("weights: preset \"" .. n .. "\"")
    end)
    b:Hide()
    ui.presets[i] = b
  end
  y = y - math.ceil(PRESETS / 2) * 22 - 4
  ui.more = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ui.more:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
  ui.note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ui.note:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y - 14)
  ui.note:SetWidth(272)
  ui.note:SetJustifyH("LEFT")
  local help = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  help:SetPoint("TOPLEFT", ui.note, "BOTTOMLEFT", 0, -4)
  help:SetWidth(272)
  help:SetJustifyH("LEFT")
  help:SetText("Click a preset to load it; shift-right-click deletes it.")
  ns.weightsUI, ns.weightsBoxes = ui, boxes
end

-- Show or hide the panel; show = true keeps it open.
function ns.toggleWeights(show)
  if not ns.frame then return end
  if not panel then build() end
  if panel:IsShown() and not show then panel:Hide() return end
  panel:Show()
  ns.paintWeights()
end
