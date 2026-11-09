-- Glance keyboard bar: one button per key, laid out like the left hand of
-- a keyboard. A key's spell is the action slot that key fires, so moving a
-- spell to another key is a drag, not a trip to Key Bindings.
local addonName, ns = ...
local K, api = ns.keys, ns.api

local SIZE, GAP = 44, 4
local UNIT = SIZE + GAP
local MIN_X = 0.4          -- Tab's left edge
local bar, buttons = nil, {}
ns.keybar = { buttons = buttons }

local function shiftDown() return IsShiftKeyDown and IsShiftKeyDown() end

-- The slot a button shows and takes drops on now.
local function currentSlot(b)
  if shiftDown() and b.shiftSlot then return b.shiftSlot end
  return b.plainSlot or b.shiftSlot
end
ns.keybar.currentSlot = currentSlot

local function keyText(key)
  if key == "TAB" then return "Tab" end
  return key
end

---------------------------------------------------------------------------
-- Painting (not secure: textures and text may change in combat)
---------------------------------------------------------------------------
local ARROWS = { up = "^", down = "v", left = "<", right = ">", jump = "_", run = ">>" }

-- Newer clients give a duration object (it may hold secret times); older
-- ones give start and duration.
function ns.keybar.setCooldown(cd, slot)
  local AB = C_ActionBar
  if AB and AB.GetActionCooldownDuration and cd.SetCooldownFromDurationObject then
    local ok = pcall(function() cd:SetCooldownFromDurationObject(AB.GetActionCooldownDuration(slot)) end)
    if ok then return end
  end
  local start, dur = api.GetActionCooldown(slot)
  pcall(cd.SetCooldown, cd, start, dur)
end

local function paint(b)
  if b.mode ~= "slot" then return end
  local slot = currentSlot(b)
  local plain = ns.plain
  local has = slot and plain(api.HasAction(slot))
  if has then
    b.icon:SetTexture(api.GetActionTexture(slot))
    b.icon:Show()
    b.empty:Hide()
    ns.keybar.setCooldown(b.cooldown, slot)
    local usable, noMana = api.IsUsableAction(slot)
    usable, noMana = plain(usable), plain(noMana)
    local inRange = plain(api.IsActionInRange(slot))
    if inRange == false then
      b.icon:SetVertexColor(0.9, 0.3, 0.3)
    elseif usable then
      b.icon:SetVertexColor(1, 1, 1)
    elseif noMana then
      b.icon:SetVertexColor(0.45, 0.5, 1)
    else
      b.icon:SetVertexColor(0.4, 0.4, 0.4)
    end
    local count = ""
    if api.IsConsumableAction and plain(api.IsConsumableAction(slot)) and api.GetActionCount then
      count = api.GetActionCount(slot) or ""
    end
    b.count:SetText(count)
    local current = api.IsCurrentAction and plain(api.IsCurrentAction(slot))
    b.glow:SetShown(current and true or false)
    -- Same spell as another key: dim, and name that key.
    local dup = (not shiftDown()) and b.dupOf
    b.icon:SetAlpha(dup and 0.3 or 1)
    b.note:SetText(dup and ("= " .. keyText(dup)) or "")
  else
    b.icon:Hide()
    b.empty:Show()
    b.count:SetText("")
    b.glow:Hide()
    pcall(b.cooldown.Clear, b.cooldown)
  end
  -- The other layer, small in the top-right corner.
  local other = shiftDown() and b.plainSlot or b.shiftSlot
  if other and other ~= slot and plain(api.HasAction(other)) then
    b.peek:SetTexture(api.GetActionTexture(other))
    b.peek:Show()
  else
    b.peek:Hide()
  end
end

