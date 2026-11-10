-- Offline tests for QuestBoard with a small mock of the WoW API and Questie.
-- Run from the repo root: lua5.1 tests/questboard.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/questboard%.lua$") or ""
local failures, chat, calls = 0, {}, {}
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end
local function log(name, ...) table.insert(calls, { name = name, ... }) end
local function lastCall(name)
  for i = #calls, 1, -1 do if calls[i].name == name then return calls[i] end end
end

local function widget(name)
  local w = { scripts = {}, shown = false, name = name, points = {} }
  function w:SetScript(what, fn) self.scripts[what] = fn end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:IsShown() return self.shown end
  function w:SetText(t) self.text = t end
  function w:GetText() return self.text end
  function w:SetRotation(r) self.rotation = r end
  function w:SetAttribute(k, v) self.attrs = self.attrs or {} self.attrs[k] = v end
  function w:RegisterEvent(e) self.events = self.events or {} self.events[e] = true end
  function w:CreateTexture() return widget() end
  function w:CreateFontString() return widget() end
  function w:GetPoint() return "TOPRIGHT", nil, nil, -16, -260 end
  return setmetatable(w, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end
local frames = {}
function CreateFrame(kind, name)
  local f = widget(name)
  f.kind = kind
  if name then _G[name] = f end
  table.insert(frames, f)
  return f
end
UIParent = widget("UIParent")
GameTooltip = widget("GameTooltip")
GameTooltip.lines = {}
function GameTooltip:AddLine(t) table.insert(self.lines, t) end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, strip(m)) end }
SlashCmdList = {}
local timers = {}
C_Timer = { After = function(_, f) table.insert(timers, f) end }
local P = { level = 27, shift = false, facing = 0 }
function UnitLevel() return P.level end
function GetQuestGreenRange() return 7 end
function IsShiftKeyDown() return P.shift end
function IsAltKeyDown() return false end
function GetPlayerFacing() return P.facing end
function GetUnitSpeed() return 0 end
function GetQuestLink(id) return "|Hquest:" .. id .. "|h[q]|h" end
function ChatEdit_InsertLink(l) log("link", l) return true end
local clock = 0
function debugprofilestop() clock = clock + 1 return clock end

-- Quest log: a header, a quest ready to turn in, two in progress.
local LOG = {
  { title = "Redridge Mountains", isHeader = true },
  { title = "Murloc Poachers", questID = 127, level = 22 },
  { title = "Underbelly Scales", questID = 122, level = 26 },
  { title = "The Lost Tools", questID = 125, level = 28 },
}
local OBJ = {
  [127] = { { text = "Spotted Sunfin Fin: 8/8", finished = true, numFulfilled = 8, numRequired = 8 } },
  [122] = { { text = "Underbelly Whelp Scale: 3/6", finished = false, numFulfilled = 3, numRequired = 6 } },
  [125] = { { text = "Oslow's Toolbox: 0/1", finished = false, numFulfilled = 0, numRequired = 1 } },
}
C_QuestLog = {
  GetNumQuestLogEntries = function() return #LOG end,
  GetInfo = function(i) return LOG[i] end,
  ReadyForTurnIn = function(id) return id == 127 end,
  GetQuestObjectives = function(id) return OBJ[id] end,
  SetSelectedQuest = function(id) log("select", id) end,
}
C_Map = {
  CanSetUserWaypointOnMap = function(id) return id == 1433 end,
  SetUserWaypoint = function(p) log("waypoint", p) return true end,
}
C_Map.OpenWorldMap = function(id) log("openMap", id) WorldMapFrame.shown = true end
WorldMapFrame = { shown = false, IsShown = function(self) return self.shown end, SetMapID = function(self, id) self.mapID = id end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) log("track", on) end }
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }

-- Questie: quest levels, places (distance per quest), XP.
local QUESTS = {
  [127] = { level = 22, requiredLevel = 18, name = "Murloc Poachers", place = { 300, "Wiley" } },
  [122] = { level = 26, requiredLevel = 20, name = "Underbelly Scales", place = { 900, "Whelp" } },
  [125] = { level = 28, requiredLevel = 22, name = "The Lost Tools", place = { 200, "Toolbox" } },
  -- Available: fits, fits (big XP, far), grey, too high, needs level 30, other continent.
  [201] = { level = 27, requiredLevel = 22, name = "Blackrock Menace", place = { 150, "Marshal" }, xp = 2000, obj = 1 },
  [202] = { level = 28, requiredLevel = 23, name = "Shadow Magic", place = { 1200, "Mage" }, xp = 4000, obj = 1 },
  [203] = { level = 15, requiredLevel = 10, name = "Old Errand", place = { 50, "Farmer" }, xp = 200, obj = 1 },
  [204] = { level = 33, requiredLevel = 26, name = "Too Hard", place = { 60, "Guard" }, xp = 5000, obj = 1 },
  [205] = { level = 31, requiredLevel = 30, name = "Not Yet", place = { 60, "Guard" }, xp = 5000, obj = 1 },
  [206] = { level = 27, requiredLevel = 20, name = "Far Away", place = { 600000, "Elf" }, xp = 3000, obj = 1 },
}
QUESTS[127].xp, QUESTS[122].xp, QUESTS[125].xp = 1500, 1800, 2400
local function questObj(id)
  local q = QUESTS[id]
  if not q then return nil end
  local o = { Id = id, name = q.name, level = q.level, requiredLevel = q.requiredLevel,
    Starts = { NPC = { id * 10 } }, Finisher = { NPC = { id * 10 + 1 } }, Objectives = {}, place = q.place }
  if q.obj then o.objectives = { { { 1, "kill" } } } end
  return o
