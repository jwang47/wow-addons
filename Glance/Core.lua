-- Glance: a lighter HUD. Core: saved settings, events, API shims, slash
-- command and hiding the Blizzard frames that Glance replaces.
local addonName, ns = ...
Glance = ns                      -- global, for /dump and other addons

ns.VERSION = "0.1.0"
ns.hidden = CreateFrame("Frame")  -- parent for the frames we hide
ns.hidden:Hide()

local defaults = {
  keybar = true,        -- the keyboard bar
  units = true,         -- floating player/target frames and cast bar
  minimap = true,       -- square minimap restyle
  chat = true,          -- chat windows in the Glance look
  hideBlizzard = true,  -- hide PlayerFrame, TargetFrame, cast bar
  scale = 1,
}

function ns.print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff9cd0ffGlance|r: " .. tostring(msg))
end

-- Run fn now, or after combat if the game locks secure frames now.
local queued = {}
function ns.outOfCombat(key, fn)
  if InCombatLockdown() then queued[key] = fn else fn() end
end

-- Call fn and report an error once per name instead of breaking the HUD.
local reported = {}
function ns.safe(name, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not reported[name] then
    reported[name] = true
    ns.print(name .. " failed: " .. tostring(err))
  end
  return ok, err
end

---------------------------------------------------------------------------
-- Secret values: the Forever client hides some numbers from addons (health
-- always, power and cast times at times). Such a value may go straight to a
-- status bar or SetText, but any compare or sum on it is an error. plain(v)
-- gives v when it is an ordinary value and nil when it is secret.
---------------------------------------------------------------------------
function ns.plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

---------------------------------------------------------------------------
-- API shims: the Forever client has C_ActionBar, older clients globals.
---------------------------------------------------------------------------
local AB = C_ActionBar or {}
ns.api = {
  HasAction = AB.HasAction or HasAction,
  GetActionTexture = AB.GetActionTexture or GetActionTexture,
  GetActionCount = AB.GetActionDisplayCount or GetActionCount,
  IsUsableAction = AB.IsUsableAction or IsUsableAction,
  IsActionInRange = AB.IsActionInRange or IsActionInRange,
  IsCurrentAction = AB.IsCurrentAction or IsCurrentAction,
  IsConsumableAction = AB.IsConsumableAction or IsConsumableAction,
}
-- start, duration of an action's cooldown; the new API returns a table.
function ns.api.GetActionCooldown(slot)
  local fn = AB.GetActionCooldown or GetActionCooldown
  if not fn then return 0, 0 end
  local a, b = fn(slot)
  if type(a) == "table" then return a.startTime or 0, a.duration or 0 end
  return a or 0, b or 0
end

---------------------------------------------------------------------------
-- Hiding Blizzard frames
---------------------------------------------------------------------------
function ns.hideFrame(f)
  if not f then return end
  ns.safe("hide " .. (f.GetName and f:GetName() or "frame"), function()
    f:UnregisterAllEvents()
    f:Hide()
    f:SetParent(ns.hidden)
  end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
ns.events = events
local handlers = {}
function ns.on(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    events:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end
events:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_REGEN_ENABLED" then
    for key, fn in pairs(queued) do
      queued[key] = nil
      ns.safe(key, fn)
    end
  end
  for _, fn in ipairs(handlers[event] or {}) do ns.safe(event, fn, ...) end
end)
events:RegisterEvent("PLAYER_REGEN_ENABLED")

ns.editHooks = {}  -- fn(unlocked), run on /glance edit
ns.modules = {}  -- name -> setup function, run at PLAYER_LOGIN in order
ns.order = {}
function ns.module(name, setup)
  ns.modules[name] = setup
  table.insert(ns.order, name)
end

ns.on("PLAYER_LOGIN", function()
  GlanceDB = GlanceDB or {}
  for k, v in pairs(defaults) do
    if GlanceDB[k] == nil then GlanceDB[k] = v end
  end
  GlanceCharDB = GlanceCharDB or {}
  ns.db, ns.char = GlanceDB, GlanceCharDB
  for _, name in ipairs(ns.order) do
    if ns.db[name] ~= false then
      ns.safe(name, ns.modules[name])
    end
  end
end)

---------------------------------------------------------------------------
-- /glance
---------------------------------------------------------------------------
local help = {
  "/glance edit - unlock the keyboard bar: drag spells off keys, drag the bar to move it",
  "/glance reset - put the keyboard bar back at the bottom centre",
  "/glance map SIZE - minimap size in pixels (120-400); or drag its corner in /glance edit",
  "/glance import - read your key bindings again and rebuild the keyboard bar",
  "/glance take KEY - put KEY on the keyboard bar even if it has another binding",
  "/glance take all - the same for every key with another command, except Tab",
  "/glance free KEY - give KEY back to its normal binding",
  "/glance keybar|units|minimap|chat on|off - turn a part on or off (reloads)",
  "/glance blizzard on|off - show or hide Blizzard's player, target and cast frames (reloads)",
}
ns.commands = {}
SLASH_GLANCE1 = "/glance"
SlashCmdList.GLANCE = function(text)
  local cmd, rest = (text or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if ns.commands[cmd] then return ns.commands[cmd](rest) end
  if cmd == "keybar" or cmd == "units" or cmd == "minimap" or cmd == "chat" or cmd == "blizzard" then
    local on = rest:lower() ~= "off"
    if cmd == "blizzard" then ns.db.hideBlizzard = not on else ns.db[cmd] = on end
    ns.print(cmd .. (on and " on" or " off") .. ". Reloading.")
    if ReloadUI then ReloadUI() end
    return
  end
  for _, line in ipairs(help) do ns.print(line) end
end
