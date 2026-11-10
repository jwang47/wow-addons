-- UpgradeFinder scanning: reads items through a hidden tooltip (stats, red
-- "can't use" lines, required level), scores what you wear, and walks the
-- Auctionator scan and your bags a slice per frame.
local _, ns = ...
local S = ns.score
local Scan = {}
ns.scan = Scan

local function pass(ok, ...) if ok then return ... end end
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  return pass(pcall(fn, ...))
end
ns.call = call
local function api(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = rawget(t, part)
  end
  return t
end
ns.api = api

function ns.db()
  if type(UpgradeFinderDB) ~= "table" then UpgradeFinderDB = {} end
  local db = UpgradeFinderDB
  db.weights = db.weights or {}   -- [weight key] = { stat = weight } overrides
  db.presets = db.presets or {}   -- [class][name] = { stat = weight }, from /uf save
  db.active = db.active or {}     -- [weight key] = the preset name loaded there
  db.opts = db.opts or { ahead = 0, sort = "gain", affordable = false, group = 1 }
  return db
end

function ns.class()
  local _, class = call(UnitClass, "player")
  return class or S.DEFAULT_CLASS
end

-- The talent tree with the most points (nil below level 10). Classic
-- GetTalentTabInfo returns name, icon, points, ...; later clients return
-- id, name, description, icon, points, ...
function ns.talentTab()
  local get = rawget(_G, "GetTalentTabInfo")
  local best, most = nil, 0
  for tab = 1, call(rawget(_G, "GetNumTalentTabs")) or 3 do
    local r = { call(get, tab) }
    local points = type(r[1]) == "number" and r[5] or r[3]
    if type(points) == "number" and points > most then best, most = tab, points end
  end
  return best
end

-- Where weights and overrides come from: "CLASS" or "CLASS:Spec".
function ns.weightKey()
  local class = ns.class()
  local spec = S.specName(class, ns.talentTab())
  return spec and (class .. ":" .. spec) or class, class, spec
end

function ns.weights()
  local key, class = ns.weightKey()
  return S.weightsFor(class, ns.db().weights[key], ns.talentTab())
end

-- The score function: MageMentor's own for a mage when it is loaded (so the
-- numbers match its tooltips), otherwise the built-in weights for your spec.
function ns.valueOf(lines, w)
  lines = S.withoutSets(lines) -- MageMentor's reader would count set bonuses
  local mm = rawget(_G, "MageMentorAPI")
  if ns.class() == "MAGE" and type(mm) == "table" and mm.parseStats and mm.score then
    local ok, v = pcall(function() return mm.score(mm.parseStats(lines)) end)
    if ok and type(v) == "number" then return v end
  end
  return S.value(S.parse(lines), w or ns.weights())
end

---------------------------------------------------------------------------
-- Hidden tooltip
---------------------------------------------------------------------------
local TT = "UpgradeFinderScanTooltip"
local scanner

local function isRed(fs)
  if not fs or not fs.GetTextColor then return false end
  local r, g, b = fs:GetTextColor()
  return r and r > 0.9 and g < 0.3 and b < 0.3 and true or false
end

local REQ_LEVEL = "^" .. (type(rawget(_G, "ITEM_MIN_LEVEL")) == "string" and ITEM_MIN_LEVEL or "Requires Level %d")
  :gsub("%%d", "(%%d+)")

-- Lines, unusable (a red line other than the level), required level, and
-- the red lines themselves. nil while the game still loads the item
-- ("Retrieving item information").
function Scan.read(setter)
  if not scanner then
    scanner = CreateFrame("GameTooltip", TT, nil, "GameTooltipTemplate")
  end
  scanner:SetOwner(rawget(_G, "WorldFrame") or UIParent, "ANCHOR_NONE")
  scanner:ClearLines()
  setter(scanner)
  local lines, unusable, req, red = {}, false, nil, {}
  for i = 1, scanner:NumLines() do
    local left = _G[TT .. "TextLeft" .. i]
    local t = left and left:GetText()
    if t then table.insert(lines, t) end
    local lvl = t and tonumber(t:match(REQ_LEVEL))
    if lvl then req = lvl
    elseif isRed(left) or isRed(_G[TT .. "TextRight" .. i]) then
      unusable = true
      table.insert(red, t or "")
    end
  end
  if #lines < 2 then return nil end
  return lines, unusable, req, red
end

