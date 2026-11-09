-- QuestBoard: a small floating list of the quests that matter now. Three
-- groups: quests to turn in (nearest finisher first), quests in your log
-- (nearest objective first) and quests you can pick up that fit your level
-- (best estimated XP per minute first). Click a row to pin the place on the
-- map. /qb for the commands.
local addonName, ns = ...
QuestBoard = ns                     -- global, for /dump
ns.VERSION = "0.1.0"
local D = ns.data
local call, api = D.call, D.api

local defaults = {
  shown = true,
  sortLog = "near",      -- near | xp
  sortPickup = "xp",     -- near | xp
  maxAbove = 3,          -- pick-ups at most this many levels over you
  rows = { turnin = 6, log = 8, pickup = 8 },
  collapsed = {},
  combatAlpha = 0.35,
  hideTrackers = false,  -- hide the game's quest tracker (and Questie's)
  point = nil,           -- saved position { point, x, y }
}

local function say(msg)
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  if f then f:AddMessage("|cff9cd0ffQuestBoard|r: " .. tostring(msg)) end
end
ns.say = say

---------------------------------------------------------------------------
-- Look: the Glance "floating minimal" style. A see-through dark panel, no
-- frame art, small text, colour only for quest level.
---------------------------------------------------------------------------
local W, ROW_H, HEAD_H, PAD = 270, 15, 16, 6
local FONT, FONT_DIM = "GameFontHighlightSmall", "GameFontDisableSmall"
local HEADS = { turnin = "Turn in", log = "In your log", pickup = "Pick up" }
local ORDER = { "turnin", "log", "pickup" }

local panel, rows, heads = nil, {}, {}
local state = nil        -- last collect() result

local function rgb(name) local c = D.COLORS[name] or D.COLORS.yellow return c[1], c[2], c[3] end

-- Right-hand text of a row: progress, XP/min (pick-ups), distance.
function ns.meta(e)
  local parts = {}
  if e.kind == "log" then
    local p = D.progress(e)
    if p ~= "" then table.insert(parts, p) end
  end
  if e.kind == "pickup" and e.rate then table.insert(parts, "~" .. D.short(e.rate) .. " xp/m") end
  if e.dist then table.insert(parts, D.yards(e.dist))
  elseif e.far then table.insert(parts, "far")
  elseif e.fromItem then table.insert(parts, "item") end
  return table.concat(parts, "  ")
end

local function facing() return D.plain(call(rawget(_G, "GetPlayerFacing"))) end

local function updateArrow(r)
  local e = r.entry
  if not (e and e.angle) then r.arrow:Hide() return end
  local f = facing()
  if not f then r.arrow:Hide() return end
  r.arrow:SetRotation(e.angle - f)
  r.arrow:Show()
end

