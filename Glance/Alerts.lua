-- Glance alerts: a Reload button, then small amber chips under the minimap for things you can
-- spend or fix: unspent talent points, legacy points, keys with an old
-- spell rank, full bags. A chip shows only while there is something to do;
-- a click opens the matching window.
local addonName, ns = ...
local mm = ns.minimap
local alerts = { chips = {} }
ns.alerts = alerts

local plain = function(v) return ns.plain(v) end

-- Each check returns a count (0 or nil = nothing to do).
local function unspentTalents()
  if UnitCharacterPoints then
    local n = plain(UnitCharacterPoints("player"))
    if type(n) == "number" and n > 0 then return n end
  end
  if GetUnspentTalentPoints then
    local ok, n = pcall(GetUnspentTalentPoints)
    n = ok and plain(n)
    if type(n) == "number" and n > 0 then return n end
  end
  if C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
    local ok, has = pcall(C_ClassTalents.HasUnspentTalentPoints)
    if ok and plain(has) then return 1 end
  end
  return 0
end

-- Legacy points: the currency of the Legacy trees (Forever). Same call the
-- game's Legacy window uses.
local function legacyPoints()
  local LC = Constants and Constants.LegacyConsts
  if not (LC and C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetTreeCurrencyInfo) then return 0 end
  if C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
    local lvl = plain(C_MajorFactions.GetCurrentRenownLevel(LC.LEGACY_REWARD_TRACK_FACTION_ID))
    if type(lvl) == "number" and lvl <= 0 then return 0 end
  end
  local tree = LC.LEGACY_TREE_PROFESSIONS_ID
  local config = C_Traits.GetConfigIDByTreeID(tree)
  if not config then return 0 end
  local info = C_Traits.GetTreeCurrencyInfo(config, tree, false)
  local q = info and info[1] and plain(info[1].quantity)
  return type(q) == "number" and q or 0
end

local function oldRanks()
  local n = 0
  for _, b in pairs(ns.keybar and ns.keybar.buttons or {}) do
    for _, slot in ipairs({ b.plainSlot, b.shiftSlot }) do
      if slot and ns.keybar.betterRank(slot) then n = n + 1 end
    end
  end
  return n
end

local function freeBagSlots()
  if not (C_Container and C_Container.GetContainerNumFreeSlots) then return nil end
  local free = 0
  for bag = 0, 4 do
    local n = plain(C_Container.GetContainerNumFreeSlots(bag))
    free = free + (type(n) == "number" and n or 0)
  end
  return free
end

local function open(fn, ...) if type(fn) == "function" then pcall(fn, ...) end end

alerts.list = {
  { key = "talents", label = "Talents", count = unspentTalents, click = function()
      if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentOrSpecFrame then
        open(PlayerSpellsUtil.ToggleClassTalentOrSpecFrame)
      else open(ToggleTalentFrame) end
    end },
  { key = "legacy", label = "Legacy", count = legacyPoints, click = function() open(ToggleLegacySystemUI) end },
  { key = "ranks", label = "Ranks", count = oldRanks, tip = "Keys with an old spell rank. Click: /glance ranks.",
    click = function() open(ns.commands.ranks) end },
  { key = "bags", label = "Bags full", count = function()
      local free = freeBagSlots()
      return (free and free <= 2) and 1 or 0
    end, click = function() open(ToggleAllBags) end, noNumber = true },
}

function alerts.refresh()
  if not mm.holder then return end
  local prev = alerts.reload
  for _, a in ipairs(alerts.list) do
    local c = alerts.chips[a.key]
    local ok, n = pcall(a.count)
    n = ok and n or 0
    if n and n > 0 then
      c.text:SetText(a.noNumber and a.label or (a.label .. " " .. n))
      c:SetWidth((c.text.GetStringWidth and c.text:GetStringWidth() or 50) + 12)
      c:ClearAllPoints()
      c:SetPoint("LEFT", prev, "RIGHT", 4, 0)
      c:Show()
      prev = c
    else
      c:Hide()
    end
  end
end

ns.module("alerts", function()
  if not (mm.holder and mm.chip) then return end
  -- Reload: always there, first on the row (handy after an addon update).
  local r = mm.chip(mm.holder, "Reload")
  r:SetWidth(50)
  r:SetPoint("TOPLEFT", mm.tab, "BOTTOMLEFT", 0, -3)
  r:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)
  alerts.reload = r
  for _, a in ipairs(alerts.list) do
    local c = mm.chip(mm.holder, a.label)
    c.bg:SetColorTexture(0.35, 0.22, 0.04, 0.7)
    c.text:SetTextColor(1, 0.8, 0.35)
    c:SetScript("OnClick", function()
      if InCombatLockdown() then return end
      a.click()
      alerts.refresh()
    end)
    if a.tip then
      c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(a.tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    c:Hide()
    alerts.chips[a.key] = c
  end
  for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED",
      "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "SPELLS_CHANGED",
      "ACTIONBAR_SLOT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do
    ns.on(ev, alerts.refresh)
  end
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, alerts.refresh) end
  alerts.refresh()
end)