end
local mods = {
  QuestieDB = { GetQuest = function(id) return questObj(id) end },
  DistanceUtils = {
    GetNearestFinisherOrStarter = function(who)
      local id = math.floor((who.NPC[1]) / 10)
      local p = QUESTS[id].place
      return { 40, 50 }, 44, p[2], p[1]
    end,
    GetNearestSpawnForQuest = function(q) return { 30, 60 }, 44, q.place[2], q.place[1] end,
  },
  ActiveQuests = { Get = function(id) if QUESTS[id] then return { questId = id, quest = questObj(id) } end end },
  AvailableQuests = { __availableQuests = { [201] = true, [202] = true, [203] = true, [204] = true, [205] = true, [206] = true } },
  QuestXP = { GetQuestLogRewardXP = function(_, id) return QUESTS[id] and QUESTS[id].xp or 0 end },
  ZoneDB = { GetUiMapIdByAreaId = function(_, area) return area == 44 and 1433 or nil end },
  QuestieMap = { ShowNPC = function(_, id) log("showNPC", id) end, ResetManualFrames = function() end },
}
local questieOn = true
QuestieLoader = { ImportModule = function(_, name)
  if not questieOn then error("no module") end
  return mods[name]
end }
-- HereBeDragons: the player at (0, 0); every spawn due north.
local HBD = {
  GetPlayerWorldPosition = function() return 0, 0, 0 end,
  GetWorldCoordinatesFromZone = function() return 100, 0, 0 end,
  GetWorldVector = function() return 0.5, 100 end,
}
function LibStub(name) if name == "HereBeDragonsQuestie-2.0" then return HBD end end

local ns = {}
-- Quest 122 (log index 3) has a usable quest item.
function GetQuestLogSpecialItemInfo(i) if i == 3 then return "|Hitem:5000|h[Vial]|h", 134400, 1 end end
for _, file in ipairs({ "Data.lua", "Chain.lua", "QuestBoard.lua", "Items.lua" }) do
  local chunk = assert(loadfile(root .. "QuestBoard/" .. file))
  chunk("QuestBoard", ns)
end
local D = ns.data
-- "Here" makes quests near you active; the tests below turn it on themselves.
local hereYards = D.HERE_YARDS
D.HERE_YARDS = 0
-- Areas too: the area tests turn them on.
local areaYards = D.AREA_YARDS
D.AREA_YARDS = 0
local function fire(event) for _, f in ipairs(frames) do if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end end end

---------------------------------------------------------------------------
-- Pure helpers
check("difficulty colours", D.difficulty(32, 27) == "red" and D.difficulty(30, 27) == "orange"
  and D.difficulty(26, 27) == "yellow" and D.difficulty(21, 27) == "green" and D.difficulty(19, 27) == "grey")
check("fits: grey out", not D.fits(15, 10, 27, 3))
check("fits: too high out", not D.fits(31, 26, 27, 3) and D.fits(30, 26, 27, 3))
check("fits: required level out", not D.fits(28, 28, 27, 3))
check("yards rounds to tens", D.yards(237) == "240 yd" and D.yards(1530) == "1.5k yd")
check("short numbers", D.short(850) == "850" and D.short(1520) == "1.5k" and D.short(23400) == "23k")
check("compass", D.compass(0) == "N" and D.compass(math.pi / 2) == "W" and D.compass(math.pi) == "S" and D.compass(3 * math.pi / 2) == "E")
check("rate", D.rate(1200, 120) == 600 and D.rate(nil, 10) == nil)