local function tooltip(r)
  local e, tip = r.entry, rawget(_G, "GameTooltip")
  if not (e and tip) then return end
  tip:SetOwner(r, "ANCHOR_LEFT")
  tip:AddLine(e.name, rgb(e.color))
  local lvl = "Level " .. (e.level or "?")
  if e.req and e.req ~= e.level then lvl = lvl .. " (needs " .. e.req .. ")" end
  tip:AddLine(lvl, 0.8, 0.8, 0.8)
  if e.xp then tip:AddLine(D.short(e.xp) .. " XP", 0.6, 0.8, 1) end
  if e.rate and e.secs then
    tip:AddLine(string.format("~%s XP per minute (about %d min)", D.short(e.rate), math.max(1, math.floor(e.secs / 60 + 0.5))), 0.6, 0.8, 1)
  end
  local verb = e.kind == "turnin" and "Turn in at " or e.kind == "pickup" and "Get it from " or "Nearest: "
  if e.target then
    tip:AddLine(verb .. e.target .. (e.dist and ("  " .. D.yards(e.dist) .. " " .. D.compass(e.angle)) or ""), 1, 1, 1)
  elseif e.fromItem then
    tip:AddLine("Starts from an item that drops", 0.8, 0.8, 0.8)
  end
  for _, o in ipairs(e.left or {}) do
    if o.text then tip:AddLine("- " .. o.text, 0.8, 0.8, 0.8) end
  end
  tip:AddLine(" ")
  tip:AddLine("Click: pin it on the map   Shift-click: link", 0.5, 0.5, 0.5)
  if e.kind ~= "pickup" then tip:AddLine("Right-click: open the quest log", 0.5, 0.5, 0.5)
  else tip:AddLine("Right-click: show the giver on the map", 0.5, 0.5, 0.5) end
  tip:Show()
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
-- A point on mapID, moved up to the first map that takes a user pin.
local function pinPoint(mapID, x, y)
  local id, px, py = mapID, x, y
  for _ = 1, 4 do
    if call(api("C_Map.CanSetUserWaypointOnMap"), id) then return id, px, py end
    local info = call(api("C_Map.GetMapInfo"), id)
    local parent = type(info) == "table" and info.parentMapID
    if not parent or parent == 0 then return nil end
    local left, right, top, bottom = call(api("C_Map.GetMapRectOnMap"), id, parent)
    if not (left and right and top and bottom) then return nil end
    id, px, py = parent, left + px * (right - left), top + py * (bottom - top)
  end
end
ns.pinPoint = pinPoint

-- Sets and tracks the game's map pin at the entry's place.
function ns.pin(e)
  local zdb = D.module("ZoneDB")
  local s = e.spawn
  if not (zdb and s and s[1] and s[1] >= 0) then say(e.name .. ": no place known") return false end
  local mapID = call(zdb.GetUiMapIdByAreaId, zdb, e.zone)
  local id, px, py
  if mapID then id, px, py = pinPoint(mapID, s[1] / 100, s[2] / 100) end
  local point, set = api("UiMapPoint.CreateFromCoordinates"), api("C_Map.SetUserWaypoint")
  if not (id and point and set) then say(e.name .. ": the map takes no pin here") return false end
  local ok, wasSet = pcall(set, call(point, id, px, py))
  if not ok or wasSet == false then say(e.name .. ": the map takes no pin here") return false end
  call(api("C_SuperTrack.SetSuperTrackedUserWaypoint"), true)
  say(string.format("%s: pin set at %s (%.0f, %.0f)", e.name, e.target or "the place", s[1], s[2]))
  return true
end

function ns.link(e)
  local link = call(rawget(_G, "GetQuestLink"), e.id) or e.name
  if not call(rawget(_G, "ChatEdit_InsertLink"), link) then call(rawget(_G, "ChatFrame_OpenChat"), link) end
end

function ns.openLog(e)
  local f = rawget(_G, "QuestLogFrame")
  if f and rawget(_G, "SelectQuestLogEntry") and e.index then
    call(rawget(_G, "SelectQuestLogEntry"), e.index)
    if not f:IsShown() then call(rawget(_G, "ShowUIPanel"), f) end
    call(rawget(_G, "QuestLog_SetSelection"), e.index)
    call(rawget(_G, "QuestLog_Update"))
    return
  end
  if call(rawget(_G, "QuestMapFrame_OpenToQuestDetails"), e.id) == nil then
    call(api("C_QuestLog.SetSelectedQuest"), e.id)
    call(rawget(_G, "ToggleQuestLog"))
  end
end

-- Questie's own map icon for the giver, as Omni does.
function ns.showGiver(e)
  local qmap, qdb = D.module("QuestieMap"), D.module("QuestieDB")
  local quest = qdb and call(qdb.GetQuest, e.id)
  local npc = quest and quest.Starts and quest.Starts.NPC and quest.Starts.NPC[1]
  if qmap and npc and type(qmap.ShowNPC) == "function" then
    call(qmap.ResetManualFrames, qmap, "questboard")
    call(qmap.ShowNPC, qmap, npc, nil, nil, nil, nil, nil, "questboard")
  end
  ns.pin(e)
