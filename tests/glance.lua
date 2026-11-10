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
  function w:SetAlpha(a) self.alpha = a end
  function w:IsMouseOver() return false end
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
BT4Bar1, BT4Bar3, BT4BarBlizzardArt = widget("BT4Bar1"), widget("BT4Bar3"), widget("BT4BarBlizzardArt")
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
  B = "OPENALLBAGS", C = "TOGGLECHARACTER0",
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
overridePrio = {}
function SetOverrideBindingClick(owner, prio, key, button, mouse)
  overrides[key] = button .. ":" .. mouse; overridePrio[key] = prio
end
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

-- The game's Edit Mode callbacks.
local editCallbacks = {}
EventRegistry = { RegisterCallback = function(_, ev, fn) editCallbacks[ev] = fn end }

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
check("button 1 shift action", b1:GetAttribute("shift-action1") == 49 and b1:GetAttribute("shift-action*") == 49)
check("cooldown not on the secure button", b1.cooldown.parent == _G.GlanceKeyOverlay)
check("1 bound to our button", overrides["1"] == "GlanceKey1:LeftButton")
check("Shift-1 bound to the Shift button", overrides["SHIFT-1"] == "GlanceKey1Shift:LeftButton")
check("Shift button casts the Shift slot", _G.GlanceKey1Shift:GetAttribute("type") == "action"
  and _G.GlanceKey1Shift:GetAttribute("action") == 49)
check("bindings take priority", overridePrio["1"] == true and overridePrio["SHIFT-1"] == true)
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
check("plain drag picks up", placed == -1)
SlashCmdList.GLANCE("lock")
placed = nil
b1.scripts.OnDragStart(b1)
check("locked keys keep spells", placed == nil)
SlashCmdList.GLANCE("edit")
b1.scripts.OnDragStart(b1)
check("edit mode picks up", placed == -1)
SlashCmdList.GLANCE("lock")
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
check("C, V and B not on the bar", _G.GlanceKeyC == nil and _G.GlanceKeyV == nil and _G.GlanceKeyB == nil)
check("take all leaves B and C", ns.char.map.B == nil and overrides.B == nil and overrides.C == nil)
check("Shift-B left alone", ns.char.map["SHIFT-B"] == nil and overrides["SHIFT-B"] == nil)
SlashCmdList.GLANCE("take b")
SlashCmdList.GLANCE("take shift-b")
check("bag key cannot be taken", overrides.B == nil and overrides["SHIFT-B"] == nil)
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
check("health numbers", _G.GlancePlayer.hp.text.text == "50 / 100", _G.GlancePlayer.hp.text.text)
-- A formatter that takes secrets (as the game's does) still prints them.
AbbreviateLargeNumbers = function(v) return rawequal(v, SECRET) and "?" or tostring(v) end
fire("UNIT_MAXPOWER", "player")
check("secret mana numbers", _G.GlancePlayer.mp.text.text == "30 / ?", _G.GlancePlayer.mp.text.text)
AbbreviateLargeNumbers = nil
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
check("right-edge bar kept", BT4Bar3.shown and drivers[BT4Bar3] == nil)
check("xp bar shown", _G.GlanceXP.shown)

-- Chat.
check("chat fades", fadeSet == true)
check("chat side buttons hidden", not ChatFrame1ButtonFrame.shown and not ChatFrameMenuButton.shown)
check("tabs hide without the mouse", CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA == 0)
check("edit box restyled", ChatFrame1EditBox.glanceBg ~= nil)

check("no bags tab", ns.minimap.bags == nil)

-- Spell ranks: slot 1 holds Frostbolt Rank 4, the book knows Rank 5.
local SPELLS = { [116] = { "Frostbolt", "Rank 4" }, [205] = { "Frostbolt", "Rank 5" } }
C_Spell = {
  GetSpellName = function(id) return SPELLS[id] and SPELLS[id][1] end,
  GetSpellSubtext = function(id) return SPELLS[id] and SPELLS[id][2] end,
  PickupSpell = function(id) _G.cursorSpell = id end,
}
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1 } end,
  GetSpellBookItemInfo = function() return { spellID = 205, name = "Frostbolt", subName = "Rank 5" } end,
}
function GetActionInfo(s) if s == 1 then return "spell", 116 end end
function ClearCursor() end
ns.keybar.scanRanks()
ns.keybar.paintAll()
check("old rank found", ns.keybar.betterRank(1) and ns.keybar.betterRank(1).id == 205)
check("old rank marked", _G.GlanceKey1.rankUp.shown)
check("other keys not marked", not _G.GlanceKeyQ.rankUp.shown)
placed = nil
SlashCmdList.GLANCE("ranks")
check("ranks places the best rank", cursorSpell == 205 and placed == 1)

