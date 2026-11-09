-- Offline tests for Glance with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/glance.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/glance%.lua$") or ""
local failures, chat = 0, {}
local function check(name, ok, detail)
  if not ok then
    failures = failures + 1
    print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
  end
end

-- Generic widget: unknown capitalised methods are no-ops; attributes,
-- scripts, points and shown state are kept.
local function widget(name)
  local w = { scripts = {}, attrs = {}, shown = true, name = name, text = "" }
  function w:SetScript(what, fn) self.scripts[what] = fn end
  function w:HookScript(what, fn) self.scripts["hook" .. what] = fn end
  function w:GetScript(what) return self.scripts[what] end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:SetShown(v) self.shown = v and true or false end
  function w:IsShown() return self.shown end
  function w:GetName() return self.name end
  function w:SetAttribute(k, v) self.attrs[k] = v end
  function w:GetAttribute(k) return self.attrs[k] end
  function w:SetText(t) self.text = t end
  function w:GetText() return self.text end
  function w:SetFormattedText(f, ...) self.text = string.format(f, ...) end
  function w:SetParent(p) self.parent = p end
  function w:CreateTexture() return widget() end
  function w:CreateFontString() return widget() end
  function w:GetChildren() return unpack(self.children or {}) end
  function w:GetZoom() return self.zoom or 0 end
  function w:SetZoom(z) self.zoom = z end
  function w:GetZoomLevels() return 5 end
  return setmetatable(w, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end
function CreateFrame(kind, name, parent)
  local f = widget(name)
  f.kind, f.parent = kind, parent
  if name then _G[name] = f end
  return f
end
UIParent = widget("UIParent")
Minimap = widget("Minimap")
MinimapCluster = widget("MinimapCluster")
MinimapCluster.IndicatorFrame = widget()
PlayerFrame, TargetFrame, PlayerCastingBarFrame = widget("PlayerFrame"), widget("TargetFrame"), widget("PlayerCastingBarFrame")
GameTooltip = widget("GameTooltip")
NUM_CHAT_WINDOWS = 2
BT4Bar1, BT4BarBlizzardArt = widget("BT4Bar1"), widget("BT4BarBlizzardArt")
function BT4Bar1:IsProtected() return true end
local drivers = {}
function RegisterStateDriver(f, k, v) drivers[f] = v end
function UnitXP() return 300 end
function UnitXPMax() return 1000 end
function GetXPExhaustion() return 200 end
ChatFrame1, ChatFrame2 = widget("ChatFrame1"), widget("ChatFrame2")
ChatFrame1Tab = widget("ChatFrame1Tab")
ChatFrame1Tab.Left = widget()
ChatFrame1ButtonFrame = widget("ChatFrame1ButtonFrame")
ChatFrame1EditBox = widget("ChatFrame1EditBox")
ChatFrameMenuButton = widget("ChatFrameMenuButton")
CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0.2
local fadeSet
function ChatFrame1:SetFading(v) fadeSet = v end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, m) end }
SlashCmdList = {}
function hooksecurefunc() end
function ReloadUI() end

local P = { combat = false, shift = false }
function InCombatLockdown() return P.combat end
function IsShiftKeyDown() return P.shift end
function IsAltKeyDown() return false end
local timers = {}
C_Timer = { After = function(_, f) table.insert(timers, f) end, NewTicker = function() end }
function GetTime() return 100 end
function GetGameTime() return 16, 3 end
function GetMinimapZoneText() return "Black Channel Marsh" end
C_Map = {
  GetBestMapForUnit = function() return 1437 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.234, 0.513 end } end,
}