end

function ns.click(e, button)
  if not e then return end
  if rawget(_G, "IsShiftKeyDown") and IsShiftKeyDown() then return ns.link(e) end
  if button == "RightButton" then
    if e.kind == "pickup" then return ns.showGiver(e) end
    return ns.openLog(e)
  end
  return ns.pin(e)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function makeRow(i)
  local r = CreateFrame("Button", nil, panel)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.lvl = r:CreateFontString(nil, "OVERLAY", FONT)
  r.lvl:SetPoint("LEFT", 0, 0)
  r.lvl:SetWidth(20)
  r.lvl:SetJustifyH("RIGHT")
  r.arrow = r:CreateTexture(nil, "OVERLAY")
  r.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  r.arrow:SetSize(14, 14)
  r.arrow:SetPoint("RIGHT", 0, 0)
  r.meta = r:CreateFontString(nil, "OVERLAY", FONT_DIM)
  r.meta:SetPoint("RIGHT", -16, 0)
  r.meta:SetJustifyH("RIGHT")
  r.name = r:CreateFontString(nil, "OVERLAY", FONT)
  r.name:SetPoint("LEFT", r.lvl, "RIGHT", 6, 0)
  r.name:SetPoint("RIGHT", r.meta, "LEFT", -6, 0)
  r.name:SetJustifyH("LEFT")
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.06)
  r.hl:Hide()
  r:SetScript("OnEnter", function(self) self.hl:Show() tooltip(self) end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() if GameTooltip then GameTooltip:Hide() end end)
  r:SetScript("OnClick", function(self, button) ns.click(self.entry, button) end)
  rows[i] = r
  return r
end

local function makeHead(kind)
  local h = CreateFrame("Button", nil, panel)
  h:SetHeight(HEAD_H)
  h.text = h:CreateFontString(nil, "OVERLAY", FONT_DIM)
  h.text:SetPoint("LEFT", 0, 0)
  h.right = h:CreateFontString(nil, "OVERLAY", FONT_DIM)
  h.right:SetPoint("RIGHT", 0, 0)
  h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  h:SetScript("OnClick", function(_, button)
    if button == "RightButton" and kind ~= "turnin" then
      local key = kind == "pickup" and "sortPickup" or "sortLog"
      ns.db[key] = ns.db[key] == "xp" and "near" or "xp"
    else
      ns.db.collapsed[kind] = not ns.db.collapsed[kind]
    end
    ns.refresh()
  end)
  heads[kind] = h
  return h
end

