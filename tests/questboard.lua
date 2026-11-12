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
function GameTooltip:AddDoubleLine(l, r) table.insert(self.lines, l .. " | " .. r) end
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
for _, file in ipairs({ "Data.lua", "Chain.lua", "QuestBoard.lua", "Items.lua", "Spare3.lua" }) do
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
-- Every quest can be pinned: a hand-in and a pick-up too.
local pickID = doing.pickup[1].id
local pins = { [127] = true, [pickID] = true, [9999] = true, [9998] = true }
local realDone = C_QuestLog.IsQuestFlaggedCompleted
C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 9999 end
local all = D.collect({ time = 4001, doing = pins })
C_QuestLog.IsQuestFlaggedCompleted = realDone
local inActive = {}
for _, e in ipairs(all.active) do inActive[e.id] = e end
-- A quest you were working on that is now done stays in Active.
D.heldAt[127] = 3990
local justDone = D.collect({ time = 4000 })
local stays = false
for _, e in ipairs(justDone.active) do if e.id == 127 then stays = true end end
check("just done: the hand-in stays in Doing", stays)
D.heldAt[127] = nil
check("a pinned hand-in is Active", inActive[127] and inActive[127].kind == "turnin" and inActive[127].pinned and #all.turnin == 0)
check("a pinned pick-up is Active", inActive[pickID] and inActive[pickID].kind == "pickup" and inActive[pickID].pinned)
check("a pinned pick-up leaves Pick up", (function() for _, e in ipairs(all.pickup) do if e.id == pickID then return false end end return true end)())
check("a pin of a quest you handed in goes", pins[9999] == nil and pins[127] and pins[pickID])
check("a pin stays when the quest is not seen yet (just after /reload)", pins[9998])
check("hand-ins and pick-ups are pinnable", ns.pinnable(inActive[127]) and ns.pinnable(inActive[pickID]) and not ns.pinnable({ kind = "area" }))
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
QuestBoardDB.collapsed = { next = true, active = true }
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
check("out in the world the whole board shows", countRows() == 4)
local inside = true
function IsInInstance() return inside end
ns.render()
check("focus: in an instance, no rows when nothing is active", countRows() == 0 and QuestBoardFrame.tabs[1].shown)
local over = false
QuestBoardFrame.IsMouseOver = function() return over end
over = true
QuestBoardFrame.scripts.OnUpdate(QuestBoardFrame, 0.05)
check("focus: mouse-over shows the whole board", countRows() == 4)
over = false
QuestBoardFrame.scripts.OnUpdate(QuestBoardFrame, 0.1)
check("focus: it stays open for a moment", countRows() == 4)
QuestBoardFrame.scripts.OnUpdate(QuestBoardFrame, 0.5)
check("focus: then only Next and Active again", countRows() == 0)
SlashCmdList.QUESTBOARD("focus")
check("/qb focus off shows the whole board", countRows() == 4 and QuestBoardDB.focus == false)
SlashCmdList.QUESTBOARD("focus")
inside = false
ns.render()
check("leaving the instance shows the whole board again", countRows() == 4)

local shownRows = 0
local firstRow
for _, f in ipairs(frames) do
  if f.kind == "Button" and f.entry and f.shown then
    shownRows = shownRows + 1
    firstRow = firstRow or f
  end
end
check("Nearby: every stop within 1000 yd", shownRows == 4 and ns.tab() == "nearby")
check("first row is the turn-in", firstRow.entry.id == 127 and firstRow.name.text == "Murloc Poachers")
check("row shows what to do, marked complete", strip(firstRow.sub.text) == "Complete  Hand in to Wiley")
-- Alt-click a list's heading: pin every quest in it (an area's stops too).
local setList = { { id = 501, kind = "log", name = "x" }, { kind = "area", stops = { { id = 502, kind = "pickup", name = "y" }, { id = 501, kind = "log", name = "x" } } },
  { kind = "more", name = "+1 more" } }
