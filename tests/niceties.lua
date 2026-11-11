-- Offline tests for Niceties with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/niceties.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/niceties%.lua$") or ""
local failures = 0
local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end

local said = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end }
local onEvent
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function(_, _, fn) onEvent = fn end }
end
SlashCmdList = {}

-- The game's addon profiler, with counters the test sets per addon.
local PROF = {
  Questie = { [1] = 0.8, [0] = 0.5, [4] = 120, [8] = 2, [10] = 0, [6] = 40 },
  UpgradeFinder = { [1] = 0.1, [0] = 0.1, [4] = 3, [8] = 0, [10] = 0, [6] = 1 },
}
local LOADED = { "Questie", "UpgradeFinder", "Niceties" }
C_AddOnProfiler = {
  IsEnabled = function() return true end,
  GetAddOnMetric = function(a, m) return (PROF[a] or {})[m] or 0 end,
  GetOverallMetric = function() return 1 end,
  GetApplicationMetric = function() return 8 end,
}
C_AddOns = {
  GetNumAddOns = function() return #LOADED end,
  GetAddOnInfo = function(i) return LOADED[i] end,
  IsAddOnLoaded = function() return true end,
}
local T = 1794350000
function time() return T end
function GetTime() return T end
function GetRealZoneText() return "Stranglethorn Vale" end
function InCombatLockdown() return false end
local tickers = 0
C_Timer = { NewTicker = function() tickers = tickers + 1 return { Cancel = function() tickers = tickers - 1 end } end }

-- A CVar store. mode "clamp": values above cap are stored as cap.
-- mode "refuse": values above cap leave the old value.
local CV = { value = "1", cap = 2.6, mode = "clamp" }
C_CVar = {
  GetCVar = function(name) assert(name == "cameraDistanceMaxZoomFactor") return CV.value end,
  SetCVar = function(_, v)
    v = tonumber(v)
    if v > CV.cap then
      if CV.mode == "refuse" then return false end
      v = CV.cap
    end
    CV.value = tostring(v)
    return true
  end,
  GetCVarDefault = function() return "1" end,
}