---------------------------------------------------------------------------
-- What you wear
---------------------------------------------------------------------------
-- Equip location ("" or nil for non-gear), and whether the game knew the
-- item at all (the instant lookup can return nothing for an unseen item).
local function equipLoc(id)
  local instant = api("C_Item.GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
  local known, _, _, loc = call(instant, id)
  return loc, known ~= nil
end
Scan.equipLoc = equipLoc

local worn = { value = {}, twoHander = false }
Scan.SLOT_NAMES = { "head", "neck", "shoulder", "shirt", "chest", "waist", "legs", "feet", "wrist", "hands",
  "ring", "ring", "trinket", "trinket", "back", "main hand", "off hand", "ranged" }

-- The score of each worn item is saved (per weight set, per item link), so
-- the next login need not wait for the game to load your own gear.
function Scan.readWorn()
  worn = { value = {}, twoHander = false, missing = 0 }
  local db, key = ns.db(), Scan.key or ns.weightKey()
  db.worn = db.worn or {}
  local saved, keep = db.worn[key] or {}, {}
  for slot = 1, 18 do
    local link = call(GetInventoryItemLink, "player", slot)
    if link then
      local lines = Scan.read(function(tt) tt:SetInventoryItem("player", slot) end)
      if lines then
        keep[link] = ns.valueOf(lines, Scan.w)
      elseif saved[link] then
        keep[link] = saved[link] -- last time's score while the game loads it
      else
        -- Not loaded and never seen: it would count as 0 and make every
        -- item for this slot look like a big upgrade, so wait for it.
        worn.missing = worn.missing + 1
        worn.missingSlot = Scan.SLOT_NAMES[slot]
        call(api("C_Item.RequestLoadItemDataByID"), tonumber(link:match("item:(%d+)")))
      end
      worn.value[slot] = keep[link] or 0
      if slot == 16 then worn.twoHander = equipLoc(link) == "INVTYPE_2HWEAPON" end
    end
  end
  -- Dual wield: the game says so, or (older client) an off-hand weapon.
  local can = rawget(_G, "CanDualWield")
  if type(can) == "function" then
    worn.dualWield = call(can) and true or false
  else
    local off = call(GetInventoryItemLink, "player", 17)
    worn.dualWield = off and equipLoc(off) == "INVTYPE_WEAPON" or false
  end
  db.worn[key] = keep -- only what you wear now
  return worn
end
function Scan.worn() return worn end

---------------------------------------------------------------------------
-- Candidates: the Auctionator scan, your bags and the dungeon drops
---------------------------------------------------------------------------
-- cache[id] = { name, loc, value, unusable, reqLevel, craft } or false (not
-- gear). craft: the profession line of a recipe ("Requires Tailoring (125)").
local cache = {}
Scan.cache = cache
local state = { busy = false, pending = 0, done = 0, total = 0 }
Scan.state = state
Scan.SLICE = 60

function Scan.forget() for k in pairs(cache) do cache[k] = nil end end

-- The item scores are saved (UpgradeFinderDB.items, the same table as
-- cache), so a /reload or the next login shows the list without reading
-- thousands of tooltips again. They are kept while the weights are the
-- same: the key holds the weight set, VERSION (bump it when scoring
-- changes), and for a mage with MageMentor a fingerprint of its weights.
Scan.VERSION = 5 -- 3: recipes score as the item they make; 4: their reagents; 5: damage vs Undead
Scan.SKIP_FOR = 24 * 3600 -- items that never loaded are skipped this long
local PROBE = { "int", "spi", "sta", "sp", "frost", "fire", "arcane", "crit", "hit", "mp5", "armor", "slay" }
function Scan.cacheKey()
  -- The weights themselves are in the key, so a changed weight or a loaded
  -- preset scores the items again.
  local w, parts0 = ns.weights(), {}
  for k, v in pairs(w) do table.insert(parts0, k .. "=" .. v) end
  table.sort(parts0)
  local key = ns.weightKey() .. "#v" .. Scan.VERSION .. "#w" .. table.concat(parts0, ",")
  local mm = rawget(_G, "MageMentorAPI")
  if ns.class() == "MAGE" and type(mm) == "table" and type(mm.score) == "function" then
    local parts = {}
    for _, stat in ipairs(PROBE) do
      local ok, v = pcall(mm.score, { [stat] = 1 })
      table.insert(parts, ok and tostring(v) or "?")
    end
    key = key .. "#mm" .. table.concat(parts, ",")
  end
  return key
end

local function useStore()
  local db, key = ns.db(), Scan.cacheKey()
  if db.items ~= cache then
    if db.itemsKey == key and type(db.items) == "table" then
      for id, c in pairs(db.items) do if cache[id] == nil then cache[id] = c end end
    end
    db.items = cache
  end
  if db.itemsKey ~= key then Scan.forget() db.itemsKey = key end
  db.missing = db.missing or {}
  return db
end

local function now() return call(rawget(_G, "time")) or 0 end

local function auctionatorIDs(into)
  local db = api("Auctionator.Database.db")
  if type(db) ~= "table" then return end
  -- Keys are "12345", and gear can be keyed with a prefix and item level
  -- ("g:12345:20"): the first number is the item ID.
  for key in pairs(db) do
    local id = tonumber(type(key) == "string" and key:match("(%d+)") or key)
    if id then into[id] = into[id] or "AH" end
  end
end

-- Where a dungeon item drops: { name, short, min, max, boss } from
-- ns.DUNGEONS (Dungeons.lua), or nil. The first boss listed wins.
local drops
function Scan.dropOf(id)
  if not drops then
    drops = {}
    for _, d in ipairs(ns.DUNGEONS or {}) do
      for i = 5, #d do
        local b = d[i]
        for j = 2, #b do
          drops[b[j]] = drops[b[j]] or { name = d[1], short = d[2], min = d[3], max = d[4], boss = b[1] }
        end
      end
    end
  end
  return drops[id]
end

-- Off with /uf dungeons off. An item on the AH stays an AH row (it gets a
-- "drops in" note); one in your bags is a bags row.
local function dungeonIDs(into)
  if ns.db().opts.dungeons == false then return end
  Scan.dropOf(0)
  for id in pairs(drops) do into[id] = into[id] or "dungeon" end
end

local function bagIDs(into)
  for id, src in pairs(into) do if src == "bags" then into[id] = nil end end
  for bag = 0, rawget(_G, "NUM_BAG_SLOTS") or 4 do
    for slot = 1, call(api("C_Container.GetContainerNumSlots"), bag) or 0 do
      local info = call(api("C_Container.GetContainerItemInfo"), bag, slot)
      if type(info) == "table" and info.itemID then into[info.itemID] = "bags" end
    end
  end
end

-- Items the client has not seen yet load from the server. We ask for
-- REQUESTS of them per pass, look again every WAIT seconds, and stop after
-- PATIENCE passes in a row with nothing new.
Scan.REQUESTS, Scan.WAIT, Scan.PATIENCE = 150, 1.5, 4

local function cached(id)
  local f = api("C_Item.IsItemDataCachedByID")
  if not f then return true end -- older client: let the tooltip tell
  return call(f, id) and true or false
end

-- A recipe (item class 9) shows the item it makes inside its own tooltip:
-- the name, the slot line ("Head    Cloth"), the stats. We score that.
Scan.RECIPE_CLASS = 9
local slotText -- "Head" -> INVTYPE_HEAD, from the client's own strings
local ENGLISH = { Head = "INVTYPE_HEAD", Neck = "INVTYPE_NECK", Shoulder = "INVTYPE_SHOULDER",
  Chest = "INVTYPE_CHEST", Waist = "INVTYPE_WAIST", Legs = "INVTYPE_LEGS", Feet = "INVTYPE_FEET",
  Wrist = "INVTYPE_WRIST", Hands = "INVTYPE_HAND", Finger = "INVTYPE_FINGER", Trinket = "INVTYPE_TRINKET",
  Back = "INVTYPE_CLOAK", ["One-Hand"] = "INVTYPE_WEAPON", ["Main Hand"] = "INVTYPE_WEAPONMAINHAND",
  ["Two-Hand"] = "INVTYPE_2HWEAPON", ["Held In Off-hand"] = "INVTYPE_HOLDABLE",
  ["Off Hand"] = "INVTYPE_SHIELD", Ranged = "INVTYPE_RANGED", Thrown = "INVTYPE_THROWN",
  Relic = "INVTYPE_RELIC" }
local function slotOf(line)
  if not slotText then
    slotText = {}
    for text, loc in pairs(ENGLISH) do slotText[text] = loc end
    for loc in pairs(S.SLOTS) do
      local t = rawget(_G, loc)
      if type(t) == "string" and not slotText[t] then slotText[t] = loc end
    end
  end
  return slotText[line]
end
Scan.slotOf = slotOf

local PROFESSION = "^Requires (.+) %((%d+)%)$"
local function recipe(id)
  local lines, unusable, req, red = Scan.read(function(tt) tt:SetHyperlink("item:" .. id) end)
  if not lines then return false end
  local loc
  for i = 2, #lines do
    loc = slotOf(lines[i])
    if loc then break end
    if lines[i] == rawget(_G, "RETRIEVING_ITEM_INFO") or lines[i]:match("^Retrieving item") then return false end
  end
  if not loc then cache[id] = false return true end
  -- A red profession line only means you cannot craft it yourself yet.
  local craft
  for _, line in ipairs(lines) do
    if line:match(PROFESSION) and not line:match("^Requires Level") then craft = line end
  end
  unusable = false
  for _, line in ipairs(red) do
    if not line:match(PROFESSION) then unusable = true end
  end
  local made = lines[1]:match("^[^:]+: (.+)$") or lines[2]
  -- Reagents: the line after "Use: Teaches ...", such as "Bolt of Silk
  -- Cloth (8), Fine Thread (4)". A reagent without a count is one.
  local reagents, bop = {}, false
  for i, line in ipairs(lines) do
    if line == rawget(_G, "ITEM_BIND_ON_PICKUP") or line == "Binds when picked up" then bop = true end
    if line:match("^Use: Teaches") and lines[i + 1] and not lines[i + 1]:match(PROFESSION) then
      for part in (lines[i + 1] .. ","):gmatch("%s*([^,]+),") do
        local name, n = part:match("^(.-)%s*%((%d+)%)$")
        table.insert(reagents, { name or part, tonumber(n) or 1 })
      end
    end
  end
  local body = {}
  for i = 2, #lines do table.insert(body, lines[i]) end
  cache[id] = { name = made, recipe = lines[1], loc = loc, value = ns.valueOf(body, Scan.w), unusable = unusable,
    reqLevel = req, craft = craft and craft:gsub("^Requires ", "") or nil, reagents = reagents, bop = bop }
  return true
end

-- One item: fills cache[id]; returns false if it is still loading.
function Scan.item(id)
  if cache[id] ~= nil then return true end
  local loc, known = equipLoc(id)
  if not known then return false end -- not seen yet: ask and look again
  if not loc or not S.SLOTS[loc] then
    local instant = api("C_Item.GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
    local classID = select(6, call(instant, id))
    if classID == Scan.RECIPE_CLASS then
      if not cached(id) then return false end
      return recipe(id)
    end
    cache[id] = false
    return true
  end
  if not cached(id) then return false end
  local lines, unusable, req = Scan.read(function(tt) tt:SetHyperlink("item:" .. id) end)
  if not lines then return false end
  cache[id] = { name = lines[1], loc = loc, value = ns.valueOf(lines, Scan.w), unusable = unusable, reqLevel = req }
  local missing = ns.db().missing
  if missing then missing[id] = nil end
  return true
end

-- Walks ids a slice per frame; done(stillLoading, loadedCount) at the end.
local function walk(ids, gen, onStep, done)
  local i, still, got = 1, {}, 0
  local function step()
    if gen ~= state.gen then return end -- a newer scan took over
    local budget = Scan.SLICE
    while budget > 0 and i <= #ids do
      if Scan.item(ids[i]) then got = got + 1 else table.insert(still, ids[i]) end
      i, budget = i + 1, budget - 1
    end
    if onStep then onStep(i - 1) end
    if i <= #ids then call(api("C_Timer.After"), 0, step) else done(still, got) end
  end
  step()
end

-- Scans every candidate. onDone(rows) runs when the first pass ends and
-- again each time more items finish loading; onStep(state) repaints.
function Scan.run(onStep, onDone)
  if state.busy then return end
  local sources = {}
  auctionatorIDs(sources)
  dungeonIDs(sources)
  bagIDs(sources)
  local ids = {}
  local db = useStore()
  local skipped = 0
  for id in pairs(sources) do
    local t = db.missing[id]
    if cache[id] == nil and t and now() - t < Scan.SKIP_FOR then skipped = skipped + 1
    else table.insert(ids, id) end
  end
  table.sort(ids)
  state.skipped = skipped
  state.gen = (state.gen or 0) + 1
  local gen = state.gen
  state.busy, state.loading, state.total, state.done, state.pending = true, false, #ids, 0, 0
  Scan.w, Scan.key = ns.weights(), ns.weightKey()
  local asked, idle, due = {}, 0, true -- due: rows changed since last shown
  local function ask(list)
    local n = 0
    for _, id in ipairs(list) do
      if n >= Scan.REQUESTS then break end
      if not asked[id] then
        asked[id], n = true, n + 1
        call(api("C_Item.RequestLoadItemDataByID"), id)
      end
    end
    return n
  end
  local function after(still, got)
    if gen ~= state.gen then return end
    local n = ask(still)
    if got > 0 or n > 0 then idle = 0 else idle = idle + 1 end
    state.busy, state.pending = false, #still
    Scan.readWorn() -- gear may have changed during the scan
    local gearReady = worn.missing == 0
    state.loading = (#still > 0 or not gearReady) and idle < Scan.PATIENCE
    if not state.loading then
      -- Gave up on these: skip them next time (Rescan tries them again).
      for _, id in ipairs(still) do db.missing[id] = now() end
    end
    state.gearLoading = not gearReady and state.loading
    due = due or got > 0
    -- Gains are shown only once your own gear has loaded (or we gave up).
    if due and (gearReady or not state.loading) and onDone then
      due = false
      onDone(Scan.rows(sources))
    end
    if onStep then onStep(state) end
    if state.loading then
      call(api("C_Timer.After"), Scan.WAIT, function() walk(still, gen, nil, after) end)
    end
  end
  Scan.readWorn()
  walk(ids, gen, function(done)
    state.done = done
    if onStep then onStep(state) end
  end, after)
end

-- Bags changed or gear moved: rebuild the "bags" sources (an item you
-- equipped is no longer a free candidate; an AH copy stays), score new bag
-- items, reread what you wear and return fresh rows.
function Scan.refresh()
  local sources = {}
  auctionatorIDs(sources)
  dungeonIDs(sources)
  bagIDs(sources)
  for id, src in pairs(sources) do if src == "bags" then Scan.item(id) end end
  Scan.readWorn()
  return Scan.rows(sources)
end

-- The price of one item by name or id: the AH price from Auctionator, or
-- the vendor's price when that is lower (thread, dye). nil: not known.
-- The name lookup works only for items the client has seen.
local function linkOf(name)
  local info = api("C_Item.GetItemInfo") or rawget(_G, "GetItemInfo")
  local _, link = call(info, name)
  return link
end
function Scan.priceOf(item)
  local v1 = "Auctionator.API.v1."
  local link = type(item) == "number" and ("item:" .. item) or linkOf(item)
  if not link then return nil end
  local id = tonumber(link:match("item:(%d+)"))
  local ah = call(api(v1 .. "GetAuctionPriceByItemID"), "UpgradeFinder", id)
    or call(api(v1 .. "GetAuctionPriceByItemLink"), "UpgradeFinder", link)
  local vendor = call(api(v1 .. "GetVendorPriceByItemID"), "UpgradeFinder", id)
  if vendor and vendor > 0 and (not ah or vendor < ah) then return vendor, "vendor" end
  return ah, ah and "AH" or nil
end

-- What a recipe row costs to craft (the pattern, if it has an AH price,
-- plus the reagents) and to buy the made item instead (nil for a bind on
-- pickup item, or with no AH price).
-- { total, pattern, reagents, parts = { {name, count, each, from} }, missing, buy, bop }
function Scan.craftCost(c, patternPrice)
  local out = { pattern = patternPrice, reagents = 0, parts = {}, missing = 0, bop = c.bop }
  for _, r in ipairs(c.reagents or {}) do
    local each, from = Scan.priceOf(r[1])
    table.insert(out.parts, { r[1], r[2], each, from })
    if each then out.reagents = out.reagents + each * r[2] else out.missing = out.missing + 1 end
  end
  out.total = (patternPrice or 0) + out.reagents
  if not c.bop then out.buy = Scan.priceOf(c.name) end
  return out
end

-- Rows for S.rank from the cache, with gains against what you wear now.
function Scan.rows(sources)
  local rows = {}
  local price = api("Auctionator.API.v1.GetAuctionPriceByItemID")
  for id, src in pairs(sources) do
    local c = cache[id]
    if c then
      local base, note = S.replaced(c.loc, worn.value, worn.twoHander, worn.dualWield)
      local p = src == "AH" and (call(price, "UpgradeFinder", id)
        or call(api("Auctionator.API.v1.GetAuctionPriceByItemLink"), "UpgradeFinder", "item:" .. id)) or nil
      -- A recipe row costs the pattern plus the reagents.
      local cost = c.recipe and Scan.craftCost(c, p) or nil
      if cost then p = cost.total > 0 and cost.total or nil end
      table.insert(rows, { id = id, name = c.name, loc = c.loc, gain = c.value - (base or 0), price = p, cost = cost,
        reqLevel = c.reqLevel, unusable = c.unusable, source = src, note = note, value = c.value,
        drop = Scan.dropOf(id), recipe = c.recipe, craft = c.craft })
    end
  end
  Scan.lastSources = sources
  return rows
end
