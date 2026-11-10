-- LootValue: what to do with an item, from Auctionator's prices.
-- Adds one tooltip line, "LootValue: Vendor 10s  (or AH 10s, disenchant 4s)": the
-- option that pays most, with the AH counted as a sure sale only when it
-- clearly pays more (see ahWins). Works for any character; MageMentor, when
-- installed, draws this line itself after its own advice (equip, keep for
-- Tailoring) and LootValue's own tooltip hook stays quiet.
-- Auctionator API (v342, 2026-11-08): Auctionator.API.v1.* with the
-- caller ID first; prices are copper or nil.
local LV = {}
LootValue = LV

local CALLER = "LootValue"
local C_GOLD, C_GREY = "|cffffd100", "|cff9d9d9d"
local R = "|r"

local function api()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

-- Calls an Auctionator API function; nil when Auctionator is missing or errors.
local function call(fn, ...)
  local a = api()
  if not a or not a[fn] then return nil end
  local ok, value = pcall(a[fn], CALLER, ...)
  if ok then return value end
  return nil
end
LV.call = call

function LV.hasAuctionator() return api() ~= nil end

-- When Auctionator last scanned the AH (unix seconds), or nil. Auctionator
-- keeps TimeOfLast...Scan fields in its saved state (Auctionator.SavedState,
-- the AUCTIONATOR_SAVEDVARS table). TimeOfLastBrowseScan changes on every AH
-- search or browse page, which sees only the items it showed; the other
-- fields (GetAll, Replicate) are full scans of every listing.
-- kind: "full", "search" or nil (any). Omni and MageMentor use
-- LootValue.scanText() too.
function LV.lastScan(kind)
  local state = Auctionator and Auctionator.SavedState
  if type(state) ~= "table" then state = rawget(_G, "AUCTIONATOR_SAVEDVARS") end
  if type(state) ~= "table" then return nil end
  local newest
  for k, v in pairs(state) do
    local search = k == "TimeOfLastBrowseScan"
    if type(k) == "string" and k:find("^TimeOfLast.*Scan$") and type(v) == "number" and v > 0
      and (not kind or (kind == "search") == search) and (not newest or v > newest) then newest = v end
  end
  return newest
end

-- Local midnight today (unix seconds). Auctionator counts price days from
-- local midnight, so a full scan after it holds today's price of every
-- item that was listed.
function LV.midnight()
  local now = time and time() or 0
  local date = rawget(_G, "date") or (os and os.date)
  local ok, t = pcall(date, "*t", now)
  if not ok or type(t) ~= "table" then return nil end
  return now - (t.hour or 0) * 3600 - (t.min or 0) * 60 - (t.sec or 0)
end

-- True when a full scan ran today: an item with an older price was not listed.
function LV.fullScanToday()
  local full, midnight = LV.lastScan("full"), LV.midnight()
  return full ~= nil and midnight ~= nil and full >= midnight
end

-- "5m ago", "3h ago", "2d ago".
function LV.ago(t)
  local s = math.max(0, (time and time() or 0) - t)
  if s < 60 then return "just now" end
  if s < 3600 then return math.floor(s / 60) .. "m ago" end
  if s < 86400 then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / 86400) .. "d ago"
end

-- "AH full scan 3h ago", or "AH search 13m ago, no full scan" when
-- Auctionator only saw searches; nil when the scan time is unknown.
function LV.scanText()
  local full = LV.lastScan("full")
  if full then return "AH full scan " .. LV.ago(full) end
  local search = LV.lastScan("search")
  return search and ("AH search " .. LV.ago(search) .. ", no full scan") or nil
end

