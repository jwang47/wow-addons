-- BuffCheck: party buffs at a glance. A small grid shows you and your group,
-- one column for each buff your group can give. Green: on. Yellow: ends
-- soon (minutes left). Red: missing. Grey: unknown (too far, or hidden by
-- the client). Click a row to cast your buff on that person; the Next line
-- (and its key binding) buffs whoever needs it next, then a stranger who
-- buffed you, then players near you. /buffs for the commands.
local addonName, ns = ...
BuffCheck = ns                         -- global, for /dump
ns.VERSION = "0.1.0"
local M = ns.logic
local call, plain = M.call, M.plain

local defaults = {
  hidden = false,
  nearby = true,    -- offer your buff to players near you
  point = nil,      -- saved position { point, x, y }
  lastSelf = nil,   -- the self buff you cast last (Frost Armor, Mage Armor)
}

local NAME_W, CELL_W, ROW_H, PAD = 96, 34, 18, 6
local MAX_ROWS, MAX_CELLS = 5, 5
local COLOURS = {
  on = { 0.20, 0.62, 0.30 }, low = { 0.86, 0.68, 0.16 },
  off = { 0.78, 0.18, 0.16 }, unknown = { 0.32, 0.32, 0.32 },
}

local function say(msg)
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  if f then f:AddMessage("|cff9cd0ffBuffCheck|r: " .. tostring(msg)) end
end
ns.say = say

local function G(name) return rawget(_G, name) end
local function now() return plain(call(G("GetTime"))) or 0 end
local function inCombat() return call(G("InCombatLockdown")) == true end

local st = { owed = {}, skip = {}, rows = {}, next = nil, macros = {} }
ns.st = st

---------------------------------------------------------------------------
-- Reading the game
---------------------------------------------------------------------------
local function classOf(unit)
  local _, class = call(G("UnitClass"), unit)
  return plain(class)
end

function ns.fullName(unit)
  return M.joinName(call(G("UnitName"), unit))
end

-- The last full read of each unit's auras, by GUID (or name). In combat
-- the Forever client hides aura names, so a read there is partial: buffs
-- from the last full read that have not run out yet fill it in.
local remembered = {}
ns.remembered = remembered

local function auraKey(unit)
  local guid = plain(call(G("UnitGUID"), unit))
  if type(guid) == "string" then return guid end
  return ns.fullName(unit)
end

-- Every helpful aura on `unit`: name -> { expires, duration }. nil when
-- nothing can be read; `partial` is set when the client hid some of them.
function ns.readAuras(unit)
  local out = ns.readAurasNow(unit)
  local key = out and auraKey(unit)
  if not key then return out end
  if not out.partial then
    remembered[key] = out
    return out
  end
  local last, t = remembered[key], now()
  if last then
    for name, a in pairs(last) do
      if type(a) == "table" and out[name] == nil and ((a.expires or 0) <= 0 or a.expires > t) then
        out[name] = a
      end
    end
  end
  return out
end

function ns.readAurasNow(unit)
  local api = G("C_UnitAuras")
  local out = {}
  if api and api.GetAuraDataByIndex then
    for i = 1, 40 do
      local ok, a = pcall(api.GetAuraDataByIndex, unit, i, "HELPFUL")
      if not ok then out.partial = true break end
      if a == nil then break end
      local name = type(plain(a)) == "table" and plain(a.name)
      if type(name) == "string" then
        out[name] = { expires = plain(a.expirationTime) or 0, duration = plain(a.duration) or 0 }
      else
        out.partial = true
      end
    end
    return out
  end
  local unitBuff = G("UnitBuff")
  if not unitBuff then return nil end
  for i = 1, 40 do
    local name, _, _, _, duration, expires = call(unitBuff, unit, i)
    name = plain(name)
    if not name then break end
    out[name] = { expires = plain(expires) or 0, duration = plain(duration) or 0 }
  end
  return out
end

