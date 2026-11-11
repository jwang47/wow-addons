-- UpgradeFinder crafting lines: on a recipe item (a pattern in your bags,
-- at a vendor or on the AH) and on a recipe in your profession window, the
-- tooltip says what the reagents cost, what the made item sells for, the
-- profit or loss, and the score of the made item against what you wear.
-- Prices come from Auctionator, or with LootValue from its own full scans:
-- the fair price (outliers dropped) weighed by the chance it sells, so a
-- lone high listing or a dead market does not look like profit. /uf craft
-- turns the lines off.
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
  -- LootValue's market quote: the AH counts at its expected value (the
  -- chance it sells in 24 h), and says how sure that is.
  if not bop and type(lv) == "table" and lv.marketQuote then
    local sure = math.max(out.vendor or 0, out.de or 0)
    local q = call(lv.marketQuote, it.id, it.link, sure, out.vendor)
    if q then
      out.quote = q
      out.ah = q.expected or q.net
    end
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
      local q = sale.how == "AH" and sale.quote
      local how = sale.how
      if q and q.expected then how = "AH, expected" end
      table.insert(out, { label, (sale.how == "vendor" and "" or "~") .. money(each) .. " " .. how, GOLD, WHITE })
      -- How sure the AH price is (LootValue's scans).
      if q then
        local warn = q.confidence ~= "ok"
        table.insert(out, { "  " .. (warn and (q.confidence == "thin" and "Thin market: " or "Unsure: ") or "") .. q.note
          .. (q.expected and q.expected < q.net and ("; listed at ~" .. money(q.price)) or ""), nil, warn and RED or GREY })
      end
      if cost.total > 0 or not unknown then
        local diff = each - cost.total
        local unsure = unknown or (q and q.confidence ~= "ok")
        local text = (diff >= 0 and "+" or "-") .. money(math.abs(diff)) .. (unsure and " ?" or "")
        table.insert(out, { diff >= 0 and "Profit" or "Loss", text, GOLD, diff >= 0 and (unsure and GREY or GREEN) or RED })
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
      out.confidence = sale.how == "AH" and sale.quote and sale.quote.confidence or nil
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

-- The modern profession window (Forever uses it): C_TradeSkillUI lists
-- every recipe of the open profession, learned or not. relativeDifficulty
-- 0-3 is the skill-up colour.
C.DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
C.REREAD = 60
local lastRead = { at = -math.huge }
function C.readProfession()
  -- Blizzard's own list uses GetFilteredRecipeIDs; GetAllRecipeIDs skips
  -- the window's filters where the client has it.
  local ids = call(api("C_TradeSkillUI.GetAllRecipeIDs"))
  if type(ids) ~= "table" or #ids == 0 then ids = call(api("C_TradeSkillUI.GetFilteredRecipeIDs")) end
  if type(ids) ~= "table" or #ids == 0 then return false end
  -- The window fires its update events often (every bag change, every
  -- craft): read the same list once a minute at most.
  local now, sig = call(rawget(_G, "GetTime")) or 0, #ids .. ":" .. tostring(ids[1]) .. ":" .. tostring(ids[#ids])
  if lastRead.sig == sig and now - lastRead.at < C.REREAD then return true end
  lastRead.sig, lastRead.at = sig, now
  local list, unlearned = {}, {}
  for _, rid in ipairs(ids) do
    local r = call(api("C_TradeSkillUI.GetRecipeInfo"), rid)
    local sch = call(api("C_TradeSkillUI.GetRecipeSchematic"), rid, false)
    if type(r) == "table" and r.name and type(sch) == "table" then
      local product = sch.outputItemID
      local reagents = {}
      for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        if first and first.itemID then table.insert(reagents, { first.itemID, slot.quantityRequired or 1 }) end
      end
      C.saveRecipe(product, reagents, ((sch.quantityMin or 1) + (sch.quantityMax or sch.quantityMin or 1)) / 2)
      local entry = { product = product, kind = C.DIFFICULTY[r.relativeDifficulty] }
      if r.learned == false then unlearned[r.name] = entry else list[r.name] = entry end
    end
  end
  local p = call(api("C_TradeSkillUI.GetBaseProfessionInfo")) or call(api("C_TradeSkillUI.GetChildProfessionInfo"))
  if type(p) ~= "table" then
    local name, rank, max = call(rawget(_G, "GetTradeSkillLine"))
    p = { professionName = name, skillLevel = rank, maxSkillLevel = max }
  end
  C.saveKnown(p.professionName, p.skillLevel, p.maxSkillLevel, list, unlearned)
  return true
end

-- Every recipe of the open profession window.
function C.readTradeSkills()
  if C.readProfession() then return end
  local g = function(n) return rawget(_G, n) end
  local list = {}
  for i = 1, call(g("GetNumTradeSkills")) or 0 do
    local name, kind = call(g("GetTradeSkillInfo"), i)
    if kind ~= "header" then
      local product = idOf(call(g("GetTradeSkillItemLink"), i))
      local reagents = {}
      for r = 1, call(g("GetTradeSkillNumReagents"), i) or 0 do
        local rname, _, count = call(g("GetTradeSkillReagentInfo"), i, r)
        local id = idOf(call(g("GetTradeSkillReagentItemLink"), i, r))
        if id and rname then C.learn(rname, id) end
        table.insert(reagents, { id or rname, count or 1 })
      end
      local lo, hi = call(g("GetTradeSkillNumMade"), i)
      C.saveRecipe(product, reagents, ((lo or 1) + (hi or lo or 1)) / 2)
      if name then list[name] = { product = product, kind = kind } end
    end
  end
  local prof, rank, max = call(g("GetTradeSkillLine"))
  C.saveKnown(prof, rank, max, list)
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

---------------------------------------------------------------------------
-- The recipes you know and the ones your trainer teaches, for other
-- addons (Omni: "tailoring"). The profession window saves what you know
-- (UpgradeFinderDB.known[profession]); a trainer window saves what it
-- teaches (UpgradeFinderDB.trainer[profession]). Neither is in the game
-- API while the window is closed.
---------------------------------------------------------------------------
local function dbTable(key)
  local db = ns.db()
  db[key] = db[key] or {}
  return db[key]
end

-- Saves the open profession window's line (name, rank) and its recipes:
-- name -> { product, kind } (kind is the skill-up colour: optimal, medium,
-- easy, trivial). Recipes merge in, so a filtered window loses nothing.
-- unlearned: recipes the modern window lists that you do not know yet;
-- they go with the trainer's (UpgradeFinderDB.trainer).
local knownCache -- { at, list }: C.known() is asked on every Omni keystroke
function C.saveKnown(prof, rank, max, list, unlearned)
  if type(prof) ~= "string" or prof == "" then return end
  knownCache = nil
  local all = dbTable("known")
  local p = all[prof] or { recipes = {} }
  p.rank, p.max = rank, max
  for name, r in pairs(list) do p.recipes[name] = r end
  all[prof] = p
  if unlearned and next(unlearned) then
    local t = dbTable("trainer")
    t[prof] = t[prof] or {}
    for name, r in pairs(unlearned) do
      if not t[prof][name] then t[prof][name] = { product = r.product, kind = r.kind } end
    end
  end
end

function C.readTrainer()
  local g = function(n) return rawget(_G, n) end
  local out = {}
  for i = 1, call(g("GetNumTrainerServices")) or 0 do
    local name, _, kind = call(g("GetTrainerServiceInfo"), i)
    local skill, req = call(g("GetTrainerServiceSkillReq"), i)
    local product = idOf(call(g("GetTrainerServiceItemLink"), i))
    if name and kind ~= "header" and type(skill) == "string" and product then
      local reagents = {}
      for r = 1, call(g("GetTrainerServiceNumReagents"), i) or 0 do
        local rname, _, count = call(g("GetTrainerServiceReagentInfo"), i, r)
        local id = idOf(call(g("GetTrainerServiceReagentLink"), i, r))
        if id and rname then C.learn(rname, id) end
        if id or rname then table.insert(reagents, { id or rname, count or 1, rname }) end
      end
      out[skill] = out[skill] or {}
      out[skill][name] = { product = product, req = tonumber(req), price = call(g("GetTrainerServiceCost"), i),
        reagents = reagents }
    end
  end
  knownCache = nil
  local all = dbTable("trainer")
  for skill, list in pairs(out) do
    all[skill] = all[skill] or {}
    for name, r in pairs(list) do all[skill][name] = r end
  end
end

-- Cost, sale and profit of one craft: fills t and returns it.
local function priced(t, reagents, product, made)
  local cost = C.cost(reagents)
  t.cost, t.unknown = cost.total, #cost.missing > 0
  local sale = product and C.sale(product)
  if sale then
    t.sale, t.how = sale.best * (made or 1), sale.how
    -- How sure an AH sale is (LootValue's quote): "ok", "thin" or "no scan".
    t.confidence = sale.how == "AH" and sale.quote and sale.quote.confidence or nil
    if cost.total > 0 or not t.unknown then t.profit = t.sale - cost.total end
  end
  return t
end

-- Every saved recipe: { prof, name, product, source ("known" or
-- "trainer"), kind, req, price, rank, max, cost, unknown, sale, how,
-- profit }. A trainer recipe you know already is left out.
-- Prices change slowly: the list is kept C.KNOWN_TTL seconds.
C.KNOWN_TTL = 15
function C.known()
  local now = call(rawget(_G, "GetTime")) or 0
  if knownCache and now - knownCache.at < C.KNOWN_TTL then return knownCache.list end
  local out = C.knownNow()
  knownCache = { at = now, list = out }
  return out
end

function C.knownNow()
  local out, have = {}, {}
  local recipes = recipesDB()
  for prof, p in pairs(dbTable("known")) do
    have[prof] = {}
    for name, r in pairs(p.recipes or {}) do
      have[prof][name] = true
      local saved = r.product and recipes[r.product]
      table.insert(out, priced({ prof = prof, name = name, product = r.product, source = "known", kind = r.kind,
        rank = p.rank, max = p.max }, saved and saved.reagents or {}, r.product, saved and saved.made))
    end
  end
  for prof, list in pairs(dbTable("trainer")) do
    local p = dbTable("known")[prof]
    for name, r in pairs(list) do
      if not (have[prof] and have[prof][name]) then
        table.insert(out, priced({ prof = prof, name = name, product = r.product, source = "trainer", req = r.req,
          price = r.price, rank = p and p.rank, max = p and p.max },
          (r.reagents and #r.reagents > 0 and r.reagents) or (recipes[r.product] and recipes[r.product].reagents) or {}, r.product,
          recipes[r.product] and recipes[r.product].made or 1))
      end
    end
  end
  return out
end

-- Runs fn once, C.READ_DELAY seconds after the first of a burst of events.
C.READ_DELAY = 1
local soonPending = {}
function C.soon(key, fn)
  local after = api("C_Timer.After")
  if not after then return C.guard(fn) end
  if soonPending[key] then return end
  soonPending[key] = true
  after(C.READ_DELAY, function() soonPending[key] = nil C.guard(fn) end)
end

-- Errors are reported once in chat, so a broken line does not fail silently.
local reported = false
function C.guard(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then C.lastError = tostring(err) end
  if not ok and not reported then
    reported = true
    if ns.say then ns.say("crafting lines error: " .. tostring(err)) end
  end
end
C.onTooltip = function(tt, data) C.guard(onTooltip, tt, data) end

---------------------------------------------------------------------------
-- The profession window (Blizzard_TradeSkillUI)
---------------------------------------------------------------------------
-- The reagents of the profession window's recipe at index: { { id or name,
-- count, name } }.
local function tradeSkillReagents(index)
  local g = function(n) return rawget(_G, n) end
  local reagents = {}
  for i = 1, call(g("GetTradeSkillNumReagents"), index) or 0 do
    local name, _, count = call(g("GetTradeSkillReagentInfo"), index, i)
    local id = idOf(call(g("GetTradeSkillReagentItemLink"), index, i))
    if id and name then C.learn(name, id) end
    if id or name then table.insert(reagents, { id or name, count or 1, name }) end
  end
  return reagents
end

function C.forTradeSkill(index)
  local g = function(n) return rawget(_G, n) end
  local link = call(g("GetTradeSkillItemLink"), index)
  local reagents = tradeSkillReagents(index)
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

---------------------------------------------------------------------------
-- Shopping for several crafts: the reagents for N crafts of the selected
-- recipe, less what is in your bags and bank, as an Auctionator shopping
-- list with the amounts, and a summary in chat with the estimated cost.
---------------------------------------------------------------------------
C.SHOP_LIST = "UpgradeFinder crafts"
local bankSeen = false -- the game counts the bank only after a visit this session
function C.bankSeen(v) if v ~= nil then bankSeen = v end return bankSeen end

-- How many of an item you have in your bags and (once seen) your bank.
function C.have(id)
  if type(id) ~= "number" then return 0 end
  local count = api("C_Item.GetItemCount") or rawget(_G, "GetItemCount")
  return call(count, id, true) or 0
end

-- The shopping rows for want = { [id or name] = { id, name, count } }:
-- { name, id, want, have, buy, each, from }, sorted by name, then the AH
-- total of what to buy, the vendor total, and the names with no price.
function C.shopRows(want)
  local rows, ah, vendor, missing = {}, 0, 0, {}
  for _, w in pairs(want or {}) do
    local id = w.id or C.idByName(w.name)
    local got = C.have(id)
    local buy = math.max(0, w.count - got)
    local each, from = Scan.priceOf(id or w.name)
    local it = (not w.name and id) and info(id) or nil
    local name = w.name or (it and it.name) or ("item " .. tostring(id))
    table.insert(rows, { name = name, id = id, want = w.count, have = got, buy = buy, each = each, from = from })
    if buy > 0 then
      if not each then table.insert(missing, name)
      elseif from == "vendor" then vendor = vendor + each * buy
      else ah = ah + each * buy end
    end
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows, ah, vendor, missing
end

-- Auctionator search strings for the rows to buy at the AH (not the ones a
-- vendor sells for less): the exact name and the amount to buy.
function C.searchTerms(rows)
  local convert = api("Auctionator.API.v1.ConvertToSearchString")
  local terms = {}
  for _, r in ipairs(rows) do
    if r.buy > 0 and r.from ~= "vendor" then
      local s = call(convert, "UpgradeFinder", { searchString = r.name, isExact = true, quantity = r.buy })
        or call(convert, "UpgradeFinder", { searchString = r.name, isExact = true })
      table.insert(terms, s or ('"' .. r.name .. '"'))
    end
  end
  return terms
end

-- Makes (or replaces) the Auctionator shopping list. true when it worked.
function C.toAuctionator(rows)
  local create = api("Auctionator.API.v1.CreateShoppingList")
  local terms = C.searchTerms(rows)
  if not create or #terms == 0 then return false end
  return (pcall(create, "UpgradeFinder", C.SHOP_LIST, terms))
end

-- The chat lines for a shopping list.
function C.shopLines(crafts, rows, ah, vendor, missing)
  local money, out = ns.money, {}
  table.insert(out, "Shopping for " .. table.concat(crafts, ", ") .. " (less your bags"
    .. (bankSeen and " and bank)" or "; open your bank once to count it too)"))
  local enough = {}
  for _, r in ipairs(rows) do
    if r.buy == 0 then table.insert(enough, r.name)
    else
      local price = r.each and (money(r.each) .. " each" .. (r.from == "vendor" and " at a vendor" or "")) or "no price"
      table.insert(out, string.format("  %s: buy %d (need %d, have %d), %s", r.name, r.buy, r.want, r.have, price))
    end
  end
  if #enough > 0 then table.insert(out, "  You have enough " .. table.concat(enough, ", ")) end
  if ah + vendor == 0 and #missing == 0 then
    table.insert(out, "You have every reagent.")
  else
    local parts = {}
    if ah > 0 then table.insert(parts, "about " .. money(ah) .. " at the AH") end
    if vendor > 0 then table.insert(parts, money(vendor) .. " at vendors") end
    if #missing > 0 then table.insert(parts, #missing .. " with no price") end
    table.insert(out, "Cost: " .. table.concat(parts, ", ") .. ".")
  end
  return out
end

-- The modern profession window (Blizzard_Professions). Forever uses it,
-- not the old TradeSkillFrame: there is no TradeSkillFrame global at all.
local function schematicForm()
  local f = rawget(_G, "ProfessionsFrame")
  return f and f.CraftingPage and f.CraftingPage.SchematicForm or nil, f
end
C.schematicForm = schematicForm

-- The count in the profession window's Create box (at least 1).
local function createCount()
  local _, pf = schematicForm()
  local box = pf and pf.CraftingPage and pf.CraftingPage.CreateMultipleInputBox
  local n = box and ((box.GetValue and call(box.GetValue, box)) or (box.GetNumber and call(box.GetNumber, box)))
  if not box then
    box = rawget(_G, "TradeSkillInputBox")
    n = box and box.GetNumber and call(box.GetNumber, box)
  end
  return (type(n) == "number" and n >= 1) and math.floor(n) or 1
end
C.createCount = createCount

-- The selected recipe: name and reagents { { id or name, count, name } },
-- from the modern profession window, or else the old one (index).
function C.selectedRecipe(index)
  local form = schematicForm()
  local recipe = form and form.GetRecipeInfo and call(form.GetRecipeInfo, form)
  if not index and type(recipe) == "table" and recipe.recipeID then
    local level = form.GetCurrentRecipeLevel and call(form.GetCurrentRecipeLevel, form)
    local sch = call(api("C_TradeSkillUI.GetRecipeSchematic"), recipe.recipeID, false, level)
    local basic = api("Enum.CraftingReagentType.Basic")
    local reagents = {}
    for _, slot in ipairs(type(sch) == "table" and sch.reagentSlotSchematics or {}) do
      local first = slot.reagents and slot.reagents[1]
      if first and first.itemID and (basic == nil or slot.reagentType == basic) then
        local it = info(first.itemID)
        if not it then call(api("C_Item.RequestLoadItemDataByID"), first.itemID) end
        if it and it.name then C.learn(it.name, first.itemID) end
        table.insert(reagents, { first.itemID, slot.quantityRequired or 1, it and it.name or nil })
      end
    end
    return recipe.name, reagents
  end
  local g = function(n) return rawget(_G, n) end
  index = index or call(g("GetTradeSkillSelectionIndex"))
  local name, kind = call(g("GetTradeSkillInfo"), index or 0)
  if not (index and index > 0 and name and kind ~= "header") then return nil, {} end
  return name, tradeSkillReagents(index)
end

-- Shop for times crafts of the selected recipe (index), or add them to the
-- list you have (add). Says the list in chat and makes the Auctionator list.
function C.shop(times, add, index)
  local name, reagents = C.selectedRecipe(index)
  if #reagents == 0 then
    if ns.say then ns.say("open your profession window and pick a recipe to shop for") end
    return nil
  end
  for _, r in ipairs(reagents) do
    if not r[3] then
      if ns.say then ns.say("reagent names are still loading; click Shop again in a moment") end
      return nil
    end
  end
  times = math.max(1, math.floor(tonumber(times) or createCount()))
  local db = ns.db()
  if not add or type(db.shop) ~= "table" then db.shop = { want = {}, crafts = {} } end
  local want = db.shop.want
  for _, r in ipairs(reagents) do
    local id = type(r[1]) == "number" and r[1] or nil
    local key = id or r[3] or r[1]
    local w = want[key] or { id = id, name = r[3] or (type(r[1]) == "string" and r[1]) or nil, count = 0 }
    w.count = w.count + r[2] * times
    want[key] = w
  end
  table.insert(db.shop.crafts, times .. "x " .. name)
  local rows, ah, vendor, missing = C.shopRows(want)
  local lines = C.shopLines(db.shop.crafts, rows, ah, vendor, missing)
  local made = C.toAuctionator(rows)
  if made then
    local frame = ns.ahFrame and ns.ahFrame()
    local open = frame and frame.IsShown and frame:IsShown()
    table.insert(lines, "Auctionator shopping list \"" .. C.SHOP_LIST .. "\" is ready"
      .. (open and ": open it on the Shopping tab." or ": open it on the Shopping tab at the Auction House."))
  elseif #C.searchTerms(rows) > 0 then
    table.insert(lines, "Auctionator is not loaded (or too old for shopping lists), so there is no list to open.")
  end
  if ns.say then for _, l in ipairs(lines) do ns.say(l) end end
  return rows, lines
end

-- The Shop button beside "Reagents:" in the profession window.
local shopButton
local function shopText()
  if shopButton then shopButton:SetText("Shop x" .. createCount()) end
end
C.shopText = shopText
function C.forgetShopButton() shopButton = nil end -- tests
local function makeButton(parent)
  local b = CreateFrame("Button", "UpgradeFinderShopButton", parent, "UIPanelButtonTemplate")
  b:SetSize(72, 20)
  if b.SetFrameLevel and parent.GetFrameLevel then b:SetFrameLevel((parent:GetFrameLevel() or 0) + 30) end
  if b.SetNormalFontObject and rawget(_G, "GameFontNormalSmall") then b:SetNormalFontObject(rawget(_G, "GameFontNormalSmall")) end
  b:SetScript("OnClick", function()
    C.guard(C.shop, nil, call(rawget(_G, "IsShiftKeyDown")) and true or false)
  end)
  b:SetScript("OnEnter", function(self)
    local tt = rawget(_G, "GameTooltip")
    tt:SetOwner(self, "ANCHOR_RIGHT")
    tt:AddLine("Shop for these crafts")
    tt:AddLine("The reagents for the number in the Create box, less what is in your bags and bank, as an Auctionator shopping list.", 1, 1, 1, true)
    tt:AddLine("Shift-click adds this recipe to the list you have.", 0.6, 0.6, 0.6, true)
    tt:Show()
  end)
  b:SetScript("OnLeave", function() local tt = rawget(_G, "GameTooltip") if tt then tt:Hide() end end)
  b:SetScript("OnShow", shopText)
  return b
end

function C.shopButton()
  if shopButton then return shopButton end
  local form, pf = schematicForm()
  if form then
    -- Beside the "Reagents:" label of the recipe pane, like Auctionator's
    -- crafting info (AuctionatorCraftingInfoProfessionsFrame) below it.
    shopButton = makeButton(form)
    local reagents = form.Reagents
    local label = reagents and reagents.Label
    if label then shopButton:SetPoint("LEFT", label, "RIGHT", 10, 0)
    elseif reagents then shopButton:SetPoint("BOTTOMLEFT", reagents, "TOPLEFT", 90, -18)
    else shopButton:SetPoint("TOPRIGHT", form, "TOPRIGHT", -20, -110) end
    local secure = rawget(_G, "hooksecurefunc")
    if secure and form.Init then secure(form, "Init", function() pcall(shopText) end) end
    local box = pf.CraftingPage and pf.CraftingPage.CreateMultipleInputBox
    local edit = box and (type(box.NumericInputBox) == "table" and box.NumericInputBox or box)
    if edit and edit.HookScript then edit:HookScript("OnTextChanged", function() pcall(shopText) end) end
    shopText()
    return shopButton
  end
  local frame, label = rawget(_G, "TradeSkillFrame"), rawget(_G, "TradeSkillReagentLabel")
  if not frame then return nil end
  shopButton = makeButton(frame)
  if label and label.IsVisible and label:IsVisible() then shopButton:SetPoint("LEFT", label, "RIGHT", 10, 0)
  else shopButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -50) end
  local box = rawget(_G, "TradeSkillInputBox")
  if box and box.HookScript then box:HookScript("OnTextChanged", function() pcall(shopText) end) end
  shopText()
  return shopButton
end

-- /uf shop debug: where the Shop button is, for a profession window that
-- does not show it.
function C.shopDebug()
  local function region(n, r)
    if r == nil then r = rawget(_G, n) end
    if not r then return n .. ": none" end
    local function m(f) local ok, v = pcall(r[f], r) if ok then return v end end
    local x, y = m("GetLeft"), m("GetTop")
    return string.format("%s: shown %s, visible %s, at %s,%s, level %s, parent %s", n, tostring(m("IsShown")),
      tostring(m("IsVisible")), x and math.floor(x) or "?", y and math.floor(y) or "?", tostring(m("GetFrameLevel")),
      tostring(r.GetParent and r:GetParent() and r:GetParent().GetName and r:GetParent():GetName()))
  end
  local out = { region("UpgradeFinderShopButton", shopButton) }
  local form, pf = schematicForm()
  table.insert(out, region("ProfessionsFrame", pf or false))
  table.insert(out, region("SchematicForm", form or false))
  table.insert(out, region("SchematicForm.Reagents", form and form.Reagents or false))
  table.insert(out, region("Reagents.Label", form and form.Reagents and form.Reagents.Label or false))
  table.insert(out, region("CreateMultipleInputBox", pf and pf.CraftingPage and pf.CraftingPage.CreateMultipleInputBox or false))
  for _, n in ipairs({ "AuctionatorCraftingInfoProfessionsFrame", "TradeSkillFrame" }) do table.insert(out, region(n)) end
  local rname, rr = C.selectedRecipe()
  table.insert(out, "recipe: " .. tostring(rname) .. ", " .. #rr .. " reagents")
  table.insert(out, "last error: " .. tostring(C.lastError))
  return out
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
    elseif ev == "TRADE_SKILL_SHOW" or ev == "TRADE_SKILL_UPDATE" or ev == "TRADE_SKILL_LIST_UPDATE" then
      C.soon("trade", C.readTradeSkills)
      if ev ~= "TRADE_SKILL_LIST_UPDATE" then
        C.guard(C.shopButton)
        pcall(shopText)
      end
    elseif ev == "TRAINER_SHOW" or ev == "TRAINER_UPDATE" then C.soon("trainer", C.readTrainer)
    elseif ev == "BANKFRAME_OPENED" then C.bankSeen(true)
    elseif name == "Blizzard_TradeSkillUI" or name == "Blizzard_Professions" then C.hookRows() C.guard(C.shopButton) end
  end)
  pcall(f.RegisterEvent, f, "ADDON_LOADED")
  pcall(f.RegisterEvent, f, "PLAYER_EQUIPMENT_CHANGED")
  pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
  pcall(f.RegisterEvent, f, "TRADE_SKILL_SHOW")
  pcall(f.RegisterEvent, f, "TRADE_SKILL_UPDATE")
  pcall(f.RegisterEvent, f, "TRADE_SKILL_LIST_UPDATE")
  pcall(f.RegisterEvent, f, "TRAINER_SHOW")
  pcall(f.RegisterEvent, f, "TRAINER_UPDATE")
  pcall(f.RegisterEvent, f, "BANKFRAME_OPENED")
end
C.hook()
