-- QuestBoard: a small floating board of the quests that matter now, in
-- four tabs for what you are doing: Doing (the quest you are on and the
-- stops on the way), Nearby (what to chain next, best XP per minute with
-- the walk counted), Areas (zones to go to or swap to) and Log (every
-- quest in your log, by zone). The board picks Doing or Nearby by itself;
-- a click on a tab keeps that tab. Click a row to pin the place on the
-- map. /qb for the commands.
local addonName, ns = ...
QuestBoard = ns                     -- global, for /dump
-- GroupUp uses these; keep them stable: QuestBoardDB.doing (questID set),
-- QuestBoard.click(e, button), QuestBoard.panel, row.entry. Ctrl-click on a
-- quest row belongs to GroupUp.
ns.VERSION = "0.2.0"
local D = ns.data
local call, api = D.call, D.api

local defaults = {
  shown = true,
  sortLog = "near",      -- near | xp
  sortPickup = "xp",     -- near | xp
  maxAbove = 3,          -- pick-ups at most this many levels over you
  rows = { onway = 5, next = 8, zones = 8, town = 2, members = 4 },
  collapsed = {},
  showAll = {},      -- groups opened past their row limit ("+N more")
  combatAlpha = 0.35,
  hideTrackers = false,  -- hide the game's quest tracker (and Questie's)
  locked = false,        -- /qb lock: no dragging
  compact = false,       -- /qb compact: one line per quest, no "what to do" line
  stops = true,          -- /qb stops: the Doing tab groups its quests by stop (Spare1.lua)
  dungeons = true,       -- /qb dungeons off: dungeon and raid quests only in the Log tab
  party = true,          -- /qb party off: no party quests here, nor Questie's party objectives on the map
  focus = true,          -- in combat and instances: only the quests you are on until mouse-over
  point = nil,           -- saved position { point, x, y }
  maxHeight = nil,       -- drag the grip (or /qb height N): scroll past it
  width = 270,           -- drag the grip sideways (or /qb width N)
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
local W, ROW_H, HEAD_H, PAD = 270, 15, 16, 6   -- W: the board width, from ns.db.width
local LVL_W = 26                 -- the level column: room for "33D"
local TEXT_X = LVL_W + 6         -- where the name and the lines under it start
local WRAP_MAX = 2               -- screen lines one text line may take
ns.MIN_W, ns.MAX_W = 220, 560
-- Spacing that shows the grouping: a quest's two lines sit close, quests
-- have a small gap between them, groups a bigger one.
local SUB_UP, ROW_GAP, GROUP_GAP = 3, 8, 12
local BAR_GAP = 4                -- space above a quest's progress bar
local FONT, FONT_DIM = "GameFontHighlightSmall", "GameFontDisableSmall"
-- Where the board shows each kind of quest (for /qb why).
ns.WHERE = { active = "in the Doing tab (you are on it)", nearby = "in the Log tab, and in Nearby (close by)",
  turnin = "ready to hand in: the Log tab, and Nearby within 1000 yd", log = "in the Log tab, and in Nearby within 1000 yd",
  party = "a party quest: Nearby within 1000 yd", pickup = "to pick up: Nearby within 1000 yd, else under its zone in Areas",
  farPickup = "to pick up, far away: under its zone in the Areas tab" }

local panel, rows, heads = nil, {}, {}
ns.rows = rows
local state = nil        -- last collect() result

local function rgb(name) local c = D.COLORS[name] or D.COLORS.yellow return c[1], c[2], c[3] end

