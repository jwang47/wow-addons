-- QuestBoard stops (in a spare file so it loads with /reload; rename it
-- Stops.lua before a release, AGENTS.md).
--
-- The Doing tab groups its quests by stop: the quests whose places are
-- close together make one trip. A stop shows how far it is, what you do
-- there and what it pays, once. Under it, one line per quest: a gold "?"
-- (hand in), a gold "!" (pick up) or a grey "?" (still to finish), like the
-- marks over the game's NPCs. /qb stops turns the layout off and on.
local _, ns = ...
local D = ns.data

ns.STOP_YARDS = 150          -- places this close to a stop's first quest join it
ns.STOP_INDENT = 14          -- room for the mark before the level
local GOLD, GREY, GREEN = "ffd100", "909090", "66dd66"

-- "hand" (ready to hand in), "pick" (to pick up) or "todo" (to finish).
function ns.stopRole(e)
  if ns.complete(e) then return "hand" end
  if e.kind == "pickup" or e.kind == "party" then return "pick" end
  return "todo"
end

local MARKS = { hand = "|cff" .. GOLD .. "?|r", pick = "|cff" .. GOLD .. "!|r", todo = "|cff" .. GREY .. "?|r" }
function ns.stopMark(e) return MARKS[ns.stopRole(e)] end

local function near(a, b)
  if a.wx and b.wx then
    if a.inst ~= b.inst then return false end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return dx * dx + dy * dy <= ns.STOP_YARDS * ns.STOP_YARDS
  end
  -- No place on the map: only the same NPC, as far away, is the same stop.
  return a.target ~= nil and a.target == b.target and a.dist == b.dist
end

local function plural(n, one) return n .. " " .. one .. (n == 1 and "" or "s") end

-- Fills in a stop's totals from its quests.
function ns.stopTotals(s)
  local hand, pick, todo = 0, 0, 0
  local handXP, allXP, work, guess, longest = 0, 0, 0, false, nil
  s.dist, s.angle, s.seed = nil, nil, s.list[1]
  for _, e in ipairs(s.list) do
    local role = ns.stopRole(e)
    if role == "hand" then hand = hand + 1 handXP = handXP + (e.xp or 0)
    elseif role == "pick" then pick = pick + 1
    else
      todo = todo + 1
      if e.left and #e.left > 0 then
        local secs, g = D.workSecs(e)
        work, guess = work + (secs or 0), guess or g or false
      end
    end
    allXP = allXP + (e.xp or 0)
    if e.secs and (not longest or e.secs > longest) then longest = e.secs end
    if e.dist and (not s.dist or e.dist < s.dist) then s.dist, s.angle, s.seed = e.dist, e.angle, e end
  end
  s.hand, s.pick, s.todo, s.handXP = hand, pick, todo, handXP
  -- XP: what the stop pays when you get there (its hand-ins), else what
  -- its quests pay in the end.
  s.xp = hand > 0 and handXP or allXP
  -- Time: the run there and the work on the quests you finish there. A
  -- stop with only pick-ups: the longest of those quests, a guess.
  if hand + todo > 0 then
    s.secs, s.guess = s.dist and (D.travelSecs(s.dist) + work) or nil, guess
  else
    s.secs, s.guess = longest, true
  end
  return s
end

-- The stops of a list of quests, in the order the list first reaches them.
function ns.stops(list)
  local out = {}
  for _, e in ipairs(list or {}) do
    local home
    for _, s in ipairs(out) do
      if near(e, s.list[1]) then home = s break end
    end
    if not home then home = { list = {} } table.insert(out, home) end
    table.insert(home.list, e)
  end
  for _, s in ipairs(out) do ns.stopTotals(s) end
  return out
end

-- "3 hand-ins", "1 hand-in, 2 pick-ups", "1 to finish". Hand-ins in green.
function ns.stopWhat(s)
  local parts = {}
  if s.hand > 0 then table.insert(parts, "|cff" .. GREEN .. plural(s.hand, "hand-in") .. "|r") end
  if s.pick > 0 then table.insert(parts, plural(s.pick, "pick-up")) end
  if s.todo > 0 then table.insert(parts, s.todo .. " to finish") end
  return table.concat(parts, ", ")
end