function LV.money(copper)
  if not copper then return "?" end
  copper = math.floor(copper + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return s > 0 and string.format("%dg%ds", g, s) or (g .. "g") end
  if s > 0 then return (copper >= 1000 or c == 0) and (s .. "s") or string.format("%ds%dc", s, c) end
  return c .. "c"
end

local function itemID(link)
  return tonumber(link and link:match("item:(%d+)"))
end

-- Profession rank by name, from the profession API or the skill list.
local function professionRank(prof)
  if GetProfessions and GetProfessionInfo then
    local p1, p2 = GetProfessions()
    for _, idx in ipairs({ p1 or 0, p2 or 0 }) do
      if idx > 0 then
        local name, _, rank = GetProfessionInfo(idx)
        if name == prof then return rank end
      end
    end
  end
  if not GetNumSkillLines or not GetSkillLineInfo then return nil end
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if not isHeader and name == prof then return rank end
  end
  return nil
end

-- Enchanting from the skill list, or the Disenchant spell (13262) if the
-- skill list doesn't name it.
function LV.knowsEnchanting()
  if professionRank("Enchanting") then return true end
  -- Try each API that exists; one that errors falls through to the next.
  for _, known in ipairs({ C_SpellBook and C_SpellBook.IsSpellKnown or false, IsPlayerSpell or false,
    IsSpellKnown or false }) do
    if known then
      local ok, yes = pcall(known, 13262)
      if ok and yes then return true end
    end
  end
  return false
end

-- Expected disenchant value from the Classic disenchant table and the AH
-- prices of the materials, for when Auctionator has no disenchant price
-- (Auctionator loads its Classic disenchant tables only on classic game
-- types, and Forever runs its modern code, so it has none). Rows: highest item level, then
-- { dust, min, max }, { essence, min, max }, { shard, chance } for green
-- armor; weapons swap the dust and essence chances (75% essence). Blue items
-- give one shard. From the Classic table (wowhead), 2026-11-08: Forever may
-- differ, so the line says "~".
local DUST = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local ESS = { lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134,
  gmystic = 11135, lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203 }
local SHARD = { sglimmer = 10978, lglimmer = 11084, sglow = 11138, lglow = 11139, sradiant = 11177,
  lradiant = 11178, sbrilliant = 14343, lbrilliant = 14344 }
local DE_GREEN = {
  { 15, { DUST.strange, 1, 2 }, { ESS.lmagic, 1, 2 }, { nil, 0 } },
  { 20, { DUST.strange, 2, 3 }, { ESS.gmagic, 1, 2 }, { SHARD.sglimmer, 0.05 } },
  { 25, { DUST.strange, 4, 6 }, { ESS.lastral, 1, 2 }, { SHARD.sglimmer, 0.10 } },
  { 30, { DUST.soul, 1, 2 }, { ESS.gastral, 1, 2 }, { SHARD.lglimmer, 0.05 } },
  { 35, { DUST.soul, 2, 5 }, { ESS.lmystic, 1, 2 }, { SHARD.sglow, 0.05 } },
  { 40, { DUST.vision, 1, 2 }, { ESS.gmystic, 1, 2 }, { SHARD.lglow, 0.05 } },
  { 45, { DUST.vision, 2, 5 }, { ESS.lnether, 1, 2 }, { SHARD.sradiant, 0.05 } },
  { 50, { DUST.dream, 1, 2 }, { ESS.gnether, 1, 2 }, { SHARD.lradiant, 0.05 } },
  { 55, { DUST.dream, 2, 5 }, { ESS.leternal, 1, 2 }, { SHARD.sbrilliant, 0.05 } },
  { 60, { DUST.illusion, 1, 2 }, { ESS.geternal, 1, 2 }, { SHARD.lbrilliant, 0.05 } },
  { 65, { DUST.illusion, 2, 5 }, { ESS.geternal, 2, 3 }, { SHARD.lbrilliant, 0.05 } },
}
local DE_BLUE = { { 25, SHARD.sglimmer }, { 30, SHARD.lglimmer }, { 35, SHARD.sglow }, { 40, SHARD.lglow },
  { 45, SHARD.sradiant }, { 50, SHARD.lradiant }, { 55, SHARD.sbrilliant }, { 65, SHARD.lbrilliant } }
LV.DE_GREEN, LV.DE_BLUE = DE_GREEN, DE_BLUE

-- Three lesser essences make one greater and back, so a lesser essence is
-- worth at most a third of a greater (as Auctionator's Classic code does).
local GREATER = { [ESS.lmagic] = ESS.gmagic, [ESS.lastral] = ESS.gastral, [ESS.lmystic] = ESS.gmystic,
  [ESS.lnether] = ESS.gnether, [ESS.leternal] = ESS.geternal }
local function matPrice(id)
  local p = call("GetAuctionPriceByItemID", id)
  local g = GREATER[id] and call("GetAuctionPriceByItemID", GREATER[id])
  if g then p = p and math.min(p, g / 3) or g / 3 end
  return p
end

-- Copper, or nil when the item can't be estimated or its dust or essence
-- has no price.
function LV.estimateDisenchant(link)
  local info = C_Item and C_Item.GetItemInfo
  if not info then return nil end
  local ok, _, _, quality, ilvl, _, _, _, _, _, _, _, classID = pcall(info, link)
  if not ok or type(quality) ~= "number" or type(ilvl) ~= "number" then return nil end
  if quality == 3 then
    for _, row in ipairs(DE_BLUE) do
      if ilvl <= row[1] then return matPrice(row[2]) end
    end
    return nil
  end
  if quality ~= 2 or ilvl < 5 then return nil end
  for _, row in ipairs(DE_GREEN) do
    if ilvl <= row[1] then
      local weapon = classID == 2
      local dust, ess, shard = row[2], row[3], row[4]
      local shardChance = shard[2]
      local pDust = weapon and 0.20 or (1 - shardChance) - 0.20
      local pEss = weapon and (1 - shardChance) - 0.20 or 0.20
      local dp, ep = matPrice(dust[1]), matPrice(ess[1])
      if not dp or not ep then return nil end
      local value = pDust * dp * (dust[2] + dust[3]) / 2 + pEss * ep * (ess[2] + ess[3]) / 2
      if shard[1] and shardChance > 0 then
        -- Shards are rare (5-10%); an unpriced one counts as nothing.
        value = value + shardChance * (matPrice(shard[1]) or 0)
      end
      return math.floor(value + 0.5)
    end
  end
  return nil
end

-- How the AH market for an item looks, from Auctionator's history (today's
-- listings, price trend) and price age: { listed, age, slow, note }.
-- "slow" when many are listed (50+ items, or 50+ full stacks), the low fell 10% or more since the last
-- scan day, the price is 3+ days old, or today's full scan did not see the item.
function LV.marketInfo(link)
  local info = {}
  local db = Auctionator and Auctionator.Database
  local key = Auctionator and Auctionator.Utilities and Auctionator.Utilities.BasicDBKeyFromLink
  if db and db.GetPriceHistory and key then
    local ok, hist = pcall(function() return db:GetPriceHistory(key(link)) end)
    -- Internal data: use only fields of the expected type.
    local function num(entry, field)
      local v = type(entry) == "table" and entry[field]
      return type(v) == "number" and v or nil
    end
    if ok and type(hist) == "table" then
      info.listed = num(hist[1], "available")
      local now, before = num(hist[1], "minSeen"), num(hist[2], "minSeen")
      info.falling = now and before and now <= before * 0.9 or false
    end
  end
  local age = call("GetAuctionAgeByItemLink", link)
  info.age = type(age) == "number" and age or nil
  -- Auctionator counts items, not auctions: 50 full stacks of a trade good
  -- is as crowded as 50 single items.
  local stack = 1
  local maxStack = C_Item and C_Item.GetItemMaxStackCount
  if maxStack then
    local ok, n = pcall(maxStack, link)
    if ok and type(n) == "number" and n > 1 then stack = n end
  end
  local notes = {}
  -- Today's full scan did not see it: the listings and trend are old news.
  info.unlisted = info.age ~= nil and info.age >= 1 and LV.fullScanToday()
  if info.unlisted then
    table.insert(notes, "not in today's full scan")
  end
  if not info.unlisted and info.listed and info.listed >= 50 * stack then
    table.insert(notes, "slow: " .. info.listed .. " listed")
  end
  if not info.unlisted and info.falling then table.insert(notes, "price falling") end
  if not info.unlisted and info.age and info.age >= 3 then
    table.insert(notes, "price " .. info.age .. " days old")
  end
  info.slow = #notes > 0
  info.note = #notes > 0 and table.concat(notes, ", ") or nil
  return info
end

-- An AH sale is not sure. It wins over the best sure option only when, after
-- the 5% cut and the deposit you lose if it doesn't sell (about 30% of the
-- vendor price for 24 h, as on the Classic AH), it pays 1.5x as much and at
-- least 1s more (2x when the market looks slow). With no sure option it wins.
function LV.ahWins(ah, vendor, sure, slow)
  if not sure or sure <= 0 then return true end
  local net = math.floor(ah * 0.95) - math.floor((vendor or 0) * 0.3)
  return net >= sure * (slow and 2 or 1.5) and net - sure >= 100