local function known(spell)
  local cs = G("C_Spell")
  if cs and cs.GetSpellInfo then
    if call(cs.GetSpellInfo, spell) then return true end
    return false
  end
  return call(G("GetSpellInfo"), spell) ~= nil
end

local function spellIcon(spell)
  local cs = G("C_Spell")
  return (cs and call(cs.GetSpellTexture, spell)) or call(G("GetSpellTexture"), spell)
end

-- Your group's unit tokens, you first: party1-4, or your raid subgroup.
function ns.roster()
  local list = { "player" }
  if call(G("IsInRaid")) then
    local mine
    local n = plain(call(G("GetNumGroupMembers"))) or 0
    local info = {}
    for i = 1, math.min(n, 40) do
      local _, _, sub = call(G("GetRaidRosterInfo"), i)
      info[i] = plain(sub)
      if call(G("UnitIsUnit"), "raid" .. i, "player") then mine = info[i] end
    end
    for i = 1, math.min(n, 40) do
      local u = "raid" .. i
      if info[i] == mine and not call(G("UnitIsUnit"), u, "player") and #list < MAX_ROWS then
        list[#list + 1] = u
      end
    end
  else
    for i = 1, 4 do
      if call(G("UnitExists"), "party" .. i) then list[#list + 1] = "party" .. i end
    end
  end
  return list
end

local function inGroup(unit)
  return call(G("UnitInParty"), unit) == true or call(G("UnitInRaid"), unit) ~= nil
end

local function mounted() return call(G("IsMounted")) == true end
local function manaShare()
  local cur = plain(call(G("UnitPower"), "player", 0))
  local max = plain(call(G("UnitPowerMax"), "player", 0))
  if not cur or not max or max <= 0 then return 1 end
  return cur / max
end

-- Players near you who are not in your group (nameplates, your target and
-- mouseover), by full name.
local function strangers()
  local seen, list = {}, {}
  local function add(unit)
    if not call(G("UnitExists"), unit) or not call(G("UnitIsPlayer"), unit) then return end
    if call(G("UnitIsUnit"), unit, "player") or inGroup(unit) then return end
    if not call(G("UnitCanAssist"), "player", unit) then return end
    if call(G("UnitIsDeadOrGhost"), unit) then return end
    local name = ns.fullName(unit)
    if not name or seen[name] then return end
    seen[name] = true
    list[#list + 1] = {
      name = name, unit = unit, class = classOf(unit), auras = ns.readAuras(unit),
      near = plain(call(G("CheckInteractDistance"), unit, 2)) == true,
    }
  end
  add("target")
  add("mouseover")
  for i = 1, 40 do add("nameplate" .. i) end
  return list, seen
end

---------------------------------------------------------------------------
-- The grid
---------------------------------------------------------------------------
local panel, header, nextBtn

local function setColour(tex, key)
  local c = COLOURS[key]
  if c then tex:SetColorTexture(c[1], c[2], c[3], 0.9) tex:Show() else tex:Hide() end
end

local function secureButton(name, parent)
  local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
  -- What works on the Forever client (as its own secure buttons do): a
  -- down click with pressAndHoldAction. Without it the click casts nothing.
  b:RegisterForClicks("AnyDown")
  b:SetAttribute("pressAndHoldAction", true)
  b:SetAttribute("type", "macro")
  b:SetAttribute("macrotext", "")
  -- The right button never casts: it skips (Next) or does nothing (rows).
  b:SetAttribute("type2", "none")
  b:SetAttribute("*type2", "none")
  return b
end

local function setMacro(b, text)
  if st.macros[b] == text or inCombat() then return end
  b:SetAttribute("macrotext", text)
  st.macros[b] = text
end

local function makeRow(i)
  local r = secureButton("BuffCheckRow" .. i, panel)
  r:SetSize(NAME_W + MAX_CELLS * CELL_W, ROW_H)
  r:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD + ROW_H * i))
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.08)
  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.label:SetPoint("LEFT", r, "LEFT", 2, 0)
  r.label:SetWidth(NAME_W - 4)
  r.label:SetJustifyH("LEFT")
  r.cells = {}
  for c = 1, MAX_CELLS do
    local tex = r:CreateTexture(nil, "ARTWORK")
    tex:SetSize(CELL_W - 4, ROW_H - 4)
    tex:SetPoint("LEFT", r, "LEFT", NAME_W + (c - 1) * CELL_W + 2, 0)
    local txt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER", tex, "CENTER", 0, 0)
    r.cells[c] = { tex = tex, txt = txt }
  end
  r:SetScript("OnEnter", function(self) ns.rowTooltip(self) end)
  r:SetScript("OnLeave", function() local t = G("GameTooltip") if t then t:Hide() end end)
  return r