-- Alerts under the minimap.
local A = ns.alerts
UnitCharacterPoints = function() return 0 end
A.refresh()
check("no alerts when nothing to do", not A.chips.talents.shown and not A.chips.legacy.shown)
C_Container = { GetContainerNumFreeSlots = function() return 3 end }
A.refresh()
check("bag slots always shown", A.chips.bags.shown and A.chips.bags.text.text == "Bags 15 free", A.chips.bags.text.text)
UnitCharacterPoints = function() return 2 end
Constants = { LegacyConsts = { LEGACY_REWARD_TRACK_FACTION_ID = 2802, LEGACY_TREE_PROFESSIONS_ID = 1187 } }
C_MajorFactions = { GetCurrentRenownLevel = function() return 3 end }
C_Traits = { GetConfigIDByTreeID = function() return 9 end,
  GetTreeCurrencyInfo = function() return { { quantity = 5 } } end }
C_Container = { GetContainerNumFreeSlots = function() return 0 end }
GetActionInfo = function() end
A.refresh()
check("talent alert", A.chips.talents.shown and A.chips.talents.text.text == "Talents 2")
check("legacy alert", A.chips.legacy.shown and A.chips.legacy.text.text == "Legacy 5")
check("bags full alert", A.chips.bags.shown and A.chips.bags.text.text == "Bags 0 free")
check("no rank alert after /glance ranks", not A.chips.ranks.shown)
local opened
ToggleLegacySystemUI = function() opened = "legacy" end
A.chips.legacy.scripts.OnClick()
check("legacy chip opens the Legacy window", opened == "legacy")

-- Range: Frostbolt (30 yd) on 1 reaches, Fire Blast (20 yd) on 2 does not.
local RANGES = { [116] = 30, [2136] = 20 }
C_Spell.GetSpellInfo = function(id) return { maxRange = RANGES[id] } end
GetActionInfo = function(s) if s == 1 then return "spell", 116 elseif s == 2 then return "spell", 2136 end end
local reach = { [1] = true, [2] = false }
ns.api.IsActionInRange = function(s) return reach[s] end
ns.units.paintRange()
local tf = _G.GlanceTarget
check("range in reach", tf.edge.shown and tf.range.text == "20-30 yd", tf.range.text)
reach[1] = false
ns.units.paintRange()
check("range out of reach", tf.range.text == "> 30 yd", tf.range.text)
reach = {}
ns.units.paintRange()
check("range unknown hides", not tf.edge.shown and tf.range.text == "")
-- Spellbook spells and interact distances refine it.
ns.keybar.bookSpells = { 116, 2136 }
local spellIn = { [116] = true, [2136] = false }
C_Spell.IsSpellInRange = function(id) return spellIn[id] end
local interact = { [3] = false, [2] = false, [4] = true }
CheckInteractDistance = function(_, i) return interact[i] end
ns.units.paintRange()
check("bracket from book and interact", tf.range.text == "20-28 yd", tf.range.text)
-- A party member: exact.
UnitDistanceSquared = function() return 529, true end
ns.units.paintRange()
check("exact yards for party", tf.range.text == "23 yd", tf.range.text)
UnitDistanceSquared = nil
ns.keybar.bookSpells = nil
GetActionInfo = function() end
local reloaded
ReloadUI = function() reloaded = true end
A.reload.scripts.OnClick()
check("reload button", reloaded)

