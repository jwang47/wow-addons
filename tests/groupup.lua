-- Offline tests for GroupUp with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/groupup.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/groupup%.lua$") or ""
local failures, chat = 0, {}
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end
local function near(a, b) return a and math.abs(a - b) < 0.01 end

local function widget(name)
  local w = { scripts = {}, shown = false, name = name }
  function w:SetScript(what, fn) self.scripts[what] = fn end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:IsShown() return self.shown end
  function w:SetText(t) self.text = t end
  function w:RegisterEvent(e) self.events = self.events or {} self.events[e] = true end
  function w:CreateTexture() return widget() end
  function w:CreateFontString() return widget() end
  function w:GetPoint() return "CENTER", nil, nil, 0, 120 end
  return setmetatable(w, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end
function CreateFrame(kind, name)
  local f = widget(name)
  if name then _G[name] = f end
  return f
end
UIParent = widget("UIParent")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, strip(m)) end }
SlashCmdList = {}

local P = { level = 27, xp = 1000, max = 20000, t = 100, party = {} }
function UnitLevel(u)
  if u == "player" then return P.level end
  local i = tonumber(u:match("party(%d)"))
  return i and P.party[i] and P.party[i].level
end
function UnitName(u)
  if u == "player" then return "Ded" end
  local i = tonumber(u:match("party(%d)"))
  return i and P.party[i] and P.party[i].name
end
function UnitExists(u) return UnitName(u) ~= nil end
function GetRealmName() return "Forever" end
function UnitXP() return P.xp end
function UnitXPMax() return P.max end
function GetTime() return P.t end
function GetNumGroupMembers() return #P.party > 0 and #P.party + 1 or 0 end
function IsInRaid() return false end

-- Quest log: a header, an elite quest, a kill quest shared with party1, a
-- drop quest, a talk quest and a finished one.
local LOG = {
  { title = "Redridge Mountains", isHeader = true },
  { title = "Blackrock Champions", questID = 20, level = 28, suggestedGroup = 3 },
  { title = "Redridge Goulash", questID = 92, level = 25 },
  { title = "Wanted: Lieutenant Fangore", questID = 180, level = 26 },
  { title = "Underbelly Scales", questID = 122, level = 26 },
  { title = "A Letter", questID = 7, level = 25 },
  { title = "Murloc Poachers", questID = 127, level = 22 },
}
local OBJ = {
  [20] = { { text = "Blackrock Champion slain: 0/15", type = "monster", finished = false } },
  [92] = { { text = "Tarantula Silk: 2/6", type = "item", finished = false } },
  [180] = { { text = "Shadowhide Gnoll slain: 3/10", type = "monster", finished = false } },
  [122] = { { text = "Underbelly Whelp Scale: 3/6", type = "item", finished = false },
    { text = "Whelp slain: 4/4", type = "monster", finished = true } },
  [7] = { { text = "Talk to Marshal", type = "event", finished = false } },
  [127] = { { text = "Spotted Sunfin Fin: 8/8", type = "item", finished = true } },
}
C_QuestLog = {
  GetNumQuestLogEntries = function() return #LOG end,
  GetInfo = function(i) return LOG[i] end,
  ReadyForTurnIn = function(id) return id == 127 end,
  GetQuestObjectives = function(id) return OBJ[id] end,
  IsUnitOnQuest = function(u, id) return u == "party1" and id == 180 end,
}
function GetQuestTagInfo(id) if id == 20 then return 1, "Elite" end end

local ns = {}
assert(loadfile(root .. "GroupUp/Logic.lua"))("GroupUp", ns)
assert(loadfile(root .. "GroupUp/GroupUp.lua"))("GroupUp", ns)
local M = ns.logic
local fire = ns.events.scripts.OnEvent
fire(ns.events, "ADDON_LOADED", "GroupUp")
fire(ns.events, "PLAYER_ENTERING_WORLD")

-- Split math
check("solo share is 1", M.share(27, { 27 }) == 1)
check("duo share is 50%", near(M.share(27, { 27, 27 }), 0.5))
check("trio share is 1.166/3", near(M.share(27, { 27, 27, 27 }), 1.166 / 3))
check("five share is 28%", near(M.share(27, { 27, 27, 27, 27, 27 }), 0.28))
check("share goes by level", near(M.share(20, { 20, 30 }), 0.4))
check("grey level 27 is 20", M.greyLevel(27) == 20)
check("a level 35 member greys level 27 mobs", M.highMemberGreys(27, { 27, 35 }) == true)
check("a level 30 member does not", M.highMemberGreys(27, { 27, 30 }) == false)