-- Lays out the groups from the last result.
function ns.render()
  if not panel then return end
  local y, used = -PAD, 0
  local level = state and state.level or D.playerLevel()
  panel.title:SetText("Quests")
  panel.sub:SetText(state and (state.questie and ("level " .. level) or "level " .. level .. "  (no Questie: log only)") or "")
  y = y - HEAD_H
  for _, kind in ipairs(ORDER) do
    local list = state and state[kind] or {}
    local h = heads[kind] or makeHead(kind)
    local show = #list > 0 or kind == "pickup" and state and state.questie
    if show then
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", PAD, y)
      h:SetPoint("TOPRIGHT", -PAD, y)
      local collapsed = ns.db.collapsed[kind]
      h.text:SetText((collapsed and "+ " or "") .. HEADS[kind] .. "  " .. #list)
      local sortKey = kind == "pickup" and "sortPickup" or kind == "log" and "sortLog"
      h.right:SetText(sortKey and (ns.db[sortKey] == "xp" and "best XP" or "nearest") or "nearest")
      h:Show()
      y = y - HEAD_H
      if not collapsed then
        for i = 1, math.min(#list, ns.db.rows[kind] or 6) do
          used = used + 1
          local r = rows[used] or makeRow(used)
          local e = list[i]
          r.entry = e
          r:ClearAllPoints()
          r:SetPoint("TOPLEFT", PAD, y)
          r:SetPoint("TOPRIGHT", -PAD, y)
          r.lvl:SetText(e.level or "?")
          r.lvl:SetTextColor(rgb(e.color))
          r.name:SetText(e.name)
          if e.kind == "turnin" then r.name:SetTextColor(0.55, 0.9, 0.55) else r.name:SetTextColor(0.92, 0.92, 0.92) end
          r.meta:SetText(ns.meta(e))
          updateArrow(r)
          r:Show()
          y = y - ROW_H
        end
      end
      y = y - 4
    else
      h:Hide()
    end
  end
  for i = used + 1, #rows do rows[i]:Hide() rows[i].entry = nil end
  panel:SetHeight(-y + PAD - 4)
end

---------------------------------------------------------------------------
-- Refresh: one collect() pass at a time, spread over frames.
---------------------------------------------------------------------------
local job, again = nil, false
local runner = CreateFrame("Frame")
local function step()
  if not job then return end
  local ok, err = coroutine.resume(job)
  if not ok then
    job = nil
    say("refresh failed: " .. tostring(err))
  elseif coroutine.status(job) == "dead" then
    job = nil
    ns.render()
    if again then again = false ns.refresh() end
  end
  if not job then runner:SetScript("OnUpdate", nil) end
end

function ns.refresh()
  if not (ns.db and ns.db.shown) then return end
  if job then again = true return end
  job = coroutine.create(function()
    state = D.collect({ sortLog = ns.db.sortLog, sortPickup = ns.db.sortPickup, maxAbove = ns.db.maxAbove,
      yield = coroutine.yield })
  end)
  runner:SetScript("OnUpdate", step)
  step()
end
ns.step = step
function ns.state() return state end

-- Arrows turn with you; distances update every few seconds.
local sinceArrow, sinceFull = 0, 0
ns.FULL_SECS = 3
local function tickFn(_, dt)
  sinceArrow, sinceFull = sinceArrow + dt, sinceFull + dt
  if sinceArrow > 0.1 then
    sinceArrow = 0
    for _, r in ipairs(rows) do if r:IsShown() then updateArrow(r) end end
  end
  if sinceFull > ns.FULL_SECS then
    sinceFull = 0
    ns.refresh()
  end
end

local function savePos()
  local p, _, _, x, y = panel:GetPoint(1)
  ns.db.point = { p, x, y }
end

local function build()
  panel = CreateFrame("Frame", "QuestBoardFrame", UIParent)
  panel:SetWidth(W)
  panel:SetHeight(60)
  panel:SetFrameStrata("LOW")
  panel:SetClampedToScreen(true)
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  panel.title = panel:CreateFontString(nil, "OVERLAY", FONT)
  panel.title:SetPoint("TOPLEFT", PAD, -PAD)
  panel.sub = panel:CreateFontString(nil, "OVERLAY", FONT_DIM)
  panel.sub:SetPoint("TOPRIGHT", -PAD, -PAD)
  local p = ns.db.point
  if p then panel:SetPoint(p[1], UIParent, p[1], p[2], p[3])
  else panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -260) end
  -- Alt-drag moves it.
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) if IsAltKeyDown() then self:StartMoving() end end)
  panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePos() end)
  panel:SetScript("OnUpdate", tickFn)
  ns.panel = panel
end

function ns.show(on)
  ns.db.shown = on
  if on then panel:Show() ns.refresh() else panel:Hide() end
end

---------------------------------------------------------------------------
-- Hiding the other quest trackers (/qb tracker off). The game's tracker
-- holds secure quest-item buttons, so it is hidden only out of combat; in
-- combat it goes see-through and hides when combat ends.
---------------------------------------------------------------------------
ns.TRACKERS = { "ObjectiveTrackerFrame", "WatchFrame", "QuestWatchFrame", "Questie_BaseFrame" }
local hooked = {}
local function inCombat() return rawget(_G, "InCombatLockdown") and InCombatLockdown() end