-- How far, or why there is no distance ("far", "no place").
function ns.stopPlace(s)
  if s.dist then return D.yards(s.dist) end
  return (ns.place(s.seed):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- "4.0k xp  1 min", "~" on a guess.
function ns.stopStats(s)
  local parts = {}
  if s.xp and s.xp > 0 then table.insert(parts, D.short(s.xp) .. " xp") end
  if s.secs then table.insert(parts, (s.guess and "~" or "") .. D.mins(s.secs)) end
  return table.concat(parts, "  ")
end

ns.HAND_IN_YARDS = 600       -- a hand-in this close is in Doing, and its stop comes first

-- The Doing tab as sections: one per stop, then the "+N more" line.
-- active: the quests you are on; way: the ones on the way; handIns: every
-- other quest ready to hand in.
-- A quest you can hand in close by is always here, and so is one whose
-- hand-in is at a stop already shown: you are there anyway. Only the other
-- quests on the way count against the group's row limit.
-- Order: the stops with a hand-in within HAND_IN_YARDS first, the best XP
-- per minute of the run first (so two hand-ins in one place beat one);
-- then the rest as the board ranked them. In a stop: hand-ins, quests to
-- finish, pick-ups.
function ns.stopSections(active, way, handIns)
  local quests, capped, seen = {}, {}, {}
  local function take(e) if not seen[e] then seen[e] = true table.insert(quests, e) end end
  for _, e in ipairs(active or {}) do take(e) end
  for _, e in ipairs(way or {}) do
    if ns.stopRole(e) == "hand" then take(e) else table.insert(capped, e) end
  end
  local rest = {}
  for _, e in ipairs(ns.shownRows("onway", capped)) do
    if e.kind == "more" then table.insert(rest, e) else take(e) end
  end
  local base = #quests
  for _, e in ipairs(handIns or {}) do
    if not seen[e] and not e.hiddenTag and ns.stopRole(e) == "hand" then
      local join = e.dist and e.dist <= ns.HAND_IN_YARDS
      for i = 1, base do
        if join then break end
        join = near(e, quests[i])
      end
      if join then take(e) end
    end
  end
  local stops = ns.stops(quests)
  local ORDER = { hand = 1, todo = 2, pick = 3 }
  for i, s in ipairs(stops) do
    s.index = i
    local at = {}
    for j, e in ipairs(s.list) do at[e] = j end
    table.sort(s.list, function(a, b)
      local ra, rb = ORDER[ns.stopRole(a)], ORDER[ns.stopRole(b)]
      if ra ~= rb then return ra < rb end
      return at[a] < at[b]
    end)
    s.first = s.hand > 0 and s.dist ~= nil and s.dist <= ns.HAND_IN_YARDS
    s.handRate = s.first and s.handXP / math.max(20, D.travelSecs(s.dist)) or 0
  end
  table.sort(stops, function(a, b)
    if a.first ~= b.first then return a.first end
    if a.handRate ~= b.handRate then return a.handRate > b.handRate end
    return a.index < b.index
  end)
  local out = {}
  for i, s in ipairs(stops) do
    table.insert(out, { key = "stop" .. i, stop = s, list = s.list, cap = math.huge })
  end
  if #rest > 0 then table.insert(out, { key = "stopmore", nohead = true, list = rest, cap = math.huge }) end
  return out
end

---------------------------------------------------------------------------
-- Drawing: the board's layout pass calls these for a stop's head and rows.
---------------------------------------------------------------------------
local function facing() return D.plain(D.call(rawget(_G, "GetPlayerFacing"))) end

function ns.stopArrow(h)
  if not h.arrow then return end
  local s, f = h.stop, facing()
  if not (s and s.angle and f) then h.arrow:Hide() return end
  h.arrow:SetRotation(s.angle - f)
  h.arrow:Show()
end

-- A stop's head: a dot (green with a hand-in, else gold), how far with an
-- arrow, what you do there, and at the right what it pays.
function ns.stopHead(h, sec)
  local s = sec.stop
  h.stop, h.list, h.hint = s, s.list, nil
  if not h.dot then
    h.dot = h:CreateTexture(nil, "ARTWORK")
    h.dot:SetSize(6, 6)
    h.dot:SetPoint("LEFT", 3, 0)
    h.arrow = h:CreateTexture(nil, "OVERLAY")
    h.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    h.arrow:SetSize(14, 14)
    h.what = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h.text:ClearAllPoints()
    h.text:SetPoint("LEFT", ns.STOP_INDENT, 1)
    h.arrow:SetPoint("LEFT", h.text, "RIGHT", 1, 0)
    h.what:SetPoint("LEFT", h.arrow, "RIGHT", 3, 0)
    h.line:Hide()
  end
  if s.hand > 0 then h.dot:SetColorTexture(0.4, 0.87, 0.4, 1) else h.dot:SetColorTexture(1, 0.82, 0, 1) end
  h.text:SetTextColor(1, 1, 1)
  h.text:SetText(ns.stopPlace(s))
  h.what:SetText(ns.stopWhat(s))
  h.right:SetText(ns.stopStats(s))
  ns.stopArrow(h)
end

function ns.stopTip(h)
  local tip, s = rawget(_G, "GameTooltip"), h.stop
  if not (tip and s) then return end
  tip:SetOwner(h, "ANCHOR_LEFT")
  local dir = s.dist and s.angle and (" " .. D.compass(s.angle)) or ""
  tip:AddLine("Stop: " .. ns.stopPlace(s) .. dir, 1, 1, 1)
  local VERB = { hand = "hand in to ", pick = "get it from ", todo = "" }
  for _, e in ipairs(s.list) do
    local role = ns.stopRole(e)
    local who = e.target and (VERB[role] .. e.target) or (role == "hand" and "hand it in" or role == "pick" and "pick it up" or "to finish")
    tip:AddLine("- " .. e.name .. ": " .. who, 0.85, 0.85, 0.85)
  end
  local stats = ns.stopStats(s)
  if stats ~= "" then
    tip:AddLine(stats .. (s.hand > 0 and "  (the hand-ins, and the run there)" or s.todo > 0 and "  (when you finish them)" or "  (the quests you pick up, a guess)"), 0.6, 0.8, 1)
  end
  tip:AddLine(" ")
  tip:AddLine("Click: show the stop on the map", 0.6, 0.6, 0.6)
  local n = #ns.listQuests(s.list)
  if n > 0 then
    tip:AddLine(ns.listPinned(s.list) and ("Alt-click: unpin these " .. n .. " quests") or ("Alt-click: pin all " .. n .. " quests (keep them in Doing)"), 0.6, 0.8, 1)
  end
  tip:Show()
end

-- A click on a stop's head shows the stop on the map (its nearest quest).
function ns.stopClick(h, button)
  if rawget(_G, "IsAltKeyDown") and IsAltKeyDown() then return ns.pinList(h.stop.list) end
  return ns.click(h.stop.seed, button == "RightButton" and "LeftButton" or button)
end

-- A small square in the colour of the gear a quest gives or leads to.
local QUALITY = { [2] = "30:255:0", [3] = "0:112:221", [4] = "163:53:238", [5] = "255:128:0" }
function ns.gearMark(e)
  if not ns.rewardLine(e) then return "" end
  local c = e.chain
  local item = c and (c.best and c.best.gear and c.best or c.own)
  local rgb = QUALITY[item and item.quality or 2] or QUALITY[2]
  return " |TInterface\\Buttons\\WHITE8X8:6:6:0:0:8:8:0:8:0:8:" .. rgb .. "|t"
end

-- Who a quest's row names at the right: the NPC to see or the thing to
-- find. Left out when the name and it do not both fit in width, so the
-- quest's name is never cut for it (the tooltip has it).
function ns.stopWho(e, name, width)
  local who = e.target
  if not who or who == "" then return "" end
  local probe = ns.probe
  if probe and probe.GetStringWidth and width then
    probe:SetText(name .. "    " .. who)
    if (probe:GetStringWidth() or 0) > width then return "" end
  end
  return "|cff" .. GREY .. who .. "|r"
end

-- The lines under a quest's row in a stop: only for a quest still to
-- finish, its open objectives and your party. Hand-ins and pick-ups are
-- one line.
function ns.stopLines(e)
  if ns.db.compact or ns.stopRole(e) ~= "todo" then return {} end
  local lines = ns.activeLines(e, true)
  -- The row already names the place at its right.
  if #lines == 1 and e.target and lines[1] == "Go to " .. e.target then return {} end
  return lines
end