end

function ns.build()
  if panel then return end
  panel = CreateFrame("Frame", "BuffCheckPanel", UIParent)
  panel:SetSize(200, 100)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  local p = ns.db.point
  if p then panel:SetPoint(p[1], UIParent, p[1], p[2], p[3])
  else panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -420) end
  panel.bg = panel:CreateTexture(nil, "BACKGROUND")
  panel.bg:SetAllPoints()
  panel.bg:SetColorTexture(0.05, 0.05, 0.06, 0.72)

  -- The header row: drag it to move the panel.
  header = CreateFrame("Frame", nil, panel)
  header:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
  header:SetSize(NAME_W + MAX_CELLS * CELL_W, ROW_H)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() if not inCombat() then panel:StartMoving() end end)
  header:SetScript("OnDragStop", function()
    panel:StopMovingOrSizing()
    local point, _, _, x, y = panel:GetPoint()
    ns.db.point = { point, x, y }
  end)
  header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header.title:SetPoint("LEFT", header, "LEFT", 2, 0)
  header.title:SetText("Buffs")
  header.cols = {}
  for c = 1, MAX_CELLS do
    local t = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("CENTER", header, "LEFT", NAME_W + (c - 1) * CELL_W + CELL_W / 2, 0)
    header.cols[c] = t
  end

  st.rowFrames = {}
  for i = 1, MAX_ROWS do st.rowFrames[i] = makeRow(i) end

  nextBtn = secureButton("BuffCheckNext", panel)
  nextBtn:SetHeight(ROW_H + 2)
  nextBtn.icon = nextBtn:CreateTexture(nil, "ARTWORK")
  nextBtn.icon:SetSize(ROW_H, ROW_H)
  nextBtn.icon:SetPoint("LEFT", nextBtn, "LEFT", 2, 0)
  nextBtn.label = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  nextBtn.label:SetPoint("LEFT", nextBtn.icon, "RIGHT", 4, 0)
  nextBtn.label:SetPoint("RIGHT", nextBtn, "RIGHT", -2, 0)
  nextBtn.label:SetJustifyH("LEFT")
  nextBtn.hl = nextBtn:CreateTexture(nil, "HIGHLIGHT")
  nextBtn.hl:SetAllPoints()
  nextBtn.hl:SetColorTexture(1, 1, 1, 0.08)
  nextBtn:HookScript("OnClick", function(_, button) ns.pressed(button) end)
  nextBtn:SetScript("OnEnter", function(self)
    local t = G("GameTooltip")
    if not t then return end
    t:SetOwner(self, "ANCHOR_RIGHT")
    t:AddLine("BuffCheck: next buff")
    t:AddLine("Click (or the key in Key Bindings > BuffCheck) to cast.", 1, 1, 1, true)
    t:AddLine("Right-click skips this person for 10 minutes.", 1, 1, 1, true)
    t:Show()
  end)
  nextBtn:SetScript("OnLeave", function() local t = G("GameTooltip") if t then t:Hide() end end)
end

local LABELS = { on = "", off = "x", unknown = "?" }