end

-- "LootValue: <what to do>": the best option, then the others in grey. The
-- AH and disenchant amounts are estimates, so they get "~".
local ACTION = { Vendor = "Vendor", AH = "AH", ["AH (if tradable)"] = "AH if tradable", Disenchant = "Disenchant" }
local OTHER = { Vendor = "vendor", AH = "AH", ["AH (if tradable)"] = "AH if tradable", Disenchant = "disenchant" }

-- The advice tooltip line for an item, or nil. isGear: the item can be
-- disenchanted (equippable gear). ctx (from the tooltip text): bound = this
-- copy can't be auctioned; without ctx the AH entry says "if tradable".
function LV.adviceLine(link, isGear, ctx)
  local id = itemID(link)
  if not id or not LV.hasAuctionator() then return nil end
  local ah = call("GetAuctionPriceByItemLink", link) or call("GetAuctionPriceByItemID", id)
  local options = {}
  -- Disenchant: gear only, when you know Enchanting. "disenchant: no price" when
  -- Auctionator has no price for it, so a missing price is visible.
  local deUnknown = false
  if isGear and LV.knowsEnchanting() then
    local de = call("GetDisenchantPriceByItemLink", link)
    if not de or de <= 0 then de = LV.estimateDisenchant(link) end
    if de and de > 0 then table.insert(options, { "Disenchant", de }) else deUnknown = true end
  end
  -- The game's sell price. Not Auctionator's GetVendorPrice*: that is what a
  -- vendor charges you (Rune of Teleportation: 9s to buy, 2s50c to sell).
  local vendor
  if C_Item and C_Item.GetItemInfo then
    local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, link)
    if ok and type(sell) == "number" then vendor = sell end
  end
  if vendor and vendor > 0 then table.insert(options, { "Vendor", vendor }) end
  table.sort(options, function(a, b) return a[2] > b[2] end)
  if ah and not (ctx and ctx.bound) then
    local market = LV.marketInfo(link)
    local entry = { ctx and "AH" or "AH (if tradable)", math.floor(ah * 0.95), market.note }
    if LV.ahWins(ah, vendor, options[1] and options[1][2] or 0, market.slow) then
      table.insert(options, 1, entry)
    else
      table.insert(options, 2, entry)
    end
  end
  if #options == 0 or (#options < 2 and not deUnknown and not options[1][1]:find("^AH")) then return nil end
  local function note(o) return o[3] and (" (" .. o[3] .. ")") or "" end
  local best = options[1]
  local rest = {}
  for i = 2, #options do
    local o = options[i]
    table.insert(rest, (OTHER[o[1]] or o[1]) .. " " .. LV.money(o[2]) .. note(o))
  end
  if deUnknown then table.insert(rest, "disenchant: no price") end
  -- With an AH price on the line, say how old the AH snapshot is.
  local scan = ah and not (ctx and ctx.bound) and LV.scanText()
  return string.format("%s  LootValue: %s %s%s%s%s%s", C_GOLD, ACTION[best[1]] or best[1],
    best[1] == "Vendor" and "" or "~", LV.money(best[2]) .. note(best), R,
    #rest > 0 and (C_GREY .. "  (or " .. table.concat(rest, ", ") .. ")" .. R) or "",
    scan and (C_GREY .. "  · " .. scan .. R) or "")
