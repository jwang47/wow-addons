-- Offline tests for Workbench with a small mock of the WoW API.
-- Run from the repo root: lua5.1 tests/workbench.lua   (fails on error)
local root = arg and arg[0]:match("^(.*)tests/workbench%.lua$") or ""
local failures, chat = 0, {}
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function check(name, cond)
  if cond then print("ok   " .. name) else failures = failures + 1 print("FAIL " .. name) end
end

local frames, events = {}, {}
local function widget(name)
  local w = { scripts = {}, shown = true, name = name }
  local methods = {
    SetScript = function(self, k, fn) self.scripts[k] = fn end,
    RegisterEvent = function(self, e) events[e] = self end,
    SetText = function(self, t) self.text = strip(t) end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    CreateFontString = function() return widget() end,
    CreateTexture = function() return widget() end,
    GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
  }
  return setmetatable(w, { __index = function(_, k) return methods[k] or function() end end })
end
function CreateFrame(_, name)
  local f = widget(name)
  if name then frames[name] = f end
  return f
end
UIParent = widget("UIParent")
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, strip(m)) end }
SlashCmdList = {}

local ns = {}
local function load(file) assert(loadfile(root .. "Workbench/" .. file))("Workbench", ns) end
load("Logic.lua")
local L = ns.logic

-- UpgradeFinder's list: Tailoring 142/150 and Enchanting 60/75.
local KNOWN = {
  { prof = "Tailoring", name = "Small Silk Pack", product = 4245, source = "known", kind = "medium", rank = 142, max = 150,
    cost = 6000, sale = 7200, how = "AH", profit = 1200 },
  { prof = "Tailoring", name = "Bolt of Silk Cloth", product = 4305, source = "known", kind = "easy", rank = 142, max = 150,
    cost = 4000, sale = 3800, how = "AH", profit = -200 },
  { prof = "Tailoring", name = "Azure Silk Hood", product = 7048, source = "known", kind = "optimal", rank = 142, max = 150,
    cost = 9000, sale = 2500, how = "vendor", profit = -6500 },
  { prof = "Tailoring", name = "Woolen Cape", product = 2584, source = "known", kind = "trivial", rank = 142, max = 150,
    cost = 900, sale = 400, how = "vendor", profit = -500 },
  { prof = "Tailoring", name = "Silk Headband", product = 7050, source = "known", kind = "optimal", rank = 142, max = 150,
    cost = 0, unknown = true },
  { prof = "Tailoring", name = "Crimson Silk Belt", product = 7055, source = "trainer", req = 175, price = 5000, rank = 142,
    max = 150, cost = 8000, sale = 3000, how = "AH", profit = -5000 },
  { prof = "Tailoring", name = "Silk Pants", product = 4316, source = "trainer", req = 140, price = 2000, rank = 142,
    max = 150, cost = 3000, sale = 2800, how = "AH", profit = -200 },
  { prof = "Enchanting", name = "Enchant Bracer - Minor Stamina", source = "known", kind = "easy", rank = 60, max = 75,
    cost = 500 },
}