function ns.keybar.paintAll()
  for _, b in pairs(buttons) do ns.safe("paint", paint, b) end
  if bar then bar.shiftTag:SetShown(shiftDown() and true or false) end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function makeButton(key, x, y)
  local b = CreateFrame("Button", "GlanceKey" .. key, bar, "SecureActionButtonTemplate")
  b.key = key
  b:SetSize(SIZE, SIZE)
  b:SetPoint("TOPLEFT", bar, "TOPLEFT", (x - MIN_X) * UNIT, -y * UNIT)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:RegisterForDrag("LeftButton")

  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0, 0, 0, 0.35)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1)
  b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.empty = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.empty:SetPoint("CENTER")
  b.empty:SetText("+")
  -- The cooldown sweep lives on a plain overlay frame, not on the secure
  -- button: a child of a secure button is protected, and the game blocks
  -- SetCooldown on it from addon code (no sweep at all).
  b.cooldown = CreateFrame("Cooldown", nil, ns.keybar.overlay, "CooldownFrameTemplate")
  b.cooldown:SetAllPoints(b)
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetAllPoints()
  b.glow:SetColorTexture(1, 0.85, 0.3, 0.25)
  b.glow:Hide()
  b.peek = b:CreateTexture(nil, "OVERLAY")
  b.peek:SetSize(15, 15)
  b.peek:SetPoint("TOPRIGHT", -2, -2)
  b.peek:SetAlpha(0.85)
  b.label = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.label:SetPoint("BOTTOMLEFT", 3, 2)
  b.label:SetText(keyText(key))
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  b.note = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.note:SetPoint("CENTER", 0, 3)
  b.note:SetWidth(SIZE - 4)

  b:SetScript("OnDragStart", function(self)
    if InCombatLockdown() or self.mode ~= "slot" then return end
    -- Plain drag moves a spell, unless /glance lock asks for Alt.
    if not ns.db.lockDrag or ns.unlocked or (IsAltKeyDown and IsAltKeyDown()) then
      PickupAction(currentSlot(self))
      ns.keybar.paintAll()
    end
  end)
  b:SetScript("OnReceiveDrag", function(self)
    if InCombatLockdown() or self.mode ~= "slot" then return end
    PlaceAction(currentSlot(self))
    ns.keybar.paintAll()
  end)
  b:SetScript("OnEnter", function(self)
    if self.mode ~= "slot" then return end
    local slot = currentSlot(self)
    if slot and api.HasAction(slot) then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetAction(slot)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:HookScript("PostClick", function() ns.keybar.paintAll() end)
  -- Shift+key clicks its own hidden button. The game reads Shift again
  -- when it runs the click (on key up by default), so a Shift released a
  -- moment early fired the plain spell. A second button needs no Shift.
  b.shiftButton = CreateFrame("Button", "GlanceKey" .. key .. "Shift", bar, "SecureActionButtonTemplate")
  b.shiftButton:RegisterForClicks("AnyUp", "AnyDown")
  b.shiftButton:SetSize(1, 1)
  b.shiftButton:SetPoint("CENTER", b)
  b.shiftButton:SetAlpha(0)
  b.shiftButton:EnableMouse(false)
  b.shiftButton:HookScript("PostClick", function() ns.keybar.paintAll() end)
  buttons[key] = b
  return b
end

-- Point each button at its slots, bind the keys. Out of combat only.
function ns.keybar.apply()
  local map = ns.char.map
  ClearOverrideBindings(bar)
  for key, b in pairs(buttons) do
    local plain, shift = map[key], map["SHIFT-" .. key]
    b.plainSlot = plain and plain.kind == "slot" and plain.slot or nil
    b.shiftSlot = shift and shift.kind == "slot" and shift.slot or nil
    b.dupOf = plain and plain.dupOf or nil
    if b.plainSlot or b.shiftSlot then
      b.mode = "slot"
      b:SetAttribute("type", "action")
      b:SetAttribute("action", b.plainSlot or b.shiftSlot)
      -- Modified attributes need a button part: shift-action1 is Shift with
      -- the left button (a key binding clicks as LeftButton). A bare
      -- "shift-action" is never read, so Shift+key fired the plain spell.
      -- (Mouse clicks only; Shift+key uses the Shift button below.)
      b:SetAttribute("shift-action1", b.shiftSlot)
      b:SetAttribute("shift-action*", b.shiftSlot)
      b.shiftButton:SetAttribute("type", b.shiftSlot and "action" or nil)
      b.shiftButton:SetAttribute("action", b.shiftSlot)
      b.bg:SetColorTexture(0, 0, 0, 0.35)
      b.note:SetText("")
      b.label:SetTextColor(1, 1, 1)
    else
      b.mode = (plain and plain.kind) or "none"
      b:SetAttribute("type", nil)
      b.shiftButton:SetAttribute("type", nil)
      b.icon:Hide()
      b.empty:Hide()
      b.peek:Hide()
      b.count:SetText("")
      b.bg:SetColorTexture(0, 0, 0, 0.12)
      b.label:SetTextColor(0.6, 0.6, 0.6)
      if plain and plain.kind == "move" then
        b.note:SetText(ARROWS[plain.dir] or "")
      elseif plain and plain.kind == "command" then
        b.note:SetText(K.label(plain.cmd))
      else
        b.note:SetText("")
      end
    end
    for _, mod in ipairs(K.MODS) do
      local e = map[mod .. key]
      if e and e.kind == "slot" then
        -- Priority bindings: Bartender4 keeps its own override bindings on
        -- the number keys even while its bars are hidden.
        local target = (mod == "SHIFT-") and b.shiftButton or b
        SetOverrideBindingClick(bar, true, mod .. key, target:GetName(), "LeftButton")
      end
    end
  end
  ns.keybar.paintAll()
end

-- Read the bindings again and rebuild the map.
local function allBindings()
  local list = {}
  local n = GetNumBindings and GetNumBindings() or 0
  for i = 1, n do
    local cmd, _, k1, k2 = GetBinding(i)
    if k1 or k2 then table.insert(list, cmd) end
  end
  return list
end

function ns.keybar.import()
  ns.char.map = K.build(function(mk) return GetBindingAction(mk) end,
    function(s) return api.HasAction(s) and true or false end,
    allBindings, ns.char.take, ns.char.map)
end

ns.module("keybar", function()
  ns.char.take = ns.char.take or {}
  bar = CreateFrame("Frame", "GlanceKeyBar", UIParent)
  ns.keybar.frame = bar
  bar:SetSize((7.25 - MIN_X + 1) * UNIT, 4 * UNIT)
  local pos = ns.db.barPos
  if pos then
    bar:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
  else
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 14)
  end
  -- In edit mode, drag the bar by its empty space to move it.
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function(self)
    if ns.unlocked and not InCombatLockdown() then self:StartMoving() end
  end)
  bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    ns.db.barPos = { point, x, y }
  end)
  bar.edge = bar:CreateTexture(nil, "BACKGROUND")
  bar.edge:SetPoint("TOPLEFT", -6, 6)
  bar.edge:SetPoint("BOTTOMRIGHT", 6, -6)
  bar.edge:SetColorTexture(1, 0.85, 0.3, 0.15)
  bar.edge:Hide()
  bar:SetScale(ns.db.scale or 1)
  ns.keybar.overlay = CreateFrame("Frame", "GlanceKeyOverlay", UIParent)
  ns.keybar.overlay:SetAllPoints(bar)
  ns.keybar.overlay:SetFrameStrata("MEDIUM")
  ns.keybar.overlay:SetFrameLevel(50)
  ns.keybar.overlay:EnableMouse(false)
  bar.shiftTag = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.shiftTag:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
  bar.shiftTag:SetText("Shift")
  bar.shiftTag:Hide()
  bar.editTag = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.editTag:SetPoint("BOTTOM", bar, "TOP", 0, 4)
  bar.editTag:SetText("Edit: drag the gold area to move the bar. /glance edit when done.")
  bar.editTag:Hide()

  for y, row in ipairs(K.ROWS) do
    if row.lead then makeButton(row.lead, MIN_X, y - 1) end
    for i, key in ipairs(row.keys) do makeButton(key, row.x + i - 1, y - 1) end
  end

  ns.outOfCombat("keybar", function()
    if not ns.char.map then ns.keybar.import() end
    ns.keybar.apply()
  end)

  for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_COOLDOWN",
      "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE", "SPELL_UPDATE_USABLE",
      "MODIFIER_STATE_CHANGED", "PLAYER_TARGET_CHANGED", "UNIT_POWER_FREQUENT",
      "BAG_UPDATE_DELAYED", "CURSOR_CHANGED" }) do
    ns.on(ev, ns.keybar.paintAll)
  end
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.25, ns.keybar.paintAll) end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
ns.commands.edit = function()
  ns.unlocked = not ns.unlocked
  for _, fn in ipairs(ns.editHooks) do ns.safe("edit", fn, ns.unlocked) end
  if bar then
    bar.editTag:SetShown(ns.unlocked)
    bar.edge:SetShown(ns.unlocked)
    bar:EnableMouse(ns.unlocked)
  end
  ns.print(ns.unlocked and "Edit mode: drag the gold area to move the bar, the gold corner to size the map."
    or "Edit mode off.")
