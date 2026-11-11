-- Blocked actions: name the addon behind "Interface action failed because
-- of an AddOn". The game fires ADDON_ACTION_BLOCKED (and _FORBIDDEN) with
-- the addon's name and the call it refused, but prints only that line.
-- This feature says which addon it was, keeps the last few in NicetiesDB,
-- and turns on the game's taint log (Logs\taint.log) for the full story.
-- (In Spare1.lua so that it loads with /reload; rename it in a release.)
local _, ns = ...

local KEEP = 20
local CVAR = "taintLog"

local pending = {}  -- events before the saved variables load
local ready = false
local told = {}     -- "addon fn" -> true once said this session

local function getCVar(name)
  local fn = C_CVar and C_CVar.GetCVar or GetCVar
  if not fn then return nil end
  local ok, v = pcall(fn, name)
  if ok then return v end
end
local function setCVar(name, v)
  local fn = C_CVar and C_CVar.SetCVar or SetCVar
  if fn then pcall(fn, name, tostring(v)) end
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function record(entry)
  local data = ns.Data("blocked")
  data.log = data.log or {}
  local log = data.log
  local last = log[#log]
  if last and last.addon == entry.addon and last.fn == entry.fn and last.kind == entry.kind then
    last.count = (last.count or 1) + 1
    last.time = entry.time
    last.combat = last.combat or entry.combat
  else
    log[#log + 1] = entry
    while #log > KEEP do table.remove(log, 1) end
  end
  local key = entry.addon .. " " .. entry.fn
  if not told[key] then
    told[key] = true
    ns.say(("|cffff6060%s|r was %s: %s%s (/nice blocked shows the list)"):format(
      entry.addon, entry.kind, entry.fn, entry.combat and ", in combat" or ""))
  end
end

local function onBlocked(kind, addon, fn)
  local entry = {
    kind = kind,
    addon = tostring(addon or "?"),
    fn = tostring(fn or "?"),
    combat = inCombat(),
    time = time and time() or 0,
    zone = GetRealZoneText and GetRealZoneText() or nil,
  }
  if not ready then pending[#pending + 1] = entry return end
  if ns.IsOn("blocked") then record(entry) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, addon, fn)
  if event == "PLAYER_LOGIN" then
    ready = true
    local list = pending
    pending = {}
    if ns.IsOn("blocked") then
      for _, e in ipairs(list) do record(e) end
    end
  elseif event == "ADDON_ACTION_BLOCKED" then
    onBlocked("blocked", addon, fn)
  else
    onBlocked("forbidden", addon, fn)
  end
end)
ns.OnBlocked = onBlocked

local function show(data)
  local log = data.log or {}
  if #log == 0 then ns.say("no blocked actions recorded") return end
  ns.say("last blocked actions (newest last):")
  for _, e in ipairs(log) do
    DEFAULT_CHAT_FRAME:AddMessage(("  %s  %s %s: %s%s%s"):format(
      date and date("%m-%d %H:%M", e.time) or tostring(e.time), e.addon, e.kind, e.fn,
      e.combat and ", in combat" or "", (e.count or 1) > 1 and (" x" .. e.count) or ""))
  end
end
ns.ShowBlocked = function() show(ns.Data("blocked")) end

ns.Add({
  key = "blocked",
  show = show,
  name = "Blocked-action report",
  help = "say which addon caused \"Interface action failed\"; also writes Logs\\taint.log",
  apply = function(on, data)
    if on then
      if data.taintBefore == nil then data.taintBefore = getCVar(CVAR) or "0" end
      if tostring(getCVar(CVAR) or "0") == "0" then setCVar(CVAR, 1) end
      return nil
    end
    setCVar(CVAR, data.taintBefore or "0")
    data.taintBefore = nil
  end,
  status = function(data)
    local n = data.log and #data.log or 0
    if n == 0 then return "none recorded" end
    local e = data.log[n]
    return ("%d recorded, last: %s %s"):format(n, e.addon, e.fn)
  end,
})