end

---------------------------------------------------------------------------
-- Tooltip, when LootValue runs on its own.
---------------------------------------------------------------------------

-- The game colours a requirement you don't meet red, and says when a copy is
-- bound; read both from the tooltip text.
local BOUND = {}
for _, key in ipairs({ "ITEM_SOULBOUND", "ITEM_BIND_ON_PICKUP", "ITEM_BIND_QUEST", "ITEM_ACCOUNTBOUND",
  "ITEM_BNETACCOUNTBOUND" }) do
  local t = rawget(_G, key)
  if type(t) == "string" then BOUND[t] = true end
end
for _, t in ipairs({ "Soulbound", "Binds when picked up", "Quest Item" }) do BOUND[t] = true end

local function readContext(tooltip)
  local ctx = { bound = false }
  local name = tooltip.GetName and tooltip:GetName()
  if not name or not tooltip.NumLines then return ctx end
  for i = 1, tooltip:NumLines() do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs:GetText()
    if t and BOUND[t] then ctx.bound = true end
  end
  return ctx
end

-- Not disenchantable even though they can be equipped.
local NO_DISENCHANT = { [""] = true, INVTYPE_BAG = true, INVTYPE_AMMO = true, INVTYPE_QUIVER = true,
  INVTYPE_BODY = true, INVTYPE_TABARD = true }
function LV.isGear(link)
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not instant then return false end
  local ok, _, _, _, loc = pcall(instant, link)
  return ok and loc ~= nil and not NO_DISENCHANT[loc] or false
end

-- MageMentor sets LootValue.deferTo = "MageMentor" and draws the line itself.
function LV.onTooltipItem(tooltip)
  if LV.deferTo or not tooltip.GetItem then return end
  local name = tooltip.GetName and tooltip:GetName()
  if name and name:find("Scan") then return end
  local _, link = tooltip:GetItem()
  if not link then return end
  local line = LV.adviceLine(link, LV.isGear(link), readContext(tooltip))
  if line then
    tooltip:AddLine(line)
    tooltip:Show()
  end
end

local function guarded(tt)
  local ok, err = pcall(LV.onTooltipItem, tt)
  if not ok and not LV.reported then
    LV.reported = true
    print("|cffffd100LootValue|r: tooltip error: " .. tostring(err))
  end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, guarded)
elseif GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnTooltipSetItem", guarded)
  if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", guarded) end
end