end

ns.commands.lock = function()
  ns.db.lockDrag = not ns.db.lockDrag
  ns.print(ns.db.lockDrag and "Keys locked: Alt-drag (or /glance edit) moves a spell."
    or "Keys unlocked: drag a spell to move it, drop it on another key to swap.")
end

ns.commands.reset = function()
  if InCombatLockdown() then return ns.print("Not in combat.") end
  ns.db.barPos = nil
  bar:ClearAllPoints()
  bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 14)
  ns.print("Keyboard bar back at the bottom centre.")
end

ns.commands.import = function()
  if InCombatLockdown() then return ns.print("Not in combat.") end
  ns.keybar.import()
  ns.keybar.apply()
  ns.print("Read your key bindings again.")
end

local function keyArg(rest)
  local k = (rest or ""):upper():gsub("%s", "")
  return k ~= "" and k or nil
end

ns.commands.take = function(rest)
  local k = keyArg(rest)
  if not k then return ns.print("/glance take KEY (for example F or SHIFT-TAB), or /glance take all") end
  if k == "ALL" then
    -- Every key with another command, except Tab (targeting) and movement.
    local n = 0
    for mk, e in pairs(ns.char.map or {}) do
      if e.kind == "command" and mk ~= "TAB" and mk ~= "SHIFT-TAB"
          and not K.isKept(e.cmd) then
        ns.char.take[mk] = true
        n = n + 1
      end
    end
    ns.print("Took " .. n .. " keys for spells. /glance free KEY gives one back.")
  else
    ns.char.take[k] = true
  end
  ns.commands.import()
end

ns.commands.free = function(rest)
  local k = keyArg(rest)
  if not k then return ns.print("/glance free KEY") end
  ns.char.take[k] = nil
  if ns.char.map then ns.char.map[k] = nil end
  ns.commands.import()
end
