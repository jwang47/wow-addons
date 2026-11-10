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
C.INTO = "Make into "
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

---------------------------------------------------------------------------
-- Item names. A recipe names its reagents and its made item by name, and
-- the game finds an item by name only when the client has seen it. So the
-- names of the items in the Auctionator scan are learned once in the
-- background and saved (UpgradeFinderDB.names[name] = id).
---------------------------------------------------------------------------
local function names()
  local db = ns.db()
  db.names = db.names or {}
  return db.names
end

function C.learn(name, id)
  if type(name) == "string" and type(id) == "number" then names()[name] = id end
end

-- The item ID for a name, or nil (then C.learnNames runs once).
function C.idByName(name)
  local it = info(name)
  if it and it.id then C.learn(name, it.id) return it.id end
  local id = names()[name]
  if id then return id end
  C.learnNames()
  return nil
end

-- Per step: up to NAME_LOOKUPS names read from the client cache (cheap) and
-- up to NAME_BATCH items asked from the server.
C.NAME_BATCH, C.NAME_LOOKUPS, C.NAME_WAIT, C.NAME_TRIES, C.NAME_COOLDOWN = 150, 2000, 1.5, 3, 60
local learning = nil -- { queue, tries } while the names load
local learnedAt = nil -- when the last pass ended; a new scan can add names
function C.learnNames()
  if learning then return end
  local now = call(rawget(_G, "time"))
  if learnedAt and now and now - learnedAt < C.NAME_COOLDOWN then return end
  local db = api("Auctionator.Database.db")
  if type(db) ~= "table" then return end
  local known, queue = {}, {}
  for _, id in pairs(names()) do known[id] = true end
  for key in pairs(db) do
    -- Gear is keyed "g:12345:20"; reagents and made items without a level are plain.
    local id = tonumber(key)
    if id and not known[id] then table.insert(queue, id) end
  end
  learning = { queue = queue, tries = {} }
  local function step()
    local q, again = learning.queue, {}
    local n, looked = 0, 0
    while #q > 0 and n < C.NAME_BATCH and looked < C.NAME_LOOKUPS do
      local id = table.remove(q)
      looked = looked + 1
      local it = info(id)
      if it and it.name then C.learn(it.name, id)
      else
        learning.tries[id] = (learning.tries[id] or 0) + 1
        if learning.tries[id] <= C.NAME_TRIES then
          n = n + 1
          call(api("C_Item.RequestLoadItemDataByID"), id)
          table.insert(again, id)
        end
      end
    end
    for _, id in ipairs(again) do table.insert(q, 1, id) end
    local after = api("C_Timer.After")
    if #q > 0 and after then after(C.NAME_WAIT, step)
    else learning, learnedAt = nil, call(rawget(_G, "time")) end
  end
  step()
end

-- "names: 1234 learned, 56 still loading" for /uf craft names.
function C.namesStatus()
  local n = 0
  for _ in pairs(names()) do n = n + 1 end
  local left = learning and #learning.queue or 0
  return string.format("item names: %d learned%s", n, left > 0 and (", " .. left .. " still loading") or "")
end

-- What the reagents cost: { total, missing = { names }, parts }. Each
-- reagent is { id or name, count, name } and costs its AH price or the
-- vendor's price when that is lower (Scan.priceOf).
function C.cost(reagents)
  local out = { total = 0, missing = {}, parts = {} }
  for _, r in ipairs(reagents or {}) do
    local item = r[1]
    if type(item) == "string" then item = C.idByName(item) or item end
    local each, from = Scan.priceOf(item)
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
  if type(item) == "string" then item = C.idByName(item) or item end
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
    local t = fs and fs.GetText and fs:GetText()
    if t == C.LABEL or (type(t) == "string" and t:find("^" .. C.INTO)) then return true end
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
  local made, reagents, bop, craft = Scan.recipeParts(lines)
  if not made or #reagents == 0 then return nil end
  local skill, rank
  if craft then skill, rank = craft:match(Scan.PROFESSION) end
  recipes[id] = { made = made, reagents = reagents, bop = bop, skill = skill, rank = tonumber(rank) }
  return recipes[id]
