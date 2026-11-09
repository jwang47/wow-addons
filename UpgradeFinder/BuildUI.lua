-- UpgradeFinder Build window (/uf build, or the Build button on Upgrades):
-- 18 slot buttons on the left, the sheet on the right (now, with the build,
-- change), and the build controls at the bottom. Put an item in a slot by
-- dropping it there (from your bags) or Alt-clicking an Upgrades row.
local _, ns = ...
local B = ns.build
local call, api = ns.call, ns.api
local frame, slots, cells, ui = nil, {}, {}, {}
local ROWS, W, H = 14, 560, 440
B.base = nil -- compare against: nil = what you wear, or a saved build name

local SLOT_LABEL = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
  "Ring", "Ring", "Trinket", "Trinket", "Back", "Main hand", "Off hand", "Ranged" }
local LEFT = { 1, 2, 3, 15, 5, 4, 9, 10, 6 }
local RIGHT = { 7, 8, 11, 12, 13, 14, 16, 17, 18 }

local function say(msg) if ns.say then ns.say(msg) end end

function ns.paintBuild(tries)
  if not frame or not frame:IsShown() then return end
  local items = B.items()
  local worn = B.worn()
  for slot, b in pairs(slots) do
    local link = items[slot]
    local id = B.idOf(link)
    b.icon:SetTexture(id and call(api("C_Item.GetItemIconByID"), id) or 136528)
    b.icon:SetDesaturated(not link)
    local changed = B.work[slot] ~= nil and link ~= worn[slot]
    if changed then b.mark:Show() else b.mark:Hide() end
  end
  local base = B.base and B.get(B.base) or nil
  local ok, sheet = pcall(B.sheet, items, base)
  for i = 1, ROWS do
    local r = ok and sheet.rows[i]
    local c = cells[i]
    if r then
      c[1]:SetText(r[1]) c[2]:SetText(r[2]) c[3]:SetText(r[3])
      c[4]:SetText(r[4] ~= "" and ((r[5] and "|cff40ff40" or "|cffff6060") .. r[4] .. "|r") or "")
    else
      for j = 1, 4 do c[j]:SetText("") end
    end
  end
  ui.head:SetText("|cff9d9d9d" .. (B.base and ("vs " .. B.base) or "Now") .. "|r")
  local rot = ok and sheet.rotation
  if rot and #rot.parts > 0 then
    local parts = {}
    for i = 1, math.min(4, #rot.parts) do
      table.insert(parts, string.format("%s %d%%", rot.parts[i][1].name, math.floor(rot.parts[i][3] * 100 + 0.5)))
    end
    ui.rotation:SetText("Rotation: " .. table.concat(parts, ", "))
  else
    ui.rotation:SetText(ok and sheet.role == "caster" and "Put damage spells on your action bars for a DPS number." or "")
  end
  ui.changes:SetText(ok and next(sheet.diff) and ("Changes: " .. ns.stats.statLine(sheet.diff)) or
    "Changes: none. Drop an item on a slot, or Alt-click an Upgrades row.")
  ui.status:SetText(ok and sheet.loading > 0 and string.format("|cff9d9d9dLoading %d items...|r", sheet.loading) or "")
  ui.compare:SetText("Compare: " .. (B.base or "worn"))
  ui.builds:SetText(#B.names() > 0 and ("Builds (" .. #B.names() .. ")") or "No builds")
  if ok and sheet.loading > 0 and (tries or 0) < 10 then
    call(api("C_Timer.After"), 0.5, function() ns.paintBuild((tries or 0) + 1) end)
  end
  if not ok then ui.status:SetText("|cffff6060" .. tostring(sheet) .. "|r") end
end

-- Put the item on the cursor into a slot (it must fit there).
local function dropOn(slot)
  local kind, _, link = call(rawget(_G, "GetCursorInfo"))
  if kind ~= "item" or not link then return false end
  local loc = ns.scan.equipLoc(B.idOf(link))
  local fits = ns.score.SLOTS[loc or ""]
  local ok = false
  for _, s in ipairs(fits or {}) do if s == slot then ok = true end end
  call(rawget(_G, "ClearCursor"))
  if not ok then say("that item does not go in the " .. SLOT_LABEL[slot]:lower() .. " slot") return true end
  B.set(slot, link)
  ns.paintBuild()
  return true
end
B.dropOn = dropOn

local function slotTip(b)
  local tt = rawget(_G, "GameTooltip")
  if not tt then return end
  tt:SetOwner(b, "ANCHOR_RIGHT")
  local link = B.items()[b.slot]
  if link then tt:SetHyperlink(link) else tt:AddLine(SLOT_LABEL[b.slot] .. ": empty") end
  tt:AddLine(" ")
  tt:AddLine("Drop an item here to try it. Right-click: back to what you wear.", 0.6, 0.6, 0.6, true)
  tt:AddLine("Shift-right-click: leave the slot empty.", 0.6, 0.6, 0.6)
  tt:Show()
end

local function newButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 20)
  b:SetText(text)
  return b
end

local function buildFrame()
  frame = CreateFrame("Frame", "UpgradeFinderBuild", UIParent, rawget(_G, "BackdropTemplateMixin") and "BackdropTemplate" or nil)
  ns.buildFrame = frame
  frame:SetSize(W, H)
  frame:SetPoint("CENTER", UIParent, "CENTER", -200, 40)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
  end
  local special = rawget(_G, "UISpecialFrames")
  if type(special) == "table" then table.insert(special, "UpgradeFinderBuild") end
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
  title:SetText("Build")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

  -- Slots: two columns of 9.
  local SIZE, GAP = 34, 4
  local function slotButton(slot, x, y)
    local b = CreateFrame("Button", nil, frame)
    b.slot = slot
    b:SetSize(SIZE, SIZE)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.mark:SetColorTexture(1, 0.82, 0, 0.35)
    b.mark:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnReceiveDrag", function() dropOn(slot) end)
    b:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
        if call(rawget(_G, "IsShiftKeyDown")) then B.clear(slot) else B.unset(slot) end
        ns.paintBuild()
      else
        dropOn(slot)
      end
    end)
    b:SetScript("OnEnter", slotTip)
    b:SetScript("OnLeave", function() local tt = rawget(_G, "GameTooltip") if tt then tt:Hide() end end)
    slots[slot] = b
  end
  for i, slot in ipairs(LEFT) do slotButton(slot, 12, -34 - (i - 1) * (SIZE + GAP)) end
  for i, slot in ipairs(RIGHT) do slotButton(slot, 12 + SIZE + 8, -34 - (i - 1) * (SIZE + GAP)) end

  -- The sheet: label, now (or the compared build), with this build, change.
  local X = 104
  local heads = { { "", 130 }, { "Now", 74 }, { "Build", 74 }, { "Change", 120 } }
  local x = X
  for j, h in ipairs(heads) do
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -36)
    fs:SetWidth(h[2])
    fs:SetJustifyH(j == 1 and "LEFT" or "RIGHT")
    fs:SetText(h[1])
    if j == 2 then ui.head = fs end
    x = x + h[2] + 6
  end
  for i = 1, ROWS do
    cells[i] = {}
    x = X
    for j, h in ipairs(heads) do
      local fs = frame:CreateFontString(nil, "OVERLAY", j == 1 and "GameFontNormalSmall" or "GameFontHighlightSmall")
      fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -54 - (i - 1) * 18)
      fs:SetWidth(h[2])
      fs:SetJustifyH(j == 1 and "LEFT" or "RIGHT")
      cells[i][j] = fs
      x = x + h[2] + 6
    end
  end
  ui.rotation = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.rotation:SetPoint("TOPLEFT", frame, "TOPLEFT", X, -54 - ROWS * 18 - 4)
  ui.rotation:SetWidth(W - X - 12)
  ui.rotation:SetJustifyH("LEFT")
  ui.changes = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.changes:SetPoint("TOPLEFT", ui.rotation, "BOTTOMLEFT", 0, -6)
  ui.changes:SetWidth(W - X - 12)
  ui.changes:SetJustifyH("LEFT")
  ui.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -12)

  -- Bottom row: name, Save, Builds (load the next), Compare, Reset.
  local name = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  name:SetSize(110, 20)
  name:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 12)
  name:SetAutoFocus(false)
  name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  ui.name = name
  local save = newButton(frame, "Save", 52)
  save:SetPoint("LEFT", name, "RIGHT", 6, 0)
  save:SetScript("OnClick", function()
    local n = (name:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if n == "" then say("type a name for the build first") return end
    B.save(n)
    say("build saved: " .. n)
    ns.paintBuild()
  end)
  ui.save = save
  -- Builds: click loads the next saved build; shift-right-click deletes it.
  local builds = newButton(frame, "Builds", 96)
  builds:SetPoint("LEFT", save, "RIGHT", 6, 0)
  builds:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  builds:SetScript("OnClick", function(_, button)
    local names = B.names()
    if #names == 0 then say("no saved builds yet: type a name and Save") return end
    if button == "RightButton" then
      if call(rawget(_G, "IsShiftKeyDown")) and ui.loaded then
        B.delete(ui.loaded)
        say("build deleted: " .. ui.loaded)
        ui.loaded = nil
      else say("shift-right-click deletes the loaded build") end
      ns.paintBuild()
      return
    end
    local i = 1
    for k, n in ipairs(names) do if n == ui.loaded then i = k % #names + 1 end end
    ui.loaded = names[i]
    B.load(names[i])
    name:SetText(names[i])
    say("build loaded: " .. names[i])
    ns.paintBuild()
  end)
  ui.builds = builds
  -- Compare: worn, then each saved build.
  local compare = newButton(frame, "Compare: worn", 140)
  compare:SetPoint("LEFT", builds, "RIGHT", 6, 0)
  compare:SetScript("OnClick", function()
    local names, nextName = B.names(), nil
    if not B.base then nextName = names[1]
    else for k, n in ipairs(names) do if n == B.base then nextName = names[k + 1] end end end
    B.base = nextName
    ns.paintBuild()
  end)
  ui.compare = compare
  local reset = newButton(frame, "Reset", 60)
  reset:SetPoint("LEFT", compare, "RIGHT", 6, 0)
  reset:SetScript("OnClick", function() B.reset() ui.loaded = nil name:SetText("") ns.paintBuild() end)
  ui.reset = reset
  frame:SetScript("OnShow", function() ns.paintBuild() end)
end
ns.buildUI = ui
ns.buildSlots = slots

function ns.toggleBuild(show)
  if not frame then buildFrame() end
  if show == nil then show = not frame:IsShown() end
  if show then frame:Show() ns.paintBuild() else frame:Hide() end
end

-- An Upgrades row into the build: the slot it would replace.
function ns.rowToBuild(r)
  local worn = ns.scan.worn()
  local slotsFor = ns.score.replacedSlots(r.loc, worn.value or {}, worn.twoHander, worn.dualWield)
  if not slotsFor or not slotsFor[1] then return false end
  B.set(slotsFor[1], "item:" .. r.id)
  if ns.score.SLOTS[r.loc] and ns.score.SLOTS[r.loc].both then B.clear(17) end
  ns.toggleBuild(true)
  return true
end
