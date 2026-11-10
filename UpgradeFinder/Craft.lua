-- UpgradeFinder crafting lines: on a recipe item (a pattern in your bags,
-- at a vendor or on the AH) and on a recipe in your profession window, the
-- tooltip says what the reagents cost, what the made item sells for, the
-- profit or loss, and the score of the made item against what you wear.
-- Prices come from Auctionator (and LootValue's disenchant estimate when it
-- is loaded); /uf craft turns the lines off.
local _, ns = ...
local S, Scan = ns.score, ns.scan
local call, api = ns.call, ns.api
local C = {}
ns.craft = C

C.LABEL = "Cost to craft"
C.CUT = 0.95 -- the AH keeps 5% of a sale

local GOLD, GREY, BLUE = { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }, { 0.41, 0.8, 0.94 }
local GREEN, RED, WHITE = { 0.3, 1, 0.3 }, { 1, 0.35, 0.35 }, { 1, 1, 1 }

local function idOf(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end

-- Item info by id, link or name (a name works only for items the client has seen).
local function info(item)
  local get = api("C_Item.GetItemInfo") or rawget(_G, "GetItemInfo")
  local name, link, quality, ilvl, _, _, _, _, loc, _, sell, classID, _, bind = call(get,
    type(item) == "number" and ("item:" .. item) or item)
  if not link then return nil end
  return { name = name, link = link, id = idOf(link), quality = quality, ilvl = ilvl, loc = loc,
    sell = type(sell) == "number" and sell or 0, classID = classID, bind = bind, bop = bind == 1 }
end
C.info = info

-- What the reagents cost: { total, missing = { names }, parts }. Each
-- reagent is { id or name, count, name } and costs its AH price or the
-- vendor's price when that is lower (Scan.priceOf).
function C.cost(reagents)
  local out = { total = 0, missing = {}, parts = {} }
  for _, r in ipairs(reagents or {}) do
    local each, from = Scan.priceOf(r[1])
    table.insert(out.parts, { r[3] or r[1], r[2], each, from })
    if each then out.total = out.total + each * r[2]
    else table.insert(out.missing, tostring(r[3] or r[1])) end
  end
  return out
end

-- The best of what one made item brings: the AH after the cut (not for a
-- bind on pickup item), the vendor and, with Enchanting and LootValue, the
-- disenchant estimate. { best, how, ah, vendor, de } or nil when unknown.
function C.sale(item, bop)
  local it = info(item)
  if not it then return nil end
  -- The made item's own bind type wins: a bind on pickup pattern can make
  -- an item you can sell.
  if it.bind ~= nil then bop = it.bop end
  local v1 = "Auctionator.API.v1."
  local ah = not bop and (call(api(v1 .. "GetAuctionPriceByItemID"), "UpgradeFinder", it.id)
    or call(api(v1 .. "GetAuctionPriceByItemLink"), "UpgradeFinder", it.link)) or nil
  local out = { ah = ah and math.floor(ah * C.CUT) or nil, vendor = it.sell > 0 and it.sell or nil }
  local lv = rawget(_G, "LootValue")
  if type(lv) == "table" and it.loc and it.loc ~= "" and S.SLOTS[it.loc] and call(lv.knowsEnchanting) then
    local de = call(lv.call, "GetDisenchantPriceByItemLink", it.link)
    if not de or de <= 0 then de = call(lv.estimateDisenchant, it.link) end
    out.de = de and de > 0 and de or nil
  end
  for _, o in ipairs({ { "AH", out.ah }, { "vendor", out.vendor }, { "disenchant", out.de } }) do
    if o[2] and (not out.best or o[2] > out.best) then out.best, out.how = o[2], o[1] end
  end
  if not out.best then return nil end
  return out
end

-- The score of a made item and its change against what you wear. c is a
-- Scan cache entry ({ value, loc, unusable }). { value, gain, slot, note, unusable }.
local wornStale = true
function C.score(c)
  if type(c) ~= "table" or not c.loc or not c.value then return nil end
  if wornStale then Scan.readWorn() wornStale = false end
  local worn = Scan.worn()
  local base, note = S.replaced(c.loc, worn.value, worn.twoHander, worn.dualWield)
  if not base then return nil end
  return { value = c.value, gain = c.value - base, slot = S.groupName(c.loc), note = note, unusable = c.unusable }
end
function C.wornChanged() wornStale = true end

-- The lines for one recipe: { { left, right, colour, rightColour } }.
-- r = { reagents, product (id or name), made (count per craft), bop, enchant }.
function C.lines(r)
  local money = ns.money
  local out = {}
  local cost = C.cost(r.reagents)
  local unknown = #cost.missing > 0
  table.insert(out, { C.LABEL, (cost.total > 0 and money(cost.total) or "?") .. (unknown and cost.total > 0 and " +?" or ""),
    GOLD, WHITE })
  if unknown then
    table.insert(out, { "  No price: " .. table.concat(cost.missing, ", "), nil, GREY })
  end
  if not r.enchant and r.product then
    local made = r.made or 1
    local sale = C.sale(r.product, r.bop)
    if sale then
      local each = sale.best * made
      local label = made ~= 1 and string.format("Sells for (x%s)", (made % 1 == 0) and made or string.format("%.1f", made))
        or "Sells for"
      table.insert(out, { label, (sale.how == "vendor" and "" or "~") .. money(each) .. " " .. sale.how, GOLD, WHITE })
      if cost.total > 0 or not unknown then
        local diff = each - cost.total
        local text = (diff >= 0 and "+" or "-") .. money(math.abs(diff)) .. (unknown and " ?" or "")
        table.insert(out, { diff >= 0 and "Profit" or "Loss", text, GOLD, diff >= 0 and GREEN or RED })
      end
    else
      table.insert(out, { "Sells for", "no price", GOLD, GREY })
    end
  end
  local sc = r.score and C.score(r.score)
  if sc then
    local text = string.format("%.1f (%s%.1f vs %s)", sc.value, sc.gain >= 0 and "+" or "", sc.gain,
      sc.slot and ("your " .. sc.slot:lower()) or "equipped")
    if sc.unusable then text = text .. ", you can't use it" end
    table.insert(out, { "Score of the made item", text, BLUE, sc.unusable and RED or (sc.gain > 0 and GREEN or GREY) })
    if sc.note then table.insert(out, { "  " .. sc.note, nil, GREY }) end
  end
  return out
end

local function add(tt, lines)
  for _, l in ipairs(lines) do
    local a, b = l[3] or WHITE, l[4] or WHITE
    if l[2] and tt.AddDoubleLine then tt:AddDoubleLine(l[1], l[2], a[1], a[2], a[3], b[1], b[2], b[3])
    else tt:AddLine(l[1] .. (l[2] and ("  " .. l[2]) or ""), a[1], a[2], a[3]) end
  end
  if tt.Show then tt:Show() end
end

-- The game fires the item hook twice on a recipe tooltip; add the lines once.
local function hasLines(tt)
  local name = tt.GetName and tt:GetName()
  if not name or not tt.NumLines then return false end
  for i = 1, tt:NumLines() do
    local fs = rawget(_G, name .. "TextLeft" .. i)
    if fs and fs.GetText and fs:GetText() == C.LABEL then return true end
  end
  return false
end

local function on() return ns.db().opts.craft ~= false end

---------------------------------------------------------------------------
-- Recipe items
---------------------------------------------------------------------------
local recipes = {} -- [recipe id] = { made, reagents, bop }

function C.recipe(id)
  if recipes[id] then return recipes[id] end
  local lines = Scan.read(function(tt) tt:SetHyperlink("item:" .. id) end)
  if not lines then return nil end
  for _, l in ipairs(lines) do
    if l == rawget(_G, "RETRIEVING_ITEM_INFO") or l:match("^Retrieving item") then return nil end
  end
  local made, reagents, bop = Scan.recipeParts(lines)
  if not made or #reagents == 0 then return nil end
  recipes[id] = { made = made, reagents = reagents, bop = bop }
  return recipes[id]
end

function C.forRecipe(id)
  local r = C.recipe(id)
  if not r then return nil end
  -- Enchanting formulas make no item: show the cost only.
  local enchant = r.made:match("^Enchant ") ~= nil
  local score
  if Scan.item(id) and Scan.cache[id] then score = Scan.cache[id] end
  return C.lines({ reagents = r.reagents, product = r.made, bop = r.bop, enchant = enchant, score = score })
end

local function onTooltip(tt)
  if not (tt and tt.GetItem) or not on() then return end
  if tt == rawget(_G, "UpgradeFinderScanTooltip") then return end
  local _, link = tt:GetItem()
  local id = idOf(link)
  if not id then return end
  local instant = api("C_Item.GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
  if select(6, call(instant, id)) ~= Scan.RECIPE_CLASS or hasLines(tt) then return end
  local lines = C.forRecipe(id)
  if lines then add(tt, lines) end
end
C.onTooltip = function(tt) pcall(onTooltip, tt) end

---------------------------------------------------------------------------
-- The profession window (Blizzard_TradeSkillUI)
---------------------------------------------------------------------------
function C.forTradeSkill(index)
  local g = function(n) return rawget(_G, n) end
  local link = call(g("GetTradeSkillItemLink"), index)
  local reagents = {}
  for i = 1, call(g("GetTradeSkillNumReagents"), index) or 0 do
    local name, _, count = call(g("GetTradeSkillReagentInfo"), index, i)
    local id = idOf(call(g("GetTradeSkillReagentItemLink"), index, i))
    if id or name then table.insert(reagents, { id or name, count or 1, name }) end
  end
  if #reagents == 0 then return nil end
  local lo, hi = call(g("GetTradeSkillNumMade"), index)
  local made = ((lo or 1) + (hi or lo or 1)) / 2
  local id = idOf(link)
  local score
  if id and Scan.item(id) and Scan.cache[id] then score = Scan.cache[id] end
  return C.lines({ reagents = reagents, product = id, made = made, score = score })
end

-- After GameTooltip:SetTradeSkillItem(index) for the made item (not a reagent).
local function afterSetTradeSkillItem(tt, index, reagent)
  if reagent or not index or not on() or hasLines(tt) then return end
  local lines = C.forTradeSkill(index)
  if lines then add(tt, lines) end
end

-- The recipe list has no tooltip of its own: hovering a row shows the made
-- item with the crafting lines, like the icon in the detail pane.
local function rowEnter(row)
  local index = row.GetID and row:GetID()
  if not index or index == 0 or not on() then return end
  local _, kind = call(rawget(_G, "GetTradeSkillInfo"), index)
  if kind == "header" then return end
  local tt = rawget(_G, "GameTooltip")
  tt:SetOwner(row, "ANCHOR_RIGHT")
  tt:SetTradeSkillItem(index)
  tt:Show()
end
local function rowLeave(row)
  local tt = rawget(_G, "GameTooltip")
  if tt and tt.GetOwner and tt:GetOwner() == row then tt:Hide() end
end
C.rowEnter, C.rowLeave = rowEnter, rowLeave

local rowsHooked = false
function C.hookRows()
  if rowsHooked or not rawget(_G, "TradeSkillSkill1") then return end
  rowsHooked = true
  for i = 1, rawget(_G, "TRADE_SKILLS_DISPLAYED") or 8 do
    local row = rawget(_G, "TradeSkillSkill" .. i)
    if row and row.HookScript then
      row:HookScript("OnEnter", function(self) pcall(rowEnter, self) end)
      row:HookScript("OnLeave", function(self) pcall(rowLeave, self) end)
    end
  end
end

local hooked = false
function C.hook()
  if hooked then return end
  hooked = true
  local proc, enum = rawget(_G, "TooltipDataProcessor"), api("Enum.TooltipDataType.Item")
  if type(proc) == "table" and proc.AddTooltipPostCall and enum then
    proc.AddTooltipPostCall(enum, C.onTooltip)
  else
    for _, n in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
      local t = rawget(_G, n)
      if t and t.HookScript then t:HookScript("OnTooltipSetItem", C.onTooltip) end
    end
  end
  local gt, secure = rawget(_G, "GameTooltip"), rawget(_G, "hooksecurefunc")
  if gt and gt.SetTradeSkillItem and secure then
    secure(gt, "SetTradeSkillItem", function(tt, index, reagent) pcall(afterSetTradeSkillItem, tt, index, reagent) end)
  end
  C.hookRows()
  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", function(_, ev, name)
    if ev == "PLAYER_EQUIPMENT_CHANGED" then C.wornChanged()
    elseif name == "Blizzard_TradeSkillUI" then C.hookRows() end
  end)
  pcall(f.RegisterEvent, f, "ADDON_LOADED")
  pcall(f.RegisterEvent, f, "PLAYER_EQUIPMENT_CHANGED")
end
C.hook()