-- Cells for one row: { state, left, name } per column.
local function paintRow(r, row, cols)
  r.label:SetText(row.short or row.name or "?")
  local cc = G("RAID_CLASS_COLORS") and G("RAID_CLASS_COLORS")[row.class or ""]
  if cc then r.label:SetTextColor(cc.r, cc.g, cc.b) else r.label:SetTextColor(1, 1, 1) end
  for c = 1, MAX_CELLS do
    local cell, info = r.cells[c], row.cells[c]
    if c > #cols or not info then
      cell.tex:Hide() cell.txt:SetText("")
    else
      setColour(cell.tex, info.state)
      cell.txt:SetText(info.state == "low" and M.short(info.left) or (LABELS[info.state] or ""))
    end
  end
end

function ns.rowTooltip(r)
  local t = G("GameTooltip")
  local row = r.data
  if not t or not row then return end
  t:SetOwner(r, "ANCHOR_RIGHT")
  t:AddLine(row.name or "?")
  for c, def in ipairs(st.cols or {}) do
    local info = row.cells[c]
    if info then
      local text = ({ on = "on", low = "ends in " .. M.short(info.left), off = "missing",
                      unknown = "unknown (too far, or hidden)" })[info.state]
      if info.state == "on" and info.left then text = "on, " .. M.short(info.left) .. " left" end
      t:AddDoubleLine(def.title or def.label, text, 1, 1, 1, unpack(COLOURS[info.state] or { 1, 1, 1 }))
    end
  end
  if row.castText and row.castText ~= "" then t:AddLine("Click: cast " .. row.castSpell, 0.6, 0.8, 1) end
  t:Show()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function ns.myBuff(class)
  for _, def in ipairs(M.BUFFS) do
    if def.class == class and def.cast and known(def.cast) then return def end
  end
  return nil
end

