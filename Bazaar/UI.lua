-- Bazaar window: categories on the left, a search box and level and price
-- filters on top, sortable columns (click a header; click again to turn
-- the order round), mouse wheel to scroll. Hover a row for the item;
-- Shift+click links it in chat. /bazaar (or /ahb) opens it; Esc closes it.
local B = Bazaar
local call, api = B.call, B.api

local W, H = 0, 500
local ROW_H, ROWS = 18, 20
local CAT_W = 170
local COLS = { -- key, title, width, right-aligned
  { "name", "Item", 210 }, { "req", "Lvl", 35, true }, { "listed", "Listed", 55, true },
  { "min", "Cheapest", 80, true }, { "fair", "Fair price", 80, true }, { "sold", "Sold 2d", 55, true },
  { "profit", "Profit", 95, true },
}
-- The window fits its columns: categories, the icon, the columns, and the
-- frame's border.
for _, c in ipairs(COLS) do W = W + c[3] end
W = CAT_W + 10 + ROW_H + 4 + W + 30

local frame, rows, catButtons, headers = nil, {}, {}, {}
local view = { filter = {}, sort = "sold", desc = true, top = 1, list = {}, open = {} }
B.view = view

local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }

B.HOW = { craft = "one craft (reagents at AH prices, made item at its sale price)",
  flip = "buy the cheapest, sell again at the fair price after the 5% AH cut",
  vendor = "buy the cheapest, sell to a vendor" }

local function moneyOr(v) return v and B.money(v) or "|cff9d9d9d-|r" end