-- What to do for a quest, in a few words: the open objective and where
-- (Questie's nearest mob, object or NPC for it), or who takes it in.
function ns.todo(e)
  local text = ns.todoWho(e)
  -- A hand-in shows what it gives, so you can judge the trip.
  local tag = e.kind == "turnin" and D.rewardTag and D.rewardTag(e.chain) or ns.chainNote(e)
  if tag then text = (text and (text .. "   ") or "") .. tag end
  return text
end

-- Where the chain leads, for the line under a quest. "XP only" is left
-- out (the tooltip says it): only gear at the end is worth a line.
function ns.chainNote(e)
  local tag = D.chainTag and D.chainTag(e.chain)
  if not tag or tag == "XP only" then return nil end
  return (tag:gsub(", XP only$", ""))
end

-- The lines under an Active quest: each open objective (the first with
-- where to find it), who in your party has it, and where the chain leads.
ns.ACTIVE_LINES = 5
function ns.activeLines(e, noTag)
  local lines = {}
  for i, o in ipairs(e.left or {}) do
    local text = o.text
    if text and text ~= "" then
      if i == 1 and e.target and not text:find(e.target, 1, true) then text = text .. "  (" .. e.target .. ")" end
      table.insert(lines, text)
    end
  end
  if #lines == 0 then local t = ns.todoBase(e) if t then table.insert(lines, t) end end
  if e.party and #e.party > 0 then table.insert(lines, "|cff99ccffParty: " .. D.partyText(e.party) .. "|r") end
  local tag = not noTag and ns.chainNote(e)
  if tag then table.insert(lines, tag) end
  while #lines > ns.ACTIVE_LINES do table.remove(lines) end
  return lines
end

function ns.todoWho(e)
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
  if e.kind == "member" then return D.memberText(e) end
  if e.kind == "zone" then return D.zoneText(e) end
  if e.kind == "town" then
    local where = D.zoneName(e.zone)
    return (e.role == "inn" and "Innkeeper" or "Flight master") .. (where and (", " .. where) or "")
  end
  if e.kind == "turnin" then
    -- Far away (another continent or an instance): say where.
    local where = e.far and D.zoneName(e.zone)
    return (e.target and ("Hand in to " .. e.target) or "Hand it in") .. (where and (" in " .. where) or "")
  end
  if e.fromItem then
    local what = e.startItem and ((e.dropHow == "vendor" and "Buy " or "Loot ") .. e.startItem) or "Starts from an item"
    local from = e.dropFrom and (" from " .. e.dropFrom) or (e.kind == "pickup" or e.kind == "party") and " (drop unknown)" or ""
    return what .. from .. (e.finisher and (", hand in to " .. e.finisher) or "")
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
  -- Not when you are already there: then the nearest stop is the next step.
  local best = not st.active[1] and st.area and st.area[1]
  if best and #best.stops >= 3 and (best.dist or 0) > D.AREA_YARDS then
    return "Go " .. best.name:lower() .. ": " .. D.areaText(best) .. "  " .. D.yards(best.dist), best
  end
  -- Else the step with the best XP per minute from here (travel counts),
  -- among the hand-ins and quests with a known place; a far hand-in with
  -- big XP loses to a near one.
  local e = st.active[1]
  if not e then
    local bestRate
    for _, list in ipairs({ st.turnin, st.nearby, st.log }) do
      for _, c in ipairs(list or {}) do
        if c.dist and c.rate and (not bestRate or c.rate > bestRate) then e, bestRate = c, c.rate end
      end
    end
  end
  e = e or st.turnin[1] or st.nearby[1] or st.log[1]
  if not e then return nil end
  local todo = ns.todoWho(e)
  if e.kind == "turnin" then todo = "Hand in " .. e.name .. (e.target and (" to " .. e.target) or "") end
  -- For a quest you are on: about how long the rest takes, at your pace.
  local left = e == st.active[1] and e.left and #e.left > 0 and ("  ~" .. D.mins(D.travelSecs(e.dist, e) + D.workSecs(e)) .. " left") or ""
  return todo and (todo .. (e.dist and ("  " .. D.yards(e.dist)) or "") .. left), e
end

-- Right-hand text of a row: progress, XP and run time (hand-ins), XP/min
-- (pick-ups), distance. The
-- progress is in the "what to do" line unless the board is compact.
-- Quest rows (not zones, areas, towns or party members) use the two-line
-- layout: line 1 the name and how far, line 2 what to do and what it pays.
ns.QUEST_KINDS = { log = true, turnin = true, pickup = true, party = true }

-- Line 1, right: how far, or why there is no distance.
function ns.place(e)
  if e.dist then return D.yardsText(e.dist) end
  if e.far then return "|cff909090far|r" end
  if e.toFinisher then return "|cff909090drop unknown|r" end
  if e.kind == "log" and not e.done then return "|cff909090no place|r" end
  return ""
end

-- Line 2, right: the same two numbers on every quest, "625 xp  3 min",
-- coloured by how good the XP per minute is. "~" marks a guess.
function ns.stats(e, kind)
  if e.toFinisher then return "" end
  local secs, guess
  if e.kind == "turnin" then
    secs = e.dist and D.travelSecs(e.dist, e)
  elseif e.kind == "log" and not e.done and e.left and #e.left > 0 then
    local work
    work, guess = D.workSecs(e)
    secs = D.travelSecs(e.dist, e) + work
  else
    secs, guess = e.secs, true
  end
  local parts = {}
  if e.xp and e.xp > 0 then table.insert(parts, D.short(e.xp) .. " xp") end
  if secs then table.insert(parts, (guess and "~" or "") .. D.mins(secs)) end
  return D.tierText(e, table.concat(parts, "  "))
end

-- The gear line under a quest, or nil when it gives only XP:
-- "Reward: [Rose Mantle]" or "Leads to [Seal of Wrynn], 4 quests on".
function ns.rewardLine(e)
  local info = e.chain
  if not info then return nil end
  local b = info.best
  local good = b and b.gear and (b.quality or 2) >= 2
  if e.kind == "turnin" then
    local text = info.own and ("Reward: " .. D.itemText(info.own) .. (info.count > 1 and (" or " .. (info.count - 1) .. " more") or "")) or nil
    if good and not info.here then
      text = (text and (text .. ", then ") or "Leads to ") .. D.itemText(b)
    end
    return text
  end
  if not good then return nil end
  if info.here then return "Reward: " .. D.itemText(b) end
  local steps = info.steps or 0
  return "Leads to " .. D.itemText(b) .. (steps > 0 and (", " .. steps .. (steps == 1 and " quest on" or " quests on")) or "")
end

function ns.meta(e, kind)
  local parts = {}
  if e.kind == "log" and ns.db and ns.db.compact then
    local p = D.progress(e)
    if p ~= "" then table.insert(parts, p) end
  end
  if e.kind == "log" and not e.done and kind == "active" and e.left and #e.left > 0 then
    table.insert(parts, "~" .. D.mins(D.travelSecs(e.dist, e) + D.workSecs(e)))
  end
  if e.kind == "turnin" and e.xp then table.insert(parts, D.tierText(e, D.short(e.xp) .. " xp")) end
  -- A hand-in: the run there, so you can weigh the trip against the XP.
  if e.kind == "turnin" and e.dist then table.insert(parts, D.mins(D.travelSecs(e.dist, e))) end
  if e.toFinisher then table.insert(parts, "|cff909090drop unknown|r")
  elseif (e.kind == "pickup" or e.kind == "area" or e.kind == "zone") and e.rate then table.insert(parts, D.tierText(e, "~" .. D.short(e.rate) .. " xp/m")) end
  if e.dist then table.insert(parts, D.yardsText(e.dist))
  elseif e.far then table.insert(parts, "|cff909090far|r")
  elseif e.kind == "log" and not e.done then table.insert(parts, "|cff909090no place|r")
  elseif e.fromItem then table.insert(parts, "item") end
  return table.concat(parts, "  ")
end

-- The quests in your log, from the last pass: questID -> true.
function ns.inLog()
  local set = {}
  for _, kind in ipairs({ "active", "nearby", "turnin", "log" }) do
    for _, e in ipairs(state and state[kind] or {}) do
      if e.kind == "log" or e.kind == "turnin" then set[e.id] = true end
    end
  end
  return set
end

local function facing() return D.plain(call(rawget(_G, "GetPlayerFacing"))) end

local function updateArrow(r)
  local e = r.entry
  if r.noArrow or not (e and e.angle) then r.arrow:Hide() return end
  local f = facing()
  if not f then r.arrow:Hide() return end
  r.arrow:SetRotation(e.angle - f)
  r.arrow:Show()
end

local function tooltip(r)
  local e, tip = r.entry, rawget(_G, "GameTooltip")
  if not (e and tip) then return end
  tip:SetOwner(r, "ANCHOR_LEFT")
  if e.kind == "more" and e.tab then
    tip:AddLine("Click: the " .. ns.TAB_NAMES[e.tab] .. " tab", 1, 1, 1)
    tip:Show()
    return
  end
  if e.kind == "zone" then
    tip:AddLine(e.name .. (e.dist and ("  (" .. D.yards(e.dist) .. ")") or "  (far)"), 1, 1, 1)
    tip:AddLine(D.zoneText(e), 0.8, 0.8, 0.8)
    if e.rate then tip:AddLine(string.format("~%s XP per minute, %s XP there, trip counted", D.short(e.rate), D.short(e.xp)), 0.6, 0.8, 1) end
    for i, s in ipairs(e.stops) do
      if i > 12 then tip:AddLine("  (" .. (#e.stops - 12) .. " more)", 0.6, 0.6, 0.6) break end
      local what = s.kind == "turnin" and "hand in" or (s.kind == "pickup" or s.kind == "party") and "pick up" or "in your log"
      tip:AddLine("- [" .. (s.level or "?") .. "] " .. s.name .. "  (" .. what .. ")", rgb(s.color))
    end
    tip:AddLine(" ")
    tip:AddLine(e.near and "Click: pin the nearest stop on the map" or "Far away: no pin from here", 0.5, 0.5, 0.5)
    tip:AddLine(ns.listPinned({ e }) and "Alt-click: unpin these quests" or "Alt-click: pin all of them (keep them in Doing)", 0.5, 0.5, 0.5)
    tip:Show()
    return
  end
  if e.kind == "more" then
    tip:AddLine(ns.db.showAll and ns.db.showAll[e.group] and "Click: back to the first rows" or "Click: show the whole group", 1, 1, 1)
    for _, n in ipairs(e.hidden or {}) do tip:AddLine("- " .. n, 0.8, 0.8, 0.8) end
    tip:Show()
    return
  end
  if e.kind == "member" then
    tip:AddLine(e.name .. (e.level and ("  level " .. e.level) or ""), 1, 1, 1)
    local where = e.dist and (D.yards(e.dist) .. (e.angle and (" " .. D.compass(e.angle)) or "")) or e.zoneName or "place unknown"
    tip:AddLine((e.status and (e.status .. ", ") or "") .. (e.hp and (e.hp .. "% health, ") or "") .. where, 0.8, 0.8, 0.8)
    if #(e.shared or {}) > 0 then
      tip:AddLine(" ")
      tip:AddLine("Your quests they have (theirs / yours):", 0.6, 0.8, 1)
      for _, s in ipairs(e.shared) do
        local theirs = s.progress ~= "" and s.progress or "?"
        local mine = s.mine ~= "" and s.mine or "-"
        tip:AddLine("- " .. s.name .. "  " .. theirs .. " / " .. mine, 0.85, 0.85, 0.85)
      end
    end
    if (e.theirs or 0) > 0 then tip:AddLine(e.theirs .. " of their quests you do not have (Party has)", 0.6, 0.6, 0.6) end
    tip:AddLine(" ")
    tip:AddLine("Click: pin where they are on the map", 0.5, 0.5, 0.5)
    tip:AddLine("Progress needs Questie on their side too; /qb party off hides this", 0.5, 0.5, 0.5)
    tip:Show()
    return
  end
  if e.kind == "town" then
    tip:AddLine(e.name .. "  (" .. D.yards(e.dist) .. " " .. D.compass(e.angle) .. ")", 1, 1, 1)
    tip:AddLine(ns.todoBase(e), 0.8, 0.8, 0.8)
    tip:AddLine("Nearest " .. (e.role == "inn" and "innkeeper" or "flight master") .. " friendly to you (Questie's NPC data)", 0.6, 0.6, 0.6)
    tip:AddLine(" ")
    tip:AddLine("Click: pin it on the map and follow the arrow", 0.5, 0.5, 0.5)
    tip:Show()
    return
  end
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
    if #ns.areaQuests(e) > 0 then
      tip:AddLine(ns.areaPinned(e) and "Alt-click: no longer doing these" or "Alt-click: I'm doing all of these (keep them in Active)", 0.5, 0.5, 0.5)
    end
    tip:Show()
    return
  end
  tip:AddLine(e.name, rgb(e.color))
  local slow = (e.kind == "log" or e.kind == "pickup" or e.kind == "party") and not e.done and not D.pace[e.id] and D.levelFactor(e.level) or 1
  if slow > 1 then
    tip:AddLine(string.format("%d level%s over you: counted %.1fx slower%s", e.level - D.playerLevel(), e.level - D.playerLevel() == 1 and "" or "s", slow,
      slow >= D.RED_SLOW and " (hard to do alone)" or ""), 1, 0.6, 0.3)
  end
  if e.tag then tip:AddLine("Level " .. (e.level or "?") .. " " .. D.TAG_TEXT[e.tag] .. (D.isDungeon(e) and " (/qb dungeons off hides these outside the Log tab)" or ""), 1, 0.6, 0.3) end
  local lvl = "Level " .. (e.level or "?")
  if e.req and e.req ~= e.level then lvl = lvl .. " (needs " .. e.req .. ")" end
  tip:AddLine(lvl, 0.8, 0.8, 0.8)
  if e.xp then tip:AddLine(D.short(e.xp) .. " XP", 0.6, 0.8, 1) end
  if e.kind == "turnin" and e.dist then
    tip:AddLine(string.format("About %s to %s, ~%s XP per minute of the trip", D.mins(D.travelSecs(e.dist, e)), e.by == "fly" and "fly there (if you have the flight path)" or "run there", D.short(e.rate)), 0.6, 0.8, 1)
  elseif e.kind == "turnin" and e.far then
    tip:AddLine("On another continent or in an instance: a boat, a flight or a dungeon run", 0.8, 0.5, 0.5)
  elseif e.rate and e.secs then
    local guess = (e.kind == "log" and not e.done) and select(2, D.workSecs(e))
    tip:AddLine(string.format("~%s XP per minute (about %d min%s)", D.short(e.rate), math.max(1, math.floor(e.secs / 60 + 0.5)),
      D.runSecs and D.runSecs(e) and (e.tag == "R" and ", a raid run" or ", a dungeon run")
        or guess and ", a guess until you make progress" or ""), 0.6, 0.8, 1)
    if e.by == "fly" then tip:AddLine("The trip is by flight (if you have the flight path)", 0.6, 0.8, 1) end
    if e.far then tip:AddLine("On another continent: about " .. D.mins(D.FAR_TRIP_SECS) .. " counted for the boat or zeppelin, a guess", 0.8, 0.5, 0.5) end
  end
  local verb = e.kind == "turnin" and "Turn in at " or e.toFinisher and "Hand in to " or (e.kind == "pickup" or e.kind == "party") and "Get it from " or "Nearest: "
  if e.target then
    local where = D.zoneName(e.zone)
    tip:AddLine(verb .. e.target .. (where and (", " .. where) or "") .. (e.dist and ("  " .. D.yards(e.dist) .. " " .. D.compass(e.angle)) or ""), 1, 1, 1)
  end
  if e.fromItem then
    local how = e.dropHow == "vendor" and ", sold by " or e.dropHow == "object" and ", found in " or ", drops from "
    tip:AddLine("Starts from an item" .. (e.startItem and (": " .. e.startItem) or "") .. (e.dropFrom and (how .. e.dropFrom) or ""), 0.8, 0.8, 0.8)
    if e.toFinisher then tip:AddLine("Questie does not know where it drops; the distance is to " .. e.finisher, 0.8, 0.5, 0.5) end
    if e.finisher and not e.toFinisher then tip:AddLine("Hand in to " .. e.finisher, 0.8, 0.8, 0.8) end
  end
  if not e.spawn and not e.spot then tip:AddLine("Questie has no place for this quest", 0.8, 0.5, 0.5) end
  for _, o in ipairs(e.left or {}) do
    if o.text then tip:AddLine("- " .. o.text, 0.8, 0.8, 0.8) end
  end
  tip:AddLine(" ")
  tip:AddLine("Click: show it on the map   Shift-click: link", 0.5, 0.5, 0.5)
  if e.item then tip:AddLine("Quest item: the button left of this row uses it", 0.6, 0.8, 1) end
  local c = e.chain
  if c and c.own then
    tip:AddLine("Reward: " .. D.itemText(c.own) .. (c.count > 1 and ("  (one of " .. c.count .. ")") or ""), 1, 1, 1)
  end
  if c then
    if c.best and c.best.gear and c.here then
      -- The reward line above already names it.
    elseif c.best and c.best.gear then
      tip:AddLine((c.here and "Reward: " or ("Chain (" .. c.steps .. " more quest" .. (c.steps == 1 and "" or "s") .. ") leads to: ")) ..
        (D.chainTag({ steps = 0, here = true, best = c.best }):gsub("^%-> ", "")), 1, 1, 1)
    else
      tip:AddLine("No gear at the end of this quest" .. (c.steps > 0 and " chain" or "") .. ": XP only, fine to drop", 0.6, 0.6, 0.6)
    end
  end
  if e.id and e.id > 0 and D.chainSteps then
    local steps, at = D.chainSteps(e.id, ns.inLog())
    for _, line in ipairs(D.chainLines(steps, at, e)) do
      if type(line) == "table" then tip:AddDoubleLine(line[1], line[2], 0.85, 0.85, 0.85, 0.6, 0.8, 1)
      else tip:AddLine(line, 0.85, 0.85, 0.85) end
    end
  end
  if e.party and #e.party > 0 then
    tip:AddLine((e.kind == "party" and "Your party has it: " or "With ") .. D.partyText(e.party), 0.6, 0.8, 1)
  end
  if ns.pinnable(e) then
    tip:AddLine(e.pinned and "Alt-click: no longer doing it" or "Alt-click: I'm doing this (keep it in Active)", 0.5, 0.5, 0.5)
  end
  if e.kind ~= "pickup" and e.kind ~= "party" then tip:AddLine("Right-click: open the quest log", 0.5, 0.5, 0.5)
  else tip:AddLine("Right-click: show the giver on the map (not in your quest log yet)", 0.5, 0.5, 0.5) end
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
  -- Placed by where you last made progress: pin that spot.
  if e.spot and e.spot.mapID then
    ns.openMap(e.spot.mapID)
    local id, px, py = pinPoint(e.spot.mapID, e.spot.x, e.spot.y)
    local point, set = api("UiMapPoint.CreateFromCoordinates"), api("C_Map.SetUserWaypoint")
    if id and point and set and pcall(set, call(point, id, px, py)) then
      call(api("C_SuperTrack.SetSuperTrackedUserWaypoint"), true)
      return true
    end
  end
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
  if e.kind == "town" or e.kind == "area" or e.kind == "member" or e.kind == "more" or e.kind == "zone" then return end
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

-- Alt-click marks any quest (log, hand-in or pick-up) as one you are doing (Active), or
-- takes the mark off.
function ns.toggleDoing(e)
  ns.db.doing = ns.db.doing or {}
  if ns.db.doing[e.id] then
    ns.db.doing[e.id] = nil
    D.heldAt[e.id] = nil
  else
    ns.db.doing[e.id] = true
  end
  ns.refresh()
end

-- Quest entries (not areas or town rows) can be marked as doing.
function ns.pinnable(e) return e and e.id and e.kind ~= "more" and e.kind ~= "zone" and e.kind ~= "area" and e.kind ~= "town" and e.kind ~= "member" and true or false end

-- The quests in an area that you can mark as doing: every stop there
-- (objectives, hand-ins and pick-ups).
function ns.areaQuests(a)
  local list = {}
  for _, s in ipairs(a.stops or {}) do
    if ns.pinnable(s) then table.insert(list, s) end
  end
  return list
end
function ns.areaPinned(a)
  local list = ns.areaQuests(a)
  if #list == 0 then return false end
  for _, s in ipairs(list) do if not (ns.db.doing and ns.db.doing[s.id]) then return false end end
  return true
end

-- The quests in a list (an area's stops count as quests), for pin all.
function ns.listQuests(list)
  local out, seen = {}, {}
  local function add(e) if ns.pinnable(e) and not seen[e.id] then seen[e.id] = true table.insert(out, e) end end
  for _, e in ipairs(list or {}) do
    if e.kind == "area" or e.kind == "zone" then for _, s in ipairs(e.stops or {}) do add(s) end else add(e) end
  end
  return out
end
function ns.listPinned(list)
  local qs = ns.listQuests(list)
  if #qs == 0 then return false end
  for _, e in ipairs(qs) do if not (ns.db.doing and ns.db.doing[e.id]) then return false end end
  return true
end
-- Alt-click on a list's heading: pin every quest in it; again to unpin.
function ns.pinList(list)
  ns.db.doing = ns.db.doing or {}
  local off = ns.listPinned(list)
  for _, e in ipairs(ns.listQuests(list)) do
    if off then ns.db.doing[e.id] = nil D.heldAt[e.id] = nil else ns.db.doing[e.id] = true end
  end
  ns.refresh()
end

-- Alt-click on an area: mark every quest there as doing; again to unmark.
function ns.toggleArea(a)
  ns.db.doing = ns.db.doing or {}
  local off = ns.areaPinned(a)
  for _, s in ipairs(ns.areaQuests(a)) do
    if off then ns.db.doing[s.id] = nil D.heldAt[s.id] = nil else ns.db.doing[s.id] = true end
  end
  ns.refresh()
end

function ns.click(e, button)
  if not e then return end
  if e.kind == "more" and e.tab then return ns.pickTab(e.tab) end
  -- Alt-click a zone: pin every quest there (your log, hand-ins, pick-ups).
  if e.kind == "zone" and rawget(_G, "IsAltKeyDown") and IsAltKeyDown() then return ns.pinList({ e }) end
  if e.kind == "zone" then
    if e.near then return ns.pin(e.near) end
    ns.sayOnce("zone:" .. e.name, e.name .. ": far away (another continent); open the map to plan the trip")
    return false
  end
  if e.kind == "more" then
    ns.db.showAll = ns.db.showAll or {}
    ns.db.showAll[e.group] = not ns.db.showAll[e.group] or nil
    return ns.render()
  end
  if e.kind == "member" then
    if e.spot and e.spot.mapID then return ns.pin(e) end
    ns.sayOnce("noplace:" .. e.name, e.name .. ": the game does not say where they are (a dungeon or too far)")
    return false
  end
  if rawget(_G, "IsAltKeyDown") and IsAltKeyDown() and ns.pinnable(e) then
    return ns.toggleDoing(e)
  end
  if rawget(_G, "IsAltKeyDown") and IsAltKeyDown() and e.kind == "area" then return ns.toggleArea(e) end
  if rawget(_G, "IsShiftKeyDown") and IsShiftKeyDown() then return ns.link(e) end
  if button == "RightButton" then
    if e.kind == "pickup" or e.kind == "party" then return ns.showGiver(e) end
    if e.kind == "area" or e.kind == "town" then return ns.pin(e) end
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
  if ns.updateItems then ns.updateItems(state) end   -- the item buttons follow (after combat if in it)
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

-- Rows and heads take the mouse, so they pass the wheel to the board.
local function wheel(f)
  if not f.EnableMouseWheel then return end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta) ns.scrollBy(delta) end)
end

-- Splits each line that is wider than width into screen lines, at spaces,
-- at most WRAP_MAX for one line (the last one is cut with "..." by the
-- game). Measures with a hidden font string; without one, keeps the lines.
function ns.wrapLines(lines, width)
  if not ns.probe and panel then
    -- Shown but clear: a hidden font string may not measure its text.
    ns.probe = panel:CreateFontString(nil, "BACKGROUND", FONT_DIM)
    ns.probe:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    if ns.probe.SetWordWrap then ns.probe:SetWordWrap(false) end
    if ns.probe.SetAlpha then ns.probe:SetAlpha(0) end
  end
  local probe = ns.probe
  if not (probe and probe.GetStringWidth and width and width > 0) then return lines end
  local function wide(text) probe:SetText(text) return (probe:GetStringWidth() or 0) > width end
  local out = {}
  for _, line in ipairs(lines) do
    local rest, parts = line, 0
    while rest ~= "" and wide(rest) and parts < WRAP_MAX - 1 do
      local cut
      for pos in rest:gmatch("() ") do
        if pos > 1 and not wide(rest:sub(1, pos - 1)) then cut = pos else break end
      end
      if not cut then break end
      table.insert(out, rest:sub(1, cut - 1))
      rest = "  " .. rest:sub(cut + 1)
      parts = parts + 1
    end
    table.insert(out, rest)
  end
  return out
end

local function makeRow(i)
  local r = CreateFrame("Button", nil, panel)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.lvl = r:CreateFontString(nil, "OVERLAY", FONT)
  r.lvl:SetPoint("TOPLEFT", 0, -1)
  r.lvl:SetWidth(LVL_W)
  r.lvl:SetJustifyH("RIGHT")
  if r.lvl.SetWordWrap then r.lvl:SetWordWrap(false) end
  r.arrow = r:CreateTexture(nil, "OVERLAY")
  r.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  r.arrow:SetSize(14, 14)
  r.arrow:SetPoint("TOPRIGHT", 0, 0)
  r.meta = r:CreateFontString(nil, "OVERLAY", FONT_DIM)
  r.meta:SetPoint("TOPRIGHT", -16, -1)
  r.meta:SetJustifyH("RIGHT")
  r.name = r:CreateFontString(nil, "OVERLAY", FONT)
  r.name:SetPoint("TOPLEFT", r.lvl, "TOPRIGHT", 6, 0)
  r.name:SetPoint("TOPRIGHT", r.meta, "TOPLEFT", -6, 0)
  r.name:SetJustifyH("LEFT")
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  -- The "what to do" line under the name.
  r.sub = r:CreateFontString(nil, "OVERLAY", FONT_DIM)
  r.sub:SetPoint("TOPLEFT", TEXT_X, -ROW_H + SUB_UP)
  r.sub:SetPoint("TOPRIGHT", -16, -ROW_H + SUB_UP)
  r.sub:SetJustifyH("LEFT")
  if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
  r.more = {}   -- extra lines for Active quests
  r.stats = r:CreateFontString(nil, "OVERLAY", FONT_DIM)
  r.stats:SetPoint("TOPRIGHT", -16, -ROW_H + SUB_UP)
  r.stats:SetJustifyH("RIGHT")
  if r.stats.SetWordWrap then r.stats:SetWordWrap(false) end
  r.pin = r:CreateTexture(nil, "OVERLAY")
  r.pin:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
  r.pin:SetSize(10, 10)
  r.pin:SetPoint("TOPLEFT", r.lvl, "TOPRIGHT", 5, 0)
  r.pin:Hide()
  wheel(r)
  -- Progress bar along the bottom of a quest you are on.
  r.bar = r:CreateTexture(nil, "ARTWORK")
  r.bar:SetColorTexture(0, 0, 0, 0.5)
  r.bar:SetHeight(2)
  r.bar:SetPoint("BOTTOMLEFT", TEXT_X, 0)
  r.bar:SetPoint("BOTTOMRIGHT", -16, 0)
  r.bar:Hide()
  r.fill = r:CreateTexture(nil, "OVERLAY")
  r.fill:SetHeight(2)
  r.fill:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT", 0, 0)
  r.fill:Hide()
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
  h.text = h:CreateFontString(nil, "OVERLAY", FONT)
  h.text:SetPoint("LEFT", 0, 1)
  h.text:SetTextColor(0.95, 0.8, 0.45)
  -- A thin rule under the group name marks where the group starts.
  h.line = h:CreateTexture(nil, "ARTWORK")
  h.line:SetColorTexture(0.95, 0.8, 0.45, 0.25)
  h.line:SetHeight(1)
  h.line:SetPoint("BOTTOMLEFT", 0, 0)
  h.line:SetPoint("BOTTOMRIGHT", 0, 0)
  h.right = h:CreateFontString(nil, "OVERLAY", FONT_DIM)
  h.right:SetPoint("RIGHT", 0, 1)
  h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  h:SetScript("OnEnter", function(self)
    local tip = rawget(_G, "GameTooltip")
    if not (tip and self.list) then return end
    if self.stop then return ns.stopTip(self) end
    tip:SetOwner(self, "ANCHOR_LEFT")
    local n = #ns.listQuests(self.list)
    if self.hint then tip:AddLine(self.hint, 1, 1, 1) end
    tip:AddLine("Click: fold or open", 0.6, 0.6, 0.6)
    if n > 0 then
      tip:AddLine(ns.listPinned(self.list) and ("Alt-click: unpin these " .. n .. " quests") or ("Alt-click: pin all " .. n .. " quests (keep them in Doing)"), 0.6, 0.8, 1)
    end
    tip:Show()
  end)
  h:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  h:SetScript("OnClick", function(_, button)
    if h.stop then return ns.stopClick(h, button) end
    if rawget(_G, "IsAltKeyDown") and IsAltKeyDown() and h.list then return ns.pinList(h.list) end
    if button == "RightButton" and (kind == "log" or kind == "pickup") then
      local key = kind == "pickup" and "sortPickup" or "sortLog"
      ns.db[key] = ns.db[key] == "xp" and "near" or "xp"
    else
      ns.db.collapsed[kind] = not ns.db.collapsed[kind]
    end
    ns.refresh()
  end)
  draggable(h)
  wheel(h)
  heads[kind] = h
  return h
end

ns.TURNIN_TOP_YARDS = 600   -- Nearby: a hand-in this close comes first

ns.scroll = 0            -- pixels scrolled down inside the groups
ns.MIN_HEIGHT = 80

-- The bar: for log quests not done yet; gold in Active, blue elsewhere.
ns.BAR_W = W - 2 * PAD - 26 - 16
-- The board width: ns.db.width within MIN_W..MAX_W.
function ns.width() return math.max(ns.MIN_W, math.min(ns.MAX_W, (ns.db and ns.db.width) or 270)) end
-- A quest you can hand in: done in the log, or a hand-in row.
function ns.complete(e) return e.kind == "turnin" or (e.kind == "log" and e.done) or false end

function ns.setBar(r, e, kind)
  if ns.complete(e) then
    -- Complete: a full green bar, on every tab.
    r.bar:Show()
    r.fill:SetColorTexture(0.35, 0.85, 0.35, 0.9)
    r.fill:SetWidth(ns.BAR_W)
    r.fill:Show()
    return
  end
  if e.kind ~= "log" or not e.frac then r.bar:Hide() r.fill:Hide() return end
  r.bar:Show()
  if kind == "active" then r.fill:SetColorTexture(1, 0.82, 0.25, 0.9) else r.fill:SetColorTexture(0.45, 0.7, 1, 0.7) end
  local w = math.floor(ns.BAR_W * math.max(0, math.min(1, e.frac)) + 0.5)
  if w < 1 then r.fill:Hide() return end
  r.fill:SetWidth(w)
  r.fill:Show()
end

-- The rows a group shows: the first ns.db.rows[kind], then a "+N more"
-- line (click: the whole group, then a "show fewer" line), so a quest past
-- the limit never vanishes without a word.
function ns.shownRows(kind, list, cap)
  cap = cap or ns.db.rows[kind] or 6
  if #list <= cap then return list end
  local out = {}
  local all = ns.db.showAll and ns.db.showAll[kind]
  for i = 1, all and #list or cap do out[i] = list[i] end
  local hidden = {}
  for i = cap + 1, #list do table.insert(hidden, list[i].name) end
  table.insert(out, { kind = "more", group = kind, left = {}, color = "white", hidden = hidden,
    name = all and "show fewer" or ("+" .. (#list - cap) .. " more: " .. table.concat(hidden, ", ")) })
  return out
end

---------------------------------------------------------------------------
-- Tabs: what the board shows, by what you are doing.
---------------------------------------------------------------------------
ns.TABS = { "doing", "nearby", "areas", "log" }
ns.TAB_NAMES = { doing = "Doing", nearby = "Nearby", areas = "Areas", log = "Log" }
local ALL = math.huge

-- The tab the board picks: Doing while a quest is Active, else Nearby.
function ns.autoTab(st) return st and st.active and #st.active > 0 and "doing" or "nearby" end
-- A tab you click holds until the board's own pick changes (you start or
-- finish a quest).
function ns.tab()
  local auto = ns.autoTab(state)
  if ns.pickedTab and ns.pickedFor == auto then return ns.pickedTab end
  ns.pickedTab = nil
  return auto
end
function ns.pickTab(t)
  local auto = ns.autoTab(state)
  ns.pickedTab, ns.pickedFor = (t ~= auto) and t or nil, auto
  ns.scroll = 0
  ns.render()
end

-- Every quest in your log, in log order.
function ns.logAll(st)
  local list = {}
  for _, kind in ipairs({ "active", "nearby", "turnin", "log" }) do
    for _, e in ipairs(st and st[kind] or {}) do table.insert(list, e) end
  end
  table.sort(list, function(a, b) return (a.index or 0) < (b.index or 0) end)
  return list
end

-- A line that opens another tab ("11 more in your log").
local function tabLine(text, tab)
  return { kind = "more", tab = tab, name = text, left = {}, color = "white" }
end

-- The log quests not in shown: one line that leads to the Log tab.
local function restLine(st, shown)
  local seen, n = {}, 0
  for _, e in ipairs(shown) do seen[e] = true end
  for _, e in ipairs(ns.logAll(st)) do if not seen[e] then n = n + 1 end end
  if n == 0 then return nil end
  return { key = "rest", nohead = true, list = { tabLine(n .. " more in your log: Log tab", "log") }, cap = ALL }
end

ns.NEXT_YARDS = 1000      -- Nearby: stops within this range
ns.AREA_STOPS = 3         -- an area with this many stops takes their place in Nearby

-- Nearby: one list of what to chain next. Hand-ins, objectives, pick-ups
-- and areas (several stops in one trip, in place of their stops), best
-- XP per minute first with the walk counted; a hand-in close by first.
function ns.nextList(st)
  local list, inArea = {}, {}
  for _, a in ipairs(st.area or {}) do
    if a.dist and a.dist <= ns.NEXT_YARDS and #a.stops >= ns.AREA_STOPS then
      table.insert(list, a)
      for _, s in ipairs(a.stops) do inArea[s] = true end
    end
  end
  for _, kind in ipairs({ "turnin", "nearby", "active", "log", "pickup", "party" }) do
    for _, e in ipairs(st[kind] or {}) do
      local take = not inArea[e] and not e.hiddenTag and e.dist and e.dist <= ns.NEXT_YARDS and not (e.kind == "party" and not e.canTake)
      if take then table.insert(list, e) end
    end
  end
  local function first(e) return e.kind == "turnin" and e.dist and e.dist <= ns.TURNIN_TOP_YARDS end
  table.sort(list, function(a, b)
    if first(a) ~= first(b) then return first(a) end
    if (a.rate or 0) ~= (b.rate or 0) then return (a.rate or 0) > (b.rate or 0) end
    return (a.dist or math.huge) < (b.dist or math.huge)
  end)
  return list
end

-- The sections of the board for a tab: { key, head, right, list, cap,
-- nohead, compact }.
function ns.sections(st, tab)
  if not st then return {} end
  tab = tab or ns.tab()
  local out = {}
  local function add(s) if s and #s.list > 0 then table.insert(out, s) end end
  local function members() add({ key = "members", head = "Your party", right = "click: map pin", list = st.members or {} }) end
  if ns.focused() then
    -- Combat or a dungeon: only the quest you are on, the rest on hover.
    add({ key = "active", head = "Doing", right = "hover: all", list = st.active, cap = ALL })
    return out
  end
  -- Your pins sit at the top of every other tab.
  -- Not in Log: it lists every quest once, and the star marks a pin there.
  if tab ~= "doing" and tab ~= "log" then
    local pins = {}
    for _, e in ipairs(st.active) do if e.pinned then table.insert(pins, e) end end
    add({ key = "pinned", head = "Pinned", right = "Alt-click: unpin", list = pins, cap = ALL })
  end
  if tab == "doing" then
    local byStop = ns.stopSections and ns.db.stops ~= false
    if not byStop then add({ key = "active", head = "Doing", right = "your quests now", list = st.active, cap = ALL }) end
    local cand, isActive = {}, {}
    for _, e in ipairs(st.active) do isActive[e] = true end
    for _, kind in ipairs({ "turnin", "nearby", "pickup", "party" }) do
      for _, e in ipairs(st[kind] or {}) do
        if not isActive[e] and not e.hiddenTag and not (e.kind == "party" and not e.canTake) then table.insert(cand, e) end
      end
    end
    local way = ns.onWay(cand, st.active)
    if byStop then
      -- One group per stop: your quests and the ones on the way, by place.
      for _, s in ipairs(ns.stopSections(st.active, way, st.turnin)) do add(s) end
    else
      add({ key = "onway", head = "On the way", right = "within " .. ns.ON_WAY_YARDS .. " yd", list = way })
    end
    members()
    local shown = {}
    for _, e in ipairs(st.active) do table.insert(shown, e) end
    for _, e in ipairs(way) do table.insert(shown, e) end
    if byStop then for _, sec in ipairs(out) do if sec.stop then for _, e in ipairs(sec.list) do table.insert(shown, e) end end end end
    add(restLine(st, shown))
  elseif tab == "nearby" then
    -- A pinned quest is in Pinned above: not here again.
    local list = {}
    for _, e in ipairs(ns.nextList(st)) do if not e.pinned then table.insert(list, e) end end
    add({ key = "next", head = "Chain next", right = "best XP/min, Alt-click: pin all", list = list })
    members()
    local cap = ns.db.rows.next or 8
    local shown = {}
    for i = 1, math.min(#list, cap) do shown[i] = list[i] end
    add(restLine(st, shown))
    if #list == 0 then add({ key = "rest2", nohead = true, list = { tabLine("Nothing close: see the Areas tab", "areas") }, cap = ALL }) end
  elseif tab == "areas" then
    add({ key = "zones", head = "Where to go", right = "XP/min, trip counted", list = st.zones or {} })
    add({ key = "town", head = "Travel", right = "click: map pin", list = st.town or {} })
  else
    -- Log: every quest, under its log zone, never cut.
    local by, order = {}, {}
    for _, e in ipairs(ns.logAll(st)) do
      local z = e.header or "Other"
      if not by[z] then by[z] = {} table.insert(order, z) end
      table.insert(by[z], e)
    end
    for _, z in ipairs(order) do add({ key = "log:" .. z, head = z, list = by[z], cap = ALL, compact = true }) end
  end
  return out
end

-- Lays out the groups from the last result. The title and the Next line
-- stay at the top; the groups below scroll when the board is taller than
-- the max height you set (drag the grip at the bottom right).
function ns.render()
  if not panel then return end
  W = ns.width()
  ns.BAR_W = W - 2 * PAD - TEXT_X - 16
  panel:SetWidth(W)
  local y = -PAD
  local level = state and state.level or D.playerLevel()
  -- No title line: the tabs are the top of the board. A line under them
  -- only when something is wrong (no Questie).
  panel.title:SetText("")
  panel.sub:SetText("")
  local warn = state and not state.questie and "No Questie: your log only" or nil
  -- The tabs: the one shown is gold, the others grey.
  local cur = ns.tab()
  local tw = math.floor((W - 2 * PAD) / #ns.TABS)
  for i, t in ipairs(ns.TABS) do
    local b = panel.tabs[i]
    local label = ns.TAB_NAMES[t]
    b.text:SetText(label)
    if t == cur then b.text:SetTextColor(1, 0.82, 0.25) b.line:Show() else b.text:SetTextColor(0.5, 0.5, 0.5) b.line:Hide() end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", PAD + (i - 1) * tw, y)
    b:SetWidth(tw)
    b:Show()
  end
  panel.next:Hide()
  y = y - ROW_H - 6
  if warn then
    panel.sub:ClearAllPoints()
    panel.sub:SetPoint("TOPLEFT", PAD, y)
    panel.sub:SetText(warn)
    y = y - ROW_H
  end
  local top = y
  -- First pass: what goes where, from the top of the groups (cy).
  local items, cy, used = {}, 0, 0
  for _, h in pairs(heads) do h:Hide() end
  local curName = ns.TAB_NAMES[cur]
  for si, sec in ipairs(ns.sections(state)) do
    local kind, list = sec.key, sec.list
    -- The first group needs no name when the tab already says it.
    if si == 1 and sec.head == curName then sec.nohead = true end
    do
      local collapsed = not sec.nohead and ns.db.collapsed[kind]
      local cap = sec.cap or ns.db.rows[kind] or 6
      if not sec.nohead then
        local h = heads[kind] or makeHead(kind)
        if sec.stop then
          ns.stopHead(h, sec)
        else
          local count = (#list > cap and not (ns.db.showAll and ns.db.showAll[kind])) and (cap .. " of " .. #list) or #list
          h.text:SetText((collapsed and "+ " or "") .. sec.head .. "  " .. count)
          h.right:SetText("")   -- the hint is in the group's tooltip
          h.hint = sec.right
          h.list = ns.shownRows(kind, list, cap)   -- pin all takes the rows you see
        end
        table.insert(items, { f = h, y = cy, h = HEAD_H, gap = 2, stop = sec.stop })
        cy = cy + HEAD_H + 2
      end
      if not collapsed then
        local shown = ns.shownRows(kind, list, cap)
        for i = 1, #shown do
          used = used + 1
          local r = rows[used] or makeRow(used)
          local e = shown[i]
          r.entry = e
          -- In a stop: a mark before the level, and no arrow (the stop has it).
          local inStop = sec.stop and e.kind ~= "more"
          local tx = TEXT_X + (inStop and ns.STOP_INDENT or 0)
          r.noArrow = inStop or nil
          r.lvl:SetWidth(LVL_W + (inStop and ns.STOP_INDENT or 0))
          r.lvl:SetText((inStop and (ns.stopMark(e) .. " ") or "") .. (e.kind == "more" and "" or (e.kind == "area" or e.kind == "zone") and #e.stops or e.kind == "town" and (e.role == "inn" and "Inn" or "Fly") or ((e.level or "?") .. (e.tag or ""))))
          r.lvl:SetTextColor(rgb(e.color))
          r.name:SetText(e.name .. (inStop and ns.gearMark(e) or ""))
          if e.kind == "more" then r.name:SetTextColor(0.6, 0.6, 0.6)
          elseif ns.complete(e) then r.name:SetTextColor(0.55, 0.9, 0.55)
          elseif e.classColor then r.name:SetTextColor(e.classColor[1], e.classColor[2], e.classColor[3])
          else r.name:SetTextColor(0.92, 0.92, 0.92) end
          -- Your Alt-click mark: a gold star before the name.
          if e.kind == "area" then e.pinned = ns.areaPinned(e) or nil end
          if e.kind == "zone" then e.pinned = ns.listPinned({ e }) or nil end
          r.name:ClearAllPoints()
          r.name:SetPoint("TOPLEFT", r.lvl, "TOPRIGHT", e.pinned and 18 or 6, 0)
          r.name:SetPoint("TOPRIGHT", r.meta, "TOPLEFT", -6, 0)
          if e.pinned then r.pin:Show() else r.pin:Hide() end
          local full = not ns.db.compact and not sec.compact
          local split = full and ns.QUEST_KINDS[e.kind]
          r.meta:SetText(split and ns.place(e) or ns.meta(e, kind))
          ns.setBar(r, e, kind)
          r.bar:ClearAllPoints()
          r.bar:SetPoint("BOTTOMLEFT", tx, 0)
          r.bar:SetPoint("BOTTOMRIGHT", -16, 0)
          local todo, lines
          if inStop then
            -- One line: the name, and at the right who to see. A quest
            -- still to finish keeps its objectives under it.
            lines = ns.stopLines(e)
            todo = lines[1]
            r.meta:SetText(#lines == 0 and ns.stopWho(e, e.name, W - 2 * PAD - tx - 16 - (e.pinned and 12 or 0)) or "")
            if ns.complete(e) then r.bar:Hide() r.fill:Hide() end   -- the mark and the green name say it
            split = false
          elseif split then
            -- Quest rows: what to do (each open objective when you are on
            -- it), your party, then the gear it leads to.
            lines = kind == "active" and ns.activeLines(e, true) or { ns.todoWho(e) }
            local reward = ns.rewardLine(e)
            if reward then table.insert(lines, reward) end
            todo = lines[1] or ""
            if ns.complete(e) then todo = "|cff66dd66Complete|r  " .. todo end
            lines[1] = todo
          else
            todo = full and ns.todo(e) or nil
            -- An Active quest gets a line per open objective and one for its
            -- party; the rest keep one what-to-do line.
            lines = (full and kind == "active") and ns.activeLines(e) or nil
            if lines and #lines < 2 then lines = nil end
            if lines then todo = lines[1] end
            lines = lines or (todo and { todo }) or {}
          end
          -- The numbers sit at the right of line 2.
          r.stats:SetText(split and ns.stats(e, kind) or "")
          local statsW = split and (r.stats.GetStringWidth and r.stats:GetStringWidth() or 0) or 0
          r.sub:ClearAllPoints()
          r.sub:SetPoint("TOPLEFT", tx, -ROW_H + SUB_UP)
          r.sub:SetPoint("TOPRIGHT", -16 - (statsW > 0 and statsW + 8 or 0), -ROW_H + SUB_UP)
          -- A line too long for the board goes on to the next line.
          lines = ns.wrapLines(lines, W - 2 * PAD - tx - 16 - (statsW > 0 and statsW + 8 or 0))
          r.sub:SetText(lines[1] or "")
          local n = #lines
          for i = 1, math.max(#r.more, n - 1) do
            local fs = r.more[i]
            if i <= n - 1 then
              if not fs then
                fs = r:CreateFontString(nil, "OVERLAY", FONT_DIM)
                fs:SetJustifyH("LEFT")
                if fs.SetWordWrap then fs:SetWordWrap(false) end
                r.more[i] = fs
              end
              fs:ClearAllPoints()
              fs:SetPoint("TOPLEFT", tx, -ROW_H + SUB_UP - i * (ROW_H - SUB_UP))
              fs:SetPoint("TOPRIGHT", -16, -ROW_H + SUB_UP - i * (ROW_H - SUB_UP))
              fs:SetText(lines[i + 1])
              fs:Show()
            elseif fs then
              fs:Hide()
            end
          end
          local rh = n > 0 and (ROW_H + n * (ROW_H - SUB_UP)) or ROW_H
          if r.bar:IsShown() then rh = rh + BAR_GAP end   -- room between the last line and the bar
          r:SetHeight(rh)
          local gap = todo and ROW_GAP or 1
          table.insert(items, { f = r, y = cy, h = rh, row = true, gap = gap })
          cy = cy + rh + gap
        end
      end
      -- The group's last line gets the bigger gap instead of its own.
      local last = items[#items]
      if last then cy = cy - (last.gap or 0) + GROUP_GAP last.gap = GROUP_GAP end
    end
  end
  for i = used + 1, #rows do rows[i]:Hide() rows[i].entry = nil end
  -- Second pass: the part that fits under the max height.
  -- No group gap under the last group.
  local full = items[#items] and (cy - (items[#items].gap or 0) + 4) or cy
  local view = full
  local maxH = ns.db.maxHeight
  if maxH then
    view = math.max(ROW_H, maxH - (-top) - PAD - ROW_H)   -- room for the "more" line
    if full <= maxH - (-top) - PAD + 4 then view = full end
  end
  local clipped = view < full
  -- Scrolling goes by whole lines (a head or a row): ns.scroll is the first
  -- line shown, at most the one from which the rest fits.
  local last = 1
  if clipped then
    local rest = 0
    for i = #items, 1, -1 do
      rest = rest + items[i].h + (items[i].gap or 0)
      if rest > view then break end
      last = i
    end
  end
  ns.scroll = clipped and math.max(0, math.min(ns.scroll or 0, last - 1)) or 0
  local above, below, at = 0, 0, 0
  for i, it in ipairs(items) do
    local f = it.f
    local fits = i > ns.scroll and at + it.h <= view
    if fits then
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", PAD, top - at)
      f:SetPoint("TOPRIGHT", -PAD, top - at)
      at = at + it.h + (it.gap or 0)
      if it.row then updateArrow(f) elseif it.stop then ns.stopArrow(f) end
      f:Show()
    else
      f:Hide()
      if it.row then
        if i <= ns.scroll then above = above + 1 else below = below + 1 end
      end
      if i > ns.scroll then at = view + 1 end   -- nothing after a line that did not fit
    end
  end
  ns.hiddenAbove, ns.hiddenBelow = above, below
  local height = -top + (clipped and view or full) + PAD - 4
  if clipped then
    local parts = {}
    if above > 0 then table.insert(parts, above .. " above") end
    if below > 0 then table.insert(parts, below .. " more below") end
    panel.more:SetText((#parts > 0 and table.concat(parts, ", ") or "") .. "  (scroll)")
    panel.more:Show()
    height = height + ROW_H
  else
    panel.more:Hide()
  end
  panel:SetHeight(height)
  -- Item buttons follow their rows.
  if ns.updateItems then ns.updateItems(state) end
end

-- Mouse wheel over the board: one line (a head or a row) at a time.
function ns.scrollBy(delta)
  ns.scroll = math.max(0, (ns.scroll or 0) - delta)
  ns.render()
end

-- The grip at the bottom right sets the max height: drag it; right-click
-- takes the limit off.
local function cursorXY()
  local cx, cy = call(rawget(_G, "GetCursorPosition"))
  local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  return (cx or 0) / scale, (cy or 0) / scale
end
-- While you drag, a gold outline shows the max size (the board itself is
-- only as tall as its rows), with the numbers in it.
local function showOutline()
  local o = panel.outline
  if not o then return end
  local h = ns.db.maxHeight or panel:GetHeight() or 200
  o:ClearAllPoints()
  o:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  o:SetWidth(W)
  o:SetHeight(h)
  o.text:SetText(W .. " x " .. h)
  o:Show()
end
function ns.sizeStart()
  ns.pinTop()   -- grow right and down from the top-left corner
  local x, y = cursorXY()
  ns.sizing = { x = x, y = y, h = ns.db.maxHeight or panel:GetHeight() or 200, w = ns.width() }
  showOutline()
end
function ns.sizeMove()
  if not ns.sizing then return end
  local x, y = cursorXY()
  local h = ns.sizing.h + (ns.sizing.y - y)
  ns.db.maxHeight = math.floor(math.max(ns.MIN_HEIGHT, h) + 0.5)
  ns.db.width = math.floor(math.max(ns.MIN_W, math.min(ns.MAX_W, ns.sizing.w + (x - ns.sizing.x))) + 0.5)
  ns.render()
  showOutline()
end
function ns.sizeStop()
  if not ns.sizing then return end
  ns.sizing = nil
  if panel.outline then panel.outline:Hide() end
  say("size " .. ns.width() .. " x " .. ns.db.maxHeight .. " max (right-click the grip, or /qb height off, for no height limit)")
  if ns.updateItems then ns.updateItems(state) end
end
function ns.setWidth(w)
  ns.db.width = w and math.max(ns.MIN_W, math.min(ns.MAX_W, w)) or 270
  ns.render()
end
function ns.setMaxHeight(h)
  ns.db.maxHeight = h and math.max(ns.MIN_HEIGHT, h) or nil
  ns.scroll = 0
  ns.render()
end

---------------------------------------------------------------------------
-- Pointers for Glance's minimap edge arrows: the Next quest's place, the
-- nearest hand-in and the Town rows. Built once per refresh; Glance reads
-- the cached list every 0.1 s.
---------------------------------------------------------------------------
ns.pointers = {}
local function pointFor(e, r, g, b, label)
  if not (e and e.spawn and e.zone and e.spawn[1] and e.spawn[1] >= 0) then return nil end
  local zdb = D.module("ZoneDB")
  local mapID = zdb and call(zdb.GetUiMapIdByAreaId, zdb, e.zone)
  if not mapID then return nil end
  return { mapID = mapID, x = e.spawn[1] / 100, y = e.spawn[2] / 100, r = r, g = g, b = b, label = label }
end

function ns.updatePointers(st)
  local list = {}
  if st then
    local _, nextE = ns.nextStep(st)
    local function add(p) if p and #list < 5 then table.insert(list, p) end end
    if nextE then add(pointFor(nextE, 1, 0.85, 0.3, nextE.target or nextE.name)) end
    local t = st.turnin and st.turnin[1]
    if t and t ~= nextE then add(pointFor(t, 0.45, 0.9, 0.45, "Hand in: " .. (t.target or t.name))) end
    for _, e in ipairs(st.town or {}) do
      add(pointFor(e, 0.75, 0.75, 1, (e.role == "inn" and "Inn: " or "Flight: ") .. e.name))
    end
  end
  ns.pointers = list
end

function ns.registerPointers()
  local g = rawget(_G, "Glance")
  local mm = type(g) == "table" and g.minimap
  if type(mm) == "table" and type(mm.addPointerSource) == "function" then
    call(mm.addPointerSource, function() return ns.pointers end)
    return true
  end
  return false
end

-- /qb party off|on. Questie's own map icons for party objectives follow its
-- "Show party members' tracked quest objectives" option
-- (profile.showPartyQuestObjectives); its old value comes back with on.
function ns.setParty(on)
  ns.db.party = on
  local q = rawget(_G, "Questie")
  local prof = type(q) == "table" and type(q.db) == "table" and q.db.profile
  if type(prof) == "table" then
    if on then
      if ns.db.questiePartyWas ~= nil then prof.showPartyQuestObjectives = ns.db.questiePartyWas end
      ns.db.questiePartyWas = nil
    else
      if ns.db.questiePartyWas == nil then ns.db.questiePartyWas = prof.showPartyQuestObjectives and true or false end
      prof.showPartyQuestObjectives = false
    end
    local po = D.module("QuestiePartyObjectives")
    if po and type(po.Update) == "function" then call(po.Update, po) end
  end
  ns.refresh()
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
    ns.updatePointers(state)
    ns.render()
    if ns.updateItems then ns.updateItems(state) end
    if again then again = false ns.refresh() end
  end
  if not job then runner:SetScript("OnUpdate", nil) end
end

function ns.refresh()
  if not (ns.db and ns.db.shown) then return end
  if job then again = true return end
  job = coroutine.create(function()
    state = D.collect({ dungeons = ns.db.dungeons, party = ns.db.party, doing = ns.db.doing, sortLog = ns.db.sortLog, sortPickup = ns.db.sortPickup, maxAbove = ns.db.maxAbove,
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

-- On a job (a quest in Active, by progress or your pin): only what helps
-- it shows; the whole board on mouse-over, as in focus.
ns.ON_WAY_YARDS = 300
ns.ON_WAY_KINDS = { turnin = true, pickup = true, party = true }
function ns.onJob() return state and state.active and #state.active > 0 or false end
function ns.trimmed() return false end   -- the Doing tab took its place

-- The entries within ON_WAY_YARDS of you or of an Active quest's place.
function ns.onWay(list, active)
  local out = {}
  for _, e in ipairs(list) do
    local near = e.dist and e.dist <= ns.ON_WAY_YARDS
    for _, a in ipairs(active or {}) do
      if near then break end
      if e.wx and a.wx and e.inst == a.inst then
        local dx, dy = e.wx - a.wx, e.wy - a.wy
        near = dx * dx + dy * dy <= ns.ON_WAY_YARDS * ns.ON_WAY_YARDS
      end
    end
    if near then table.insert(out, e) end
  end
  return out
end

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
    for _, h in pairs(heads) do if h.stop and h:IsShown() then ns.stopArrow(h) end end
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
  panel.tabs = {}
  for i, t in ipairs(ns.TABS) do
    local b = CreateFrame("Button", nil, panel)
    b:SetHeight(ROW_H)
    b.text = b:CreateFontString(nil, "OVERLAY", FONT)
    b.text:SetPoint("CENTER", 0, 1)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetColorTexture(1, 0.82, 0.25, 0.8)
    b.line:SetHeight(1)
    b.line:SetPoint("BOTTOMLEFT", 6, 0)
    b.line:SetPoint("BOTTOMRIGHT", -6, 0)
    b.tab = t
    b:SetScript("OnClick", function() ns.pickTab(t) end)
    draggable(b)
    panel.tabs[i] = b
  end
  panel.more = panel:CreateFontString(nil, "OVERLAY", FONT_DIM)
  panel.more:SetPoint("BOTTOMLEFT", PAD, PAD - 2)
  panel.more:Hide()
  local grip = CreateFrame("Button", nil, panel)
  grip:SetSize(12, 12)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then ns.sizeStart() end end)
  grip:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then ns.sizeStop() end end)
  grip:SetScript("OnUpdate", function() if ns.sizing then ns.sizeMove() end end)
  grip:SetScript("OnClick", function() ns.setMaxHeight(nil) say("no max height") end)
  grip:SetScript("OnEnter", function(self)
    local tip = rawget(_G, "GameTooltip")
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:AddLine("Drag: set the board's width and max height", 1, 1, 1)
    tip:AddLine("Mouse wheel scrolls past it. Right-click: no limit", 0.6, 0.6, 0.6)
    tip:Show()
  end)
  grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  panel.grip = grip
  -- The max-size outline, shown only while you drag the grip.
  local o = CreateFrame("Frame", nil, panel)
  o:SetFrameLevel((panel.GetFrameLevel and panel:GetFrameLevel() or 1) + 5)
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local t = o:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.82, 0.25, 0.9)
    t:SetPoint(edge[1], 0, 0)
    t:SetPoint(edge[2], 0, 0)
    if edge[3] then t:SetHeight(1) else t:SetWidth(1) end
  end
  o.text = o:CreateFontString(nil, "OVERLAY", FONT)
  o.text:SetPoint("BOTTOMRIGHT", -16, 4)
  o.text:SetTextColor(1, 0.82, 0.25)
  o:Hide()
  panel.outline = o
  wheel(panel)
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
  if ns.updateItems then ns.updateItems(state) end
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
  "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" }) do
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
    ns.db.spots = ns.db.spots or {}
    D.lastSpot = ns.db.spots
    build()
    ns.registerPointers()
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
  if event == "BAG_UPDATE_COOLDOWN" then
    if ns.updateItemState then ns.updateItemState() end
    return
  end
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
  "/qb stops - the Doing tab groups its quests by stop, or not (again to undo)",
  "Click a group name to fold it; right-click it to sort by nearest or best XP.",
  "/qb range N - pick-ups at most N levels over you (now %d)",
  "/qb rows N - rows per group (now %d)",
  "/qb height N - at most N pixels tall, scroll for the rest (off: no limit; or drag the grip)",
  "/qb dungeons off - dungeon and raid quests (28D, 40R) only in the Log tab, no pick-ups (on brings them back)",
  "/qb width N - the board's width, 220 to 560 (reset: 270; or drag the grip sideways)",
  "/qb doing | nearby | areas | log - open that tab (the board picks Doing or Nearby by itself)",
  "/qb why NAME - where a quest is on the board, or why it is not there",
  "/qb town - pin the nearest innkeeper or flight master on the map (/qb inn: innkeeper only)",
  "/qb party off - hide party members' quests here and Questie's party objectives on the map (on brings them back)",
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
  elseif cmd == "party" and (rest == "on" or rest == "off") then
    ns.setParty(rest == "on")
    say(rest == "on" and "party quests shown again" or "party quests hidden (here and Questie's party objectives on the map)")
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
  elseif cmd == "stops" then
    ns.db.stops = ns.db.stops == false
    say(ns.db.stops and "Doing: quests grouped by stop" or "Doing: one list, no stops")
    return ns.render()
  elseif cmd == "lock" then
    ns.db.locked = not ns.db.locked
    say(ns.db.locked and "locked: dragging does not move the board" or "unlocked: drag the board to move it")
    return
  elseif cmd == "height" and (n or rest == "off") then
    ns.setMaxHeight(n)
    say(n and ("max height " .. ns.db.maxHeight .. ", scroll for the rest") or "no max height")
    return
  elseif cmd == "dungeons" and (rest == "on" or rest == "off") then
    ns.db.dungeons = rest == "on"
    say(ns.db.dungeons and "dungeon and raid quests show everywhere" or "dungeon and raid quests show only in the Log tab (and Pick up leaves them out)")
    return ns.refresh()
  elseif cmd == "width" and (n or rest == "reset") then
    ns.setWidth(n)
    say("width " .. ns.width())
    return
  elseif ns.TAB_NAMES[cmd] then
    ns.pickTab(cmd)
  elseif cmd == "why" or cmd == "find" then
    say(D.whyQuest(rest, state, ns.WHERE, ns.db.maxAbove))
  elseif cmd == "town" or cmd == "inn" then
    local st = ns.state()
    local e
    for _, t in ipairs(st and st.town or {}) do if cmd == "town" or t.role == "inn" then e = e or t end end
    if e then ns.click(e, "LeftButton") say(e.name .. ", " .. D.yards(e.dist) .. ": pinned on the map")
    else say("no town known yet (needs Questie; try again in a few seconds)") end
    return
  elseif cmd == "reset" then
    ns.db.point = nil
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -260)
    return
  end
  for _, line in ipairs(help) do say(string.format(line, line:find("range") and ns.db.maxAbove or ns.db.rows.log)) end
end