-- Bindings as the player has them now.
local BIND = {
  ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2", ["5"] = "ACTIONBUTTON5", R = "ACTIONBUTTON5",
  ["Q"] = "CLICK BT4Button13:Keybind", ["E"] = "MULTIACTIONBAR1BUTTON3",
  ["SHIFT-1"] = "MULTIACTIONBAR2BUTTON1",
  W = "MOVEFORWARD", A = "STRAFELEFT", S = "MOVEBACKWARD", D = "STRAFERIGHT",
  TAB = "TARGETNEARESTENEMY", ["SHIFT-TAB"] = "TARGETPREVIOUSENEMY",
  Z = "", -- unbound
}
BINDING_NAME_TARGETNEARESTENEMY = "Target Nearest Enemy"
function GetBindingAction(k) return BIND[k] or "" end
local bindList = {}
for k, v in pairs(BIND) do if v ~= "" then table.insert(bindList, { v, k }) end end
table.insert(bindList, { "MULTIACTIONBAR4BUTTON12", "F12" }) -- slot 48 in use elsewhere
function GetNumBindings() return #bindList end
function GetBinding(i) return bindList[i][1], "cat", bindList[i][2] end

-- Action slots that hold something.
local ACTIONS = { [5] = 135900, [1] = 135846, [2] = 135812, [13] = 135736, [63] = 135865, [49] = 135808, [120] = 999 }
C_ActionBar = {
  HasAction = function(s) return ACTIONS[s] ~= nil end,
  GetActionTexture = function(s) return ACTIONS[s] end,
  GetActionCooldown = function() return { startTime = 0, duration = 0 } end,
  IsUsableAction = function() return true, false end,
  IsActionInRange = function() return nil end,
  IsCurrentAction = function() return false end,
  IsConsumableAction = function() return false end,
}
local overrides = {}
function SetOverrideBindingClick(owner, prio, key, button, mouse) overrides[key] = button .. ":" .. mouse end
function ClearOverrideBindings() overrides = {} end
local placed
function PlaceAction(s) placed = s end
function PickupAction(s) placed = -s end

UnitExists = function() return true end
UnitName = function(u) return u == "player" and "Ded" or "Mottled Raptor" end
UnitLevel = function(u) return u == "player" and 28 or 23 end
UnitHealth = function() return 50 end
UnitHealthMax = function() return 100 end
UnitPower = function() return 30 end
UnitPowerMax = function() return 60 end
UnitPowerType = function() return 0, "MANA" end
UnitClass = function() return "Mage", "MAGE" end
UnitIsPlayer = function(u) return u == "player" end
UnitIsUnit = function(a, b) return a == b end
UnitIsTapDenied = function() return false end
UnitReaction = function() return 2 end
UnitCastingInfo = function() end
UnitChannelInfo = function() end
RegisterUnitWatch = function(f) f.watched = true end

-- Load the addon in .toc order.
local ns = {}
local toc = assert(io.open(root .. "Glance/Glance.toc")):read("*a")
for file in toc:gmatch("\n([%w_]+%.lua)") do
  assert(loadfile(root .. "Glance/" .. file))("Glance", ns)
end
local function fire(ev, ...) ns.events.scripts.OnEvent(ns.events, ev, ...) end
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
for _, line in ipairs(chat) do check("no error at login", not line:match("failed"), line) end

-- Pure classification.
local K = ns.keys
check("slot ACTIONBUTTON3", K.slotOf("ACTIONBUTTON3") == 3)
check("slot bottom left bar", K.slotOf("MULTIACTIONBAR1BUTTON1") == 61)
check("slot bottom right bar", K.slotOf("MULTIACTIONBAR2BUTTON12") == 60)
check("slot right bar", K.slotOf("MULTIACTIONBAR3BUTTON1") == 25)
check("slot bartender", K.slotOf("CLICK BT4Button27:LeftButton") == 27)
check("move", select(1, K.classify("STRAFELEFT")) == "move")
check("command", select(1, K.classify("TARGETNEARESTENEMY")) == "command")
check("own button free", K.classify("CLICK GlanceKey1:LeftButton") == "free")

