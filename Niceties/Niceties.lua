-- Niceties: a home for small nice-to-haves. Each feature is one file that
-- calls ns.Add; this file keeps the on/off state and the /nice command.
local ADDON, ns = ...
Niceties = ns

ns.features, ns.order = {}, {}

function ns.say(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffNiceties:|r " .. msg)
end

-- f = { key, name, help, default (true when nil), apply(on, data, why),
-- status(data), show(data) }. With show, "/nice KEY" alone calls show
-- instead of toggling; "/nice KEY on|off" still sets it.
-- apply(true, ...) runs at each login and when the player turns it on;
-- apply(false, ...) runs only when the player turns it off. data is the
-- feature's own saved table. why is "login" or "toggle".
function ns.Add(f)
  assert(f.key and f.apply, "Niceties: a feature needs key and apply")
  if f.default == nil then f.default = true end
  ns.features[f.key] = f
  ns.order[#ns.order + 1] = f.key
end

local function db()
  NicetiesDB = NicetiesDB or {}
  NicetiesDB.on = NicetiesDB.on or {}
  NicetiesDB.data = NicetiesDB.data or {}
  return NicetiesDB
end

function ns.IsOn(key)
  local f, d = ns.features[key], db()
  if d.on[key] == nil then return f.default end
  return d.on[key]
end

function ns.Data(key)
  local d = db()
  d.data[key] = d.data[key] or {}
  return d.data[key]
end

local function run(f, on, why)
  local ok, msg = pcall(f.apply, on, ns.Data(f.key), why)
  if not ok then ns.say(f.name .. " failed: " .. tostring(msg)) return end
  return msg
end

function ns.Set(key, on)
  local f = ns.features[key]
  db().on[key] = on
  local msg = run(f, on, "toggle")
  ns.say(f.name .. ": " .. (on and "on" or "off") .. (msg and (" (" .. msg .. ")") or ""))
end

function ns.ApplyAll(why)
  for _, key in ipairs(ns.order) do
    if ns.IsOn(key) then run(ns.features[key], true, why) end
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function() ns.ApplyAll("login") end)

local function list()
  ns.say("/nice KEY toggles a feature (or /nice KEY on|off):")
  for _, key in ipairs(ns.order) do
    local f = ns.features[key]
    local state = ns.IsOn(key) and "|cff40ff40on|r" or "|cffff6060off|r"
    local extra = f.status and f.status(ns.Data(key)) or nil
    DEFAULT_CHAT_FRAME:AddMessage(("  %s  %s: %s%s"):format(key, f.name, state, extra and (", " .. extra) or "")
      .. (f.help and ("|cff999999 - " .. f.help .. "|r") or ""))
  end
end
ns.List = list

SLASH_NICETIES1, SLASH_NICETIES2 = "/nice", "/niceties"
SlashCmdList.NICETIES = function(text)
  local key, arg = (text or ""):lower():match("^%s*(%S*)%s*(%S*)")
  local f = ns.features[key]
  if not f then list() return end
  if arg == "on" then ns.Set(key, true)
  elseif arg == "off" then ns.Set(key, false)
  elseif f.show then f.show(ns.Data(key))
  else ns.Set(key, not ns.IsOn(key)) end
end