-- XP buffs.
GetTime = GetTime or function() return 1000 end
local now = GetTime()
local buffs = { { name = "Arcane Intellect", spellId = 1459 }, { name = "Rested Wisdom", spellId = 9001, expirationTime = now + 2520 } }
C_UnitAuras = { GetBuffDataByIndex = function(_, i) return buffs[i] end }
C_Spell.GetSpellDescription = function(id) return id == 9001 and "Experience gained increased by 50%." or "Intellect up." end
A.refresh()
check("xp buff chip", A.chips.xp.shown and A.chips.xp.text.text == "XP 42m", A.chips.xp.text.text)
check("xp buff tooltip", A.chips.xp.tipLines[1] == "Rested Wisdom  42m left", A.chips.xp.tipLines and A.chips.xp.tipLines[1])
buffs = { { name = "Arcane Intellect", spellId = 1459 } }
A.refresh()
check("no xp buff chip", A.chips.xp.shown and A.chips.xp.text.text == "No XP buff", A.chips.xp.text.text)
local warned
RaidWarningFrame = {}
RaidNotice_AddMessage = function(_, msg) warned = msg end
A.hadXP = true
A.remindXP()
check("reminder when the xp buff runs out", warned == "No XP buff active")
warned = nil
A.remindXP()
check("no repeat right away", warned == nil)
SlashCmdList.GLANCE("xpremind off")
A.remindXP(true)
check("reminder can be turned off", warned == nil)
SlashCmdList.GLANCE("xpremind on")
-- An item buff that says XP only in its tooltip.
buffs = { { name = "Arcane Intellect", spellId = 1459, auraInstanceID = 1 }, { name = "Cheese Snack", spellId = 9002, auraInstanceID = 2, expirationTime = now + 900 } }
C_TooltipInfo = { GetUnitBuffByAuraInstanceID = function(_, inst)
  return { lines = { { leftText = inst == 2 and "Cheese Snack" or "Arcane Intellect" }, { leftText = inst == 2 and "Kills give 10% more XP." or "Intellect up." } } }
end }
A.refresh()
check("xp buff found in its tooltip", A.chips.xp.text.text == "XP 15m", A.chips.xp.text.text)
-- A buff no text match finds can be marked by hand.
C_TooltipInfo = nil
buffs = { { name = "Arcane Intellect", spellId = 1459 }, { name = "Big Cheese", spellId = 9003, expirationTime = now + 900 } }
A.refresh()
check("unmarked buff is not xp", A.chips.xp.text.text == "No XP buff", A.chips.xp.text.text)
SlashCmdList.GLANCE("xpbuff big cheese")
check("marked buff counts as xp", A.chips.xp.text.text == "XP 15m", A.chips.xp.text.text)
local menuItems = {}
MenuUtil = { CreateContextMenu = function(owner, gen)
  gen(owner, { CreateTitle = function() end, CreateCheckbox = function(_, text, isOn, toggle) menuItems[text] = { isOn = isOn, toggle = toggle } end })
end }
A.chips.xp.scripts.OnClick()
check("chip menu lists buffs", menuItems["Big Cheese"] and menuItems["Big Cheese"].isOn() == true and menuItems["Arcane Intellect"].isOn() == false)
menuItems["Big Cheese"].toggle()
check("menu unmarks a buff", A.chips.xp.text.text == "No XP buff", A.chips.xp.text.text)
MenuUtil = nil
_G.GlanceDB.xpBuffs = nil

