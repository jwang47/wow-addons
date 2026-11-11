-- Workbench: one window for crafting. Every recipe of your professions by
-- profit, or by what a skill point costs. /wb shows or hides it; it also
-- opens beside the profession window (/wb dock turns that off).
--
-- The recipes, costs and sale prices are UpgradeFinder's
-- (UpgradeFinderAPI.known). UpgradeFinder reads them when you open a
-- profession window or a trainer; Workbench only sorts and shows them.
local addonName, ns = ...
local L = ns.logic

local W, LINE_H, PAD, ROWS = 430, 16, 10, 16
local COL = { cost = 62, sale = 70, last = 70 }
local GOLD, GREY, GREEN, RED = "|cffffd100", "|cff9d9d9d", "|cff40ff40", "|cffff5959"
local R = "|r"

local function G(name) return rawget(_G, name) end
local function say(msg)
  local chat = G("DEFAULT_CHAT_FRAME")
  if chat then chat:AddMessage(GOLD .. "Workbench:" .. R .. " " .. tostring(msg)) end
end
ns.say = say

local defaults = { view = "profit", trainer = false, dock = true }
local function db()
  if type(WorkbenchDB) ~= "table" then WorkbenchDB = {} end
  for k, v in pairs(defaults) do if WorkbenchDB[k] == nil then WorkbenchDB[k] = v end end
  return WorkbenchDB
end
ns.db = db

-- UpgradeFinder's saved recipes, or nil with the reason.
function ns.known()
  local uf = G("UpgradeFinderAPI")
  if type(uf) ~= "table" or type(uf.known) ~= "function" then
    return nil, "This needs a newer UpgradeFinder (one with the recipe list)."
  end
  local ok, list = pcall(uf.known)
  if not ok or type(list) ~= "table" then return nil, "UpgradeFinder could not list your recipes." end
  if #list == 0 then return list, "Open your profession window once, so UpgradeFinder can read your recipes." end
  return list
end

local frame, lines, summary, buttons
local view = { rows = {}, offset = 0, profs = {}, auto = false }

local function opts()
  local d = db()
  return { prof = d.prof, view = d.view, trainer = d.trainer }
end

local function colour(c)
  return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

function ns.draw()
  if not frame then return end
  local d = db()
  for i = 1, ROWS do
    local line, r = lines[i], view.rows[view.offset + i]
    line.row = r
    if not r then
      line:Hide()
    else
      local name, cost, sale, last, good = L.cells(r, d.view)
      local c = r.source == "trainer" and GREY or (L.COLOUR[r.kind or ""] and colour(L.COLOUR[r.kind]) or "|cffffffff")
      line.name:SetText(c .. name .. R)
      line.cost:SetText(cost)
      line.sale:SetText(sale)
      line.last:SetText((good == true and GREEN or good == false and RED or "") .. last .. (good ~= nil and R or ""))
      line:Show()
    end
  end
  buttons.prof:SetText(d.prof or "All professions")
  buttons.view:SetText(d.view == "skill" and "Skill-ups" or "Profit")
  buttons.trainer:SetText(d.trainer and "With trainer" or "My recipes")
  frame.lastHead:SetText(d.view == "skill" and "A point" or "Profit")
  local more = #view.rows - ROWS
  summary:SetText((view.note or L.summary(view.rows, opts(), view.profs))
    .. (more > 0 and (GREY .. "  (scroll: " .. more .. " more)" .. R) or ""))
end

