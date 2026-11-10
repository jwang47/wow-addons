-- Bazaar: browse your last full AH scan anywhere, like the AH's Browse
-- tab. The auctions come from LootValue's full scan (LootValueDB.snap:
-- every auction, read when you scan at the AH), the fair price and the
-- sales from LootValue.scan. Without a LootValue scan, Bazaar lists the
-- items in Auctionator's price database with their last price.
--
-- This file has no UI: rows, filters and sorting (tests/bazaar.lua).
local _, ns = ...
ns = ns or {}
local B = {}
ns.core = B
Bazaar = B

local function api(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end
B.api = api

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n end
end
B.call = call

function B.db()
  BazaarDB = BazaarDB or {}
  return BazaarDB
end

function B.money(copper)
  copper = math.floor((copper or 0) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return string.format("%dg %ds", g, s) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return c .. "c"
end

-- "5m", "3h", "2d" since a time() stamp.
function B.ago(stamp)
  local now = call(rawget(_G, "time"))
  if type(stamp) ~= "number" or type(now) ~= "number" then return nil end
  local s = math.max(0, now - stamp)
  if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m ago" end
  if s < 86400 then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / 86400) .. "d ago"
end

---------------------------------------------------------------------------
-- The data source
---------------------------------------------------------------------------
-- { kind = "scan", snap, scan } with a LootValue full scan, { kind =
-- "auctionator", ids } with only Auctionator's prices, or nil.
function B.source()
  local lv, lvdb = rawget(_G, "LootValue"), rawget(_G, "LootValueDB")
  local scan = type(lv) == "table" and type(lv.scan) == "table" and lv.scan or nil
  local snap = type(lvdb) == "table" and type(lvdb.snap) == "table" and lvdb.snap or nil
  if scan and snap and type(snap.items) == "table" and type(scan.decode) == "function" then
    return { kind = "scan", snap = snap, scan = scan, key = "scan:" .. tostring(snap.t) }
  end
  local dbt = api("Auctionator.Database.db")
  if type(dbt) == "table" then
    local ids, seen = {}, {}
    for key in pairs(dbt) do
      local id = tonumber(type(key) == "string" and key:match("^(%d+)$") or key)
      if id and not seen[id] then seen[id] = true table.insert(ids, id) end
    end
    return { kind = "auctionator", ids = ids, key = "auctionator:" .. #ids }
  end
  return nil
end

-- { min (buyout per item), listed (items), auctions } for one snapshot
-- string "owner,count,buyout,band;...".
function B.listing(scan, snap, id)
  local ok, list = pcall(scan.decode, snap.items[id], snap.owners or {})
  if not ok or type(list) ~= "table" then return nil end
  local out = { listed = 0, auctions = #list }
  for _, a in ipairs(list) do
    local count, buyout = a[2], a[3]
    if type(count) == "number" and count > 0 then
      out.listed = out.listed + count
      if type(buyout) == "number" and buyout > 0 then
        local each = buyout / count
        if not out.min or each < out.min then out.min = each end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Rows: one per item. { id, name, lname, quality, ilvl, req, classID,
-- subclassID, icon, min, fair, listed, auctions, sold }. Item names load
-- from the server: a row with no name yet says "item 12345" and fills in
-- when GET_ITEM_INFO_RECEIVED comes (B.fillName).
---------------------------------------------------------------------------
local function itemFields(r)
  local get = api("C_Item.GetItemInfo") or rawget(_G, "GetItemInfo")
  local name, _, quality, ilvl, req, _, _, _, _, icon, _, classID, subclassID = call(get, r.id)
  if name then
    r.name, r.lname, r.quality, r.ilvl, r.req, r.icon = name, name:lower(), quality, ilvl, req, icon
    r.classID, r.subclassID = classID or r.classID, subclassID or r.subclassID
    return true
  end
  if not r.classID then
    local instant = api("C_Item.GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
    local _, _, _, _, ic, cls, sub = call(instant, r.id)
    r.icon, r.classID, r.subclassID = ic, cls, sub
  end
  r.name, r.lname = "item " .. r.id, ""
  call(api("C_Item.RequestLoadItemDataByID"), r.id)
  return false
end

-- The build runs in slices (B.step) so a big scan does not freeze the game.
local build -- { key, source, ids, i, rows, byID, missing }

function B.begin()
  local src = B.source()
  if not src then build = nil return nil end
  if build and build.key == src.key then return build end
  local ids = {}
  if src.kind == "scan" then
    for id in pairs(src.snap.items) do if type(id) == "number" then table.insert(ids, id) end end
  else
    ids = src.ids
  end
  table.sort(ids)
  build = { key = src.key, source = src, ids = ids, i = 0, rows = {}, byID = {}, missing = 0 }
  return build
end

-- Builds rows until budget (ms) runs out; true when done.
B.SLICE = 50
function B.step(budget)
  local b = build or B.begin()
  if not b then return true end
  local clock = rawget(_G, "debugprofilestop")
  local start = clock and clock() or 0
  local src = b.source
  local price = api("Auctionator.API.v1.GetAuctionPriceByItemID")
  while b.i < #b.ids do
    for _ = 1, B.SLICE do
      b.i = b.i + 1
      local id = b.ids[b.i]
      if not id then break end
      local r = { id = id }
      if src.kind == "scan" then
        local l = B.listing(src.scan, src.snap, id)
        if l then r.min, r.listed, r.auctions = l.min, l.listed, l.auctions end
        r.fair = call(src.scan.price, id)
        local st = call(src.scan.stats, id)
        r.sold = type(st) == "table" and st.sold or nil
      else
        local p = call(price, "Bazaar", id)
        r.min = type(p) == "number" and p > 0 and p or nil
      end
      if r.min or r.listed then
        if not itemFields(r) then b.missing = b.missing + 1 end
        table.insert(b.rows, r)
        b.byID[id] = r
      end
    end
    if budget and clock and clock() - start > budget then return false end
  end
  return true
end

function B.buildAll()
  B.begin()
  while not B.step() do end
  return build
end

function B.progress()
  if not build then return 0, 0 end
  return build.i, #build.ids
end

function B.current() return build end

-- An item's data arrived: fill its row. True when a row changed.
function B.fillName(id)
  local r = build and build.byID[id]
  if not r or r.lname ~= "" then return false end
  if itemFields(r) then
    build.missing = math.max(0, build.missing - 1)
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Filters: { text, classID, subclassID, minReq, maxReq, maxPrice }.
-- Every word of text must appear in the name.
---------------------------------------------------------------------------
function B.matches(r, f)
  if f.classID and r.classID ~= f.classID then return false end
  if f.subclassID and r.subclassID ~= f.subclassID then return false end
  if f.minReq and (r.req or 0) < f.minReq then return false end
  if f.maxReq and (r.req or 0) > f.maxReq then return false end
  if f.maxPrice and (not r.min or r.min > f.maxPrice) then return false end
  if f.text and f.text ~= "" then
    for w in f.text:lower():gmatch("%S+") do
      if not r.lname:find(w, 1, true) then return false end
    end
  end
  return true
end

-- Sort keys: name, req, listed, min, fair, sold. Missing numbers go last.
B.SORTS = { "name", "req", "listed", "min", "fair", "sold" }
function B.sorter(key, desc)
  return function(a, b)
    local x, y = a[key], b[key]
    if key == "name" then x, y = a.lname ~= "" and a.lname or a.name, b.lname ~= "" and b.lname or b.name end
    if x == nil and y ~= nil then return false end
    if y == nil and x ~= nil then return true end
    if x ~= nil and x ~= y then
      if desc then return x > y end
      return x < y
    end
    return a.id < b.id
  end
end

function B.query(f, key, desc)
  local out = {}
  for _, r in ipairs(build and build.rows or {}) do
    if B.matches(r, f) then table.insert(out, r) end
  end
  table.sort(out, B.sorter(key or "sold", desc))
  return out
end

-- Categories in the rows: { { classID, name, count, subs = { { subclassID,
-- name, count } } } }, by name.
function B.categories()
  local classes, list = {}, {}
  for _, r in ipairs(build and build.rows or {}) do
    if r.classID then
      local c = classes[r.classID]
      if not c then
        local name = call(api("C_Item.GetItemClassInfo"), r.classID) or call(rawget(_G, "GetItemClassInfo"), r.classID)
        c = { classID = r.classID, name = name or ("class " .. r.classID), count = 0, subs = {}, bySub = {} }
        classes[r.classID] = c
        table.insert(list, c)
      end
      c.count = c.count + 1
      if r.subclassID then
        local s = c.bySub[r.subclassID]
        if not s then
          local name = call(api("C_Item.GetItemSubClassInfo"), r.classID, r.subclassID)
            or call(rawget(_G, "GetItemSubClassInfo"), r.classID, r.subclassID)
          s = { subclassID = r.subclassID, name = name or ("type " .. r.subclassID), count = 0 }
          c.bySub[r.subclassID] = s
          table.insert(c.subs, s)
        end
        s.count = s.count + 1
      end
    end
  end
  local byName = function(a, b) return a.name < b.name end
  table.sort(list, byName)
  for _, c in ipairs(list) do table.sort(c.subs, byName) end
  return list
end

-- The footer: where the data comes from and how old it is.
function B.sourceText()
  local b = build
  if not b then return "No AH data. Open the AH and run a full scan (LootValue's Scan button)." end
  local src = b.source
  if src.kind == "scan" then
    local age = B.ago(src.snap.t)
    return string.format("Full scan %s: %d auctions of %d items", age or "", src.snap.n or 0, #b.rows)
  end
  return string.format("Auctionator prices only (%d items). A LootValue full scan adds listings and sales.", #b.rows)
end
