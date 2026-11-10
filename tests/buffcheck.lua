-- Offline tests for BuffCheck with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/buffs.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/buffs%.lua$") or ""
local failures, chat = 0, {}
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end

local function widget(name)
  local w = { scripts = {}, shown = false, name = name, attrs = {} }
  function w:SetScript(what, fn) self.scripts[what] = fn end
  function w:HookScript(what, fn) self.scripts[what] = fn end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:IsShown() return self.shown end
  function w:SetText(t) self.text = t end
  function w:SetAttribute(k, v) self.attrs[k] = v end
  function w:SetColorTexture(r, g, b) self.colour = { r, g, b } end
  function w:RegisterEvent(e) self.events = self.events or {} self.events[e] = true end
  function w:CreateTexture() return widget() end
  function w:CreateFontString() return widget() end
  function w:GetPoint() return "TOPLEFT", nil, nil, 20, -420 end
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

-- The world: you (a mage), a warrior and a priest in your party, and a
-- druid nearby who is not in your group.
local T = 1000
local W = {
  combat = false, mounted = false,
  units = {
    player = { first = "Ded", last = "Rats", class = "MAGE", auras = { ["Frost Armor"] = 0 } },
    party1 = { first = "Kan", last = "Food", class = "WARRIOR", auras = {} },
    party2 = { first = "Ramen", last = "Enjoyer", class = "PRIEST",
               auras = { ["Arcane Intellect"] = T + 100 } },
    nameplate1 = { first = "Under", last = "Left", class = "DRUID", auras = {}, near = true, stranger = true },
  },
  known = { ["Arcane Intellect"] = true, ["Frost Armor"] = true },
}
local function U(u) return W.units[u] end
function GetTime() return T end
function InCombatLockdown() return W.combat end
function IsMounted() return W.mounted end
function UnitName(u) local x = U(u) if x then return x.first, x.last end end
function UnitClass(u) local x = U(u) if x then return x.class, x.class end end
function UnitExists(u) return U(u) ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitIsPlayer(u) return U(u) ~= nil end
function UnitIsConnected() return true end
function UnitIsDeadOrGhost() return false end
function UnitIsVisible() return true end
function UnitCanAssist() return true end
function UnitInParty(u) return U(u) ~= nil and not U(u).stranger end
function UnitInRaid() return nil end
function UnitPower() return 900 end
function UnitPowerMax() return 1000 end
function CheckInteractDistance(u) return U(u) and U(u).near or false end
function IsInRaid() return false end
function GetNumGroupMembers() return 3 end
C_Spell = {
  GetSpellInfo = function(n) if W.known[n] then return { name = n } end end,
  GetSpellTexture = function() return 1 end,
  GetSpellName = function(id) return id == 7302 and "Frost Armor" or nil end,
}
C_UnitAuras = {
  GetAuraDataByIndex = function(u, i)
    local list = {}
    local x = U(u) or {}
    for name, exp in pairs(x.auras or {}) do
      list[#list + 1] = { name = name, expirationTime = exp, duration = 1800,
                          sourceUnit = x.src and x.src[name], auraInstanceID = #name * 1000 + (exp or 0) }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list[i]
  end,
}

local ns = {}
local function load(file)
  local chunk = assert(loadfile(root .. "BuffCheck/" .. file))
  chunk("BuffCheck", ns)
end
load("Logic.lua")
load("BuffCheck.lua")
local M = ns.logic

-- Logic
check("joinName joins the Forever surname", M.joinName("Ded", "Rats") == "Ded Rats")
check("joinName without a second name", M.joinName("Ded", nil) == "Ded")
local int = M.BUFFS[1]
check("state on", M.state({ ["Arcane Intellect"] = { expires = T + 900 } }, int, T) == "on")
local s, left = M.state({ ["Arcane Brilliance"] = { expires = T + 90 } }, int, T)
check("state low counts Brilliance", s == "low" and left == 90)
check("state off", M.state({}, int, T) == "off")
check("state unknown when hidden", M.state({ partial = true }, int, T) == "unknown")
check("state unknown when unread", M.state(nil, int, T) == "unknown")
check("no Int for a warrior", not M.applies(int, "WARRIOR"))
check("short minutes", M.short(150) == "3m" and M.short(42) == "42s")
check("blessing by pattern", M.state({ ["Greater Blessing of Kings"] = { expires = 0 } }, M.BUFFS[4], T) == "on")
check("self buff prefers the last cast", M.selfBuff("MAGE", "Mage Armor", function() return true end) == "Mage Armor")
check("self buff falls back to the best known",
  M.selfBuff("MAGE", "Mage Armor", function(n) return n == "Frost Armor" end) == "Frost Armor")
check("macro for a group member", M.macro("Arcane Intellect", "party1") == "/cast [@party1] Arcane Intellect")
check("macro for a stranger gives the target back",
  M.macro("Arcane Intellect", nil, "Under Left", true) == "/target Under Left\n/cast Arcane Intellect\n/targetlasttarget")
check("macro clears a target you did not have",
  M.macro("Arcane Intellect", nil, "Under Left", false):find("/cleartarget$") ~= nil)
check("macro refuses a name that could inject", M.macro("Arcane Intellect", nil, "a\n/run x", true) == "")

-- The addon, loaded
local ev = ns.ev
ev.scripts.OnEvent(ev, "ADDON_LOADED", "BuffCheck")
ev.scripts.OnEvent(ev, "PLAYER_LOGIN")
local st = ns.st
check("three rows", #st.rows == 3)
local labels = {}
for c, def in ipairs(st.cols) do labels[#labels + 1] = def.label end
check("columns: Int, Fort, Armor", table.concat(labels, ",") == "Int,Fort,Armor")
check("you: Int missing", st.rows[1].cells[1].state == "off")
check("you: armor on", st.rows[1].cells[3].state == "on")
check("warrior: no Int cell", st.rows[2].cells[1] == nil)
check("priest: Int ending soon", st.rows[3].cells[1].state == "low")
check("priest: no Fort", st.rows[3].cells[2].state == "off")
check("next: you first", st.next and st.next.reason == "you" and st.next.unit == "player")
check("next macro casts on you", BuffCheckNext.attrs.macrotext == "/cast [@player] Arcane Intellect")
check("row macro for the priest", BuffCheckRow3.attrs.macrotext == "/cast [@party2] Arcane Intellect")
check("no row macro for the warrior", BuffCheckRow2.attrs.macrotext == "")
check("a binding name", _G["BINDING_NAME_CLICK BuffCheckNext:LeftButton"] ~= nil)

-- After you buff yourself, the priest (ending in 100 s) is not yet due;
-- the druid nearby is next.
W.units.player.auras["Arcane Intellect"] = T + 1800
ns.refresh()
check("next: the druid nearby", st.next and st.next.reason == "nearby" and st.next.name == "Under Left")
check("nearby macro targets by name", BuffCheckNext.attrs.macrotext:find("^/target Under Left\n") ~= nil)

-- Under a minute, the priest is due before strangers.
T = T + 50
ns.refresh()
check("next: renew the priest", st.next and st.next.unit == "party2")
T = T - 50

-- A stranger buffs you: return the favour first. The UNIT_AURA payload
-- is secret on Forever (reading it raises an error), so it is never read.
local secretPayload = setmetatable({}, { __index = function() error("attempt to read a secret value") end })
W.units.nameplate2 = { first = "Chrome", last = "Steelhart", class = "PALADIN", auras = {}, stranger = true }
W.units.player.src = { ["Blessing of Wisdom"] = "nameplate2", ["Battle Shout"] = "nameplate2" }
W.units.player.auras["Blessing of Wisdom"] = T + 300
local okEvent, err = pcall(ev.scripts.OnEvent, ev, "UNIT_AURA", "player", secretPayload)
check("a secret UNIT_AURA payload raises no error", okEvent)
if not okEvent then print(err) end
ns.refresh()
check("next: returns a favour", st.next and st.next.reason == "returns a favour" and st.next.name == "Chrome Steelhart")
W.units.player.auras["Battle Shout"] = T + 120
ev.scripts.OnEvent(ev, "UNIT_AURA", "player", secretPayload)
check("a shout is not a favour", #st.owed == 1)
W.units.player.auras["Blessing of Wisdom"], W.units.player.auras["Battle Shout"] = nil, nil
ev.scripts.OnEvent(ev, "UNIT_AURA", "player", secretPayload)
check("a buff that ends adds nothing", #st.owed == 1)

-- Pressing it removes it; a right-click skips the next one.
ns.pressed("LeftButton")
ns.refresh()
check("favour done after the press", #st.owed == 0 and st.next and st.next.name == "Under Left")
ns.pressed("RightButton")
ns.refresh()
check("right-click skips", st.next == nil or st.next.name ~= "Under Left")

-- Nearby off; mounted; combat keeps the macros.
ns.db.nearby = false
ns.refresh()
check("nearby off", st.next == nil)
ns.db.nearby = true
W.mounted = true
ns.refresh()
check("nothing while mounted", st.next == nil)
W.mounted = false
W.units.player.auras["Arcane Intellect"] = nil
ns.refresh()
local before = BuffCheckNext.attrs.macrotext
ev.scripts.OnEvent(ev, "PLAYER_REGEN_DISABLED")
check("combat empties the Next macro", BuffCheckNext.attrs.macrotext == "" and before ~= "")
W.combat = true
ns.refresh()
check("no macro change in combat", BuffCheckNext.attrs.macrotext == "")
W.combat = false

-- Secret values: an aura the client hides shows unknown, not missing.
local secretOne = {}
function issecretvalue(v) return v == secretOne end
local oldIndex = C_UnitAuras.GetAuraDataByIndex
C_UnitAuras.GetAuraDataByIndex = function(u, i)
  if u == "party1" and i == 1 then return { name = secretOne } end
  return oldIndex(u, i)
end
W.units.party1.class = "PALADIN"
ns.refresh()
check("hidden aura: unknown", st.rows[2].cells[1].state == "unknown")
C_UnitAuras.GetAuraDataByIndex = oldIndex
issecretvalue = nil

-- In combat the client hides aura names. The last full read fills in the
-- buffs that have not run out, and Next stays empty.
W.units.player.auras = { ["Arcane Intellect"] = T + 1500, ["Frost Armor"] = T + 3000 }
ns.refresh()
function issecretvalue(v) return v == secretOne end
C_UnitAuras.GetAuraDataByIndex = function(u, i)
  if u == "player" then
    if i <= 2 then return { name = secretOne, expirationTime = secretOne } end
    return nil
  end
  return oldIndex(u, i)
end
W.combat = true
ns.refresh()
check("combat: Int remembered as on", st.rows[1].cells[1].state == "on")
local armorCol
for c, def in ipairs(st.cols) do if def.self then armorCol = c end end
check("combat: armor remembered as on", st.rows[1].cells[armorCol].state == "on")
check("combat: no next buff", st.next == nil and BuffCheckNext.label.text:find("In combat") ~= nil)
T = T + 2000
ns.refresh()
check("combat: a remembered buff runs out", st.rows[1].cells[1].state == "unknown")
check("combat: hidden armor is unknown, not missing", st.rows[1].cells[armorCol].state == "on")
T = T + 1500
ns.refresh()
check("combat: armor unknown once its time is up", st.rows[1].cells[armorCol].state == "unknown")
T = T - 3500
W.combat = false
C_UnitAuras.GetAuraDataByIndex = oldIndex
issecretvalue = nil

-- Last armor cast is remembered.
ev.scripts.OnEvent(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "x", 7302)
check("last armor saved", ns.db.lastSelf == "Frost Armor")

SlashCmdList.BUFFCHECK("nearby off")
check("slash nearby off", ns.db.nearby == false)

-- Scrolls in your bags.
local BAG = { "Scroll of Stamina II", "Scroll of Stamina III", "Scroll of Intellect", "Scroll of Strength",
              "Scroll of Recall", "Linen Cloth" }
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and #BAG or 0 end,
  GetContainerItemInfo = function(bag, slot)
    if bag == 0 and BAG[slot] then return { itemID = 100 + slot, itemName = BAG[slot], stackCount = 1 } end
  end,
}
W.units.party1.class = "WARRIOR"
W.units.player.auras = { ["Arcane Intellect"] = T + 1500, ["Frost Armor"] = T + 3000 }
ev.scripts.OnEvent(ev, "BAG_UPDATE_DELAYED")
ns.refresh()
local scrollCol
for c, def in ipairs(st.cols) do if def.scroll then scrollCol = c end end
check("a Scroll column", scrollCol ~= nil)
check("one scroll to read (Stamina III; a mage casts Int, Strength is not for a mage)",
  st.scrollsDue and #st.scrollsDue == 1 and st.scrollsDue[1].name == "Scroll of Stamina III")
check("scroll cell: missing, count 1", st.rows[1].cells[scrollCol].state == "off" and st.rows[1].cells[scrollCol].count == 1)
check("next: read the scroll", st.next and st.next.reason == "scroll" and st.next.item == "Scroll of Stamina III")
check("scroll macro", BuffCheckNext.attrs.macrotext == "/use Scroll of Stamina III")
W.units.player.auras["Power Word: Fortitude"] = T + 1500
ns.refresh()
check("Fortitude covers the Stamina scroll", st.rows[1].cells[scrollCol].state == "on" and #st.scrollsDue == 0)
W.units.player.auras["Power Word: Fortitude"] = nil
W.units.player.auras["Stamina"] = T + 1500
ns.refresh()
check("the scroll buff is on", st.rows[1].cells[scrollCol].state == "on")
BAG = { "Linen Cloth" }
ev.scripts.OnEvent(ev, "BAG_UPDATE_DELAYED")
ns.refresh()
local any = false
for _, def in ipairs(st.cols) do if def.scroll then any = true end end
check("no scrolls: no column", not any)
local M2 = ns.logic
check("warrior: no Intellect scroll", next((M2.bagScrolls({ "Scroll of Intellect" }, "WARRIOR"))) == nil)
check("warrior: Strength scroll", M2.bagScrolls({ "Scroll of Strength II" }, "WARRIOR").Strength.rank == 2)
check("priest reads an Intellect scroll", M2.scrollsDue(M2.bagScrolls({ "Scroll of Intellect" }, "PRIEST"), {}, "fort")[1] ~= nil)

-- Bags seen in game (a level 18 mage): two staff imbues,
-- Agility and Intellect. Agility is no use to a mage and Arcane Intellect
-- beats the Intellect scroll, so only the imbues can count.
BAG = { "Scroll of Imbue Frost", "Scroll of Imbue Striking", "Scroll of Agility", "Scroll of Intellect", "Goaz Scrolls" }
local BAG_IDS = { 277485, 277486, 3012, 955, 209848 }
C_Container.GetContainerItemInfo = function(bag, slot)
  if bag == 0 and BAG[slot] then return { itemID = BAG_IDS[slot], itemName = BAG[slot], stackCount = 1 } end
end
local HAND = { id = nil, enchant = false }
function UnitLevel() return 18 end
function GetInventoryItemID(_, slot) return slot == 16 and HAND.id or nil end
C_Item = { GetItemInfoInstant = function(id)
  local sub = ({ [1] = 10, [2] = 15 })[id]
  if sub then return id, "Weapon", "", "", 0, 2, sub end
end }
function GetWeaponEnchantInfo() return HAND.enchant end
HAND.id = 2   -- a dagger
ev.scripts.OnEvent(ev, "BAG_UPDATE_DELAYED")
ns.refresh()
scrollCol = nil
for c, def in ipairs(st.cols) do if def.scroll then scrollCol = c end end
check("no usable scroll: grey, not green", scrollCol and st.rows[1].cells[scrollCol].state == "none")
local why = {}
for _, sk in ipairs(st.scrollsSkipped) do why[sk.name] = sk.why end
check("imbue needs a staff", why["Scroll of Imbue Frost"] == "needs a staff in your main hand")
check("Agility is no use to a mage", why["Scroll of Agility"] == "no use to your class")
check("Arcane Intellect beats the Intellect scroll", why["Scroll of Intellect"] == "your Arcane Intellect is better")
check("Goaz Scrolls is not a scroll", why["Goaz Scrolls"] == nil)
HAND.id = 1   -- a staff
ns.refresh()
check("staff: imbue due", st.rows[1].cells[scrollCol].state == "off" and st.scrollsDue[1].def.imbue)
check("imbue macro applies it to the main hand", BuffCheckNext.attrs.macrotext:find("^/use Scroll of Imbue %a+\n/use 16$") ~= nil)
HAND.enchant = true
ns.refresh()
check("staff with an imbue: on", st.rows[1].cells[scrollCol].state == "on")
check("a level 25 imbue waits", ns.logic.bagScrolls({ "Scroll of Imbue Flame" },
  { class = "MAGE", ids = { ["Scroll of Imbue Flame"] = 277497 }, level = 18, weapon = 10 }).Imbue == nil)

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
print("all passed")