end

-- The numbers for one recipe item, for other addons (Omni lists recipes by
-- profit): { made, skill, rank, cost, unknown, sale, how, profit }. nil
-- while the recipe's tooltip is still loading or it is not a recipe.
-- profit is nil when the made item has no price.
function C.summary(id)
  local r = C.recipe(id)
  if not r then return nil end
  local cost = C.cost(r.reagents)
  local out = { made = r.made, skill = r.skill, rank = r.rank, cost = cost.total, unknown = #cost.missing > 0 }
  if not r.made:match("^Enchant ") then
    local sale = C.sale(r.made, r.bop)
    if sale then
      out.sale, out.how = sale.best, sale.how
      if cost.total > 0 or not out.unknown then out.profit = sale.best - cost.total end
    end
  end
  return out
end

-- product: the made item's id when the caller knows it (the game's recipe
-- tooltip reports it), else it is found by name.
function C.forRecipe(id, product)
  local r = C.recipe(id)
  if not r then return nil end
  -- Enchanting formulas make no item: show the cost only.
  local enchant = r.made:match("^Enchant ") ~= nil
  local score
  if Scan.item(id) and Scan.cache[id] then score = Scan.cache[id] end
  return C.lines({ reagents = r.reagents, product = product or r.made, bop = r.bop, enchant = enchant, score = score })
end