-- Watch row: key spells by name from the spellbook.
local NAMES = { [1953] = "Blink", [2139] = "Counterspell", [116] = "Frostbolt" }
C_Spell.GetSpellName = function(id) return NAMES[id] or (SPELLS[id] and SPELLS[id][1]) end
C_Spell.GetSpellTexture = function(id) return id end
local cdur = { [1953] = 15, [2139] = 0 }
C_Spell.GetSpellCooldown = function(id) return { startTime = 1, duration = cdur[id] or 0 } end
UnitClass = function() return "Mage", "MAGE" end
ns.keybar.bookSpells = { 1953, 2139, 116 }
local W = ns.units.watch
W.build()
check("watch shows known key spells", #W.ids == 2 and W.icons[1].id == 1953 and W.icons[2].id == 2139)
check("watch icons cast on click", W.icons[2].attrs.type == "spell" and W.icons[2].attrs.spell == 2139)
check("cooling spell is dark", W.icons[1].cooling == true and W.icons[2].cooling == false)
W.icons[1].cd.scripts.OnCooldownDone()
check("ready flash", W.icons[1].flash.shown)
SlashCmdList.GLANCE("watch remove Blink")
check("watch remove", #W.ids == 1 and W.icons[1].id == 2139)
SlashCmdList.GLANCE("watch add Frostbolt")
check("watch add", #W.ids == 2 and W.icons[2].id == 116)
SlashCmdList.GLANCE("watch reset")
check("watch reset", #W.ids == 2 and W.icons[1].id == 1953)

-- Target cast bar: big, orange when interruptible, COUNTERSPELL when ready.
UnitCanAttack = function() return true end
UnitCastingInfo = function(u) if u == "target" then return "Fireball", "", 1, 1000, 3000, false, 7, false, 133 end end
local TC = ns.units.tcast
ns.units.castUpdate(TC)
check("target cast shows", TC.shown and TC.text.text == "Fireball")
check("counterspell call-out", TC.kick.text == "COUNTERSPELL" and TC.glow.shown)
local KB = _G.GlanceKickButton
check("click on the call-out casts counterspell", KB and KB.attrs.type == "spell" and KB.attrs.spell == "Counterspell" and KB.attrs.unit == "target")
check("kick button shown by the game in combat", drivers[KB] == "[combat,harm,nodead]show;hide")
local csCD = C_Spell.GetSpellCooldown
C_Spell.GetSpellCooldown = function(id) if id == 2139 then return { startTime = GetTime() - 4, duration = 24 } end return csCD(id) end
W.paint()
ns.units.castUpdate(TC)
check("counterspell cooldown on the call-out", TC.kick.text == "Counterspell 20s" and not TC.glow.shown, TC.kick.text)
C_Spell.GetSpellCooldown = csCD
W.paint()
UnitCastingInfo = function(u) if u == "target" then return "Shield Wall", "", 1, 1000, 3000, false, 7, true, 134 end end
ns.units.castUpdate(TC)
check("no call-out when it cannot be interrupted", TC.kick.text == "" and not TC.glow.shown)
UnitCastingInfo = function() end
ns.units.castUpdate(TC)
check("target cast hides", not TC.shown)
ns.keybar.bookSpells = nil

-- Party: names over party members, group CVars on and back.
local cvars = { nameplateShowFriendlyPlayers = "0", nameplateShowFriendlyClassColor = "0", UnitNameFriendlyPlayerName = "0" }
function GetCVar(k) return cvars[k] end
function SetCVar(k, v) cvars[k] = tostring(v) end
local grouped = true
function IsInGroup() return grouped end
UnitIsPlayer = function() return true end
UnitInParty = function(u) return u == "nameplate2" end
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
local plates = { nameplate2 = widget("Plate2"), nameplate3 = widget("Plate3") }
C_NamePlate = { GetNamePlateForUnit = function(u) return plates[u] end }
fire("GROUP_ROSTER_UPDATE")
check("friendly plates on in a group", cvars.nameplateShowFriendlyPlayers == "1")
fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
check("party member labelled", ns.party.labels.nameplate2 and ns.party.labels.nameplate2.shown)
check("stranger not labelled", not (ns.party.labels.nameplate3 and ns.party.labels.nameplate3.shown))
fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
check("label hides with its plate", not ns.party.labels.nameplate2.shown)
grouped = false
fire("GROUP_ROSTER_UPDATE")
-- Minimap edge pointers (checked before leaving the group).
local function vec(x, y) return { GetXY = function() return x, y end } end
local where = { player = vec(0.5, 0.5), party1 = vec(0.5, 0.2) }
C_Map = { GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function(_, u) return where[u] end,
  GetMapWorldSize = function() return 3000, 2000 end,
  GetUserWaypoint = function() return { uiMapID = 1429, position = vec(0.52, 0.5) } end }
C_Minimap = { GetViewRadius = function() return 200 end }
GetNumSubgroupMembers = function() return 1 end
UnitName = function(u) return u == "party1" and "Friend" or "Ded" end
grouped = true
ns.minimap.updatePointers()
local P1 = ns.minimap.pointers[1]
check("party pointer on the rim", P1 and P1.shown and P1.label.text == "Friend 600", P1 and P1.label.text)
check("pin on the map gets no pointer", not ns.minimap.pointers[2] or not ns.minimap.pointers[2].shown)
local ox, oy, yd = ns.minimap.offsetFor({ x = 0.5, y = 0.2 }, 0.5, 0.5, 3000, 2000, 200, 95)
check("party member north of you", math.abs(ox) < 0.01 and oy > 95 and math.floor(yd + 0.5) == 600)
local ox2 = ns.minimap.offsetFor({ x = 0.52, y = 0.5 }, 0.5, 0.5, 3000, 2000, 200, 95)
check("pin to the east, 60 yd, on the map", ox2 > 0 and ox2 < 95)
grouped = false
check("your plate settings come back", cvars.nameplateShowFriendlyPlayers == "0" and ns.db.partySaved == nil)

-- Resizing the minimap.
SlashCmdList.GLANCE("map 260")
check("map size saved", ns.db.mapSize == 260)
SlashCmdList.GLANCE("map 9999")
check("map size clamped", ns.db.mapSize == 400)
SlashCmdList.GLANCE("edit")
check("grip hidden until hover", (_G.GlanceMinimapGrip.alpha or 0) == (ns.unlocked and 0.9 or 0.25))
Minimap.scripts.hookOnEnter()
check("grip shows on map hover", _G.GlanceMinimapGrip.alpha == 0.9)
Minimap.scripts.hookOnLeave()
check("grip fades off the map", _G.GlanceMinimapGrip.alpha == 0.25)
local wasUnlocked = ns.unlocked
editCallbacks["EditMode.Enter"]()
check("game Edit Mode unlocks Glance", ns.unlocked and _G.GlanceMinimapGrip.alpha == 0.9)
editCallbacks["EditMode.Exit"]()
check("leaving Edit Mode locks it", not ns.unlocked and _G.GlanceMinimapGrip.alpha == 0.25)
if wasUnlocked then ns.setEdit(true) end
local size0 = ns.db.mapSize or 190
P.shift = true
Minimap.scripts.OnMouseWheel(Minimap, -1)
P.shift = false
check("shift+wheel resizes the map", ns.db.mapSize == size0 - 20, ns.db.mapSize)

-- A combat login defers secure setup.
for _, line in ipairs(chat) do check("no error", not line:match("failed"), line) end
if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("glance: all tests passed")