local function hideTracker(f)
  if not (ns.db and ns.db.hideTrackers) then return end
  if inCombat() then f:SetAlpha(0) return end
  f:Hide()
  f:SetAlpha(1)
end

function ns.applyTrackers()
  for _, name in ipairs(ns.TRACKERS) do
    local f = rawget(_G, name)
    if type(f) == "table" and f.Hide then
      if not hooked[name] and f.HookScript then
        hooked[name] = true
        f:HookScript("OnShow", hideTracker)
      end
      if ns.db.hideTrackers then
        hideTracker(f)
      elseif not inCombat() and f.SetAlpha then
        f:SetAlpha(1)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
ns.events = events
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED",
  "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    QuestBoardDB = QuestBoardDB or {}
    for k, v in pairs(defaults) do
      if QuestBoardDB[k] == nil then QuestBoardDB[k] = type(v) == "table" and {} or v end
    end
    for k, v in pairs(defaults.rows) do
      if QuestBoardDB.rows[k] == nil then QuestBoardDB.rows[k] = v end
    end
    ns.db = QuestBoardDB
    build()
    ns.show(ns.db.shown)
    ns.applyTrackers()
    -- Questie builds its quest lists a few seconds after login.
    if C_Timer then
      C_Timer.After(5, function() ns.refresh() ns.applyTrackers() end)
      C_Timer.After(15, ns.refresh)
    end
    return
  end
  if not panel then return end
  if event == "PLAYER_REGEN_DISABLED" then panel:SetAlpha(ns.db.combatAlpha) return end
  if event == "PLAYER_REGEN_ENABLED" then
    panel:SetAlpha(1)
    if ns.db.hideTrackers then ns.applyTrackers() end
  end
  ns.refresh()
end)

---------------------------------------------------------------------------
-- /qb
---------------------------------------------------------------------------
local help = {
  "/qb - show or hide the board. Alt-drag it to move it.",
  "Click a group name to fold it; right-click it to sort by nearest or best XP.",
  "/qb range N - pick-ups at most N levels over you (now %d)",
  "/qb rows N - rows per group (now %d)",
  "/qb reset - put the board back under the minimap",
  "/qb tracker off - hide the game's quest tracker (on brings it back)",
}
SLASH_QUESTBOARD1, SLASH_QUESTBOARD2 = "/qb", "/questboard"
SlashCmdList.QUESTBOARD = function(text)
  local cmd, rest = (text or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then return ns.show(not ns.db.shown) end
  local n = tonumber(rest)
  if cmd == "range" and n then
    ns.db.maxAbove = math.max(0, math.min(10, math.floor(n)))
    say("pick-ups up to " .. ns.db.maxAbove .. " levels over you")
    return ns.refresh()
  elseif cmd == "rows" and n then
    n = math.max(1, math.min(20, math.floor(n)))
    for k in pairs(ns.db.rows) do ns.db.rows[k] = n end
    return ns.refresh()
  elseif cmd == "tracker" and (rest == "off" or rest == "on") then
    ns.db.hideTrackers = rest == "off"
    if rest == "on" and inCombat() then say("the tracker comes back after combat") end
    ns.applyTrackers()
    if rest == "on" then
      for _, name in ipairs(ns.TRACKERS) do
        local f = rawget(_G, name)
        -- Questie's tracker shows itself only when Questie's own option is on.
        if type(f) == "table" and f.Show and name ~= "Questie_BaseFrame" and not inCombat() then f:Show() end
      end
    end
    say(rest == "off" and "the game's quest tracker is hidden" or "the game's quest tracker is back")
    return
  elseif cmd == "reset" then
    ns.db.point = nil
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -260)
    return
  end
  for _, line in ipairs(help) do say(string.format(line, line:find("range") and ns.db.maxAbove or ns.db.rows.log)) end
end