-- The recipe a tooltip shows. On a recipe tooltip GetItem gives the item
-- it makes, so also try the tooltip data id and the first line (the
-- recipe's name). Returns the recipe id, or nil when the item is not a recipe.
local function isRecipe(id)
  local instant = api("C_Item.GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
  return id and select(6, call(instant, id)) == Scan.RECIPE_CLASS
end
function C.recipeOf(tt, data)
  local _, link = tt:GetItem()
  local name = tt.GetName and tt:GetName()
  local fs = name and rawget(_G, name .. "TextLeft1")
  local first = fs and fs.GetText and fs:GetText()
  local byName = first and info(first)
  for _, id in ipairs({ type(data) == "table" and tonumber(data.id) or false, idOf(link) or false,
    byName and byName.id or false }) do
    if id and isRecipe(id) then return id end
  end
end

local function onTooltip(tt, data)
  if not (tt and tt.GetItem) or not on() then return end
  if tt == rawget(_G, "UpgradeFinderScanTooltip") then return end
  local id = C.recipeOf(tt, data)
  if not id then
    -- Not a recipe: a material you can make into something ("Make into").
    local _, link = tt:GetItem()
    local item = idOf(link)
    local lines = item and not hasLines(tt) and C.forMaterial(item)
    if lines and #lines > 0 then add(tt, lines) end
    return
  end
  if hasLines(tt) then return end
  local _, link = tt:GetItem()
  local made = idOf(link)
  if made == id or isRecipe(made) then made = nil end
  local lines = C.forRecipe(id, made)
  if lines then add(tt, lines) end
end

---------------------------------------------------------------------------
-- Transformations: a material you can make into another item with one
-- reagent (Silk Cloth -> Bolt of Silk Cloth, ore -> bar). The tooltip of the
-- material says what one craft gains or loses. The recipes come from your
-- profession windows (saved in UpgradeFinderDB.recipes); the cloth bolts
-- are built in, so they show before you open Tailoring.
---------------------------------------------------------------------------
-- [made item id] = { reagent id, count }
C.BUILT_IN = {
  [2996] = { 2589, 2 },   -- Bolt of Linen Cloth: 2 Linen Cloth
  [2997] = { 2592, 3 },   -- Bolt of Woolen Cloth: 3 Wool Cloth
  [4305] = { 4306, 4 },   -- Bolt of Silk Cloth: 4 Silk Cloth
  [4339] = { 4338, 5 },   -- Bolt of Mageweave: 5 Mageweave Cloth
  [14048] = { 14047, 5 }, -- Bolt of Runecloth: 5 Runecloth
}

local function recipesDB()
  local db = ns.db()
  db.recipes = db.recipes or {}
  return db.recipes
end

-- Saves a recipe from the profession window: made item -> { reagents = {
-- { id, count } }, made }.
function C.saveRecipe(product, reagents, made)
  if not product or #reagents == 0 then return end
  local r = { reagents = {}, made = made or 1 }
  for _, x in ipairs(reagents) do
    if type(x[1]) ~= "number" then return end -- a reagent not loaded yet: next time
    table.insert(r.reagents, { x[1], x[2] })
  end
  recipesDB()[product] = r
end

-- Every recipe of the open profession window.
function C.readTradeSkills()
  local g = function(n) return rawget(_G, n) end
  for i = 1, call(g("GetNumTradeSkills")) or 0 do
    local _, kind = call(g("GetTradeSkillInfo"), i)
    if kind ~= "header" then
      local product = idOf(call(g("GetTradeSkillItemLink"), i))
      local reagents = {}
      for r = 1, call(g("GetTradeSkillNumReagents"), i) or 0 do
        local name, _, count = call(g("GetTradeSkillReagentInfo"), i, r)
        local id = idOf(call(g("GetTradeSkillReagentItemLink"), i, r))
        if id and name then C.learn(name, id) end
        table.insert(reagents, { id or name, count or 1 })
      end
      local lo, hi = call(g("GetTradeSkillNumMade"), i)
      C.saveRecipe(product, reagents, ((lo or 1) + (hi or lo or 1)) / 2)
    end
  end
end

-- The transformation lines for a material: one per made item.
function C.forMaterial(id)
  local money, out = ns.money, {}
  local uses = {}
  for product, r in pairs(C.BUILT_IN) do
    if r[1] == id then uses[product] = { count = r[2], made = 1 } end
  end
  for product, r in pairs(recipesDB()) do
    if #r.reagents == 1 and r.reagents[1][1] == id then
      uses[product] = { count = r.reagents[1][2], made = r.made or 1 }
    end
  end
  for product, u in pairs(uses) do
    local each = Scan.priceOf(id)
    local sale = C.sale(product)
    local it = info(product)
    local name = it and it.name or ("item " .. product)
    local label = C.INTO .. name .. " (" .. u.count .. " each)"
    if each and sale then
      local cost = each * u.count
      local diff = sale.best * u.made - cost
      table.insert(out, { label, string.format("%s%s (%s -> %s%s)", diff >= 0 and "+" or "-", money(math.abs(diff)),
        money(cost), sale.how == "vendor" and "" or "~", money(sale.best * u.made)), GOLD, diff >= 0 and GREEN or RED })
    else
      table.insert(out, { label, "no price", GOLD, GREY })
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- Errors are reported once in chat, so a broken line does not fail silently.
local reported = false
function C.guard(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not reported then
    reported = true
    if ns.say then ns.say("crafting lines error: " .. tostring(err)) end
  end
end
C.onTooltip = function(tt, data) C.guard(onTooltip, tt, data) end

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
    if id and name then C.learn(name, id) end
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
      row:HookScript("OnEnter", function(self) C.guard(rowEnter, self) end)
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
    secure(gt, "SetTradeSkillItem", function(tt, index, reagent) C.guard(afterSetTradeSkillItem, tt, index, reagent) end)
  end
  C.hookRows()
  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", function(_, ev, name)
    if ev == "PLAYER_EQUIPMENT_CHANGED" then C.wornChanged()
    elseif ev == "PLAYER_LOGIN" then
      -- Learn the names soon after login, before the first recipe hover.
      local after = api("C_Timer.After")
      if after then after(5, function() C.guard(C.learnNames) end) end
    elseif ev == "TRADE_SKILL_SHOW" or ev == "TRADE_SKILL_UPDATE" then C.guard(C.readTradeSkills)
    elseif name == "Blizzard_TradeSkillUI" then C.hookRows() end
  end)
  pcall(f.RegisterEvent, f, "ADDON_LOADED")
  pcall(f.RegisterEvent, f, "PLAYER_EQUIPMENT_CHANGED")
  pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
  pcall(f.RegisterEvent, f, "TRADE_SKILL_SHOW")
  pcall(f.RegisterEvent, f, "TRADE_SKILL_UPDATE")
end
C.hook()