-- The map read from the bindings.
local map = ns.char.map
check("1 keeps slot 1", map["1"] and map["1"].slot == 1)
check("Q keeps Bartender slot 13", map.Q and map.Q.slot == 13)
check("E keeps bar slot 63", map.E and map.E.slot == 63)
check("Shift-1 keeps slot 49", map["SHIFT-1"] and map["SHIFT-1"].slot == 49)
check("5 marked as the same as R", map["5"].dupOf == "R" and not map.R.dupOf)
check("W is movement", map.W and map.W.kind == "move")
check("Shift-W left alone", map["SHIFT-W"] == nil)
check("Tab is a command", map.TAB and map.TAB.kind == "command")
check("Shift-Tab is a command", map["SHIFT-TAB"] and map["SHIFT-TAB"].kind == "command")
check("Z gets an empty slot", map.Z and map.Z.kind == "slot" and map.Z.fresh)
check("free slots skip used and full ones", map.Z.slot ~= 120 and map.Z.slot ~= 48 and map.Z.slot ~= 63)
local seen, dup = {}, false
for _, e in pairs(map) do
  if e.kind == "slot" and not e.dupOf then
    if seen[e.slot] then dup = true end
    seen[e.slot] = true
  end
end
check("no slot used twice (copies aside)", not dup)

-- Buttons and override bindings.
local b1 = _G.GlanceKey1
check("button 1 action", b1:GetAttribute("type") == "action" and b1:GetAttribute("action") == 1)
check("button 1 shift action", b1:GetAttribute("shift-action") == 49)
check("1 bound to our button", overrides["1"] == "GlanceKey1:LeftButton")
check("Shift-1 bound to our button", overrides["SHIFT-1"] == "GlanceKey1:LeftButton")
check("W not taken", overrides.W == nil)
check("Tab not taken", overrides.TAB == nil)
check("Tab shows its command", _G.GlanceKeyTAB.note.text == "Target")
check("Q shows its icon", _G.GlanceKeyQ.icon.shown)
check("Z shows empty", _G.GlanceKeyZ.empty.shown)
check("5 drawn as a copy of R", _G.GlanceKey5.note.text == "= R")
check("R drawn plain", _G.GlanceKeyR.note.text == "")

-- Shift flips the bar and drops go to the Shift layer.
P.shift = true
fire("MODIFIER_STATE_CHANGED")
check("shift slot used", ns.keybar.currentSlot(b1) == 49)
b1.scripts.OnReceiveDrag(b1)
check("drop on shift layer", placed == 49)
P.shift = false
b1.scripts.OnReceiveDrag(b1)
check("drop on plain layer", placed == 1)
placed = nil
b1.scripts.OnDragStart(b1)
check("locked bar keeps spells", placed == nil)
SlashCmdList.GLANCE("edit")
b1.scripts.OnDragStart(b1)
check("unlocked bar picks up", placed == -1)
P.combat = true
placed = nil
b1.scripts.OnReceiveDrag(b1)
check("no drop in combat", placed == nil)
P.combat = false

-- Edit mode moves the bar and saves where.
local kb = _G.GlanceKeyBar
kb.GetPoint = function() return "BOTTOM", UIParent, "BOTTOM", 40, 200 end
kb.scripts.OnDragStop(kb)
check("bar position saved", ns.db.barPos[1] == "BOTTOM" and ns.db.barPos[3] == 200)
SlashCmdList.GLANCE("reset")
check("bar reset", ns.db.barPos == nil)
SlashCmdList.GLANCE("edit")

-- A spell dropped on a fresh key stays there after import.
local zslot = map.Z.slot
ACTIONS[zslot] = 1
SlashCmdList.GLANCE("import")
check("fresh key keeps its slot", ns.char.map.Z.slot == zslot)

-- /glance take gives a command key to the bar; free gives it back.
SlashCmdList.GLANCE("take tab")
check("take Tab", ns.char.map.TAB.kind == "slot" and overrides.TAB == "GlanceKeyTAB:LeftButton")
SlashCmdList.GLANCE("free tab")
check("free Tab", ns.char.map.TAB.kind == "command" and overrides.TAB == nil)

-- take all: command keys become spell keys; Tab and movement stay.
BIND.F = "ASSISTTARGET"
SlashCmdList.GLANCE("import")
check("F is a command", ns.char.map.F.kind == "command")
SlashCmdList.GLANCE("take all")
check("take all takes F", ns.char.map.F.kind == "slot" and overrides.F == "GlanceKeyF:LeftButton")
check("take all leaves Tab", ns.char.map.TAB.kind == "command")
check("take all leaves W", ns.char.map.W.kind == "move")
check("taken F gets a Shift layer", ns.char.map["SHIFT-F"] and ns.char.map["SHIFT-F"].kind == "slot")