QuestBoardDB.doing = {}
check("pin all: the quests of a list, area stops included, once each", #ns.listQuests(setList) == 2)
ns.pinList(setList)
check("pin all: every one pinned", QuestBoardDB.doing[501] and QuestBoardDB.doing[502] and ns.listPinned(setList))
ns.pinList(setList)
check("pin all: again unpins them", next(QuestBoardDB.doing) == nil)
local zoneRow = { kind = "zone", name = "Wetlands", stops = { { id = 601, kind = "log", name = "a" }, { id = 602, kind = "pickup", name = "b" } }, left = {} }
local realAltZ = IsAltKeyDown
IsAltKeyDown = function() return true end
ns.click(zoneRow)
check("pin all: Alt-click a zone pins its quests", QuestBoardDB.doing[601] and QuestBoardDB.doing[602])
ns.click(zoneRow)
IsAltKeyDown = realAltZ
check("pin all: again unpins the zone", next(QuestBoardDB.doing) == nil)
local pinState = { active = { { id = 1, pinned = true, name = "p", kind = "log", left = {} }, { id = 2, name = "q", kind = "log", left = {} } },
  nearby = {}, turnin = {}, log = {}, party = {}, pickup = {}, area = {}, zones = {}, town = {}, members = {} }
local ps = ns.sections(pinState, "areas")
check("pins: a Pinned list on top of the other tabs", ps[1] and ps[1].key == "pinned" and #ps[1].list == 1 and ps[1].list[1].id == 1)
check("pins: not twice in Doing", ns.sections(pinState, "doing")[1].key == "active")
check("pins: not twice in Log (the star marks them there)", ns.sections(pinState, "log")[1].key ~= "pinned")
pinState.active[1].dist, pinState.active[2].dist = 100, 100
local pn = ns.sections(pinState, "nearby")
check("pins: not twice in Nearby", pn[1].key == "pinned" and pn[2].key == "next" and #pn[2].list == 1 and pn[2].list[1].id == 2)
pinState.active[1].dist, pinState.active[2].dist = nil, nil
ns.refresh()
for _ = 1, 50 do ns.step() end
local nextHead
for _, f in ipairs(frames) do if f.kind == "Button" and f.shown and f.list and f.text and (f.text.text or ""):find("^Chain next") then nextHead = f end end
local realAlt = IsAltKeyDown
IsAltKeyDown = function() return true end
nextHead.scripts.OnClick(nextHead, "LeftButton")
IsAltKeyDown = realAlt
local pinnedN = 0
for _ in pairs(QuestBoardDB.doing) do pinnedN = pinnedN + 1 end
check("pin all: Alt-click on Chain next pins its rows", pinnedN == 4)
QuestBoardDB.doing = {}
D.heldAt = {}
ns.refresh()
for _ = 1, 50 do ns.step() end
check("tabs: Nearby is picked and gold", QuestBoardFrame.tabs[2].text.text == "Nearby" and QuestBoardFrame.tabs[2].line.shown
  and QuestBoardFrame.tabs[4].text.text == "Log" and not QuestBoardFrame.next.shown)
check("tabs: no title line above them", QuestBoardFrame.title.text == "" and QuestBoardFrame.sub.text == "")
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
-- Your party: a row per member with how they are and where.
local realMap = { C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapInfo }
local realLevel = UnitLevel
UnitLevel = function(u) if u == "party1" then return 12 end return realLevel(u) end
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
UnitHealth = function() return 45 end
UnitHealthMax = function() return 60 end
UnitIsAFK = function() return false end
C_Map.GetBestMapForUnit = function(u) return u == "party1" and 1436 or 1437 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
C_Map.GetMapInfo = function(id) return { name = id == 1436 and "Westfall" or "Elwynn" } end
local realWorld = HBD.GetWorldCoordinatesFromZone
HBD.GetWorldCoordinatesFromZone = function() return 300, 400, 0 end
D.resetModules()
local mem = D.collect({}).members
local ann = mem and mem[1]
check("members: one row per member", mem and #mem == 1 and ann.name == "Ann" and ann.level == 12 and ann.classColor[1] == 0.25)
check("members: where they are", ann.dist == 500 and ann.spot.mapID == 1436 and ann.zoneName == "Westfall")
check("members: status line", D.memberText(ann) == "75% hp, in Westfall, 1 quest with you, 1 you lack"
  and D.memberText({ theirs = 2 }) == "2 you lack")
check("members: row text and distance", ns.todo(ann) == D.memberText(ann) and strip(ns.meta(ann)) == "500 yd")
check("members: not pinnable, no link", not ns.pinnable(ann))
ns.refresh()
for _ = 1, 50 do ns.step() end
local memRow
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.shown and f.entry.kind == "member" then memRow = f end end
GameTooltip.lines = {}
if memRow then memRow.scripts.OnEnter(memRow) end
local tipHas = false
for _, l in ipairs(GameTooltip.lines) do if strip(l):find("75% health, 500 yd", 1, true) then tipHas = true end end
check("members: a row on the board with a tooltip", memRow and tipHas)
UnitIsDeadOrGhost = function() return true end
check("members: dead", D.collect({}).members[1].status == "Dead")
UnitIsDeadOrGhost = nil
UnitIsConnected = function() return false end
local off = D.collect({}).members[1]
check("members: offline, no health", off.status == "Offline" and D.memberText(off):find("^Offline") ~= nil and not off.hp)
UnitIsConnected = nil
check("members: party off hides them", #D.collect({ party = false }).members == 0)
check("members: behind when you can hand in and they cannot", D.memberText({ shared = { 1, 2 }, behind = 1 }) == "2 quests with you (1 behind)")
UnitLevel, UnitClass, RAID_CLASS_COLORS, UnitHealth, UnitHealthMax, UnitIsAFK = realLevel, nil, nil, nil, nil, nil
C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapInfo = realMap[1], realMap[2], realMap[3]
HBD.GetWorldCoordinatesFromZone = realWorld
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
check("item quest: where the item drops", shard.fromItem and shard.startItem == "Glowing Shard" and not shard.item and shard.dropFrom == "Mutanus the Devourer" and shard.dist == 900)
check("a pinned item-start pickup does not break the item buttons", pcall(ns.itemList, { active = { shard } }))
do
  -- Long lines wrap at a space (5 units a letter here), at most two lines.
  local realProbe = ns.probe
  ns.probe = { SetText = function(self, t) self.t = t end, GetStringWidth = function(self) return #self.t * 5 end }
  local out = ns.wrapLines({ "short", "Loot Titan Relic from a far place, hand in to Prospector" }, 150)
  check("a short line stays one line", out[1] == "short")
  check("a long line wraps at a space", out[2] == "Loot Titan Relic from a far" and out[3] == "  place, hand in to Prospector" and #out == 3)
  ns.probe = realProbe
end
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
do
  local avail = mods.AvailableQuests.__availableQuests
  avail[207] = true
  local function has(list) for _, e in ipairs(list) do if e.id == 207 then return e end end end
  local st = D.collect({ time = 9000 })
  check("a world-drop quest is not offered as a pick-up", not has(st.pickup) and not has(st.farPickup) and not has(st.active))
  local pinnedSt = D.collect({ time = 9001, doing = { [207] = true } })
  local p = has(pinnedSt.active)
  check("a pinned world-drop quest stays, marked drop unknown", p and p.toFinisher and ns.meta(p, "active"):find("drop unknown", 1, true))
  avail[207] = nil
end
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
check("areas: hand-ins are marked too", (function()
  for _, q in ipairs(ns.areaQuests(area)) do if q.kind == "turnin" then return true end end return false end)())
D.heldAt = {}
local here = ns.nextStep(withAreas)
check("next step: not 'go to' an area you are in", not here:find("^Go "))
local savedDist = withAreas.area[1].dist
withAreas.area[1].dist = 2000
local nextArea = ns.nextStep(withAreas)
check("next step: the best area when nothing is active", nextArea:find("^Go ") ~= nil)
withAreas.area[1].dist = savedDist
local fake = { log = { { kind = "log", id = 1, name = "L", target = "Stoutfist", wx = 0, wy = 0, dist = 10, xp = 100, left = {} } },
  pickup = { { kind = "pickup", id = 2, fromItem = true, wx = 5, wy = 0, dist = 15, xp = 100 },
    { kind = "pickup", id = 3, wx = 6, wy = 0, dist = 16, xp = 100 } },
  party = { { kind = "party", id = 4, wx = 7, wy = 0, dist = 17, xp = 100 } } }
local fa = D.areas(fake)[1]
check("areas: no item-started pick-ups, no party quests you cannot take", fa and #fa.stops == 2 and D.areaText(fa) == "1 objective, 1 pick up")
check("areas: inside one, the name says so", fa.name:find("^Around you") ~= nil)
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
-- Two-line quest rows: line 1 how far, line 2 the same two numbers on
-- every quest, then a gear line only when there is gear.
check("row: line 1 has only the distance", strip(ns.place(q127)) == "300 yd" and strip(ns.place({ kind = "log", left = {} })) == "no place")
check("row: a hand-in shows XP per minute and the run", strip(ns.stats(q127)) == "1.2k xp/m  <1 min")
check("row: a pick-up shows a guessed XP per minute", strip(ns.stats({ kind = "pickup", xp = 625, secs = 180 })) == "~208 xp/m  3 min")
check("row: a hand-in names its reward", strip(ns.rewardLine(q127)) == "Reward: [Murloc Charm] or 1 more")
check("row: a chain names the gear and how far on", strip(ns.rewardLine(q125)) == "Leads to [Ironforge Gladius], 2 quests on")
check("row: XP only gets no gear line", ns.rewardLine(q122) == nil)
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

-- The whole chain in the tooltip: 124 comes before 125 (done), 125 is in
-- your log, then 126 and 128.
local PRE = { [125] = { 124 }, [126] = 125 }
local QNAMES = { [124] = "Before", [125] = "Start", [126] = "Middle", [128] = "End" }
mods.QuestieDB.QueryQuestSingle = function(id, key)
  if key == "nextQuestInChain" then return NEXT[id] or 0 end
  if key == "preQuestSingle" then return PRE[id] end
  if key == "name" then return QNAMES[id] end
  if key == "questLevel" then return 10 end
end
D.resetModules()
local full, at = D.fullChain(126)
check("chain: walks back and on", table.concat(full, ",") == "124,125,126,128" and at == 3)
local steps = D.chainSteps(126, { [125] = true })
check("chain: steps marked done, log, here, later", steps and steps[1].state == "done" and steps[2].state == "log"
  and steps[3].state == "here" and steps[4].state == "later" and steps[4].name == "End")
-- Steps not done show their XP and minutes (the trip and the work); the
-- heading sums what is left. Every place is at 100, 0; you are at 0, 0.
QUESTS[126] = { level = 27, requiredLevel = 20, name = "Middle", place = { 100, "Giver" }, xp = 1000 }
QUESTS[128] = { level = 27, requiredLevel = 20, name = "End", place = { 100, "Giver" }, xp = 500 }
local realNPC = mods.QuestieDB.QueryNPCSingle
mods.QuestieDB.QueryNPCSingle = function(id, key) if key == "spawns" then return { [44] = { { 50, 50 } } } end end
local level0 = P.level
P.level = 27
local lines = D.chainLines(D.chainSteps(126, {}))
local work = D.PICKUP_SECS * 2 + D.OBJECTIVE_SECS + D.RETURN_SECS
local stepMin = math.floor((100 / D.RUN_SPEED + work) / 60 + 0.5)
check("chain: heading sums what is left", type(lines[1]) == "table" and strip(lines[1][1]) == "Chain: quest 3 of 4"
  and lines[1][2] == string.format("2 left: 1.5k xp, %d min", math.floor((100 / D.RUN_SPEED + 2 * work) / 60 + 0.5)))
check("chain: travel and questing time", strip(lines[2][2]) == string.format("1 min travel, %d min questing (a guess)", math.floor(2 * work / 60 + 0.5)))
check("chain: done steps have no numbers", strip(lines[3]) == "  done  [10] Before" and strip(lines[4]) == "  done  [10] Start")
check("chain: a step shows its XP and minutes", strip(lines[5][1]) == "  >>  [10] Middle" and lines[5][2] == "1.0k xp  " .. stepMin .. " min")
check("chain: the next step starts where the last one ends; gear is marked", strip(lines[6][1]) == "  ...  [10] End  +gear"
  and lines[6][2] == "500 xp  " .. math.floor(work / 60 + 0.5) .. " min" and #lines == 6)
local hereLines = D.chainLines(D.chainSteps(126, {}), 3, { secs = 600, dist = 70 })
check("chain: the hovered quest uses the board's time", hereLines[5][2] == "1.0k xp  10 min")
mods.QuestieDB.QueryNPCSingle = function() end
check("chain: no place, the time is a guess", D.chainLines(D.chainSteps(126, {}))[5][2]:find("~") ~= nil)
check("chain: no chain, no lines", D.chainSteps(122, {}) == nil and #D.chainLines(nil) == 0)
D.CHAIN_SHOW = 2
local cut = D.chainLines(D.chainSteps(126, {}))
check("chain: a long chain is cut around this quest", strip(cut[3]) == "  (1 earlier)" and strip(cut[#cut][1]) == "  (1 more)"
  and cut[#cut][2]:find("^500 xp") ~= nil)
D.CHAIN_SHOW = 8
mods.QuestieDB.QueryNPCSingle, QUESTS[126], QUESTS[128], P.level = realNPC, nil, nil, level0
GameTooltip.lines = {}
turnRow.scripts.OnEnter(turnRow)
mods.QuestieDB.QueryQuestSingle = function(id, key) if key == "nextQuestInChain" then return NEXT[id] or 0 end end
D.resetModules()

-- A group past its row limit ends in a "+N more" line, never a silent cut.
local saveRows = QuestBoardDB.rows.log
QuestBoardDB.rows.log = 1
local longList = { { name = "A" }, { name = "B" }, { name = "Stopping the Cycle" } }
local cut = ns.shownRows("log", longList)
check("rows: a cut group ends in a more line", #cut == 2 and cut[2].kind == "more" and cut[2].name == "+2 more: B, Stopping the Cycle")
ns.click(cut[2])
local open = ns.shownRows("log", longList)
check("rows: click shows the whole group", #open == 4 and open[4].name == "show fewer")
ns.click(open[4])
check("rows: again folds it", #ns.shownRows("log", longList) == 2 and not ns.pinnable(cut[2]))
check("rows: a short group has no more line", #ns.shownRows("log", { { name = "A" } }) == 1)
QuestBoardDB.rows.log = saveRows
-- /qb why: where a quest is, or why not.
local whyState = { active = {}, nearby = {}, turnin = {}, log = { { name = "A" }, { name = "Stopping the Cycle" } }, party = {}, pickup = {} }
check("why: in the log", D.whyQuest("stopping", whyState, ns.WHERE, 3) == "Stopping the Cycle, no known place: in the Log tab, and in Nearby within 1000 yd")
check("why: a level too high", D.unfitReason({ level = 20 }, 10, 3):find("level 20, more than 3 over you", 1, true) ~= nil)
check("why: unknown name", D.whyQuest("no such quest", whyState, ns.WHERE, 3):find("no quest named", 1, true) ~= nil)

-- Dungeon quests: the level gets a tag, and /qb dungeons off keeps them
-- to the Log tab.
D.resetTags()
GetQuestTagInfo = function(id) if id == 122 then return 81, "Dungeon" end if id == 201 then return 62, "Raid" end end
check("tag: dungeon, raid, group by size", D.questTag(122) == "D" and D.questTag(201) == "R" and D.questTag(999, 5) == "G" and D.questTag(998) == nil)
local tagged = D.collect({})
local q122t
for _, kind in ipairs({ "active", "nearby", "log" }) do for _, e in ipairs(tagged[kind]) do if e.id == 122 then q122t = e end end end
check("tag: a log quest has it", q122t and q122t.tag == "D" and not q122t.hiddenTag)
local hid = D.collect({ dungeons = false })
local q122h, p201
for _, kind in ipairs({ "active", "nearby", "log" }) do for _, e in ipairs(hid[kind]) do if e.id == 122 then q122h = e end end end
for _, e in ipairs(hid.pickup) do if e.id == 201 then p201 = e end end
check("dungeons off: the log quest stays for the Log tab, marked hidden", q122h and q122h.hiddenTag)
check("dungeons off: a raid pick-up is left out", p201 == nil)
local inNext = false
for _, e in ipairs(ns.nextList(hid)) do if e.id == 122 then inNext = true end end
check("dungeons off: not in Nearby", not inNext)
GetQuestTagInfo = nil
D.resetTags()
do
  -- No tag from the game, but Questie files it under the Stockade (717).
  local realQ = mods.QuestieDB.QueryQuestSingle
  mods.QuestieDB.QueryQuestSingle = function(id, key)
    if key == "zoneOrSort" then return id == 386 and 717 or id == 387 and 2717 or 12 end
    return realQ and realQ(id, key)
  end
  check("tag: an untagged quest filed under a dungeon is D", D.questTag(386) == "D" and D.questTag(387) == "R" and D.questTag(388) == nil)
  mods.QuestieDB.QueryQuestSingle = realQ
  D.resetTags()
  -- A dungeon quest takes a run, not one kill.
  local secs = D.workSecs({ id = 386, tag = "D", left = { { have = 0, need = 1 } } })
  check("dungeon quest: the time is a run", secs == D.RUN_SECS.D)
  check("dungeon quest: half done, half a run", D.workSecs({ id = 386, tag = "D", frac = 0.5 }) == D.RUN_SECS.D / 2)
end

-- Level weight: a quest over your level counts slower; red near not doable.
check("level factor", D.levelFactor(10, 10) == 1 and D.levelFactor(12, 10) == 1.6 and D.levelFactor(15, 10) == D.RED_SLOW
  and D.levelFactor(6, 10) == D.LOW_FAST and D.levelFactor(nil, 10) == 1)
local easy = D.pickupSecs({ level = P.level, objectives = 2 })
local hard = D.pickupSecs({ level = P.level + 3, objectives = 2 })
check("level factor: a pick-up 3 over takes longer", hard > easy and math.abs((hard - easy) - 2 * D.OBJECTIVE_SECS * 1.2) < 0.01)
local savedPace = D.pace
D.pace = {}
local w1 = D.workSecs({ id = 77001, level = P.level, left = { { have = 0, need = 4 } } })
local w2 = D.workSecs({ id = 77002, level = P.level + 2, left = { { have = 0, need = 4 } } })
D.pace = { [77003] = 20 }
local w3 = D.workSecs({ id = 77003, level = P.level + 2, left = { { have = 0, need = 4 } } })
D.pace = savedPace
check("level factor: guessed work scales, measured pace does not", math.abs(w2 - w1 * 1.6) < 0.01 and w3 == 80)

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
check("pace: before any kill, a guess per kill left", D.workSecs(pq) == 5 * D.UNIT_SECS and select(2, D.workSecs(pq)) == true)
check("pace: 27 drops left is not 2 minutes", D.workSecs({ id = 999, left = { { have = 3, need = 30 } } }) == 27 * D.UNIT_SECS)
pq.count = 2 D.noteProgress(pq, 110)
pq.count = 4 pq.left[1].have = 4 D.noteProgress(pq, 150)
check("pace: from your kills", D.pace[900] and D.pace[900] == 20)
check("pace: time left is kills left times pace", math.abs(D.workSecs(pq) - 2 * D.pace[900]) < 1e-9)
check("pace: other quests use your pace too", D.workSecs({ id = 901, left = { { have = 0, need = 3 } } }) == 3 * math.max(D.anyPace, D.UNIT_SECS))
pq.count = 5 D.noteProgress(pq, 150 + D.PACE_GAP_SECS + 1)
check("pace: a long break does not count", D.pace[900] == 20)
check("pace: Active row shows time left", strip(ns.meta({ kind = "log", id = 900, left = pq.left, dist = 70 }, "active")):find("^~<1 min") ~= nil)
D.pace, D.anyPace, D.lastGain, D.seen = {}, nil, {}, {}

-- XP colours: best third green, worst third grey.
local tl = { { v = 10 }, { v = 50 }, { v = 30 }, { v = 90 }, { v = 70 }, { v = 20 } }
D.tier(tl, "v")
local tiers = {}
for _, e in ipairs(tl) do tiers[e.v] = e.tier or "mid" end
check("xp colours: thirds", tiers[90] == "good" and tiers[70] == "good" and tiers[10] == "low" and tiers[20] == "low" and tiers[30] == "mid" and tiers[50] == "mid")
check("xp colours: green text", D.tierText({ tier = "good" }, "1k xp") == "|cff60d0601k xp|r" and D.tierText({}, "x") == "x")
local two = { { v = 1 }, { v = 2 } }
D.tier(two, "v")
check("xp colours: too few to rank", not two[1].tier and not two[2].tier)

-- Town: nearest innkeeper and flight master of your side.
local NPCS = {
  [1] = { name = "Innkeeper A", npcFlags = 65536 + 1, friendlyToFaction = "A", d = 800 },
  [2] = { name = "Innkeeper H", npcFlags = 65536, friendlyToFaction = "H", d = 100 },
  [3] = { name = "Gryphon Master", npcFlags = 8192, friendlyToFaction = "A", d = 1500 },
  [4] = { name = "Innkeeper Far", npcFlags = 65536, friendlyToFaction = "AH", d = 3000 },
  [5] = { name = "Vendor", npcFlags = 128, friendlyToFaction = "A", d = 10 },
}
UnitFactionGroup = function() return "Alliance" end
local realQNS, realNearest = mods.QuestieDB.QueryNPCSingle, mods.DistanceUtils.GetNearestSpawn
mods.QuestieDB.NPCPointers = { [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1 }
mods.QuestieDB.QueryNPCSingle = function(id, key)
  local n = NPCS[id]
  if not n then return realQNS and realQNS(id, key) end
  if key == "spawns" then return { d = n.d } end
  return n[key]
end
mods.DistanceUtils.GetNearestSpawn = function(sp) return { 50, 50 }, 1519, sp.d end
D.townBuild, D.townNPCs = { state = "idle", i = 1 }, nil
D.resetModules()
local town = D.townList()
check("town: nearest inn of your side, then the flight master", #town == 2 and town[1].name == "Innkeeper A" and town[1].dist == 800
  and town[2].name == "Gryphon Master" and town[2].role == "flight")
check("town: what the row says", ns.todoBase({ kind = "town", role = "inn" }) == "Innkeeper")
mods.QuestieDB.NPCPointers, mods.QuestieDB.QueryNPCSingle, mods.DistanceUtils.GetNearestSpawn = nil, realQNS, realNearest
D.townBuild, D.townNPCs = { state = "idle", i = 1 }, nil
UnitFactionGroup = nil
D.resetModules()

-- Glance pointers: Next, nearest hand-in, town; registered with Glance.
local srcFn
Glance = { minimap = { addPointerSource = function(fn) srcFn = fn end } }
check("pointers: registered with Glance", ns.registerPointers() and srcFn ~= nil)
mods.ZoneDB = mods.ZoneDB or {}
local realUi2 = mods.ZoneDB.GetUiMapIdByAreaId
mods.ZoneDB.GetUiMapIdByAreaId = function() return 1437 end
ns.updatePointers({ active = { { kind = "log", name = "Q", target = "Kobold", spawn = { 41, 62 }, zone = 11, left = {} } },
  turnin = { { kind = "turnin", name = "T", target = "Bob", spawn = { 10, 20 }, zone = 11 } }, nearby = {}, log = {},
  town = { { kind = "town", role = "inn", name = "Inn Lady", spawn = { 50, 50 }, zone = 11 } } })
local pts = srcFn()
check("pointers: next, hand-in and inn", #pts == 3 and pts[1].label == "Kobold" and pts[1].mapID == 1437 and math.abs(pts[1].x - 0.41) < 1e-9
  and pts[2].label == "Hand in: Bob" and pts[3].label == "Inn: Inn Lady")
mods.ZoneDB.GetUiMapIdByAreaId = realUi2
Glance = nil
ns.pointers = {}

-- Active detail: a line per objective, the party, the chain.
local al = ns.activeLines({ target = "Kobold", left = { { text = "Candle: 2/8" }, { text = "Kobold Miner slain: 1/6" } },
  party = { { name = "Ann", progress = "5/8" } } })
check("active detail: one line each", #al == 3 and al[1] == "Candle: 2/8  (Kobold)" and al[2] == "Kobold Miner slain: 1/6"
  and strip(al[3]) == "Party: Ann 5/8")

-- /qb party off: no party data here, Questie's party objectives off, back on with on.
local poCalls = 0
Questie = { db = { profile = { showPartyQuestObjectives = true } } }
mods.QuestiePartyObjectives = { Update = function() poCalls = poCalls + 1 end }
D.resetModules()
SlashCmdList.QUESTBOARD("party off")
check("party off: Questie's party objectives off", Questie.db.profile.showPartyQuestObjectives == false and poCalls == 1 and QuestBoardDB.party == false)
SlashCmdList.QUESTBOARD("party on")
check("party on: Questie's setting comes back", Questie.db.profile.showPartyQuestObjectives == true and QuestBoardDB.party == true)
check("party off: collect skips the party", #D.collect({ party = false }).party == 0)
Questie, mods.QuestiePartyObjectives = nil, nil
D.resetModules()

-- Item objectives: where to get them, not the turn-in.
check("objective name", D.objectiveName("Perfect Razormaw Egg: 8/12") == "Perfect Razormaw Egg"
  and D.objectiveName("8/12 Perfect Razormaw Egg") == "Perfect Razormaw Egg")
local realGetItem, realGetObject, realNearest2 = mods.QuestieDB.GetItem, mods.QuestieDB.GetObject, mods.DistanceUtils.GetNearestSpawn
mods.QuestieDB.GetItem = function(_, id) if id == 777 then return { name = "Perfect Razormaw Egg", objectDrops = { 55 } } end end
mods.QuestieDB.GetObject = function(_, id) if id == 55 then return { name = "Razormaw Nest", spawns = { x = 1 } } end end
mods.DistanceUtils.GetNearestSpawn = function() return { 60, 40 }, 11, 420 end
D.resetModules()
D.itemsByName = { ["Perfect Razormaw Egg"] = 777 }
local egg = { left = { { text = "8/12 Perfect Razormaw Egg", have = 8, need = 12 } } }
D.placeObjectiveItem(egg, {})
check("item objective: found by name, in a nest", egg.target == "Razormaw Nest" and egg.dist == 420 and egg.getHow == "object")
mods.QuestieDB.GetItem, mods.QuestieDB.GetObject, mods.DistanceUtils.GetNearestSpawn = realGetItem, realGetObject, realNearest2
D.itemsByName = nil
D.resetModules()

-- No known source: the place is where you last made progress.
local realPos = HBD.GetPlayerWorldPosition
HBD.GetPlayerWorldPosition = function() return 300, 400, 0 end
C_Map.GetBestMapForUnit = function() return 1437 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.3, 0.4 end } end
D.noteSpot(950)
HBD.GetPlayerWorldPosition = function() return 0, 0, 0 end
local spotQ = { id = 950, left = {} }
D.placeSpot(spotQ)
check("spot: distance to where you last got one", spotQ.dist == 500 and spotQ.spot.mapID == 1437 and spotQ.spot.x == 0.3)
D.finish(spotQ, 27)
check("spot: arrow and world place", spotQ.angle == 0.5 and spotQ.wx == 300)
HBD.GetPlayerWorldPosition = realPos
C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition = nil, nil
D.lastSpot[950] = nil

-- Next: the best XP per minute from here, not the biggest XP far away.
local nx, ne = ns.nextStep({ active = {}, nearby = {}, area = {},
  turnin = { { kind = "turnin", name = "Far", target = "A", xp = 2000, dist = 7000, rate = 120 },
    { kind = "turnin", name = "Near", target = "B", xp = 500, dist = 200, rate = 600 } },
  log = { { kind = "log", name = "L", xp = 1000, dist = 300, rate = 300, left = {} } } })
check("next: the near hand-in wins on XP per minute", ne and ne.name == "Near")

-- Sorting: near ones by distance, far ones (past MID_YARDS) by XP.
local sorted = D.sort({ { name = "a", dist = 3000, xp = 500 }, { name = "b", dist = 200, xp = 100 },
  { name = "c", xp = 2000 }, { name = "d", dist = 5000, xp = 1500 }, { name = "e", dist = 800, xp = 50 } }, "near")
local names = {}
for _, e in ipairs(sorted) do table.insert(names, e.name) end
check("sort: near by distance, then far by XP", table.concat(names) == "becda")

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
check("progress: a hand-in has a full green bar", turnBar.bar.shown and turnBar.fill.shown and ns.complete(turnBar.entry))
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
check("on a job: the board picks Doing", ns.tab() == "doing")
local restRow
for _, f in ipairs(frames) do if f.kind == "Button" and f.entry and f.shown and f.entry.tab == "log" then restRow = f end end
check("on a job: one line counts the rest of the log", restRow and restRow.entry.name == "1 more in your log: Log tab")
ns.click(restRow.entry)
check("tabs: that line opens the Log tab with every quest, each once", ns.tab() == "log" and countRows() == 3)
ns.pickTab("areas")
check("tabs: a click holds a tab", ns.tab() == "areas")
QuestBoardDB.doing = {}
D.heldAt = {}
ns.refresh()
for _ = 1, 50 do ns.step() end
check("tabs: when you stop the quest the board picks again", ns.tab() == "nearby")
local stNow = ns.state()
local areaSecs = ns.sections(stNow, "areas")
check("areas tab: zones ranked, then travel", areaSecs[1] and areaSecs[1].key == "zones" and #areaSecs[1].list >= 1 and areaSecs[1].list[1].kind == "zone")
local z1 = areaSecs[1].list[1]
check("areas tab: a zone row says what is there", D.zoneText(z1) ~= "" and #z1.stops >= 1 and ns.todo(z1) == D.zoneText(z1))
local logSecs = ns.sections(stNow, "log")
local logRows = 0
for _, sec in ipairs(logSecs) do check("log tab: one section per log zone, never cut", sec.key:find("^log:") and sec.cap == math.huge and sec.compact) logRows = logRows + #sec.list end
check("log tab: every quest in the log", logRows == #ns.logAll(stNow) and logRows == 3)
check("no place: a log quest with no distance says so", strip(ns.meta({ kind = "log", left = {} })) == "no place")
check("zones: far ones after the ones you can reach", (function()
  local zs = D.zones({ log = { { kind = "log", name = "a", header = "Near Zone", xp = 900, dist = 400, left = {} },
    { kind = "log", name = "b", header = "Far Zone", xp = 5000, left = {} } } })
  return #zs == 2 and not zs[1].far and zs[2].far
end)())
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
local cursor, cursorX = 500, 100
function GetCursorPosition() return cursorX, cursor end
local widths = {}
local realSetWidth = board.SetWidth
function board:SetWidth(w) widths[#widths + 1] = w end
ns.sizeStart()
check("size: the outline shows while you drag", board.outline and board.outline.shown)
cursor, cursorX = 400, 160
ns.sizeMove()
check("size: the outline names the size", board.outline.text.text == "330 x " .. QuestBoardDB.maxHeight)
ns.sizeStop()
check("size: dragging right widens the board", QuestBoardDB.width == 330 and widths[#widths] == 330 and not board.outline.shown)
ns.sizeStart()
cursorX = -1000
ns.sizeMove() ns.sizeStop()
check("size: not narrower than the minimum", QuestBoardDB.width == ns.MIN_W)
SlashCmdList.QUESTBOARD("width reset")
check("/qb width reset", QuestBoardDB.width == 270)
board.SetWidth = realSetWidth
cursor, cursorX = 500, 100
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
-- Stops (Spare1.lua): the Doing tab groups its quests by place.
;(function()
assert(loadfile(root .. "QuestBoard/Spare1.lua"))("QuestBoard", ns)
local function q(name, kind, wx, wy, dist, xp, more)
  local e = { name = name, kind = kind, wx = wx, wy = wy, inst = 0, dist = dist, xp = xp, level = 33, color = "yellow", left = {}, id = 0 }
  for k, v in pairs(more or {}) do e[k] = v end
  return e
end
local camp1 = q("Raptor Mastery", "turnin", 0, 100, 100, 1400, { target = "Hemet Nesingwary", pinned = true })
local camp2 = q("Tiger Mastery", "turnin", 10, 100, 100, 1300, { target = "Ajeck Rouack" })
local thorsen = q("Jungle Secrets", "pickup", 400, 0, 400, 1300, { target = "Private Thorsen", secs = 240 })
local bay1 = q("Supply and Demand", "turnin", 0, -2800, 2800, 1200, { target = "Drizzlik" })
local camp3 = q("Panther Mastery", "turnin", 5, 110, 100, 1300, { target = "Sir S. J. Erlgadin" })
local bay2 = q("Singing Blue Shards", "pickup", 60, -2850, 2800, 2800, { target = "Crank Fizzlebub", secs = 660 })
local crystal = q("Crystal in the Mountains", "log", -200, 0, 200, 280, { target = "Bloodscalp Warrior", left = { { text = "Pendant of Myzrael: 0/1" } } })
local other = q("Elsewhere", "turnin", 5, 100, 100, 500, { inst = 1 })
local stops = ns.stops({ camp1, camp2, thorsen, bay1, camp3, bay2, crystal, other })
check("stops: quests at one place make one stop, in list order",
  #stops == 5 and #stops[1].list == 3 and stops[1].list[3] == camp3 and #stops[2].list == 1 and #stops[3].list == 2 and stops[4].list[1] == crystal)
check("stops: another continent is another stop", stops[5].list[1] == other)
check("stops: a stop with hand-ins pays their XP, and takes the run there",
  stops[1].hand == 3 and stops[1].xp == 4000 and stops[1].dist == 100 and stops[1].secs == D.travelSecs(100) and not stops[1].guess)
check("stops: pick-ups do not count in a hand-in stop's XP", stops[3].hand == 1 and stops[3].pick == 1 and stops[3].xp == 1200)
check("stops: a pick-up stop shows the quest's XP and time as a guess", stops[2].xp == 1300 and stops[2].secs == 240 and stops[2].guess)
check("stops: what you do there", strip(ns.stopWhat(stops[1])) == "3 hand-ins" and strip(ns.stopWhat(stops[3])) == "1 hand-in, 1 pick-up"
  and strip(ns.stopWhat(stops[4])) == "1 to finish" and strip(ns.stopWhat(stops[2])) == "1 pick-up")
local realZoneName, realZoneText = D.zoneName, GetRealZoneText
D.zoneName = function(z) return z == 15 and "Dustwallow Marsh" or nil end
camp1.zone = 15
GetRealZoneText = function() return "Stranglethorn Vale" end
check("stops: a stop in another zone names it", strip(ns.stopWhat(stops[1])) == "3 hand-ins  Dustwallow Marsh")
GetRealZoneText = function() return "Dustwallow Marsh" end
check("stops: not when you are in that zone", strip(ns.stopWhat(stops[1])) == "3 hand-ins" and ns.zoneOf(camp1) == "Dustwallow Marsh")
D.zoneName, GetRealZoneText, camp1.zone = realZoneName, realZoneText, nil
check("stops: the head's numbers", ns.stopStats(stops[1]) == "17k xp/m  <1 min" and ns.stopStats(stops[2]) == "~325 xp/m  4 min" and ns.stopPlace(stops[3]) == "2.8k yd")
check("stops: ? to hand in, ! to pick up, a grey ? to finish",
  ns.stopMark(camp1) == "|cffffd100?|r" and ns.stopMark(thorsen) == "|cffffd100!|r" and ns.stopMark(crystal) == "|cff909090?|r")
check("stops: only a quest to finish has lines under it", #ns.stopLines(camp1) == 0 and #ns.stopLines(thorsen) == 0 and ns.stopLines(crystal)[1]:find("Pendant", 1, true) ~= nil)
check("stops: no gear, no gear mark", ns.gearMark(camp1) == "")
local noPlace = q("Lost", "log", nil, nil, nil, 100)
check("stops: a quest with no place is its own stop", #ns.stops({ noPlace, q("Lost too", "log", nil, nil, nil, 100) }) == 2 and ns.stopPlace(ns.stops({ noPlace })[1]) == "no place")
local moreRow = { kind = "more", group = "onway", name = "+2 more", left = {} }
local ss = ns.stopSections({ camp1, bay1 }, { camp2, moreRow })
check("stops: one section per stop, the +N more line last", #ss == 3 and ss[1].stop and #ss[1].list == 2 and ss[2].stop and ss[3].nohead and ss[3].list[1] == moreRow)
-- The rules: a hand-in close by comes first, and joins Doing by itself.
local work = q("Bloodscalp Ears", "log", 0, -200, 200, 2000, { left = { { text = "Ears: 3/15" } } })
local farHand = q("Far hand-in", "turnin", 0, 3000, 3000, 900)
local order = ns.stopSections({ work, thorsen }, {}, { camp1, camp2, bay1, farHand })
check("rules: a hand-in within 600 yd joins Doing; a far one does not",
  #order == 3 and order[1].list[1] == camp1 and order[1].list[2] == camp2)
check("rules: the hand-in stop comes before the quest you are on", order[1].stop.hand == 2 and order[2].list[1] == work and order[3].list[1] == thorsen)
local two = ns.stopSections({}, {}, { q("One", "turnin", 300, 0, 300, 1000), camp1, camp2 })
check("rules: two hand-ins in one place beat one", two[1].stop.hand == 2 and two[2].list[1].name == "One")
local joined = ns.stopSections({ bay2 }, {}, { bay1, farHand })
check("rules: a far hand-in joins a stop you go to anyway, hand-ins first in the stop",
  #joined == 1 and joined[1].list[1] == bay1 and joined[1].list[2] == bay2)
local saveRows = QuestBoardDB.rows.onway
QuestBoardDB.rows.onway = 1
local capped = ns.stopSections({}, { camp1, thorsen, camp2, q("Third", "pickup", 900, 900, 1200, 100) }, {})
QuestBoardDB.rows.onway = saveRows
check("rules: hand-ins do not count against the row limit",
  #capped == 3 and capped[1].stop.hand == 2 and capped[2].list[1] == thorsen and capped[3].list[1].kind == "more")
-- Trips (Spare2.lua): a flight when it beats the run, a flat guess for
-- another continent. You are at 0, 0.
assert(loadfile(root .. "QuestBoard/Spare2.lua"))("QuestBoard", ns)
D.flyNodeList = { { wx = 0, wy = 70, inst = 0, id = 1 }, { wx = 6000, wy = 0, inst = 0, id = 2 }, { wx = 0, wy = 0, inst = 1, id = 3 } }
local farQuest = q("Across the zone", "turnin", 6000, 140, 6000, 1000)
local flySecs = 70 / D.RUN_SPEED + 140 / D.RUN_SPEED + D.FLY_BOARD_SECS + math.sqrt(6000 * 6000 + 70 * 70) / D.FLY_SPEED
local got, how = D.travelSecs(6000, farQuest)
check("trips: a long way goes by flight", how == "fly" and math.abs(got - flySecs) < 0.01 and got < D.travelSecs(6000))
check("trips: a short way is a run", select(2, D.travelSecs(1000, q("Close", "turnin", 1000, 0, 1000, 100))) == nil)
check("trips: no flight when one flight master is nearest to both ends", D.flySecs(q("By the master", "turnin", 0, 1600, 1600, 100), D.RUN_SPEED) == nil)
check("trips: a flight far from the place loses to the run", select(2, D.travelSecs(2500, q("Middle", "turnin", 2500, 0, 2500, 100))) == nil)
check("trips: no flight to another continent's flight master", D.flySecs(q("Elsewhere", "turnin", 0, 3000, 3000, 100, { inst = 1 }), D.RUN_SPEED) == nil)
local flown = D.finish(q("Flown", "turnin", 6000, 140, 6000, 1000, { done = true, spot = { wx = 6000, wy = 140, inst = 0 } }), 33)
check("trips: the quest's time and XP per minute count the flight", flown.by == "fly" and math.abs(flown.secs - (flySecs + D.PICKUP_SECS)) < 0.01 and flown.rate > D.rate(1000, D.travelSecs(6000)))
local abroad = D.finish({ name = "Abroad", kind = "turnin", done = true, far = true, xp = 1000, level = 33, left = {}, id = 0 }, 33)
check("trips: another continent counts the boat, a guess", abroad.secs == D.FAR_TRIP_SECS + D.PICKUP_SECS and abroad.rate ~= nil and abroad.by == nil)
D.flyNodeList = nil
-- On the board: the Doing tab draws stops; /qb stops goes back to one list.
ns.refresh()
ns.pickTab("doing")
local doingSecs = ns.sections(ns.state(), "doing")
local stopHeads, stopRows = 0, 0
for _, f in ipairs(frames) do
  if f.kind == "Button" and f.stop and f.shown then stopHeads = stopHeads + 1 end
  if f.kind == "Button" and f.entry and f.shown and f.noArrow then stopRows = stopRows + 1 end
end
local nStops = 0
for _, sec in ipairs(doingSecs) do if sec.stop then nStops = nStops + 1 end end
check("stops: the Doing tab has no Doing or On the way group", nStops > 0 and doingSecs[1].stop ~= nil)
check("stops: the board draws a head per stop and marks its rows", stopHeads == nStops and stopRows > 0)
SlashCmdList.QUESTBOARD("stops")
check("/qb stops: back to one list", QuestBoardDB.stops == false and not ns.sections(ns.state(), "doing")[1].stop)
SlashCmdList.QUESTBOARD("stops")
check("/qb stops again: stops", QuestBoardDB.stops == true and ns.sections(ns.state(), "doing")[1].stop ~= nil)
ns.pickTab("nearby")
end)()

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
check("a failing Questie call is skipped", #rough.log == 2);

-- The "..." menu: every option without a /qb command.
(function()
  check("menu: a button right of the tabs", QuestBoardFrame.menuBtn ~= nil)
  QuestBoardFrame.menuBtn.scripts.OnClick()
  local m = QuestBoardMenu
  check("menu: opens with the options", m and m.shown and #m.buttons >= 8)
  local dun
  for _, b in ipairs(m.buttons) do if b.text.text == "Show dungeon and raid quests" then dun = b end end
  local before = QuestBoardDB.dungeons ~= false
  dun.scripts.OnClick(dun)
  check("menu: a click runs the option and closes the menu", (QuestBoardDB.dungeons ~= false) ~= before and not m.shown)
  SlashCmdList.QUESTBOARD(before and "dungeons on" or "dungeons off")
end)()

-- XP as a share of the level, so the player need not work it out.
UnitXPMax = function() return 50000 end
check("percent: a quest's XP", D.xpText(600) == "1.2%" and D.xpText(10) == "<0.1%" and D.xpText(6000) == "12%")
check("percent: XP per minute", D.rateText(250) == "30%/h" and D.rateText(10) == "1.2%/h" and D.rateText(0) == "0%/h")
check("percent: a row shows it", strip(ns.stats({ kind = "pickup", xp = 600, secs = 180 })) == "~24%/h  3 min")
UnitXPMax = nil
check("percent: raw XP when the game gives no level size", D.xpText(625) == "625 xp" and D.rateText(250) == "250 xp/m")

-- Red quests (Spare4.lua): 0 XP per minute, and the safe ones can be dropped.
assert(loadfile(root .. "QuestBoard/Spare4.lua"))("QuestBoard", ns);
(function()
  local red = D.finish({ kind = "log", id = 7001, name = "Too High", level = 40, xp = 3000, left = {}, objectives = 1 }, 30)
  check("red: 0 XP per minute", red.red and red.rate == 0)
  local doneRed = D.finish({ kind = "turnin", id = 7002, name = "Done High", level = 40, xp = 3000, done = true }, 30)
  check("red: a hand-in still counts", not doneRed.red and doneRed.rate and doneRed.rate > 0)
  check("red: row says 0 xp/m", strip(ns.stats(red)) == "0 xp/m, red")
  local realGet = mods.QuestieDB.GetQuest
  mods.QuestieDB.GetQuest = function(id)
    if id == 7001 then return { Starts = { NPC = { 5 } } } end
    if id == 7003 then return { Starts = { Item = { 9 } } } end
  end
  check("red: safe when an NPC gives it and no progress", D.safeToAbandon(red))
  red.frac = 0.5
  check("red: not safe with progress", not D.safeToAbandon(red))
  red.frac = nil
  local itemRed = { kind = "log", id = 7003, red = true, name = "From an item", level = 40 }
  local ok, why = D.safeToAbandon(itemRed)
  check("red: not safe when an item starts it", not ok and why:find("item", 1, true))
  local shown, popups, dropped = {}, {}, {}
  StaticPopupDialogs = {}
  StaticPopup_Show = function(name, a1, a2, data) table.insert(popups, { name = name, data = data }) end
  local realQL = { C_QuestLog.SetSelectedQuest, C_QuestLog.SetAbandonQuest, C_QuestLog.AbandonQuest }
  local sel
  C_QuestLog.SetSelectedQuest = function(id) sel = id end
  C_QuestLog.SetAbandonQuest = function() end
  C_QuestLog.AbandonQuest = function() table.insert(dropped, sel) end
  local realState = ns.state
  ns.state = function() return { log = { red, itemRed }, active = {}, nearby = {} } end
  ns.abandonRed()
  check("abandon: asks first, drops nothing yet", #popups == 1 and popups[1].data == red and #dropped == 0)
  StaticPopupDialogs.QUESTBOARD_ABANDON.OnAccept(nil, popups[1].data)
  check("abandon: Abandon drops that quest only", #dropped == 1 and dropped[1] == 7001)
  ns.state = realState
  C_QuestLog.SetSelectedQuest, C_QuestLog.SetAbandonQuest, C_QuestLog.AbandonQuest = realQL[1], realQL[2], realQL[3]
  StaticPopup_Show, StaticPopupDialogs = nil, nil
  mods.QuestieDB.GetQuest = realGet
end)()

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
print("all passed")