function B.paint()
  if not frame then return end
  local list = view.list
  view.top = math.max(1, math.min(view.top, math.max(1, #list - ROWS + 1)))
  for i = 1, ROWS do
    local row, r = rows[i], list[view.top + i - 1]
    row.data = r
    if r then
      row.icon:SetTexture(r.icon)
      row.cells.name:SetText((QUALITY[r.quality or 1] or "") .. r.name .. "|r")
      row.cells.req:SetText(r.req and r.req > 0 and r.req or "")
      row.cells.listed:SetText(r.listed or "")
      row.cells.min:SetText(moneyOr(r.min))
      row.cells.fair:SetText(moneyOr(r.fair))
      row.cells.profit:SetText(r.profit and ((r.profit >= 0 and "|cff40ff40+" or "|cffff6060-") .. B.money(math.abs(r.profit))
        .. (r.how == "craft" and " |cff9d9d9dcraft|r" or "") .. "|r") or "")
      row.cells.sold:SetText(r.sold and ((r.sold > 0 and "|cff40ff40" or "|cff9d9d9d") .. r.sold .. "|r") or "")
      row:Show()
    else
      row:Hide()
    end
  end
  for _, h in ipairs(headers) do
    local arrow = h.key == view.sort and (view.desc and " v" or " ^") or ""
    h.text:SetText(h.title .. arrow)
  end
  local done, total = B.progress()
  local status = B.sourceText()
  if done < total then status = string.format("Reading the scan: %d%%", math.floor(100 * done / total)) end
  frame.status:SetText(status .. string.format("   |cff9d9d9d%d shown|r", #list))
end

function B.refresh()
  view.list = B.query(view.filter, view.sort, view.desc)
  B.paint()
end

-- The category list: classes, and the subclasses of the open class.
function B.paintCategories()
  if not frame then return end
  local items = { { label = "All", count = #(B.current() and B.current().rows or {}) } }
  for _, c in ipairs(B.categories()) do
    table.insert(items, { label = c.name, count = c.count, classID = c.classID })
    if view.open[c.classID] then
      for _, s in ipairs(c.subs) do
        table.insert(items, { label = "   " .. s.name, count = s.count, classID = c.classID, subclassID = s.subclassID })
      end
    end
  end
  local f = view.filter
  for i, btn in ipairs(catButtons) do
    local it = items[i]
    btn.item = it
    if it then
      local on = it.classID == f.classID and it.subclassID == f.subclassID
      btn.text:SetText((on and "|cffffd100" or "") .. it.label .. " |cff9d9d9d" .. it.count .. "|r")
      btn:Show()
    else
      btn:Hide()
    end
  end
end

local function readNumber(box)
  local n = tonumber(box:GetText())
  return n
end

local function applyFilters()
  local f = view.filter
  f.text = frame.search:GetText()
  f.minReq, f.maxReq = readNumber(frame.minLvl), readNumber(frame.maxLvl)
  local g = readNumber(frame.maxPrice)
  f.maxPrice = g and g * 10000 or nil
  view.top = 1
  B.refresh()
end

local function editBox(parent, w, label, numeric)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(w, 20)
  box:SetAutoFocus(false)
  if numeric then box:SetNumeric(true) end
  box:SetScript("OnTextChanged", function(_, user) if user then applyFilters() end end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  if label then
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("RIGHT", box, "LEFT", -8, 0)
    t:SetText(label)
  end
  return box
end

-- Reads the scan in slices while the window is open.
local function onUpdate()
  if not B.step(4) then
    if frame then B.paint() end
    return
  end
  frame:SetScript("OnUpdate", nil)
  B.paintCategories()
  B.refresh()
end

function B.build()
  if frame then return frame end
  frame = CreateFrame("Frame", "BazaarFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(W, H)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  if type(frame.TitleText) == "table" then frame.TitleText:SetText("Bazaar: AH Browser") end
  table.insert(UISpecialFrames, "BazaarFrame")

  frame.search = editBox(frame, 200, "Search")
  frame.search:SetPoint("TOPLEFT", frame, "TOPLEFT", CAT_W + 70, -32)
  frame.minLvl = editBox(frame, 30, "Level", true)
  frame.minLvl:SetPoint("LEFT", frame.search, "RIGHT", 60, 0)
  frame.maxLvl = editBox(frame, 30, "-", true)
  frame.maxLvl:SetPoint("LEFT", frame.minLvl, "RIGHT", 20, 0)
  frame.maxPrice = editBox(frame, 50, "Max gold", true)
  frame.maxPrice:SetPoint("LEFT", frame.maxLvl, "RIGHT", 80, 0)

  -- Categories.
  for i = 1, ROWS + 2 do
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(CAT_W - 10, ROW_H)
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -60 - (i - 1) * ROW_H)
    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("LEFT", 4, 0)
    btn.text:SetJustifyH("LEFT")
    btn:SetScript("OnClick", function(self)
      local it, f = self.item, view.filter
      if not it then return end
      if it.classID and not it.subclassID then view.open[it.classID] = not view.open[it.classID] end
      f.classID, f.subclassID = it.classID, it.subclassID
      view.top = 1
      B.paintCategories()
      B.refresh()
    end)
    catButtons[i] = btn
  end

  -- Column headers.
  local x = CAT_W + 10
  for i, c in ipairs(COLS) do
    local h = CreateFrame("Button", nil, frame)
    h:SetSize(c[3], ROW_H)
    h:SetPoint("TOPLEFT", frame, "TOPLEFT", x + (i == 1 and ROW_H + 4 or 0), -60)
    h.key, h.title = c[1], c[2]
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.text:SetAllPoints()
    h.text:SetJustifyH(c[4] and "RIGHT" or "LEFT")
    h:SetScript("OnClick", function(self)
      if view.sort == self.key then view.desc = not view.desc
      else view.sort, view.desc = self.key, self.key ~= "name" and self.key ~= "min" and self.key ~= "req" end
      B.refresh()
    end)
    headers[i] = h
    x = x + c[3] + (i == 1 and ROW_H + 4 or 0)
  end

  -- Rows.
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(x - CAT_W - 10, ROW_H)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", CAT_W + 10, -60 - i * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 2, ROW_H - 2)
    row.icon:SetPoint("LEFT", 0, 0)
    row.cells = {}
    local cx = ROW_H + 4
    for _, c in ipairs(COLS) do
      local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      t:SetSize(c[3], ROW_H)
      t:SetPoint("LEFT", row, "LEFT", cx, 0)
      t:SetJustifyH(c[4] and "RIGHT" or "LEFT")
      row.cells[c[1]] = t
      cx = cx + c[3]
    end
    row:SetScript("OnEnter", function(self)
      if not self.data then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink("item:" .. self.data.id)
      local how = B.HOW[self.data.how]
      if how then GameTooltip:AddLine("Bazaar profit: " .. how, 0.6, 0.6, 0.6, true) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
      if self.data and IsShiftKeyDown and IsShiftKeyDown() then
        local _, link = call(api("C_Item.GetItemInfo") or rawget(_G, "GetItemInfo"), self.data.id)
        if link then call(rawget(_G, "ChatEdit_InsertLink"), link) end
      end
    end)
    rows[i] = row
  end

  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, d)
    view.top = view.top - d * 3
    B.paint()
  end)

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
  frame.status:SetJustifyH("LEFT")

  -- Item names that arrive from the server fill their rows (repainted at
  -- most twice a second).
  local pending = false
  frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  frame:SetScript("OnEvent", function(_, _, id)
    if B.fillName(id) and not pending then
      pending = true
      call(api("C_Timer.After"), 0.5, function()
        pending = false
        if frame:IsShown() then B.paintCategories() B.refresh() end
      end)
    end
  end)
  return frame
end

function B.open(text)
  B.build()
  frame:Show()
  if text then
    frame.search:SetText(text)
    view.filter.text = text
  end
  B.begin()
  if B.step(4) then
    B.paintCategories()
    B.refresh()
  else
    frame:SetScript("OnUpdate", onUpdate)
  end
end

function B.toggle()
  if frame and frame:IsShown() then frame:Hide() else B.open() end
end

SLASH_BAZAAR1, SLASH_BAZAAR2 = "/bazaar", "/ahb"
SlashCmdList.BAZAAR = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  if msg == "" then B.toggle() else B.open(msg) end
end