-- Kill messages
local xp, rested = M.parseKill("Kobold Miner dies, you gain 300 experience. (+150 exp Rested bonus)")
check("kill message xp", xp == 300 and rested == 150)
xp, rested = M.parseKill("Gnoll dies, you gain 120 experience. (+12 exp group bonus)")
check("group kill message", xp == 120 and rested == 0)
check("other XP message is not a kill", M.parseKill("You gain 500 experience.") == nil)
check("secret message is not a kill", M.parseKill(nil) == nil)

-- Solo play: 10 minutes, 10 kills of 300 XP (150 rested), one quest of 1500.
for i = 1, 10 do
  P.t = P.t + 60
  P.xp = P.xp + 300
  fire(ns.events, "CHAT_MSG_COMBAT_XP_GAIN", "Kobold dies, you gain 300 experience. (+150 exp Rested bonus)")
  fire(ns.events, "PLAYER_XP_UPDATE", "player")
end
P.xp = P.xp + 1500
fire(ns.events, "QUEST_TURNED_IN", 60, 1500, 0)
fire(ns.events, "PLAYER_XP_UPDATE", "player")
local r = ns.rates()
check("solo time 10 min", r.solo.secs == 600)
check("solo xp counted", r.solo.xp == 4500 and r.solo.quest == 1500 and r.solo.kills == 10)
-- (4500 - 1500 rested) over 10 min = 18000/h
check("solo XP/h without rested", near(M.perHour(r.solo), 18000))
check("solo XP a kill without rested", near(M.perKill(r.solo), 150))
check("no grouped data yet", r.grouped.secs == 0 and M.perHour(r.grouped) == nil)

-- A break longer than BREAK_SECS is not counted.
P.t = P.t + 3600
P.xp = P.xp + 300
fire(ns.events, "PLAYER_XP_UPDATE", "player")
check("a long break is not counted", ns.rates().solo.secs == 600)

-- Join a duo: the time before the roster change stays solo.
P.t = P.t + 30
P.party = { { name = "Ann", level = 27 } }
fire(ns.events, "GROUP_ROSTER_UPDATE")
check("time before joining is solo", ns.rates().solo.secs == 630)
for i = 1, 6 do
  P.t = P.t + 60
  P.xp = P.xp + 160
  fire(ns.events, "CHAT_MSG_COMBAT_XP_GAIN", "Gnoll dies, you gain 160 experience.")
  fire(ns.events, "PLAYER_XP_UPDATE", "player")
end
r = ns.rates()
check("duo time 6 min", r.size[2].secs == 360 and r.grouped.secs == 360)
check("duo XP/h", near(M.perHour(r.grouped), 9600))

-- Level up across the XP bar
local st = { xp = 19900, max = 20000 }
check("xp delta across a level-up", M.xpDelta(st, 100, 21000) == 200)