function ns.refresh()
  if not panel then return end
  local t, combat = now(), inCombat()
  local myClass = classOf("player")
  local mine = ns.myBuff(myClass)
  local selfSpell = M.selfBuff(myClass, ns.db.lastSelf, known)

  -- Rows: the roster only changes out of combat (the secure rows keep their
  -- unit while you fight).
  if not combat or not st.units then st.units = ns.roster() end
  local rows, present = {}, {}
  for i, unit in ipairs(st.units) do
    local class = classOf(unit)
    if class then present[class] = true end
    local okUnit = call(G("UnitExists"), unit) and call(G("UnitIsConnected"), unit) ~= false
      and not call(G("UnitIsDeadOrGhost"), unit) and call(G("UnitIsVisible"), unit) ~= false
    local name = ns.fullName(unit)
    local first = plain(call(G("UnitName"), unit))
    rows[i] = { unit = unit, name = name, short = first, class = class, ok = okUnit and true or false,
                auras = okUnit and ns.readAuras(unit) or nil }
  end
  local cols = M.columns(present)
  local selfCol
  if M.SELF[myClass] then
    selfCol = { key = "self", label = "Armor", title = table.concat(M.SELF[myClass], " / "), self = true }
    cols[#cols + 1] = selfCol
  end
  while #cols > MAX_CELLS do table.remove(cols, 1) end
  st.cols = cols

  for _, row in ipairs(rows) do
    row.cells = {}
    for c, def in ipairs(cols) do
      if def.self then
        if row.unit == "player" then
          local has = M.hasSelfBuff(myClass, row.auras)
          local stt = has == true and "on" or has == false and "off" or "unknown"
          row.cells[c] = { state = stt }
        end
      elseif M.applies(def, row.class) then
        local s, left = M.state(row.auras, def, t)
        row.cells[c] = { state = row.ok and s or "unknown", left = left }
      end
    end
    -- What a click on the row casts: your buff, or on you your armor when
    -- your buff is already there.
    local spell
    if mine and M.applies(mine, row.class) then spell = mine.cast end
    if row.unit == "player" and selfSpell then
      local st1 = mine and M.state(row.auras, mine, t)
      if not spell or (st1 == "on" and M.hasSelfBuff(myClass, row.auras) == false) then spell = selfSpell end
    end
    row.castSpell = spell
    row.castText = M.macro(spell, row.unit)
  end
  st.rows = rows

  -- Players near you and strangers who buffed you.
  local near, seen = strangers()
  for _, o in ipairs(st.owed) do
    for _, n in ipairs(near) do
      if n.name == o.name then o.auras, o.class = n.auras, n.class end
    end
  end
  local nearby = {}
  if ns.db.nearby and not mounted() and manaShare() >= 0.3 then
    for _, n in ipairs(near) do if n.near then nearby[#nearby + 1] = n end end
  end
  local pick = nil
  if not mounted() and not combat then
    pick = M.nextBuff({ rows = rows, mine = mine, selfSpell = selfSpell, class = myClass,
      owed = st.owed, nearby = nearby, skip = st.skip, now = t })
  end
  st.next = pick

  -- Paint.
  for c = 1, MAX_CELLS do header.cols[c]:SetText(cols[c] and cols[c].label or "") end
  local width = NAME_W + math.max(#cols, 1) * CELL_W + 2 * PAD
  for i = 1, MAX_ROWS do
    local r, row = st.rowFrames[i], rows[i]
    r.data = row
    if row then
      paintRow(r, row, cols)
      if not combat then setMacro(r, row.castText) r:SetWidth(width - 2 * PAD) r:Show() end
    elseif not combat then
      setMacro(r, "")
      r:Hide()
    end
  end
  if pick then
    nextBtn.icon:SetTexture(spellIcon(pick.spell))
    nextBtn.icon:Show()
    nextBtn.label:SetText("Next: " .. pick.spell .. " > " .. (pick.name or "?") .. "  |cffa0a0a0(" .. pick.reason .. ")|r")
  else
    nextBtn.icon:Hide()
    nextBtn.label:SetText("|cffa0a0a0" .. (combat and "In combat" or mounted() and "Mounted" or "Everyone is buffed") .. "|r")
  end
  if not combat then
    local hadTarget = call(G("UnitExists"), "target") == true
    setMacro(nextBtn, pick and M.macro(pick.spell, pick.unit, pick.name, hadTarget) or "")
    nextBtn:ClearAllPoints()
    nextBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD + ROW_H * (#rows + 1) + 2))
    nextBtn:SetWidth(width - 2 * PAD)
    panel:SetSize(width, PAD * 2 + ROW_H * (#rows + 2) + 4)
    if ns.db.hidden then panel:Hide() else panel:Show() end
  end
end

-- After a click on Next: wait for the aura before offering the same person
-- again; a right-click skips them for 10 minutes.
function ns.pressed(button)
  local pick = st.next
  if not pick then return end
  local t = now()
  if button == "RightButton" then
    st.skip[pick.key] = t + 600
    say("Skipped " .. (pick.name or "?") .. " for 10 minutes.")
  else
    st.skip[pick.key] = t + M.PRESS_SECS
    if pick.key:find("^owed:") then
      for i = #st.owed, 1, -1 do
        if "owed:" .. st.owed[i].name == pick.key then table.remove(st.owed, i) end
      end
    end
  end
  st.dirty = true
end

-- Somebody buffed you: note it, so Next can return the favour.
--
-- The UNIT_AURA payload is not read: on Forever its addedAuras table and
-- isFullUpdate flag can be secret values, and touching them raises an
-- error. Instead, each UNIT_AURA on you rescans your buffs and compares
-- them with the last scan. The first scan after login only learns what is
-- already there.
local function favourFrom(a)
  if type(plain(a)) ~= "table" then return nil end
  local name, src = plain(a.name), plain(a.sourceUnit)
  local duration = plain(a.duration)
  if type(name) ~= "string" or type(src) ~= "string" then return nil end
  if type(duration) ~= "number" or duration <= 0 or M.NOT_A_FAVOUR[name] then return nil end
  if not call(G("UnitIsPlayer"), src) or call(G("UnitIsUnit"), src, "player") or inGroup(src) then return nil end
  local who = ns.fullName(src)
  if not who then return nil end
  return who, name, src
end

function ns.scanPlayer()
  local api = G("C_UnitAuras")
  if not (api and api.GetAuraDataByIndex) then return end
  local seen, first = {}, st.seen == nil
  for i = 1, 40 do
    local ok, a = pcall(api.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok or a == nil then break end
    local who, name, src = favourFrom(a)
    if who then
      local id = plain(a.auraInstanceID)
      local key = (type(id) == "number" and id) or (who .. ":" .. name .. ":" .. tostring(plain(a.expirationTime)))
      seen[key] = true
      if not first and not st.seen[key] then
        for j = #st.owed, 1, -1 do if st.owed[j].name == who then table.remove(st.owed, j) end end
        table.insert(st.owed, 1, { name = who, at = now(), class = classOf(src), spell = name })
        while #st.owed > 10 do table.remove(st.owed) end
      end
    end
  end
  st.seen = seen
  st.dirty = true
end

---------------------------------------------------------------------------
-- Events and commands
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.ev = ev
local EVENTS = { "ADDON_LOADED", "PLAYER_LOGIN", "UNIT_AURA", "GROUP_ROSTER_UPDATE",
  "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "UNIT_SPELLCAST_SUCCEEDED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
for _, e in ipairs(EVENTS) do ev:RegisterEvent(e) end

ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
  if event == "ADDON_LOADED" then
    if a1 ~= addonName then return end
    BuffCheckDB = type(BuffCheckDB) == "table" and BuffCheckDB or {}
    for k, v in pairs(defaults) do if BuffCheckDB[k] == nil then BuffCheckDB[k] = v end end
    ns.db = BuffCheckDB
  elseif event == "PLAYER_LOGIN" then
    ns.build()
    ns.scanPlayer()
    ns.refresh()
  elseif event == "UNIT_AURA" then
    if a1 == "player" then ns.scanPlayer() end
    st.dirty = true
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 ~= "player" then return end
    local cs = G("C_Spell")
    local name = plain((cs and call(cs.GetSpellName, a3)) or call(G("GetSpellInfo"), a3))
    for _, n in ipairs(M.SELF[classOf("player")] or {}) do
      if n == name then ns.db.lastSelf = name end
    end
    st.dirty = true
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- The Next macro would be stale for the whole fight: empty it now,
    -- while the client still lets us.
    if nextBtn and not inCombat() then setMacro(nextBtn, "") end
  else
    st.dirty = true
  end
end)

local acc = 0
ev:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + (elapsed or 0)
  if acc >= 1 or (st.dirty and acc >= 0.2) then
    acc, st.dirty = 0, false
    if ns.db and panel then ns.refresh() end
  end
end)

_G["BINDING_HEADER_BUFFCHECK"] = "BuffCheck"
_G["BINDING_NAME_CLICK BuffCheckNext:LeftButton"] = "Buff the next person"

SLASH_BUFFCHECK1 = "/buffs"
SlashCmdList.BUFFCHECK = function(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" or cmd == "show" or cmd == "hide" then
    if inCombat() then say("Not in combat.") return end
    if cmd == "" then ns.db.hidden = not ns.db.hidden else ns.db.hidden = (cmd == "hide") end
    ns.refresh()
    say(ns.db.hidden and "Hidden. /buffs shows it again." or "Shown.")
  elseif cmd == "nearby" then
    ns.db.nearby = arg ~= "off"
    say("Nearby players: " .. (ns.db.nearby and "on" or "off") .. ".")
    st.dirty = true
  elseif cmd == "reset" then
    if inCombat() then say("Not in combat.") return end
    ns.db.point = nil
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -420)
    say("Panel moved back.")
  else
    say("/buffs: show or hide the panel. /buffs nearby on|off: offer your buff to players near you. " ..
      "/buffs reset: move the panel back. Drag the header to move it.")
  end
end