-- Load the addon in .toc order, as the client does.
local ns = {}
local toc = {}
for line in io.lines(root .. "Niceties/Niceties.toc") do
  if line:match("%.lua$") then toc[#toc + 1] = line end
end
for _, file in ipairs(toc) do assert(loadfile(root .. "Niceties/" .. file))("Niceties", ns) end
check("toc lists spare files", #toc >= 5 and toc[#toc]:match("^Spare%d%.lua$") ~= nil)
check("global table", Niceties == ns and ns.features.zoom ~= nil)

-- First login: zoom is on by default and goes to the cap.
NicetiesDB = nil
onEvent()
check("login raises to the clamped cap", tonumber(CV.value) == 2.6)
check("keeps the old value", NicetiesDB.data.zoom.before == 1)

-- Off puts the player's value back; on raises it again.
SlashCmdList.NICETIES("zoom")
check("toggle off restores", tonumber(CV.value) == 1 and NicetiesDB.on.zoom == false)
check("says off", said[#said]:find("off", 1, true) ~= nil)
onEvent()
check("off stays off at login", tonumber(CV.value) == 1)
SlashCmdList.NICETIES("zoom on")
check("on again", tonumber(CV.value) == 2.6 and NicetiesDB.on.zoom == true)

-- A client that refuses values above its cap.
CV.value, CV.cap, CV.mode = "1.5", 3.4, "refuse"
NicetiesDB = nil
onEvent()
check("refusing client: finds 3.4", tonumber(CV.value) == 3.4)
SlashCmdList.NICETIES("zoom off")
check("refusing client: restores 1.5", tonumber(CV.value) == 1.5)

-- A client that keeps anything: takes the highest try.
CV.value, CV.cap, CV.mode = "1", 99, "clamp"
NicetiesDB = nil
onEvent()
check("open client: 4.0", tonumber(CV.value) == 4.0)

-- Already above every try: left alone.
CV.value = "5"
NicetiesDB = nil
onEvent()
check("higher value kept", tonumber(CV.value) == 5)

-- The list and unknown words do not error.
said = {}
SlashCmdList.NICETIES("")
check("list names zoom", #said >= 2 and said[2]:find("zoom", 1, true) ~= nil)
SlashCmdList.NICETIES("nonsense")

-- CPU tracker -------------------------------------------------------------
local cpu = ns.cpu
check("cpu feature", ns.features.cpu ~= nil and cpu ~= nil)
check("cpu ticker started once", tickers == 1)
onEvent()
check("no second ticker on a loading screen", tickers == 1)
local data = ns.Data("cpu")
cpu.tick(data, T)
-- First read: the peak and slow frames from loading are one loading spike.
check("loading spike", #data.spikes == 1 and data.spikes[1].a == "Questie" and data.spikes[1].n == 2
  and data.spikes[1].peak == 120 and data.spikes[1].loading == true)
-- Later, out of the loading window: two new slow frames for UpgradeFinder.
T = T + 30
TradeSkillFrame = { IsShown = function() return true end }
PROF.UpgradeFinder[8] = 2
PROF.UpgradeFinder[4] = 300
PROF.UpgradeFinder[10] = 1
cpu.tick(data, T)
local s = data.spikes[#data.spikes]
check("spike names the addon", #data.spikes == 2 and s.a == "UpgradeFinder" and s.n == 2 and s.peak == 300 and s.huge == 1)
check("spike context", s.open == "profession" and s.zone == "Stranglethorn Vale" and not s.loading)
check("spike line", cpu.spikeLine(s):find("UpgradeFinder", 1, true) and cpu.spikeLine(s):find("profession", 1, true))
-- Nothing new: no spike.
T = T + 1
cpu.tick(data, T)
check("quiet tick adds nothing", #data.spikes == 2)
-- Counters restart (a /reload): the new count is new slow frames.
PROF.Questie[8] = 1
T = T + 1
cpu.tick(data, T)
check("restart counts", #data.spikes == 3 and data.spikes[3].a == "Questie" and data.spikes[3].n == 1)
-- A new minute writes the last one.
T = T + 120
cpu.tick(data, T)
check("minute saved", data.minutes and #data.minutes >= 1 and data.minutes[#data.minutes].top[1] ~= nil)
check("minute percent", data.minutes[#data.minutes].pct == 13)
local worst = cpu.offenders(data)
check("worst: UpgradeFinder first (loading frames count last)", worst[1].a == "UpgradeFinder" and worst[1].n == 2)
local snap = cpu.snapshot()
check("snapshot busiest first", snap[1].a == "Questie" and snap[1].pct == 10)
-- The history keeps its cap.
local keep = cpu.KEEP_SPIKES
cpu.KEEP_SPIKES = 3
for i = 1, 5 do PROF.Questie[8] = PROF.Questie[8] + 1 T = T + 1 cpu.tick(data, T) end
check("spike cap", #data.spikes == 3 and data.spikes[3].t == T)
cpu.KEEP_SPIKES = keep
-- Commands print and do not error.
said = {}
for _, c in ipairs({ "top", "spikes", "worst", "worst 2", "history", "help" }) do SlashCmdList.NICETIESCPU(c) end
check("commands print", #said > 10)
SlashCmdList.NICETIESCPU("reset")
check("reset", #data.spikes == 0 and #data.minutes == 0)
SlashCmdList.NICETIES("cpu off")
check("off stops the ticker", tickers == 0 and NicetiesDB.on.cpu == false)
-- No profiler: says so, no error.
local P = C_AddOnProfiler
C_AddOnProfiler = nil
SlashCmdList.NICETIES("cpu on")
check("no profiler: no ticker", tickers == 0 and said[#said]:find("profiler", 1, true) ~= nil)
C_AddOnProfiler = P

if failures > 0 then print(failures .. " failed") os.exit(1) end
print("all ok")
