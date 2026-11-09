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
for _, file in ipairs({ "Data.lua", "QuestBoard.lua" }) do
  local chunk = assert(loadfile(root .. "QuestBoard/" .. file))
  chunk("QuestBoard", ns)
end
local D = ns.data
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
check("row meta for a pick-up", ns.meta(e201):match("^~%d+ xp/m  150 yd$") ~= nil)
check("row meta for a log quest", ns.meta(out.log[2]) == "3/6  900 yd")

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
QuestBoardFrame.GetPoint = function() return "TOPLEFT", nil, nil, 100, -200 end
firstRow.scripts.OnDragStart(firstRow)
firstRow.scripts.OnDragStop(firstRow)
check("dragging a row moves the board", moved == 1 and QuestBoardDB.point[1] == "TOPLEFT" and QuestBoardDB.point[2] == 100)
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
