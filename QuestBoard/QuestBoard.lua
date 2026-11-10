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
  rows = { active = 4, area = 3, turnin = 6, log = 8, party = 5, pickup = 8 },
  collapsed = {},
  combatAlpha = 0.35,
  hideTrackers = false,  -- hide the game's quest tracker (and Questie's)
  locked = false,        -- /qb lock: no dragging
  compact = false,       -- /qb compact: one line per quest, no "what to do" line
  focus = true,          -- in combat and instances: only Next and Active until mouse-over
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
local HEADS = { active = "Active", area = "Areas", turnin = "Turn in", log = "In your log", party = "Party has", pickup = "Pick up" }
local ORDER = { "active", "area", "turnin", "log", "party", "pickup" }

local panel, rows, heads = nil, {}, {}
local state = nil        -- last collect() result

local function rgb(name) local c = D.COLORS[name] or D.COLORS.yellow return c[1], c[2], c[3] end

-- What to do for a quest, in a few words: the open objective and where
-- (Questie's nearest mob, object or NPC for it), or who takes it in.
function ns.todo(e)
  local text = ns.todoBase(e)
  local with = e.party and #e.party > 0 and D.partyText(e.party)
  if with and with ~= "" then
    if e.kind == "party" then return with .. (text and ("  -  " .. text) or "") end
    return (text and (text .. "  -  ") or "") .. "with " .. with
  end
  return text
end

function ns.todoBase(e)
  if e.kind == "area" then return D.areaText(e) end
  if e.kind == "turnin" then return e.target and ("Hand in to " .. e.target) or "Hand it in" end
  if e.fromItem then
    local what = e.item and ("Loot " .. e.item) or "Starts from an item"
    return what .. (e.dropFrom and (" from " .. e.dropFrom) or "") .. (e.finisher and (", hand in to " .. e.finisher) or "")
  end
  if e.deliver and e.target then
    local o = e.left and e.left[1]
    return (o and o.text and (o.text .. "  -  ") or "") .. "Take it to " .. e.target
  end
  if e.kind == "pickup" or e.kind == "party" then return e.target and ("Get it from " .. e.target) or nil end
  local o = e.left and e.left[1]
  local text = o and o.text
  if text and text ~= "" then
    if e.target and not text:find(e.target, 1, true) then text = text .. "  (" .. e.target .. ")" end
    return text
  end
  return e.target and ("Go to " .. e.target) or nil
end

-- The one thing to do next: a quest you are on now, else the nearest
-- hand-in, else the nearest quest in your log.
function ns.nextStep(st)
  if not st then return nil end
  -- With nothing on the go, the best area (several stops in one trip).
  local best = not st.active[1] and st.area and st.area[1]
  if best and #best.stops >= 3 then
    return "Go " .. best.name:lower() .. ": " .. D.areaText(best) .. "  " .. D.yards(best.dist), best
  end
  local e = st.active[1] or st.turnin[1] or st.log[1]
  if not e then return nil end
  local todo = ns.todo(e)
  if e.kind == "turnin" then todo = "Hand in " .. e.name .. (e.target and (" to " .. e.target) or "") end
  return todo and (todo .. (e.dist and ("  " .. D.yards(e.dist)) or "")), e
end

-- Right-hand text of a row: progress, XP/min (pick-ups), distance. The
-- progress is in the "what to do" line unless the board is compact.
function ns.meta(e)
  local parts = {}
  if e.kind == "log" and ns.db and ns.db.compact then
    local p = D.progress(e)
    if p ~= "" then table.insert(parts, p) end
  end
  if (e.kind == "pickup" or e.kind == "area") and e.rate then table.insert(parts, "~" .. D.short(e.rate) .. " xp/m") end
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
  if e.kind == "area" then
    tip:AddLine(e.name .. "  (" .. D.yards(e.dist) .. ")", 1, 1, 1)
    tip:AddLine(D.areaText(e), 0.8, 0.8, 0.8)
    if e.rate then tip:AddLine(string.format("~%s XP per minute, %s XP here", D.short(e.rate), D.short(e.xp)), 0.6, 0.8, 1) end
    for _, s in ipairs(e.stops) do
      local what = s.kind == "turnin" and "hand in" or (s.kind == "pickup" or s.kind == "party") and "pick up" or "objective"
      tip:AddLine("- " .. s.name .. "  (" .. what .. ")", rgb(s.color))
    end
    tip:AddLine(" ")
    tip:AddLine("Click: show it on the map", 0.5, 0.5, 0.5)
    tip:Show()
    return
  end
  tip:AddLine(e.name, rgb(e.color))
  local lvl = "Level " .. (e.level or "?")
  if e.req and e.req ~= e.level then lvl = lvl .. " (needs " .. e.req .. ")" end
  tip:AddLine(lvl, 0.8, 0.8, 0.8)
  if e.xp then tip:AddLine(D.short(e.xp) .. " XP", 0.6, 0.8, 1) end
  if e.rate and e.secs then
    tip:AddLine(string.format("~%s XP per minute (about %d min)", D.short(e.rate), math.max(1, math.floor(e.secs / 60 + 0.5))), 0.6, 0.8, 1)
  end
  local verb = e.kind == "turnin" and "Turn in at " or (e.kind == "pickup" or e.kind == "party") and "Get it from " or "Nearest: "
  if e.target then
    tip:AddLine(verb .. e.target .. (e.dist and ("  " .. D.yards(e.dist) .. " " .. D.compass(e.angle)) or ""), 1, 1, 1)
  end
  if e.fromItem then
    tip:AddLine("Starts from an item" .. (e.item and (": " .. e.item) or "") .. (e.dropFrom and (", drops from " .. e.dropFrom) or ""), 0.8, 0.8, 0.8)
    if e.finisher then tip:AddLine("Hand in to " .. e.finisher, 0.8, 0.8, 0.8) end
  end
  if not e.spawn then tip:AddLine("Questie has no place for this quest", 0.8, 0.5, 0.5) end
  for _, o in ipairs(e.left or {}) do
    if o.text then tip:AddLine("- " .. o.text, 0.8, 0.8, 0.8) end
  end
  tip:AddLine(" ")
  tip:AddLine("Click: show it on the map   Shift-click: link", 0.5, 0.5, 0.5)
  if e.party and #e.party > 0 then
    tip:AddLine((e.kind == "party" and "Your party has it: " or "With ") .. D.partyText(e.party), 0.6, 0.8, 1)
  end
  if e.kind ~= "pickup" and e.kind ~= "party" then tip:AddLine("Right-click: open the quest log", 0.5, 0.5, 0.5)
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

-- Opens the world map (M) at mapID. Another map addon can take over
-- OpenWorldMap and show nothing, so if the map is still hidden after it,
-- toggle it open and set the map (as Omni does).
function ns.openMap(mapID)
  local f = rawget(_G, "WorldMapFrame")
  local function shown() return type(f) == "table" and f.IsShown and f:IsShown() and true or false end
  local open = api("C_Map.OpenWorldMap")
  if open then call(open, mapID) end
  if type(f) ~= "table" then return open ~= nil end
  if not shown() then
    if not call(rawget(_G, "ToggleWorldMap")) and not shown() then call(rawget(_G, "ShowUIPanel"), f) end
  end
  if f.SetMapID then call(f.SetMapID, f, mapID) end
  return true
end

-- Opens the world map at the entry's place, and sets and tracks the game's
-- map pin there.
function ns.pin(e)
  local zdb = D.module("ZoneDB")
  local s = e.spawn
  if not (zdb and s and s[1] and s[1] >= 0) then
    -- No place: open the quest log at it instead (your quests), and say so
    -- once per quest, not on every click.
    if e.kind ~= "pickup" and e.kind ~= "party" then ns.openLog(e) end
    ns.sayOnce("noplace:" .. tostring(e.id), e.name .. ": Questie has no place for it" ..
      (s and s[1] and s[1] < 0 and " (it is in a dungeon)" or ""))
    return false
  end
  local mapID = call(zdb.GetUiMapIdByAreaId, zdb, e.zone)
  if mapID then ns.openMap(mapID) end
  local id, px, py
  if mapID then id, px, py = pinPoint(mapID, s[1] / 100, s[2] / 100) end
  local point, set = api("UiMapPoint.CreateFromCoordinates"), api("C_Map.SetUserWaypoint")
  if not (id and point and set) then ns.sayOnce("nopin:" .. tostring(e.id), e.name .. ": the map takes no pin here") return false end
  local ok, wasSet = pcall(set, call(point, id, px, py))
  if not ok or wasSet == false then ns.sayOnce("nopin:" .. tostring(e.id), e.name .. ": the map takes no pin here") return false end
  call(api("C_SuperTrack.SetSuperTrackedUserWaypoint"), true)
  return true
end

local said = {}
function ns.sayOnce(key, msg)
  if said[key] then return end
  said[key] = true
  say(msg)
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
  -- The Forever client has the newer quest log inside the world map. This
  -- returns nothing, so test that it exists, not what it returns (a
  -- ToggleQuestLog after it would close the log again).
  local details = rawget(_G, "QuestMapFrame_OpenToQuestDetails")
  if type(details) == "function" then
    local ok = pcall(details, e.id)
    if ok then return end
  end
  call(api("C_QuestLog.SetSelectedQuest"), e.id)
  call(rawget(_G, "ToggleQuestLog"))
end

-- Questie's own map icon for an NPC (the giver or the finisher), as Omni
-- does: it stands out on the map more than the small pin.
function ns.markNPC(npc)
  local qmap = D.module("QuestieMap")
  if not (qmap and npc and type(qmap.ShowNPC) == "function") then return false end
  call(qmap.ResetManualFrames, qmap, "questboard")
  return call(qmap.ShowNPC, qmap, npc, nil, nil, nil, nil, nil, "questboard") ~= nil
end

function ns.showGiver(e)
  ns.markNPC(e.npc)
  ns.pin(e)
end

function ns.click(e, button)
  if not e then return end
  if rawget(_G, "IsShiftKeyDown") and IsShiftKeyDown() then return ns.link(e) end
  if button == "RightButton" then
    if e.kind == "pickup" or e.kind == "party" then return ns.showGiver(e) end
    if e.kind == "area" then return ns.pin(e) end
    return ns.openLog(e)
  end
  if e.npc then ns.markNPC(e.npc) end
  return ns.pin(e)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
-- Dragging any part of the board (rows and group names too) moves it. A
-- click without a drag still clicks.
local function dragStart()
  if panel and not ns.db.locked then panel.isMoving = true panel:StartMoving() end
end
local function dragStop()
  if not panel then return end
  panel:StopMovingOrSizing()
  panel.isMoving = false
  ns.dragEnded = rawget(_G, "GetTime") and GetTime() or nil
  ns.pinTop()
end

-- Keeps the board's top edge in place: it is anchored by its top-left
-- corner, so it grows and shrinks downward only (the game re-anchors a
-- dragged frame to its centre, which made the board grow both ways).
function ns.pinTop()
  local left, top = panel:GetLeft(), panel:GetTop()
  if not (left and top) then return end
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  ns.db.point = { "TOPLEFT", left, top, "BOTTOMLEFT" }
end
ns.dragStart, ns.dragStop = dragStart, dragStop
local function draggable(f)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", dragStart)
  f:SetScript("OnDragStop", dragStop)
end

local function makeRow(i)
  local r = CreateFrame("Button", nil, panel)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.lvl = r:CreateFontString(nil, "OVERLAY", FONT)
  r.lvl:SetPoint("TOPLEFT", 0, -1)
  r.lvl:SetWidth(20)
  r.lvl:SetJustifyH("RIGHT")
  r.arrow = r:CreateTexture(nil, "OVERLAY")
  r.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  r.arrow:SetSize(14, 14)
  r.arrow:SetPoint("TOPRIGHT", 0, 0)
  r.meta = r:CreateFontString(nil, "OVERLAY", FONT_DIM)
  r.meta:SetPoint("TOPRIGHT", -16, -1)
  r.meta:SetJustifyH("RIGHT")
  r.name = r:CreateFontString(nil, "OVERLAY", FONT)
  r.name:SetPoint("LEFT", r.lvl, "RIGHT", 6, 0)
  r.name:SetPoint("RIGHT", r.meta, "LEFT", -6, 0)
  r.name:SetJustifyH("LEFT")
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  -- The "what to do" line under the name.
  r.sub = r:CreateFontString(nil, "OVERLAY", FONT_DIM)
  r.sub:SetPoint("TOPLEFT", 26, -ROW_H + 1)
  r.sub:SetPoint("TOPRIGHT", -16, -ROW_H + 1)
  r.sub:SetJustifyH("LEFT")
  if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.06)
  r.hl:Hide()
  r:SetScript("OnEnter", function(self) self.hl:Show() tooltip(self) end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() if GameTooltip then GameTooltip:Hide() end end)
  r:SetScript("OnClick", function(self, button)
    -- The release that ends a drag is not a click.
    if ns.dragEnded and rawget(_G, "GetTime") and GetTime() - ns.dragEnded < 0.2 then return end
    ns.click(self.entry, button)
  end)
  draggable(r)
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
    if button == "RightButton" and (kind == "log" or kind == "pickup") then
      local key = kind == "pickup" and "sortPickup" or "sortLog"
      ns.db[key] = ns.db[key] == "xp" and "near" or "xp"
    else
      ns.db.collapsed[kind] = not ns.db.collapsed[kind]
    end
    ns.refresh()
  end)
  draggable(h)
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
  local nextText = ns.nextStep(state)
  if nextText then
    panel.next:SetText("Next: " .. nextText)
    panel.next:ClearAllPoints()
    panel.next:SetPoint("TOPLEFT", PAD, y)
    panel.next:SetPoint("TOPRIGHT", -PAD, y)
    panel.next:Show()
    y = y - ROW_H - 2
  else
    panel.next:Hide()
  end
  for _, kind in ipairs(ORDER) do
    local list = state and state[kind] or {}
    local h = heads[kind] or makeHead(kind)
    local show = #list > 0 or kind == "pickup" and state and state.questie
    -- Focus: only the quests you are on now, the rest on mouse-over.
    if ns.focused() and kind ~= "active" then show = false end
    if show then
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", PAD, y)
      h:SetPoint("TOPRIGHT", -PAD, y)
      local collapsed = ns.db.collapsed[kind]
      h.text:SetText((collapsed and "+ " or "") .. HEADS[kind] .. "  " .. #list)
      local sortKey = kind == "pickup" and "sortPickup" or kind == "log" and "sortLog"
      h.right:SetText(kind == "active" and "recent or here" or kind == "area" and "best XP"
        or sortKey and (ns.db[sortKey] == "xp" and "best XP" or "nearest") or "nearest")
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
          r.lvl:SetText(e.kind == "area" and #e.stops or e.level or "?")
          r.lvl:SetTextColor(rgb(e.color))
          r.name:SetText(e.name)
          if e.kind == "turnin" then r.name:SetTextColor(0.55, 0.9, 0.55) else r.name:SetTextColor(0.92, 0.92, 0.92) end
          r.meta:SetText(ns.meta(e))
          local todo = (not ns.db.compact) and e.kind ~= "pickup" and ns.todo(e)
          r.sub:SetText(todo or "")
          r:SetHeight(todo and ROW_H * 2 - 2 or ROW_H)
          updateArrow(r)
          r:Show()
          y = y - (todo and ROW_H * 2 - 2 or ROW_H)
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
-- Focus mode: the full board while the mouse is over it (or a drag runs),
-- back to Next and Active a moment after the mouse leaves.
ns.LEAVE_SECS = 0.4
local awaySecs = 0
-- Focus applies in combat and in a dungeon or other instance; out in the
-- world the whole board shows.
function ns.busy()
  if rawget(_G, "InCombatLockdown") and InCombatLockdown() then return true end
  local inside = call(rawget(_G, "IsInInstance"))
  return inside and true or false
end
function ns.focused() return ns.db.focus and ns.busy() and not ns.expanded end

function ns.hover(over, dt)
  if not (ns.db.focus and ns.busy()) then ns.expanded = false return end
  if over then
    awaySecs = 0
    if not ns.expanded then ns.expanded = true ns.render() end
  elseif ns.expanded then
    awaySecs = awaySecs + (dt or 0)
    if awaySecs >= ns.LEAVE_SECS then ns.expanded = false awaySecs = 0 ns.render() end
  end
end

local function tickFn(self, dt)
  ns.hover(self:IsMouseOver() or (self.isMoving == true), dt)
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
  panel.next = panel:CreateFontString(nil, "OVERLAY", FONT)
  panel.next:SetJustifyH("LEFT")
  panel.next:SetTextColor(1, 0.85, 0.35)
  if panel.next.SetWordWrap then panel.next:SetWordWrap(false) end
  local p = ns.db.point
  if p then
    panel:SetPoint(p[1], UIParent, p[4] or p[1], p[2], p[3])
    -- A place saved by an older build may be the centre: move it to the top.
    if p[1] ~= "TOPLEFT" and p[1] ~= "TOPRIGHT" and p[1] ~= "TOP" then ns.pinTop() end
  else panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -260) end
  panel:SetMovable(true)
  panel:EnableMouse(true)
  draggable(panel)
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
-- Far nameplates (/qb far on): enemy nameplates on, at the longest range the
-- client takes, so quest monsters (and Questie's nameplate icons) show from
-- further away. Only game settings; the old values are saved and put back
-- by /qb far off. The game keeps settings itself, so this runs only once.
---------------------------------------------------------------------------
ns.FAR = { nameplateMaxDistance = "60", nameplateShowEnemies = "1" }
local function getCVar(name)
  return call(api("C_CVar.GetCVar"), name) or call(rawget(_G, "GetCVar"), name)
end
local function setCVar(name, value)
  local set = api("C_CVar.SetCVar") or rawget(_G, "SetCVar")
  return type(set) == "function" and pcall(set, name, value)
end
function ns.far(on)
  if inCombat() then say("not in combat; try again after the fight") return false end
  if on then
    ns.db.farSaved = ns.db.farSaved or {}
    for name, value in pairs(ns.FAR) do
      if ns.db.farSaved[name] == nil then ns.db.farSaved[name] = getCVar(name) or false end
      setCVar(name, value)
    end
    say("enemy nameplates on, range " .. tostring(getCVar("nameplateMaxDistance") or "?") .. " yards (the most this client takes)")
  else
    for name, value in pairs(ns.db.farSaved or {}) do
      if value then setCVar(name, value) end
    end
    ns.db.farSaved = nil
    say("nameplates back to range " .. tostring(getCVar("nameplateMaxDistance") or "?") .. " yards")
  end
  return true
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
      C_Timer.After(5, function()
        ns.refresh()
        ns.applyTrackers()
        if ns.db.point and ns.db.point[1] ~= "TOPLEFT" then ns.pinTop() end
      end)
      C_Timer.After(15, ns.refresh)
    end
    return
  end
  if not panel then return end
  if event == "PLAYER_REGEN_DISABLED" then panel:SetAlpha(ns.db.combatAlpha) ns.render() return end
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
  "/qb - show or hide the board. Drag it anywhere to move it.",
  "/qb lock - stop dragging (again to undo)",
  "/qb focus - show the whole board all the time, not only on mouse-over (again to undo)",
  "/qb compact - one line per quest, without the what-to-do line (again to undo)",
  "Click a group name to fold it; right-click it to sort by nearest or best XP.",
  "/qb range N - pick-ups at most N levels over you (now %d)",
  "/qb rows N - rows per group (now %d)",
  "/qb reset - put the board back under the minimap",
  "/qb tracker off - hide the game's quest tracker (on brings it back)",
  "/qb far on - show enemy nameplates from as far as the game allows (off puts it back)",
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
  elseif cmd == "far" and (rest == "on" or rest == "off") then
    ns.far(rest == "on")
    return
  elseif cmd == "focus" then
    ns.db.focus = not ns.db.focus
    ns.expanded = false
    say(ns.db.focus and "in combat and instances: Next and Active only, mouse over for the rest" or "showing the whole board all the time")
    return ns.render()
  elseif cmd == "compact" then
    ns.db.compact = not ns.db.compact
    return ns.render()
  elseif cmd == "lock" then
    ns.db.locked = not ns.db.locked
    say(ns.db.locked and "locked: dragging does not move the board" or "unlocked: drag the board to move it")
    return
  elseif cmd == "reset" then
    ns.db.point = nil
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -260)
    return
  end
  for _, line in ipairs(help) do say(string.format(line, line:find("range") and ns.db.maxAbove or ns.db.rows.log)) end
end