-- Import in combat waits.
P.combat = true
SlashCmdList.GLANCE("import")
check("import refused in combat", chat[#chat]:match("Not in combat"))
P.combat = false

-- Units.
local pf = _G.GlancePlayer
check("player frame", pf and pf:GetAttribute("unit") == "player" and pf.name.text == "Ded")
check("target watched", _G.GlanceTarget and _G.GlanceTarget.watched)
check("blizzard player frame hidden", PlayerFrame.parent == ns.hidden and not PlayerFrame.shown)
local r = ns.units.healthColor("target")
check("hostile is red", r > 0.8)
local pr, pg = ns.units.healthColor("player")
check("own health is green", pg > pr)

-- Secret values: compares on them must not happen.
local SECRET = setmetatable({}, { __eq = function() error("compare on secret") end,
  __lt = function() error("compare on secret") end, __le = function() error("compare on secret") end })
function issecretvalue(v) return v == nil and false or rawequal(v, SECRET) end
UnitPowerMax = function() return SECRET end
UnitLevel = function() return SECRET end
UnitReaction = function() return SECRET end
local before = #chat
fire("UNIT_MAXPOWER", "player")
fire("PLAYER_TARGET_CHANGED")
check("secret power and level are fine", #chat == before, chat[#chat])
check("power bar kept", _G.GlancePlayer.mp.shown)
UnitCastingInfo = function() return "Frostbolt", "", 1, SECRET, SECRET end
UnitCastingDuration = function() return "duration" end
local timerSet
ns.units.cast.bar.SetTimerDuration = function(_, d) timerSet = d end
fire("UNIT_SPELLCAST_START", "player")
check("cast uses the game timer", timerSet == "duration" and ns.units.cast.timer)
ns.units.cast.scripts.OnUpdate(ns.units.cast)
check("no cast error", #chat == before, chat[#chat])
UnitCastingInfo = function() end
fire("UNIT_SPELLCAST_STOP", "player")
check("cast bar hides", not ns.units.cast.shown)
issecretvalue = nil

-- Minimap.
check("square shape", GetMinimapShape() == "SQUARE")
check("minimap moved", Minimap.parent == _G.GlanceMinimap)
check("coords", ns.minimap.coords() == "23.4, 51.3")
check("clock", ns.minimap.clock() == "16:03")
local lib = widget("LibDBIcon10_Questie")
Minimap.children = { lib, widget("SomethingElse") }
ns.minimap.layoutDrawer()
check("addon button in drawer", lib.parent == _G.GlanceAddonDrawer)
check("tab counts buttons", ns.minimap.tab.text.text == "Addons 1")
_G.GlanceMinimap.scripts.OnUpdate(_G.GlanceMinimap, 1)
check("minimap info line", ns.minimap.info.text == "23.4, 51.3  16:03")

-- Old bars.
check("bars left alone by default", drivers[BT4Bar1] == nil and BT4BarBlizzardArt.shown)
SlashCmdList.GLANCE("bars hide")
check("bartender bar hidden by driver", drivers[BT4Bar1] == "hide")
check("gryphon art hidden", not BT4BarBlizzardArt.shown)
check("xp bar shown", _G.GlanceXP.shown)

-- Chat.
check("chat fades", fadeSet == true)
check("chat side buttons hidden", not ChatFrame1ButtonFrame.shown and not ChatFrameMenuButton.shown)
check("tabs hide without the mouse", CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA == 0)
check("edit box restyled", ChatFrame1EditBox.glanceBg ~= nil)

-- Resizing the minimap.
SlashCmdList.GLANCE("map 260")
check("map size saved", ns.db.mapSize == 260)
SlashCmdList.GLANCE("map 9999")
check("map size clamped", ns.db.mapSize == 400)
SlashCmdList.GLANCE("edit")
check("grip shows in edit", _G.GlanceMinimapGrip.shown == ns.unlocked)

-- A combat login defers secure setup.
for _, line in ipairs(chat) do check("no error", not line:match("failed"), line) end
if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("glance: all tests passed")