---------------------------------------------------------------------------
-- A full pass with Questie
local out = D.collect({})
check("turn-in group has the finished quest", #out.turnin == 1 and out.turnin[1].id == 127)
check("turn-in places the finisher", out.turnin[1].target == "Wiley" and out.turnin[1].dist == 300)
check("log sorted nearest first", #out.log == 2 and out.log[1].id == 125 and out.log[2].id == 122)
check("log carries XP and progress", out.log[2].xp == 1800 and D.progress(out.log[2]) == "3/6")
local ids = {}
for _, e in ipairs(out.pickup) do ids[#ids + 1] = e.id end
check("pick-ups keep only quests that fit and are near", table.concat(ids, ",") == "202,201")
check("pick-ups sorted by XP per minute", out.pickup[1].rate > out.pickup[2].rate)
local near = D.collect({ sortPickup = "near" })
check("pick-ups by distance", near.pickup[1].id == 201)
local wide = D.collect({ maxAbove = 6 })
local hasHard = false
for _, e in ipairs(wide.pickup) do if e.id == 204 then hasHard = true end end
check("range widens the level window", hasHard)
check("bearing from HereBeDragons", out.log[1].angle == 0.5)

-- XP per minute model: 150 yd at 7 yd/s + 30 + 90 + 60 seconds.
local e201
for _, e in ipairs(out.pickup) do if e.id == 201 then e201 = e end end
local secs = 150 / 7 + 30 + 90 + 60
check("XP per minute estimate", math.abs(e201.rate - 2000 / (secs / 60)) < 0.01)
check("row meta for a pick-up", strip(ns.meta(e201)):match("^~%d+ xp/m  150 yd$") ~= nil)
check("row meta for a log quest", strip(ns.meta(out.log[2])) == "900 yd")
check("what to do: the objective", ns.todo(out.log[2]) == "Underbelly Whelp Scale: 3/6")
check("what to do: and where, when the name is not in it",
  ns.todo({ kind = "log", left = { { text = "Gnoll Paw: 2/8" } }, target = "Redridge Mystic" }) == "Gnoll Paw: 2/8  (Redridge Mystic)")
check("what to do: who takes it in", ns.todo(out.turnin[1]) == "Hand in to Wiley")
check("what to do: where to get it", ns.todo(e201) == "Get it from Marshal")
local nextText = ns.nextStep(out)
check("next step: the nearest hand-in", nextText == "Hand in Murloc Poachers to Wiley  300 yd")

-- Active: a quest whose count went up in the last 5 minutes moves to the top.
D.seen, D.activeAt, D.heldAt = {}, {}, {}
D.collect({ time = 100 })
OBJ[122][1].numFulfilled = 4
local act = D.collect({ time = 160 })
check("a kill makes the quest active", #act.active == 1 and act.active[1].id == 122 and #act.log == 1)
local later = D.collect({ time = 160 + 301 })
check("it stays Active for the grace time", #later.active == 1)
local gone = D.collect({ time = 160 + 601 })
check("it leaves Active after the grace time", #gone.active == 0 and #gone.log == 2)
D.seen, D.activeAt, D.heldAt = {}, {}, {}
local first = D.collect({ time = 1000 })
check("nothing is active on the first look", #first.active == 0)
OBJ[122][1].numFulfilled = 3
D.seen, D.activeAt, D.heldAt = {}, {}, {}
D.HERE_YARDS = hereYards
local here = D.collect({ time = 2000 })
check("a quest whose objective is near is Nearby, not Active", #here.active == 0 and #here.nearby == 1 and here.nearby[1].id == 125)
-- Progress makes it active; it stays while you hunt up to STAY_YARDS away.
OBJ[125][1].numFulfilled = 0
D.collect({ time = 2010 })
OBJ[125][1].text = "Oslow's Toolbox: 0/1"
QUESTS[125].place[1] = 200
OBJ[122][1].numFulfilled = 4
D.collect({ time = 2020 })
QUESTS[122].place[1] = 500
D.collect({ time = 2020 + 300 })
local hunting = D.collect({ time = 2020 + 900 })
check("an active quest stays while you are within the wider range", #hunting.active == 1 and hunting.active[1].id == 122)
QUESTS[122].place[1] = 800
local away = D.collect({ time = 2020 + 900 + 601 })
check("it leaves when you are far and the grace time is over", #away.active == 0)
QUESTS[122].place[1] = 900
OBJ[122][1].numFulfilled = 3
-- Alt-click marks a quest as one you are doing.
local doing = D.collect({ time = 4000, doing = { [122] = true } })
check("a quest you mark is Active", #doing.active == 1 and doing.active[1].id == 122 and doing.active[1].pinned)
D.HERE_YARDS = 0
D.seen, D.activeAt, D.heldAt = {}, {}, {}

-- Yields when the frame budget is spent.
local yields = 0
local co = coroutine.create(function() D.collect({ yield = function() yields = yields + 1 coroutine.yield() end }) end)
while coroutine.status(co) ~= "dead" do assert(coroutine.resume(co)) end
check("collect yields on its frame budget", yields > 0)

---------------------------------------------------------------------------
-- Panel
fire("PLAYER_LOGIN")
for _ = 1, 50 do ns.step() end
check("board built and shown", QuestBoardFrame and QuestBoardFrame.shown)
local st = ns.state()
check("state after login", st and #st.turnin == 1 and #st.pickup == 2)
-- Quest items: a secure item button for each, left of the board.
local itemBtn = QuestBoardItem1
check("quest item gets a button", itemBtn and itemBtn.shown and itemBtn.attrs.type == "item" and itemBtn.attrs.item == "item:5000")
check("the button knows its quest", itemBtn.info.quest.id == 122)
check("only one item button", not QuestBoardItem2)
local rowOf122
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.entry.id == 122 and f.shown then rowOf122 = f end end
function rowOf122:GetTop() return 400 end
function QuestBoardFrame:GetLeft() return 900 end
local placed
function itemBtn:SetPoint(...) placed = { ... } end
ns.updateItems(ns.state())
check("the item button sits left of its quest's row", placed and placed[1] == "TOPRIGHT" and placed[4] == 897 and placed[5] == 400)
itemBtn.SetPoint, rowOf122.GetTop, QuestBoardFrame.GetLeft = nil, nil, nil
local savedCollapsed = QuestBoardDB.collapsed
QuestBoardDB.collapsed = { active = true, nearby = true, log = true, turnin = true }
ns.render()
check("no button when the quest's row is hidden", not itemBtn.shown)
QuestBoardDB.collapsed = savedCollapsed
ns.render()
check("the button comes back with the row", itemBtn.shown)
local combatNow = true
local realLockdown = InCombatLockdown
InCombatLockdown = function() return combatNow end
itemBtn.attrs.item = "unchanged"
ns.updateItems(ns.state())
check("in combat the item buttons wait", itemBtn.attrs.item == "unchanged" and ns.itemsPending())
combatNow = false
ns.updateItems(ns.state())
check("after combat they update", itemBtn.attrs.item == "item:5000" and not ns.itemsPending())
InCombatLockdown = realLockdown

-- Focus (the default): only Next and Active until the mouse is over the board.
local function countRows()
  local n = 0
  for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.shown then n = n + 1 end end
  return n
end
ns.render()
check("out in the world the whole board shows", countRows() == 5)
local inside = true
function IsInInstance() return inside end
ns.render()
check("focus: in an instance, no rows when nothing is active", countRows() == 0 and QuestBoardFrame.next.shown)
local over = false
QuestBoardFrame.IsMouseOver = function() return over end
over = true
QuestBoardFrame.scripts.OnUpdate(QuestBoardFrame, 0.05)
check("focus: mouse-over shows the whole board", countRows() == 5)
over = false
QuestBoardFrame.scripts.OnUpdate(QuestBoardFrame, 0.1)
check("focus: it stays open for a moment", countRows() == 5)
QuestBoardFrame.scripts.OnUpdate(QuestBoardFrame, 0.5)
check("focus: then only Next and Active again", countRows() == 0)
SlashCmdList.QUESTBOARD("focus")
check("/qb focus off shows the whole board", countRows() == 5 and QuestBoardDB.focus == false)
SlashCmdList.QUESTBOARD("focus")
inside = false
ns.render()
check("leaving the instance shows the whole board again", countRows() == 5)

local shownRows = 0
local firstRow
for _, f in ipairs(frames) do
  if f.kind == "Button" and f.entry and f.shown then
    shownRows = shownRows + 1
    firstRow = firstRow or f
  end
end
check("rows drawn for every quest", shownRows == 5)
check("first row is the turn-in", firstRow.entry.id == 127 and firstRow.name.text == "Murloc Poachers")
check("row shows what to do", firstRow.sub.text == "Hand in to Wiley")
check("board shows the next step", QuestBoardFrame.next.text == "Next: Hand in Murloc Poachers to Wiley  300 yd")
SlashCmdList.QUESTBOARD("compact")
check("/qb compact drops the what-to-do line", firstRow.sub.text == "")
SlashCmdList.QUESTBOARD("compact")
check("arrow turns with facing", firstRow.arrow.shown and firstRow.arrow.rotation == 0.5)
P.facing = 0.2
firstRow.scripts.OnUpdate = nil
QuestBoardFrame.scripts.OnUpdate(QuestBoardFrame, 0.2)
check("arrow follows the player", math.abs(firstRow.arrow.rotation - 0.3) < 1e-9)

-- Click pins the place on the map; Shift-click links.
calls = {}
firstRow.scripts.OnClick(firstRow, "LeftButton")
local wp = lastCall("waypoint")
check("click opens the world map there", lastCall("openMap") and lastCall("openMap")[1] == 1433 and WorldMapFrame.mapID == 1433)
check("click sets a map pin", wp and wp[1].m == 1433 and math.abs(wp[1].x - 0.4) < 1e-9 and lastCall("track"))
P.shift = true
firstRow.scripts.OnClick(firstRow, "LeftButton")
P.shift = false
check("shift-click links the quest", lastCall("link") and lastCall("link")[1]:match("quest:127"))
-- Right-click on a log quest opens the quest log at it, and only once.
local opened, toggled = nil, 0
function QuestMapFrame_OpenToQuestDetails(id) opened = id end
function ToggleQuestLog() toggled = toggled + 1 end
local logRow
for _, f in ipairs(frames) do if f.entry and f.entry.kind == "log" then logRow = f break end end
logRow.scripts.OnClick(logRow, "RightButton")
check("right-click opens the quest log at the quest", opened == logRow.entry.id and toggled == 0)
-- Clicking a turn-in marks the finisher with Questie's icon.
calls = {}
firstRow.scripts.OnClick(firstRow, "LeftButton")
check("click marks the finisher on the map", lastCall("showNPC") and lastCall("showNPC")[1] == 1271)
local pickRow
for _, f in ipairs(frames) do if f.entry and f.entry.kind == "pickup" then pickRow = f break end end
calls = {}
pickRow.scripts.OnClick(pickRow, "RightButton")
check("right-click a pick-up shows the giver", lastCall("showNPC") and lastCall("showNPC")[1] == pickRow.entry.id * 10)

-- Tooltip lines.
GameTooltip.lines = {}
firstRow.scripts.OnEnter(firstRow)
local tip = table.concat(GameTooltip.lines, "|")
check("tooltip names the finisher", tip:find("Turn in at Wiley", 1, true) ~= nil)

-- Slash commands.
SlashCmdList.QUESTBOARD("range 6")
for _ = 1, 50 do ns.step() end
check("/qb range widens pick-ups", QuestBoardDB.maxAbove == 6 and #ns.state().pickup == 3)
SlashCmdList.QUESTBOARD("")
check("/qb hides", not QuestBoardFrame.shown and QuestBoardDB.shown == false)
SlashCmdList.QUESTBOARD("")
check("/qb shows again", QuestBoardFrame.shown)

-- Dragging a row moves the board and saves the place; /qb lock stops it.
local moved = 0
QuestBoardFrame.StartMoving = function() moved = moved + 1 end
QuestBoardFrame.GetLeft = function() return 100 end
QuestBoardFrame.GetTop = function() return 700 end
local anchor
QuestBoardFrame.SetPoint = function(_, a, _, b, x, y) anchor = { a, b, x, y } end
firstRow.scripts.OnDragStart(firstRow)
firstRow.scripts.OnDragStop(firstRow)
check("dragging a row moves the board", moved == 1 and QuestBoardDB.point[1] == "TOPLEFT" and QuestBoardDB.point[2] == 100)
check("after a drag the board hangs from its top edge", anchor[1] == "TOPLEFT" and anchor[2] == "BOTTOMLEFT" and anchor[4] == 700)
SlashCmdList.QUESTBOARD("lock")
firstRow.scripts.OnDragStart(firstRow)
check("/qb lock stops dragging", moved == 1 and QuestBoardDB.locked)
SlashCmdList.QUESTBOARD("lock")

-- Combat fades the board.
local alpha
QuestBoardFrame.SetAlpha = function(_, a) alpha = a end
fire("PLAYER_REGEN_DISABLED")
check("combat fades the board", alpha == 0.35)
fire("PLAYER_REGEN_ENABLED")
check("out of combat it is solid", alpha == 1)

-- /qb tracker off hides the game's tracker, also when it shows again;
-- in combat it only goes see-through.
local tracker = CreateFrame("Frame", "ObjectiveTrackerFrame")
tracker.alpha = 1
function tracker:SetAlpha(a) self.alpha = a end
function tracker:HookScript(what, fn) self.hooks = self.hooks or {} self.hooks[what] = fn end
function tracker:Show() self.shown = true if self.hooks and self.hooks.OnShow then self.hooks.OnShow(self) end end
tracker:Show()
local combat = false
function InCombatLockdown() return combat end
SlashCmdList.QUESTBOARD("tracker off")
check("/qb tracker off hides it", not tracker.shown and QuestBoardDB.hideTrackers)
tracker:Show()
check("it stays hidden when the game shows it", not tracker.shown)
combat = true
tracker:Show()
check("in combat it goes see-through", tracker.shown and tracker.alpha == 0)
combat = false
fire("PLAYER_REGEN_ENABLED")
check("after combat it hides", not tracker.shown and tracker.alpha == 1)
SlashCmdList.QUESTBOARD("tracker on")
check("/qb tracker on brings it back", tracker.shown and not QuestBoardDB.hideTrackers)

-- /qb far on raises the nameplate range and /qb far off puts the old one back.
local cvars = { nameplateMaxDistance = "20", nameplateShowEnemies = "0" }
C_CVar = { GetCVar = function(n) return cvars[n] end,
  SetCVar = function(n, v) cvars[n] = math.min(tonumber(v), n == "nameplateMaxDistance" and 41 or 1) .. "" end }
SlashCmdList.QUESTBOARD("far on")
check("/qb far on: nameplates on, longest range the client takes", cvars.nameplateMaxDistance == "41" and cvars.nameplateShowEnemies == "1")
check("/qb far on says the range", chat[#chat]:find("41 yards") ~= nil)
SlashCmdList.QUESTBOARD("far on")
SlashCmdList.QUESTBOARD("far off")
check("/qb far off puts the old values back", cvars.nameplateMaxDistance == "20" and cvars.nameplateShowEnemies == "0")

-- Party: who shares your quests, and the quests they have that you do not.
local party = { party1 = "Ann" }
local realUnitName = UnitName
function UnitName(u) return party[u] end
C_QuestLog.IsUnitOnQuest = function(u, id) return u == "party1" and id == 122 end
mods.QuestieComms = { remoteQuestLogs = {
  [122] = { ["Ann-Forever"] = { { fulfilled = 5, required = 6, finished = false } } },
  [201] = { ["Ann"] = { { fulfilled = 2, required = 8, finished = false } } },
  [204] = { ["Bo"] = { { fulfilled = 1, required = 8, finished = false } } },
} }
D.resetModules()
local withParty = D.collect({})
local shared
for _, e in ipairs(withParty.log) do if e.id == 122 then shared = e end end
check("a shared quest names the party member and progress", shared and D.partyText(shared.party) == "Ann 5/6")
check("party group: quests a member has that you do not", #withParty.party == 1 and withParty.party[1].id == 201
  and D.partyText(withParty.party[1].party) == "Ann 2/8")
check("party row says who and where", ns.todo(withParty.party[1]) == "Ann 2/8  -  Get it from Marshal")
check("shared row adds who", ns.todo(shared):find("with Ann 5/6", 1, true) ~= nil)
UnitName = realUnitName
mods.QuestieComms = nil
C_QuestLog.IsUnitOnQuest = nil
D.resetModules()
check("no party: no party group", #D.collect({}).party == 0)

-- A quest that starts from an item: where it drops and who takes it in.
QUESTS[207] = { level = 26, requiredLevel = 20, name = "The Glowing Shard", place = { 0, "" }, xp = 1500, obj = 1 }
local realGetQuest = mods.QuestieDB.GetQuest
mods.QuestieDB.GetQuest = function(id)
  local q = realGetQuest(id)
  if id == 207 then q.Starts = { Item = { 10441 } } end
  return q
end
mods.QuestieDB.GetItem = function(_, id) if id == 10441 then return { name = "Glowing Shard", npcDrops = { 3654 } } end end
mods.QuestieDB.GetNPC = function(_, id) if id == 3654 then return { name = "Mutanus the Devourer", spawns = { [718] = { { -1, -1 } } } } end end
mods.DistanceUtils.GetNearestSpawn = function() return { 46, 36 }, 17, 900 end
local realFinisher = mods.DistanceUtils.GetNearestFinisherOrStarter
mods.DistanceUtils.GetNearestFinisherOrStarter = function(who)
  if who.NPC and who.NPC[1] == 2071 then return { 62, 38 }, 17, "Sputtervalve", 2000 end
  if who.NPC and who.NPC[1] == 2070 then return nil end
  return realFinisher(who)
end
local shard = D.pickup(207, 27, 3)
check("item quest: where the item drops", shard.fromItem and shard.item == "Glowing Shard" and shard.dropFrom == "Mutanus the Devourer" and shard.dist == 900)
check("item quest: who takes it in", shard.finisher == "Sputtervalve")
check("item quest: what to do", ns.todo(shard) == "Loot Glowing Shard from Mutanus the Devourer, hand in to Sputtervalve")
-- In a chest: the object's place.
mods.QuestieDB.GetItem = function(_, id) if id == 10441 then return { name = "Glowing Shard", objectDrops = { 77 } } end end
mods.QuestieDB.GetObject = function(_, id) if id == 77 then return { name = "Old Crate", spawns = { [718] = { { 1, 1 } } } } end end
local crate = D.pickup(207, 27, 3)
check("item quest: an object that holds it", crate.dropFrom == "Old Crate" and crate.dropHow == "object" and crate.dist == 900)
-- A world drop: the distance is to the one who takes it in.
mods.QuestieDB.GetItem = function(_, id) if id == 10441 then return { name = "Glowing Shard" } end end
local loose = D.pickup(207, 27, 3)
check("item quest: unknown drop has the finisher's distance", loose.dist == 2000 and loose.toFinisher and loose.target == "Sputtervalve")
check("item quest: unknown drop says so", ns.todo(loose) == "Loot Glowing Shard (drop unknown), hand in to Sputtervalve")
mods.QuestieDB.GetObject = nil
mods.QuestieDB.GetQuest = realGetQuest
mods.DistanceUtils.GetNearestFinisherOrStarter = realFinisher
QUESTS[207] = nil

-- A quest with no place says so once, not on every click.
local before = #chat
ns.pin({ id = 999, name = "Lost Letter", kind = "pickup" })
ns.pin({ id = 999, name = "Lost Letter", kind = "pickup" })
check("no place: one chat line, not one per click", #chat == before + 1 and chat[#chat]:find("Lost Letter", 1, true))

-- Areas: stops close together make one area, scored by XP per minute.
HBD.GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 0 end
D.AREA_YARDS = areaYards
local withAreas = D.collect({})
local area = withAreas.area[1]
check("areas: nearby stops make one area", area and #area.stops >= 3)
check("areas: what is there", D.areaText(area):find("hand in", 1, true) ~= nil)
check("areas: XP per minute counts hand-ins and objectives, not pick-ups", area.xp == 1500 + 1800 + 2400)
QuestBoardDB.doing = {}
ns.toggleArea(area)
local marked = 0
for _, q in ipairs(ns.areaQuests(area)) do if QuestBoardDB.doing[q.id] then marked = marked + 1 end end
check("areas: Alt-click marks every quest there", marked > 0 and marked == #ns.areaQuests(area) and ns.areaPinned(area))
ns.toggleArea(area)
check("areas: again unmarks them", next(QuestBoardDB.doing) == nil and not ns.areaPinned(area))
check("areas: a hand-in is not marked", (function()
  for _, q in ipairs(ns.areaQuests(area)) do if q.kind == "turnin" then return false end end return true end)())
D.heldAt = {}
local nextArea = ns.nextStep(withAreas)
check("next step: the best area when nothing is active", nextArea:find("^Go near ") ~= nil)
D.AREA_YARDS = 0
HBD.GetWorldCoordinatesFromZone = function() return 100, 0, 0 end

-- Chains: 125 leads to 126 and 127; 127 rewards a blue sword. 122 rewards
-- only a potion: XP only.
D.rewardBuild = { state = "idle", i = 1 }
D.rewardsByQuest = nil
D.resetChains()
local NEXT = { [125] = 126, [126] = 128 }
mods.QuestieDB.QueryQuestSingle = function(id, key) if key == "nextQuestInChain" then return NEXT[id] or 0 end end
local ITEMS = { [900] = { name = "Ironforge Gladius", class = 2, q = { 128 } }, [901] = { name = "Healing Potion", class = 0, q = { 122 } },
  [902] = { name = "Murloc Charm", class = 4, q = { 127 } }, [903] = { name = "Fin Soup", class = 0, q = { 127 } } }
mods.QuestieDB.ItemPointers = { [900] = 1, [901] = 1, [902] = 1, [903] = 1 }
mods.QuestieDB.QueryItemSingle = function(id, key)
  local it = ITEMS[id]
  if not it then return nil end
  if key == "questRewards" then return it.q end
  return it[key]
end
local QUALITY = { [900] = 3, [901] = 1, [902] = 2, [903] = 1 }
C_Item = { GetItemInfo = function(id) if ITEMS[id] then return ITEMS[id].name, nil, QUALITY[id] end end }
D.resetModules()
local chained = D.collect({})
local q125, q122
for _, list in ipairs({ chained.log, chained.nearby, chained.active }) do
  for _, e in ipairs(list) do if e.id == 125 then q125 = e end if e.id == 122 then q122 = e end end
end
check("chain: leads to a blue weapon two quests on", q125.chain and q125.chain.steps == 2 and q125.chain.best.id == 900)
check("chain: the tag names it in blue", D.chainTag(q125.chain) == "chain +2 -> |cff0070dd[Ironforge Gladius]|r")
check("chain: a potion only is XP only", D.chainTag(q122.chain) == "XP only")
check("chain: the tag is on the what-to-do line", ns.todo(q125):find("Ironforge Gladius", 1, true) ~= nil)

-- Hand-ins show their XP and reward, so you can judge the trip.
local q127 = chained.turnin[1]
check("turn-in: reward is the best own item, a choice of two", q127.chain.own and q127.chain.own.id == 902 and q127.chain.count == 2)
check("turn-in: what-to-do line names the reward", strip(ns.todo(q127)) == "Hand in to Wiley   [Murloc Charm] +1")
check("turn-in: meta has the XP", strip(ns.meta(q127)) == "1.5k xp  <1 min  300 yd")
check("run time", D.mins(30) == "<1 min" and D.mins(300) == "5 min")
check("turn-in: a long run shows its minutes", strip(ns.meta({ kind = "turnin", xp = 900, dist = 2100 })) == "900 xp  5 min  2.1k yd")
check("turn-in: no item says so", D.rewardTag({ steps = 0, count = 0 }) == "no item")
check("turn-in: better gear on down the chain",
  strip(D.rewardTag({ steps = 1, count = 1, own = { id = 1, name = "Pie", quality = 1 }, best = { id = 2, name = "Axe", quality = 3, gear = true } })) == "[Pie], chain -> [Axe]")
GameTooltip.lines = {}
local turnRow
ns.refresh()
for _ = 1, 50 do ns.step() end
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.entry.id == 127 then turnRow = f end end
turnRow.scripts.OnEnter(turnRow)
local rewardLine = false
for _, l in ipairs(GameTooltip.lines) do if strip(l) == "Reward: [Murloc Charm]  (one of 2)" then rewardLine = true end end
check("turn-in: tooltip names the reward", rewardLine)

-- Distances take a colour: green near, yellow a walk, grey far.
check("distance colours", D.yardsText(120):find("^|cff") and D.yardsText(120) ~= D.yardsText(700)
  and D.yardsText(700) ~= D.yardsText(3000) and strip(D.yardsText(700)) == "700 yd")

-- A far hand-in names its zone.
C_Map.GetMapInfo = function(id) if id == 1453 then return { name = "Stormwind City" } end end
local realUi = mods.ZoneDB and mods.ZoneDB.GetUiMapIdByAreaId
check("far hand-in: the mock has ZoneDB", mods.ZoneDB ~= nil)
if mods.ZoneDB then
  mods.ZoneDB.GetUiMapIdByAreaId = function(_, z) if z == 1519 then return 1453 end return realUi and realUi(_, z) end
  check("far hand-in: names the zone", ns.todoBase({ kind = "turnin", target = "Bob", far = true, zone = 1519 }) == "Hand in to Bob in Stormwind City")
  mods.ZoneDB.GetUiMapIdByAreaId = realUi
end
C_Map.GetMapInfo = nil

-- Pace: your own seconds per kill make the time left.
D.pace, D.anyPace, D.lastGain, D.seen = {}, nil, {}, {}
local pq = { id = 900, count = 1, left = { { have = 1, need = 6 } } }
D.noteProgress(pq, 100)
check("pace: before any kill, the default", D.workSecs(pq) == D.OBJECTIVE_SECS)
pq.count = 2 D.noteProgress(pq, 110)
pq.count = 4 pq.left[1].have = 4 D.noteProgress(pq, 150)
check("pace: from your kills", D.pace[900] and D.pace[900] == 20)
check("pace: time left is kills left times pace", math.abs(D.workSecs(pq) - 2 * D.pace[900]) < 1e-9)
check("pace: other quests use your pace too", D.workSecs({ id = 901, left = { { have = 0, need = 3 } } }) == 3 * D.anyPace)
pq.count = 5 D.noteProgress(pq, 150 + D.PACE_GAP_SECS + 1)
check("pace: a long break does not count", D.pace[900] == 20)
check("pace: Active row shows time left", strip(ns.meta({ kind = "log", id = 900, left = pq.left, dist = 70 }, "active")):find("^~<1 min") ~= nil)
D.pace, D.anyPace, D.lastGain, D.seen = {}, nil, {}, {}

-- Sorting: near ones by distance, far ones (past MID_YARDS) by XP.
local sorted = D.sort({ { name = "a", dist = 3000, xp = 500 }, { name = "b", dist = 200, xp = 100 },
  { name = "c", xp = 2000 }, { name = "d", dist = 5000, xp = 1500 }, { name = "e", dist = 800, xp = 50 } }, "near")
local names = {}
for _, e in ipairs(sorted) do table.insert(names, e.name) end
check("sort: near by distance, then far by XP", table.concat(names) == "becda")

-- Group order: hand-ins first when nothing is active and one is near;
-- Active first while you are on a quest.
local function order(st) return table.concat(ns.order(st), ",") end
check("order: a near hand-in leads when nothing is active", order({ active = {}, turnin = { { dist = 300 } } }):find("^turnin,nearby") ~= nil)
check("order: a far hand-in does not", order({ active = {}, turnin = { { dist = 3000 } } }):find("^active") ~= nil)
check("order: Active leads while you do a quest", order({ active = { {} }, turnin = { { dist = 100 } } }):find("^active,nearby") ~= nil)

-- Pinned quests get a gold star.
QuestBoardDB.doing = { [122] = true }
ns.refresh()
for _ = 1, 50 do ns.step() end
local starred, others = false, false
for _, f in ipairs(frames) do
  if f.kind == "Button" and f.entry and f.shown and f.pin then
    if f.entry.id == 122 then starred = f.pin.shown elseif f.pin.shown then others = true end
  end
end
check("pinned: a star on the quest you marked", starred and not others)
-- Progress bars: Active quest 122 is 3/6 = half way, in gold.
local barRow
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.shown and f.entry.id == 122 then barRow = f end end
check("progress: half way", barRow.entry.frac == 0.5)
check("progress: the bar shows", barRow.bar.shown and barRow.fill.shown)
local turnBar
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.shown and f.entry.id == 127 then turnBar = f end end
check("progress: no bar on a hand-in", not turnBar.bar.shown)
-- On a job: Active plus hand-ins and pick-ups on the way; the rest on hover.
local shownIDs = {}
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.shown then table.insert(shownIDs, f.entry.id) end end
table.sort(shownIDs)
local idSet = {}
for _, id in ipairs(shownIDs) do idSet[id] = true end
check("on a job: Active shows, the rest of the log does not", idSet[122] and idSet[127] and idSet[201] and not idSet[125])
local way = ns.onWay({ { id = 1, dist = 250 }, { id = 2, dist = 900, wx = 100, wy = 0, inst = 0 }, { id = 3, dist = 900, wx = 900, wy = 0, inst = 0 } },
  { { wx = 0, wy = 0, inst = 0 } })
check("on a way: near you or near an Active quest", #way == 2 and way[1].id == 1 and way[2].id == 2)
check("on a job: the title says hover shows all", (QuestBoardFrame.sub.text or ""):find("hover: all", 1, true) ~= nil)
ns.hover(true, 0)
check("on a job: mouse-over shows the whole board", countRows() > #shownIDs)
ns.hover(false, 1)
check("on a job: and trims again after", countRows() == #shownIDs)
QuestBoardDB.doing = {}
D.heldAt = {}

-- Max height: rows past it hide, the wheel scrolls, the grip sets it.
local board = QuestBoardFrame
function board:SetHeight(h) self.h = h end
function board:GetHeight() return self.h end
ns.refresh()
for _ = 1, 50 do ns.step() end
local fullH, fullRows = board.h, countRows()
SlashCmdList.QUESTBOARD("height 120")
check("height: the board is no taller than the max", board.h <= 120 and countRows() < fullRows and board.more.shown)
check("height: it says how many are below", (board.more.text or ""):find("more below", 1, true) ~= nil)
local before = {}
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.shown then before[f] = true end end
ns.scrollBy(-1)
ns.scrollBy(-1)
local moved = false
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.shown and not before[f] then moved = true end end
check("height: the wheel shows rows further down", moved and ns.scroll > 0 and (board.more.text or ""):find("above", 1, true) ~= nil)
ns.scrollBy(100)
check("height: scroll stops at the top", ns.scroll == 0)
local cursor = 500
function GetCursorPosition() return 0, cursor end
ns.sizeStart()
cursor = 400
ns.sizeMove()
ns.sizeStop()
check("height: dragging the grip down raises the max", QuestBoardDB.maxHeight == math.floor(120 + 100 + 0.5) or QuestBoardDB.maxHeight >= 200)
SlashCmdList.QUESTBOARD("height off")
check("height off: the whole board again", QuestBoardDB.maxHeight == nil and board.h == fullH and countRows() == fullRows and not board.more.shown)
mods.QuestieDB.QueryQuestSingle, mods.QuestieDB.ItemPointers, mods.QuestieDB.QueryItemSingle, C_Item = nil, nil, nil, nil
D.rewardBuild = { state = "idle", i = 1 }
D.rewardsByQuest = nil
D.resetModules()

---------------------------------------------------------------------------
-- Without Questie: the log only, no errors.
questieOn = false
D.resetModules()
local bare = D.collect({})
check("no Questie: log still read", #bare.turnin == 1 and #bare.log == 2 and #bare.pickup == 0 and not bare.questie)
check("no Questie: no distance", bare.log[1].dist == nil and not ns.meta(bare.log[1]):find("yd"))

-- A Questie function that throws does not break the pass.
questieOn = true
D.resetModules()
mods.DistanceUtils.GetNearestSpawnForQuest = function() error("changed") end
local rough = D.collect({})
check("a failing Questie call is skipped", #rough.log == 2)

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
print("all passed")