-- Quests
local qs = M.quests(ns.units())
local byId = {}
for _, q in ipairs(qs) do byId[q.id] = q end
check("headers skipped", #qs == 6)
check("elite quest needs a group", byId[20].verdict == "need" and byId[20].tag == "Elite")
check("kill quest goes faster", byId[180].verdict == "faster")
check("kill quest shared with Ann", byId[180].shared[1] == "Ann")
check("drop quest is maybe", byId[92].verdict == "maybe")
check("finished kill objective does not count", byId[122].verdict == "maybe")
check("talk quest is same", byId[7].verdict == "same")
check("done quest", byId[127].verdict == "done")
check("need first, then faster", qs[1].id == 20 and qs[2].id == 180)
local c = M.count(qs)
check("counts", c.need == 1 and c.faster == 1 and c.maybe == 2 and c.shared == 1)

-- Lean
check("leans group with an elite and a kill quest", (M.lean(c, nil, nil)) == "group")
check("leans solo with only drops and faster solo",
  (M.lean({ need = 0, faster = 0, maybe = 2, same = 0, done = 0, shared = 0 }, 18000, 9000)) == "solo")
check("even with nothing", (M.lean({ need = 0, faster = 0, maybe = 0, same = 0, done = 0, shared = 0 }, nil, nil)) == "even")
check("grouped faster adds a reason", select(2, M.lean({ need = 0, faster = 0, maybe = 0, same = 0, done = 0, shared = 0 }, 9000, 12000))[1] == "grouped XP/h is higher")

-- Panel rows
local rows = ns.rows()
local all = {}
for _, row in ipairs(rows) do table.insert(all, row.left .. " | " .. row.right) end
local text = table.concat(all, "\n")

check("panel weighs solo XP/h against the quests", rows[1].left == "About even")
check("panel has solo rate", text:find("Solo  19k/h", 1, true) ~= nil)
check("panel has duo row", text:find("Duo  9.6k/h", 1, true) ~= nil)
check("panel has this group split", text:find("This group: you get 50%", 1, true) ~= nil)
check("panel lists the elite quest", text:find("[Elite] Blackrock Champions", 1, true) ~= nil)
check("panel shows who shares", text:find("+Ann", 1, true) ~= nil)
check("panel leaves out done quests", text:find("Murloc Poachers", 1, true) == nil)

-- Solo panel shows the share table
P.party = {}
fire(ns.events, "GROUP_ROSTER_UPDATE")
text = ""
for _, row in ipairs(ns.rows()) do text = text .. row.left .. " | " .. row.right .. "\n" end
check("solo panel shows shares", text:find("2: 50%   3: 39%   4: 33%   5: 28%", 1, true) ~= nil)

-- Invite summary
chat = {}
fire(ns.events, "PARTY_INVITE_REQUEST", "Bob")
check("invite prints two lines", #chat == 2 and chat[1]:find("Bob invites you", 1, true) ~= nil)
check("invite line has quest counts", chat[1]:find("1 need a group", 1, true) ~= nil)
check("invite line has rates", chat[2]:find("solo 19k/h", 1, true) ~= nil)
SlashCmdList.GROUPUP("invite off")
chat = {}
fire(ns.events, "PARTY_INVITE_REQUEST", "Bob")
check("invite summary can be turned off", #chat == 0)

-- Slash
SlashCmdList.GROUPUP("")
check("/gu shows the panel", GroupUpFrame.shown == true and GroupUpDB.shown == true)
SlashCmdList.GROUPUP("")
check("/gu again hides it", GroupUpFrame.shown == false)
SlashCmdList.GROUPUP("clear")
check("/gu clear forgets the data", ns.rates().solo.secs == 0)

-- Thanks and leave
local sent, left = {}, 0
function SendChatMessage(t, chan) table.insert(sent, { t, chan }) end
local pendingTimers = {}
C_Timer = { After = function(_, f) table.insert(pendingTimers, f) end }
C_PartyInfo = { LeaveParty = function() left = left + 1 P.party = {} end }
P.party = { { name = "Ann", level = 27 } }
fire(ns.events, "GROUP_ROSTER_UPDATE")
for _, f in ipairs(pendingTimers) do f() end
pendingTimers = {}
check("button shows in a group", GroupUpByeButton and GroupUpByeButton.shown and GroupUpByeButton.text == "Thanks & leave")
GroupUpByeButton.scripts.OnClick()
check("thanks said in party chat", sent[1] and sent[1][1] == "Thanks for the group!" and sent[1][2] == "PARTY")
check("not left yet", left == 0 and GroupUpByeButton.text == "Stay in group")
GroupUpByeButton.scripts.OnClick()
for _, f in ipairs(pendingTimers) do f() end
pendingTimers = {}
check("second press cancels the leave", left == 0 and ns.bye == nil)
SlashCmdList.GROUPUP("bye text Thanks all, good luck!")
SlashCmdList.GROUPUP("bye delay 8")
check("bye text keeps its case", GroupUpDB.byeText == "Thanks all, good luck!" and GroupUpDB.byeDelay == 8)
sent = {}
SlashCmdList.GROUPUP("bye")
check("custom thanks said", sent[1] and sent[1][1] == "Thanks all, good luck!")
for _, f in ipairs(pendingTimers) do f() end
pendingTimers = {}
check("leaves after the delay", left == 1)
check("button hides when solo", GroupUpByeButton.shown == false)
chat = {}
SlashCmdList.GROUPUP("bye")
check("bye when solo says so", chat[1] == "GroupUp: you are not in a group" and #sent == 1)
SlashCmdList.GROUPUP("button off")
P.party = { { name = "Ann", level = 27 } }
ns.updateButton()
check("button off hides it in a group", GroupUpByeButton.shown == false)
P.party = {}

-- Secret values count as unknown
issecretvalue = function(v) return v == 777 end
check("secret level is unknown", M.plain(777) == nil)
issecretvalue = nil

-- The .toc lists every file, and the version has a changelog section.
local toc = io.open(root .. "GroupUp/GroupUp.toc"):read("*a")
check("toc lists Logic.lua and GroupUp.lua", toc:find("Logic.lua", 1, true) and toc:find("GroupUp.lua", 1, true))
local ver = toc:match("## Version: ([%d%.]+)")
check("toc version matches ns.VERSION", ver == ns.VERSION)

if failures > 0 then print(failures .. " failed") os.exit(1) end
print("all passed")