check("money", L.money(19100) == "1g91s" and L.money(205) == "2s5c" and L.money(-1200) == "-12s" and L.money(nil) == "?")
local profs = L.professions(KNOWN)
check("professions by name with their rank", #profs == 2 and profs[1].name == "Enchanting" and profs[2].rank == 142)

local rows = L.rows(KNOWN, { prof = "Tailoring", view = "profit" })
check("profit: best first, no price last, trainer recipes left out", #rows == 5 and rows[1].name == "Small Silk Pack"
  and rows[2].name == "Bolt of Silk Cloth" and rows[4].name == "Azure Silk Hood" and rows[5].name == "Silk Headband")
check("profit summary", L.summary(rows, { prof = "Tailoring", view = "profit" }, profs)
  == "Tailoring 142/150: 5 recipes, 1 make a profit, best +12s (Small Silk Pack)")
rows = L.rows(KNOWN, { view = "profit", trainer = true })
check("all professions with the trainer's recipes", #rows == 8)

rows = L.rows(KNOWN, { prof = "Tailoring", view = "skill", trainer = true })
check("skill: a recipe that pays for itself is first", rows[1].name == "Small Silk Pack" and rows[1].point == -1200)
check("skill: then the cheapest expected point", rows[2].name == "Silk Pants" and rows[2].point == 200
  and rows[3].name == "Bolt of Silk Cloth" and rows[3].point == 800 and rows[4].name == "Azure Silk Hood"
  and rows[4].point == 6500)
check("skill: grey, unpriced and too-high trainer recipes are left out", #rows == 4)
check("skill summary", L.summary(rows, { prof = "Tailoring", view = "skill" }, profs)
  == "Tailoring 142/150: cheapest point free (Small Silk Pack)")
rows = L.rows(KNOWN, { prof = "Enchanting", view = "skill" })
check("skill: an enchant costs its reagents", #rows == 1 and rows[1].point == 2000 and rows[1].chance == 0.25)
check("skill summary with a cost", L.summary(rows, { prof = "Enchanting", view = "skill" }, profs)
  == "Enchanting 60/75: cheapest point about 20s (Enchant Bracer - Minor Stamina)")
check("empty summary", L.summary({}, { view = "skill" }, profs) == "All professions: no recipe gives a skill point")

local name, cost, sale, last, good = L.cells(KNOWN[1], "profit")
check("cells: profit row", name == "Small Silk Pack" and cost == "60s" and sale == "~72s" and last == "+12s" and good == true)
name, cost, sale, last, good = L.cells(KNOWN[3], "profit")
check("cells: a loss at the vendor", sale == "25s" and last == "-65s" and good == false)
name, cost, sale, last = L.cells(KNOWN[5], "profit")
check("cells: no prices", cost == "?" and sale == "-" and last == "-")
name = L.cells(KNOWN[6], "profit")
check("cells: a trainer recipe above your skill", name == "Crimson Silk Belt (at 175, 50s)")
name = L.cells(KNOWN[7], "profit")
check("cells: a trainer recipe you can learn", name == "Silk Pants (train, 20s)")
rows = L.rows(KNOWN, { prof = "Tailoring", view = "skill" })
name, cost, sale, last = L.cells(rows[2], "skill")
check("cells: a guessed chance is marked", last == "8s*")

-- The window.
load("Workbench.lua")
SlashCmdList.WORKBENCH("")
local frame = frames.WorkbenchFrame
check("/wb without UpgradeFinder's list says what is missing", frame:IsShown() and ns.known() == nil)
UpgradeFinderAPI = { known = function() return {} end }
local _, note = ns.known()
check("an empty list asks for the profession window", note:find("Open your profession window", 1, true) ~= nil)
UpgradeFinderAPI = { known = function() return KNOWN end }
ns.refresh()
check("the window lists every known recipe by profit", WorkbenchDB.view == "profit" and WorkbenchDB.prof == nil)
check("next profession cycles through to all", ns.nextProf(nil, profs) == "Enchanting"
  and ns.nextProf("Enchanting", profs) == "Tailoring" and ns.nextProf("Tailoring", profs) == nil)
SlashCmdList.WORKBENCH("skill")
check("/wb skill picks the view", WorkbenchDB.view == "skill" and frame:IsShown())
SlashCmdList.WORKBENCH("")
check("/wb hides it again", not frame:IsShown())
-- Docking: it opens beside the profession window on the open profession.
ProfessionsFrame = widget("ProfessionsFrame")
C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionName = "Tailoring" } end }
events.TRADE_SKILL_SHOW.scripts.OnEvent(nil, "TRADE_SKILL_SHOW")
check("opens with the profession window, on its profession", frame:IsShown() and WorkbenchDB.prof == "Tailoring")
events.TRADE_SKILL_CLOSE.scripts.OnEvent(nil, "TRADE_SKILL_CLOSE")
check("and closes with it", not frame:IsShown())
SlashCmdList.WORKBENCH("dock")
events.TRADE_SKILL_SHOW.scripts.OnEvent(nil, "TRADE_SKILL_SHOW")
check("/wb dock: no longer opens by itself", not frame:IsShown() and WorkbenchDB.dock == false)
WorkbenchDB.prof = "Fishing"
SlashCmdList.WORKBENCH("")
check("a profession you no longer have falls back to all", WorkbenchDB.prof == nil)

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
print("all passed")
