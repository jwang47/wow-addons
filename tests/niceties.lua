-- Offline tests for Niceties with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/niceties.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/niceties%.lua$") or ""
local failures = 0
local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end

local said = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end }
-- Each frame keeps its own handler; onEvent is the first one (Niceties.lua).
local onEvent
local handlers = {}
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function(_, _, fn)
    handlers[#handlers + 1] = fn
    onEvent = onEvent or fn
  end }
end
local function fire(event, ...) for _, h in ipairs(handlers) do h(nil, event, ...) end end
local combat = false
function InCombatLockdown() return combat end
function time() return 1000 end
SlashCmdList = {}

-- A CVar store. mode "clamp": values above cap are stored as cap.
-- mode "refuse": values above cap leave the old value.
local CV = { value = "1", cap = 2.6, mode = "clamp" }
local taintLog = "0"
C_CVar = {
  GetCVar = function(name)
    if name == "taintLog" then return taintLog end
    assert(name == "cameraDistanceMaxZoomFactor") return CV.value
  end,
  SetCVar = function(name, v)
    if name == "taintLog" then taintLog = tostring(v) return true end
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

-- Blocked actions: an event before login waits, then is recorded.
NicetiesDB = nil
taintLog = "0"
fire("ADDON_ACTION_BLOCKED", "Early", "CastSpellByName()")
check("early event waits for login", NicetiesDB == nil or NicetiesDB.data.blocked == nil
  or NicetiesDB.data.blocked.log == nil)
fire("PLAYER_LOGIN")
onEvent()
local blog = NicetiesDB.data.blocked.log
check("early event recorded at login", blog and #blog == 1 and blog[1].addon == "Early")
check("taint log on", taintLog == "1" and NicetiesDB.data.blocked.taintBefore == "0")

said = {}
combat = true
fire("ADDON_ACTION_BLOCKED", "Glance", "PlayerFrame:SetParent()")
check("names the addon in chat", said[#said] and said[#said]:find("Glance", 1, true) ~= nil
  and said[#said]:find("in combat", 1, true) ~= nil)
local n = #said
fire("ADDON_ACTION_BLOCKED", "Glance", "PlayerFrame:SetParent()")
check("says it once, counts repeats", #said == n and blog[#blog].count == 2)
fire("ADDON_ACTION_FORBIDDEN", "Other", "UNKNOWN()")
check("forbidden recorded", blog[#blog].kind == "forbidden" and #blog == 3)
combat = false
for i = 1, 30 do fire("ADDON_ACTION_BLOCKED", "Spam" .. i, "x()") end
check("keeps the last 20", #blog == 20 and blog[20].addon == "Spam30")

said = {}
SlashCmdList.NICETIES("blocked")
check("/nice blocked lists, stays on", NicetiesDB.on.blocked == nil and #said == 21
  and said[21]:find("Spam30", 1, true) ~= nil)
SlashCmdList.NICETIES("blocked off")
check("off restores the taint log", taintLog == "0" and NicetiesDB.on.blocked == false)
local before = #blog
fire("ADDON_ACTION_BLOCKED", "Late", "y()")
check("off records nothing", #blog == before)
SlashCmdList.NICETIES("blocked on")
check("on again", taintLog == "1")

if failures > 0 then print(failures .. " failed") os.exit(1) end
print("all ok")