-- Read UpgradeFinder's list again and redraw.
function ns.refresh()
  if not frame or not frame:IsShown() then return end
  local d = db()
  local known, note = ns.known()
  view.note = note
  view.profs = L.professions(known)
  -- A saved profession you no longer have: show all.
  local found = false
  for _, p in ipairs(view.profs) do if p.name == d.prof then found = true end end
  if not found then d.prof = nil end
  view.rows = L.rows(known, opts())
  view.offset = math.max(0, math.min(view.offset, math.max(0, #view.rows - ROWS)))
  ns.draw()
end

-- The next profession after the one shown; after the last comes "all".
function ns.nextProf(current, profs)
  if not current then return profs[1] and profs[1].name or nil end
  for i, p in ipairs(profs) do
    if p.name == current then return profs[i + 1] and profs[i + 1].name or nil end
  end
  return nil
end

local function rowTooltip(line)
  local r, t = line.row, G("GameTooltip")
  if not r or not t then return end
  t:SetOwner(line, "ANCHOR_RIGHT")
  if r.product and t.SetHyperlink then t:SetHyperlink("item:" .. r.product) else t:AddLine(r.name) end
  t:AddLine(" ")
  t:AddDoubleLine("Cost to craft", (r.cost and L.money(r.cost) or "?") .. (r.unknown and " +? (a reagent has no price)" or ""),
    1, 0.82, 0, 1, 1, 1)
  if r.sale then
    t:AddDoubleLine("Sells for", (r.how == "vendor" and "" or "~") .. L.money(r.sale) .. " " .. tostring(r.how), 1, 0.82, 0, 1, 1, 1)
  end
  if r.profit then
    local win = r.profit >= 0
    t:AddDoubleLine(win and "Profit" or "Loss", L.money(math.abs(r.profit)), 1, 0.82, 0, win and 0.3 or 1, win and 1 or 0.35,
      win and 0.3 or 0.35)
  end
  local point, chance = L.perPoint(r)
  if point then
    t:AddDoubleLine("A skill point", point <= 0 and "free: the craft pays for itself"
      or ("about " .. L.money(point) .. (chance < 1 and string.format(" (%d%% a craft, a guess)", chance * 100) or "")),
      1, 0.82, 0, 1, 1, 1)
  elseif r.kind == "trivial" then
    t:AddLine("Grey: no skill points", 0.6, 0.6, 0.6)
  end
  if r.source == "trainer" then
    t:AddLine(L.canLearn(r) and "Your trainer teaches this now." or ("Your trainer teaches this at skill " .. tostring(r.req) .. "."),
      0.6, 0.6, 0.6)
  end
  if r.product then t:AddLine("Shift-click: link the item in chat", 0.6, 0.6, 0.6) end
  t:Show()
end

local function rowClick(line)
  local r = line.row
  local shift, insert = G("IsShiftKeyDown"), G("ChatEdit_InsertLink")
  if not (r and r.product and shift and shift() and insert) then return end
  local info = C_Item and C_Item.GetItemInfo
  local ok, _, link = pcall(info, r.product)
  if ok and link then insert(link) end
end

local function button(parent, width, onClick, tip)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 20)
  b:SetScript("OnClick", function() onClick() ns.refresh() end)
  b:SetScript("OnEnter", function(self)
    local t = G("GameTooltip")
    if not t then return end
    t:SetOwner(self, "ANCHOR_TOP")
    t:AddLine(tip, 1, 1, 1, true)
    t:Show()
  end)
  b:SetScript("OnLeave", function() local t = G("GameTooltip") if t then t:Hide() end end)
  return b
end

local function text(parent, font, justify, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  if width then fs:SetWidth(width) end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

local function build()
  if frame then return frame end
  frame = CreateFrame("Frame", "WorkbenchFrame", G("UIParent"), G("BackdropTemplateMixin") and "BackdropTemplate" or nil)
  frame:SetSize(W, PAD * 2 + 78 + ROWS * LINE_H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("MEDIUM")
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0, 0, 0, 0.9)
  end
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint(1)
    db().pos = { point, rel, x, y }
  end)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    view.offset = math.max(0, math.min(math.max(0, #view.rows - ROWS), view.offset - delta * 3))
    ns.draw()
  end)
  -- Prices and colours change while it is open: look again now and then.
  local acc = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 3 then acc = 0 ns.refresh() end
  end)
  local special = G("UISpecialFrames")
  if type(special) == "table" then table.insert(special, "WorkbenchFrame") end

  local title = text(frame, "GameFontNormal")
  title:SetPoint("TOPLEFT", PAD, -PAD)
  title:SetText("Workbench")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  buttons = {}
  buttons.prof = button(frame, 130, function()
    db().prof = ns.nextProf(db().prof, view.profs)
    view.offset = 0
  end, "Which profession to show. Click for the next one.")
  buttons.prof:SetPoint("TOPLEFT", PAD, -(PAD + 18))
  buttons.view = button(frame, 90, function()
    db().view = db().view == "skill" and "profit" or "skill"
    view.offset = 0
  end, "Profit: what one craft earns, best first. Skill-ups: what one skill point costs, cheapest first.")
  buttons.view:SetPoint("LEFT", buttons.prof, "RIGHT", 6, 0)
  buttons.trainer = button(frame, 100, function()
    db().trainer = not db().trainer
    view.offset = 0
  end, "My recipes: the ones you know. With trainer: also the ones a trainer you visited teaches.")
  buttons.trainer:SetPoint("LEFT", buttons.view, "RIGHT", 6, 0)

  summary = text(frame, "GameFontHighlightSmall", "LEFT", W - PAD * 2)
  summary:SetPoint("TOPLEFT", PAD, -(PAD + 44))

  local headY = -(PAD + 60)
  local function head(label, right)
    local fs = text(frame, "GameFontNormalSmall", "RIGHT", 70)
    fs:SetPoint("TOPRIGHT", -(PAD + right), headY)
    fs:SetText(label)
    return fs
  end
  local recipe = text(frame, "GameFontNormalSmall")
  recipe:SetPoint("TOPLEFT", PAD + 2, headY)
  recipe:SetText("Recipe")
  head("Cost", COL.sale + COL.last)
  head("Sells for", COL.last)
  frame.lastHead = head("Profit", 0)

  lines = {}
  for i = 1, ROWS do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(W - PAD * 2, LINE_H)
    b:SetPoint("TOPLEFT", PAD, headY - 14 - (i - 1) * LINE_H)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.08)
    b.name = text(b, nil, "LEFT", W - PAD * 2 - COL.cost - COL.sale - COL.last - 6)
    b.name:SetPoint("LEFT", 2, 0)
    b.last = text(b, nil, "RIGHT", COL.last)
    b.last:SetPoint("RIGHT", 0, 0)
    b.sale = text(b, nil, "RIGHT", COL.sale)
    b.sale:SetPoint("RIGHT", -COL.last, 0)
    b.cost = text(b, nil, "RIGHT", COL.cost)
    b.cost:SetPoint("RIGHT", -(COL.last + COL.sale), 0)
    b:SetScript("OnEnter", rowTooltip)
    b:SetScript("OnLeave", function() local t = G("GameTooltip") if t then t:Hide() end end)
    b:SetScript("OnClick", rowClick)
    lines[i] = b
  end
  frame:Hide()
  return frame
end

-- Beside the profession window when it is open, else where you dragged it.
local function place()
  local prof = G("ProfessionsFrame") or G("TradeSkillFrame")
  frame:ClearAllPoints()
  if prof and prof.IsShown and prof:IsShown() then
    frame:SetPoint("TOPLEFT", prof, "TOPRIGHT", 4, 0)
    return
  end
  local pos = db().pos
  if pos then frame:SetPoint(pos[1], G("UIParent"), pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER") end
end

function ns.show(auto)
  build()
  view.auto = auto or false
  place()
  frame:Show()
  ns.refresh()
end

function ns.hide() if frame then frame:Hide() end end

function ns.toggle()
  if frame and frame:IsShown() then ns.hide() else ns.show(false) end
end
Workbench_Toggle = ns.toggle

SLASH_WORKBENCH1 = "/wb"
SLASH_WORKBENCH2 = "/workbench"
SlashCmdList = SlashCmdList or {}
SlashCmdList.WORKBENCH = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  local d = db()
  if cmd == "" then ns.toggle()
  elseif cmd == "profit" or cmd == "skill" then
    d.view = cmd
    ns.show(false)
  elseif cmd == "dock" then
    d.dock = not d.dock
    say(d.dock and "opens beside your profession window." or "opens only with /wb.")
  elseif cmd == "reset" then
    d.pos = nil
    if frame then place() end
    say("window moved back.")
  else
    say("/wb: show or hide. /wb profit, /wb skill: pick the view. /wb dock: open beside the profession window or not. "
      .. "/wb reset: move the window back.")
  end
end

local ev = CreateFrame("Frame")
ns.ev = ev
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_CLOSE")
ev:SetScript("OnEvent", function(_, event)
  local ok, err = pcall(function()
    if event == "TRADE_SKILL_SHOW" then
      if not db().dock then return end
      -- A moment later: the window has its place, and UpgradeFinder has
      -- read the recipes (it waits a second after the window's events).
      local function open()
        local prof = G("ProfessionsFrame") or G("TradeSkillFrame")
        if not (prof and prof.IsShown and prof:IsShown()) then return end
        -- Show the profession whose window is open.
        local ts = G("C_TradeSkillUI")
        local ok, info = pcall(function() return ts.GetBaseProfessionInfo() end)
        local name = ok and type(info) == "table" and info.professionName or nil
        if type(name) == "string" and name ~= "" and db().prof ~= name then
          db().prof = name
          view.offset = 0
        end
        if not (frame and frame:IsShown()) then ns.show(true) else ns.refresh() end
      end
      local timer = G("C_Timer")
      if timer and timer.After then timer.After(1.5, open) else open() end
    elseif event == "TRADE_SKILL_CLOSE" then
      if view.auto then ns.hide() end
    end
  end)
  if not ok and not ns.reported then
    ns.reported = true
    say("error: " .. tostring(err))
  end
end)
