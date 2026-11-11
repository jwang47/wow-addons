-- LootValue scan: what sells on the AH, from two full scans.
--
-- Auctionator's Full Scan in summary mode keeps one row per item per day
-- (lowest price, how many listed). LootValue reads the same full scan, or
-- its own (the Scan button on the AH window), and keeps every auction:
-- item, seller, stack, buyout and time left. The next scan shows which
-- auctions are gone. An auction that is gone while it still had more time
-- left than passed between the scans did not expire, so it sold (or its
-- seller cancelled it; a seller who posts the same stack again at another
-- price counts as a repost, not a sale). The tooltip then says
-- "AH market: ~34 sold in 2d, 120 listed, ~9s each".
--
-- No freeze: the rows are read in slices of a few milliseconds a frame.
-- The server sends the whole list at once; only reading it needs the AH
-- window open, which takes a second or two. Then the status says "read"
-- and the compare runs on in the background while you walk away. A scan
-- that the AH closes before it is read is dropped, so a part list never
-- looks like sales.
--
-- Status and progress show above the AH window on every tab. /lv scan
-- prints it; /lv scan now starts a full scan.
local LV = LootValue
local S = {}
LV.scan = S

local C_GOLD, C_GREY = "|cffffd100", "|cff9d9d9d"
local R = "|r"
local PREFIX = C_GOLD .. "LootValue:" .. R .. " "

S.READ_MS = 10        -- per frame while the AH window is open
S.WORK_MS = 3         -- per frame for the compare, which runs anywhere
S.SLICE = 100         -- rows between clock checks
S.GAP = 15 * 60       -- the server allows one full scan per 15 minutes
S.FULL_ROWS = 1000    -- a list this long is a full scan, even unrequested
S.MIN_DT = 120        -- a scan this soon after the last one is ignored
S.KEEP = 3 * 86400    -- compare results kept per item
S.KEEP_N = 8
S.SHOW = 2 * 86400    -- the tooltip sums the last 2 days
-- Least time an auction had left, by time-left band (1 short ... 4 very
-- long): under 30 min, 30 min to 2 h, 2 to 8 h, over 8 h.
S.MIN_LEFT = { 0, 1800, 7200, 28800 }

local function now() return time and time() or 0 end
local function clock()
  local f = rawget(_G, "debugprofilestop")
  return type(f) == "function" and f() or nil
end
local function after(fn)
  local t = rawget(_G, "C_Timer")
  if t and t.After then t.After(0, fn) else fn() end
end
local function say(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) else print(PREFIX .. msg) end end

local function db()
  LootValueDB = LootValueDB or {}
  local d = LootValueDB
  d.market = d.market or {}
  return d
end
S.db = db

---------------------------------------------------------------------------
-- The two AH APIs. Both return rows in the same order: name, texture,
-- count, quality, canUse, level, levelType, minBid, minIncrement, buyout,
-- bidAmount, highBidder, bidder, owner, ownerFull, saleStatus, itemID.
---------------------------------------------------------------------------

local function modern()
  local ah = rawget(_G, "C_AuctionHouse")
  if type(ah) == "table" and ah.ReplicateItems and ah.GetNumReplicateItems and ah.GetReplicateItemInfo then
    return ah
  end
end

S.api = {}
function S.api.num()
  local ah = modern()
  if ah then return ah.GetNumReplicateItems() or 0 end
  if GetNumAuctionItems then
    local batch, total = GetNumAuctionItems("list")
    return batch or total or 0
  end
  return 0
end

-- itemID, owner, count, buyout, time-left band (1-4) of row i (from 1).
function S.api.row(i)
  local ah = modern()
  local count, buyout, owner, id, tl, link
  if ah then
    local _
    _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, id = ah.GetReplicateItemInfo(i - 1)
    local band = ah.GetReplicateItemTimeLeft and ah.GetReplicateItemTimeLeft(i - 1)
    tl = type(band) == "number" and band + 1 or nil -- 0-based bands there
    if not id and ah.GetReplicateItemLink then link = ah.GetReplicateItemLink(i - 1) end
  elseif GetAuctionItemInfo then
    local _
    _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, id = GetAuctionItemInfo("list", i)
    tl = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("list", i)
    if not id and GetAuctionItemLink then link = GetAuctionItemLink("list", i) end
  end
  id = id or tonumber(link and link:match("item:(%d+)"))
  return id, owner, count, buyout, tl
end

function S.api.request()
  local ah = modern()
  if ah then ah.ReplicateItems() return true end
  if QueryAuctionItems then
    QueryAuctionItems("", nil, nil, 0, false, -1, true)
    return true
  end
  return false
end

-- Seconds until a full scan is allowed (0 = now), or nil when no AH API.
function S.wait()
  local last = db().lastRequest or 0
  local left = math.max(0, S.GAP - (now() - last))
  if not modern() and CanSendAuctionQuery then
    local _, all = CanSendAuctionQuery()
    if all then return 0 end
    return math.max(left, 1)
  end
  return left
end

---------------------------------------------------------------------------
-- Job state: idle, waiting (for the server), reading, working, failed.
---------------------------------------------------------------------------

local job = { state = "idle" }
S.job = job
S.ahOpen = false

local function setState(state, extra)
  for k in pairs(job) do job[k] = nil end
  job.state = state
  for k, v in pairs(extra or {}) do job[k] = v end
  if S.paint then S.paint() end
end

-- 164749 -> "164,749".
function S.number(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local function pct(a, b) return b and b > 0 and math.floor(a * 100 / b) or 0 end

function S.statusText()
  local st = job.state
  if st == "waiting" then return "full scan: waiting for the server..." end
  if st == "reading" then
    return string.format("full scan: reading %d%% - stay at the AH", pct(job.done or 0, job.total))
  end
  if st == "working" then
    return string.format("full scan read, comparing %d%% (you can walk away)", pct(job.done or 0, job.total))
  end
  local d = db()
  local parts = {}
  if st == "failed" then table.insert(parts, job.why) end
  if d.snap and d.snap.t then
    table.insert(parts, string.format("last full scan %s (%s auctions)", LV.ago(d.snap.t), S.number(d.snap.n or 0)))
  else
    table.insert(parts, "no full scan yet")
  end
  local w = S.wait()
  if w == 0 then table.insert(parts, "full scan ready")
  elseif w then table.insert(parts, "next full scan in " .. math.ceil(w / 60) .. "m") end
  return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Snapshots: one string per item, "owner,count,buyout,band;..." with the
-- owner as an index into snap.owners.
---------------------------------------------------------------------------

function S.decode(str, owners)
  local list = {}
  for o, c, b, t in (str or ""):gmatch("(%d+),(%d+),(%d+),(%d+)") do
    table.insert(list, { owners[tonumber(o)] or "", tonumber(c), tonumber(b), tonumber(t) })
  end
  return list
end

-- The weighted median of { value, weight } pairs, or nil.
function S.wmedian(list)
  local total = 0
  for _, p in ipairs(list) do total = total + p[2] end
  if total <= 0 then return nil end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local cum = 0
  for _, p in ipairs(list) do
    cum = cum + p[2]
    if cum >= total / 2 then return p[1] end
  end
end

-- A fair buyout price per item from one scan's auctions, with outliers
-- dropped. Take the cheapest auctions until they hold 15% of the items
-- listed and at least 3 auctions (up to 30% while the price climbs less
-- than 20% a step). Drop the ones under 0.6x or over 1.67x the median
-- auction of that window, so a lone cheap or silly listing does not set
-- the price, even in a thin market; the price is the item-weighted mean
-- of the rest. nil with fewer than 2 auctions with a buyout.
function S.fairPrice(entries)
  local units, total = {}, 0
  for _, e in ipairs(entries) do
    if e[3] > 0 and e[2] > 0 then
      units[#units + 1] = { e[3] / e[2], e[2] }
      total = total + e[2]
    end
  end
  if #units < 2 then return nil end
  table.sort(units, function(a, b) return a[1] < b[1] end)
  local window, cum = {}, 0
  for i, u in ipairs(units) do
    local prev = units[i - 1]
    if cum >= total * 0.15 and #window >= 3
      and (cum >= total * 0.3 or (prev and u[1] > prev[1] * 1.2)) then break end
    window[#window + 1] = u
    cum = cum + u[2]
  end
  local mid = window[math.floor((#window + 1) / 2)][1] -- by auction, not by item
  local sum, w = 0, 0
  for _, u in ipairs(window) do
    if u[1] >= mid * 0.6 and u[1] <= mid / 0.6 then sum, w = sum + u[1] * u[2], w + u[2] end
  end
  if w == 0 then return math.floor(mid + 0.5) end
  return math.floor(sum / w + 0.5)
end

-- How a vanished auction ended can only be told from its time-left band:
-- gone while it had more time left than passed between the scans, it did
-- not expire. A band outside 1-4 tells nothing.
local function canSee(band, dt)
  local least = S.MIN_LEFT[band]
  return least ~= nil and dt < least
end

-- Compares one item's auctions: prev and new are lists of
-- { owner, count, buyout, band }; dt is seconds between the scans; me is
-- your own name (your auctions are left out: the mails count those).
-- Returns a table: sold and soldN (items and auctions that sold), gone,
-- listed, posted (items), median and priced (median price per item of
-- the sold ones, and their items), atRisk and prevListed (items in the
-- last scan whose end the compare could see, and all of them).
function S.compare(prev, new, dt, me)
  local r = { sold = 0, soldN = 0, gone = 0, listed = 0, posted = 0, median = 0, priced = 0,
    atRisk = 0, prevListed = 0 }
  local function mine(e) return me and e[1] == me end
  -- Match the auctions that stayed: same seller, stack and buyout.
  local before = {}
  for _, e in ipairs(prev) do
    if not mine(e) then
      local k = e[1] .. "|" .. e[2] .. "|" .. e[3]
      before[k] = before[k] or {}
      table.insert(before[k], e)
      r.prevListed = r.prevListed + e[2]
      if e[3] > 0 and canSee(e[4], dt) then r.atRisk = r.atRisk + e[2] end
    end
  end
  local appeared = {}
  for _, e in ipairs(new) do
    if not mine(e) then
      r.listed = r.listed + e[2]
      local k = e[1] .. "|" .. e[2] .. "|" .. e[3]
      local list = before[k]
      if list and #list > 0 then
        -- The one with the most time left stays; the shortest ones went.
        table.sort(list, function(a, b) return a[4] < b[4] end)
        table.remove(list)
      else
        appeared[#appeared + 1] = e
      end
    end
  end
  local vanished = {}
  for _, list in pairs(before) do
    for _, e in ipairs(list) do vanished[#vanished + 1] = e end
  end
  -- A seller name the client did not know in one of the scans: match
  -- again on stack and buyout alone.
  local byStack = {}
  for i, e in ipairs(appeared) do
    local k = e[2] .. "|" .. e[3]
    byStack[k] = byStack[k] or {}
    table.insert(byStack[k], i)
  end
  local still = {}
  for _, e in ipairs(vanished) do
    local list = byStack[e[2] .. "|" .. e[3]]
    local hit
    if list then
      for j, i in ipairs(list) do
        local a = appeared[i]
        if a and (a[1] == "" or e[1] == "") then hit = j break end
      end
    end
    if hit then
      appeared[list[hit]] = false
      table.remove(list, hit)
    else
      still[#still + 1] = e
    end
  end
  -- New items per seller: a seller who took auctions down and posted the
  -- same item again (any price or stack size) did not sell those.
  local postedBy = {}
  for _, a in ipairs(appeared) do
    if a then
      r.posted = r.posted + a[2]
      if a[1] ~= "" then postedBy[a[1]] = (postedBy[a[1]] or 0) + a[2] end
    end
  end
  local prices = {}
  for _, e in ipairs(still) do
    r.gone = r.gone + e[2]
    -- No buyout: a bid-only auction gone early was taken down.
    if e[3] > 0 and canSee(e[4], dt) then
      local re = e[1] ~= "" and math.min(postedBy[e[1]] or 0, e[2]) or 0
      if re > 0 then postedBy[e[1]] = postedBy[e[1]] - re end
      local n = e[2] - re
      if n > 0 then
        r.sold = r.sold + n
        r.soldN = r.soldN + (re > 0 and 0 or 1)
        prices[#prices + 1] = { e[3] / e[2], n }
        r.priced = r.priced + n
      end
    end
  end
  r.median = math.floor((S.wmedian(prices) or 0) + 0.5)
  return r
end

---------------------------------------------------------------------------
-- The scan job.
---------------------------------------------------------------------------

local function overBudget(t0, ms)
  local t = clock()
  return not t or not t0 or t - t0 >= ms
end

local function run(co, ms)
  local function step()
    if job.co ~= co then return end
    local t0 = clock()
    S.deadline = function() return overBudget(t0, ms()) end
    local ok, err = coroutine.resume(co)
    if not ok then
      setState("failed", { why = "scan error: " .. tostring(err) })
      say("scan error: " .. tostring(err))
      return
    end
    if S.paint then S.paint() end
    if coroutine.status(co) ~= "dead" then after(step) end
  end
  step()
end

local function finish(snap, prev, soldAuctions)
  db().snap = snap
  local text = string.format("full scan read: %s auctions of %s items.", S.number(snap.n), S.number(snap.itemCount))
  if prev then
    text = text .. string.format(" Since the full scan %s: about %d auctions sold.", LV.ago(prev.t), soldAuctions)
  else
    text = text .. " Sales show after the next full scan."
  end
  setState("idle")
  say(text)
end

-- The compare and the new snapshot, in slices; runs with the AH closed too.
local function work(rows, owners)
  local d = db()
  local prev = d.snap
  local t = now()
  local dt = prev and prev.t and t - prev.t
  local ids, seen = {}, {}
  for id in pairs(rows) do ids[#ids + 1] = id seen[id] = true end
  if prev and prev.items then
    for id in pairs(prev.items) do if not seen[id] then ids[#ids + 1] = id end end
  end
  job.total, job.done = #ids, 0
  local snap = { t = t, owners = owners, items = {}, fair = {}, n = 0, itemCount = 0 }
  local ownerIdx = {}
  for i, o in ipairs(owners) do ownerIdx[o] = i end
  local soldAuctions = 0
  local me = UnitName and UnitName("player")
  local visited = {}
  for i, id in ipairs(ids) do
    local new = rows[id] or {}
    if #new > 0 then
      local parts = {}
      for j, e in ipairs(new) do
        parts[j] = (ownerIdx[e[1]] or 0) .. "," .. e[2] .. "," .. e[3] .. "," .. e[4]
      end
      snap.items[id] = table.concat(parts, ";")
      snap.fair[id] = S.fairPrice(new)
      snap.n = snap.n + #new
      snap.itemCount = snap.itemCount + 1
    end
    if prev and prev.items then
      local old = S.decode(prev.items[id], prev.owners or {})
      local c = S.compare(old, new, dt, me)
      soldAuctions = soldAuctions + c.soldN
      local hist = d.market[id] or {}
      -- t, dt, sold, soldN, gone, listed, posted, median, priced, atRisk, prevListed
      hist[#hist + 1] = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d", t, dt, c.sold, c.soldN, c.gone,
        c.listed, c.posted, c.median, c.priced, c.atRisk, c.prevListed)
      while #hist > S.KEEP_N or (hist[1] and tonumber(hist[1]:match("^(%d+)")) < t - S.KEEP) do
        table.remove(hist, 1)
      end
      d.market[id] = #hist > 0 and hist or nil
      visited[id] = true
    end
    job.done = i
    if i % S.SLICE == 0 and S.deadline() then coroutine.yield() end
  end
  -- Items gone from the AH for longer than the history keeps.
  local old = {}
  for id, hist in pairs(d.market) do
    if not visited[id] then
      local last = hist[#hist] and tonumber(hist[#hist]:match("^(%d+)"))
      if not last or last < t - S.KEEP then old[#old + 1] = id end
    end
  end
  for _, id in ipairs(old) do d.market[id] = nil end
  return snap, prev, soldAuctions
end

-- Reads every row while the AH is open, then compares.
local function read(total)
  job.total, job.done = total, 0
  local rows, owners, ownerIdx = {}, {}, {}
  for i = 1, total do
    local id, owner, count, buyout, tl = S.api.row(i)
    if id then
      owner = type(owner) == "string" and owner or ""
      if owner ~= "" and not ownerIdx[owner] then
        owners[#owners + 1] = owner
        ownerIdx[owner] = #owners
      end
      local list = rows[id] or {}
      rows[id] = list
      list[#list + 1] = { owner, tonumber(count) or 1, tonumber(buyout) or 0, tonumber(tl) or 1 }
    end
    job.done = i
    if i % S.SLICE == 0 and S.deadline() then
      coroutine.yield()
      -- The client drops the list when the AH closes.
      if S.api.num() < total then
        local why = string.format("the AH closed at %d%%, scan dropped (stay until it says read)", pct(i, total))
        setState("failed", { why = why })
        say(why)
        return
      end
    end
  end
  local co = job.co
  setState("working", { co = co })
  finish(work(rows, owners))
end

-- The full scan's rows are in: read them.
function S.onList()
  if job.state == "reading" or job.state == "working" then return end
  local total = S.api.num()
  if total <= 0 then return end
  local d = db()
  if d.snap and d.snap.t and now() - d.snap.t < S.MIN_DT then return end
  setState("reading")
  local co = coroutine.create(function() read(total) end)
  job.co = co
  run(co, function() return job.state == "working" and S.WORK_MS or S.READ_MS end)
end

-- Starts a full scan; false and why when it can't.
function S.start()
  if job.state == "reading" or job.state == "working" or job.state == "waiting" then
    return false, "a full scan is already running"
  end
  if not S.ahOpen then return false, "open the Auction House first" end
  local w = S.wait()
  if not w then return false, "this client has no full scan" end
  if w > 0 then return false, "next full scan in " .. math.ceil(w / 60) .. "m" end
  if not S.api.request() then return false, "this client has no full scan" end
  return true
end

-- Any full scan request, ours or Auctionator's.
local function onRequest()
  db().lastRequest = now()
  if job.state ~= "reading" and job.state ~= "working" then setState("waiting") end
end
S.onRequest = onRequest

function S.hook()
  if S.hooked or not hooksecurefunc then return end
  S.hooked = true
  local ah = modern()
  if ah then
    hooksecurefunc(ah, "ReplicateItems", function() pcall(onRequest) end)
  elseif rawget(_G, "QueryAuctionItems") then
    hooksecurefunc("QueryAuctionItems", function(_, _, _, _, _, _, getAll)
      if getAll then pcall(onRequest) end
    end)
  end
end

---------------------------------------------------------------------------
-- What the scans say about an item.
---------------------------------------------------------------------------

-- { sold, gone, listed, each, scans, span } over the last 2 days, or nil.
-- Over the last 2 days of scans: sold and soldN (items and auctions
-- seen to sell), gone, listed (now), each (median price of what sold),
-- span (time covered) and seen (the part of that time the compares could
-- see sales: each interval counts by the share of items whose end it
-- could tell). An interval of 8 h or more sees nothing, so it adds no
-- seen time. rate and rateN are items and auctions a second, or nil.
function S.stats(id)
  local hist = id and db().market[id]
  if not hist or #hist == 0 then return nil end
  local t = now()
  local r = { sold = 0, soldN = 0, gone = 0, scans = 0, span = 0, seen = 0 }
  local prices = {}
  for _, line in ipairs(hist) do
    local f = {}
    for n in line:gmatch("%d+") do f[#f + 1] = tonumber(n) end
    -- t, dt, sold, soldN, gone, listed, posted, median, priced, atRisk, prevListed
    if #f == 11 and f[1] >= t - S.SHOW then
      r.sold, r.soldN, r.gone = r.sold + f[3], r.soldN + f[4], r.gone + f[5]
      if f[9] > 0 then prices[#prices + 1] = { f[8], f[9] } end
      r.scans = r.scans + 1
      r.span = r.span + f[2]
      if f[11] > 0 then r.seen = r.seen + f[2] * f[10] / f[11] end
      r.listed = f[6]
    end
  end
  if r.scans == 0 then return nil end
  r.each = S.wmedian(prices)
  if r.seen > 0 then r.rate, r.rateN = r.sold / r.seen, r.soldN / r.seen end
  return r
end

local function span(s)
  if s >= 86400 then return math.floor(s / 86400 + 0.5) .. "d" end
  return math.max(1, math.floor(s / 3600 + 0.5)) .. "h"
end

S.FRESH = 86400       -- the fair price counts for a day after its scan

-- The fair price per item from the last full scan (copper), when that
-- scan is under a day old and saw the item; else nil.
function S.price(id)
  local snap = db().snap
  if not id or not snap or not snap.fair or not snap.t or now() - snap.t > S.FRESH then return nil end
  local fair = snap.fair[id]
  -- One silly listing in a thin market: keep it near what really sold.
  local st = fair and S.stats(id)
  if st and st.each and st.each > 0 then fair = math.max(st.each * 0.5, math.min(st.each * 3, fair)) end
  return fair and math.floor(fair + 0.5)
end
LV.fairPrice = S.price

function S.line(link)
  local id = tonumber(link and link:match("item:(%d+)"))
  local s, fair = S.stats(id), S.price(id)
  if not s and not fair then return nil end
  local parts = {}
  if s then
    if s.rate then
      -- Seen sales scaled up to all the time the scans cover.
      local est = math.floor(s.rate * s.span + 0.5)
      local sold = est > 0 and ("~" .. est .. " sold") or "none sold"
      if s.each then sold = sold .. " at ~" .. LV.money(s.each) end
      table.insert(parts, sold .. " in " .. span(s.span))
    else
      table.insert(parts, "scan again within 8h to see sales")
    end
    table.insert(parts, (s.listed or 0) .. " listed")
  end
  if fair then table.insert(parts, "fair price ~" .. LV.money(fair)) end
  return C_GOLD .. "  AH market:" .. R .. " " .. C_GREY .. table.concat(parts, ", ") .. R
end
LV.marketLine = S.line

---------------------------------------------------------------------------
-- How long a sale takes. Buyers take the cheapest first, so a listing at
-- a price waits for every item listed cheaper ("ahead") to sell, then its
-- own stack. Sales come at the rate the scans measured (items an hour);
-- the wait is (ahead + stack) / rate, and the chance to sell within a 24 h
-- listing is a Poisson tail with that rate. Rough: it does not know who
-- posts after you.
---------------------------------------------------------------------------

S.LISTING = 24 * 3600
S.MIN_SPAN = 3 * 3600   -- less seen scan time than this gives no odds

-- P(N >= k) for N ~ Poisson(m).
function S.tail(m, k)
  if k <= 0 then return 1 end
  if m <= 0 then return 0 end
  if k > 400 then
    -- Normal approximation with continuity correction.
    local z = (k - 0.5 - m) / math.sqrt(m)
    local t = 1 / (1 + 0.2316419 * math.abs(z))
    local d = 0.3989423 * math.exp(-z * z / 2)
    local p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
    return z > 0 and p or 1 - p
  end
  local term, cdf = math.exp(-m), 0
  for i = 0, k - 1 do
    cdf = cdf + term
    term = term * m / (i + 1)
  end
  return math.max(0, math.min(1, 1 - cdf))
end

-- Items listed under a price per item in the last full scan.
-- Auctions listed under a price per item in the last full scan (not
-- yours); auctions at that price (within 1%) count half, as buyers pick
-- among them.
function S.ahead(id, price)
  local snap = db().snap
  if not snap or not snap.items or not snap.items[id] then return 0 end
  local me = UnitName and UnitName("player")
  local n = 0
  for _, e in ipairs(S.decode(snap.items[id], snap.owners or {})) do
    if e[3] > 0 and e[1] ~= me then
      local unit = e[3] / e[2]
      if unit < price * 0.99 then n = n + 1
      elseif unit <= price * 1.01 then n = n + 0.5 end
    end
  end
  return n
end

S.UNKNOWN = 0.35       -- the chance a sale is assumed to have with no scan odds
S.PRIOR = 12 * 3600    -- smoothing: half a sale over 12 h of seen time
S.MAIL_WEIGHT = 4      -- your own finished auctions count against 4 "virtual" ones

-- { hours, chance (within 24 h), ahead } for one auction at price per
-- item, or nil when the scans saw too little (under 3 h of seen time).
-- Counts auctions, not items: buyers take whole stacks. The rate is
-- smoothed so a quiet stretch does not give 0%. With your own sold and
-- expired mails for the item (Sales.lua, name), the chance moves toward
-- your own sell-through.
function S.odds(id, price, name)
  local s = S.stats(id)
  if not s or s.seen < S.MIN_SPAN or not price then return nil end
  local ahead = S.ahead(id, price)
  local rate = (s.soldN + 0.5) / (s.seen + S.PRIOR) -- auctions a second
  local need = math.floor(ahead + 0.5) + 1
  local o = { ahead = ahead, chance = S.tail(rate * S.LISTING, need), hours = need / rate / 3600 }
  o.chance = S.withMails(o.chance, name)
  return o
end

-- Moves a chance toward your own sell-through for the item: your sold and
-- expired mails count against MAIL_WEIGHT "virtual" auctions at chance.
function S.withMails(chance, name)
  local own = name and LV.sales and LV.sales.stats(name)
  if own and own.finished > 0 then
    return (S.MAIL_WEIGHT * chance + own.sold) / (S.MAIL_WEIGHT + own.finished)
  end
  return chance
end

-- "80% in 24h, ~5h" for the AH entry, or nil.
function S.oddsText(o)
  if not o then return nil end
  local pctText = math.floor(o.chance * 100 + 0.5) .. "% sells in 24h"
  if o.hours and o.hours < 48 then
    pctText = pctText .. ", ~" .. (o.hours < 1 and "<1" or math.floor(o.hours + 0.5)) .. "h"
  end
  return pctText
end

-- Odds for one auction of the item at its fair price.
function S.itemOdds(link)
  local id = tonumber(link and link:match("item:(%d+)"))
  local price = S.price(id)
  if not price then return nil end
  return S.odds(id, price, LV.sales and LV.sales.itemName(link))
end
LV.sellOdds = S.itemOdds

-- Auctions and items listed in the last full scan, not yours.
function S.listedNow(id)
  local snap = db().snap
  if not snap or not snap.items or not snap.items[id] then return 0, 0 end
  local me = UnitName and UnitName("player")
  local auctions, items = 0, 0
  for _, e in ipairs(S.decode(snap.items[id], snap.owners or {})) do
    if e[1] ~= me then auctions, items = auctions + 1, items + e[2] end
  end
  return auctions, items
end

-- What an AH sale of one item is worth, for other addons (UpgradeFinder's
-- craft profit). sure: what you get without the AH (vendor, disenchant),
-- in copper. Returns nil without any AH price, else
-- { price, net (after the cut), expected (net weighed by the chance, an
-- unsold listing coming back as sure less the deposit; with no scan odds
-- the chance is S.UNKNOWN moved by your own mails),
-- chance, hours, auctions, perDay (items sold a day, nil unknown),
-- fresh (from a LootValue scan under a day old), confidence ("ok",
-- "thin", "no scan"), note (short text) }.
function S.quote(id, link, sure, vendor)
  if not id then return nil end
  local fair = S.price(id)
  local price = fair
  if not price then
    local a = Auctionator and Auctionator.API and Auctionator.API.v1
    if a then
      local ok, v = pcall(a.GetAuctionPriceByItemID, "LootValue", id)
      price = ok and type(v) == "number" and v or nil
    end
  end
  if not price or price <= 0 then return nil end
  local q = { price = price, net = math.floor(price * 0.95), fresh = fair ~= nil }
  local st = S.stats(id)
  q.auctions = S.listedNow(id)
  q.perDay = st and st.rate and st.rate * 86400 or nil
  local name = link and LV.sales and LV.sales.itemName(link)
  local o = fair and S.odds(id, fair, name)
  -- No scan odds: an unknown market is not a sure sale. Assume a low
  -- chance, moved by your own sold and expired mails for the item.
  q.chance = o and o.chance or S.withMails(S.UNKNOWN, name)
  q.hours = o and o.hours
  local deposit = math.floor((vendor or 0) * 0.3)
  q.expected = math.floor(q.chance * q.net + (1 - q.chance) * math.max(0, (sure or 0) - deposit) + 0.5)
  local own = name and LV.sales and LV.sales.stats(name)
  q.own = own and own.finished > 0 and own or nil
  local parts = {}
  if not q.fresh then
    q.confidence = "no scan"
    table.insert(parts, "lowest listing, no LootValue scan today")
  else
    q.confidence = (q.auctions < 3 or not o) and "thin" or "ok"
    table.insert(parts, q.auctions .. " listed")
    if q.perDay then table.insert(parts, string.format("~%s sold/day", q.perDay >= 10 and math.floor(q.perDay + 0.5)
      or string.format("%.1f", q.perDay))) end
    if o then table.insert(parts, math.floor(o.chance * 100 + 0.5) .. "% sells in 24h") end
    if not o then table.insert(parts, "no sales seen yet") end
  end
  if not o then table.insert(parts, "assumed " .. math.floor(q.chance * 100 + 0.5) .. "% sells") end
  if q.own then table.insert(parts, "you sold " .. q.own.sold .. " of " .. q.own.finished) end
  q.note = table.concat(parts, ", ")
  return q
end
LV.marketQuote = S.quote


-- "none sold in 1d" when the scans saw 10+ listed and no sales, else nil.
function S.slowNote(link)
  local s = S.stats(tonumber(link and link:match("item:(%d+)")))
  if s and s.sold == 0 and (s.listed or 0) >= 10 and s.seen >= 6 * 3600 then
    return "none sold in " .. span(s.span)
  end
  return nil
end

---------------------------------------------------------------------------
-- Status above the AH window, on every tab.
---------------------------------------------------------------------------

local panel
function S.addPanel(tries)
  if panel then return end
  local ah, name
  for _, n in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
    local f = rawget(_G, n)
    if type(f) == "table" then ah, name = f, n break end
  end
  if not ah then
    if (tries or 0) < 5 and C_Timer and C_Timer.After then
      C_Timer.After(0.2, function() S.addPanel((tries or 0) + 1) end)
    end
    return
  end
  -- Just above the window, on the right, so it stays the same on every
  -- tab. Not below it: the tabs (and Auctionator's) hang there.
  panel = CreateFrame("Frame", nil, ah)
  panel:SetSize(460, 24)
  panel:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", name == "AuctionFrame" and -10 or 0, 2)
  panel:SetFrameLevel((ah.GetFrameLevel and ah:GetFrameLevel() or 0) + 10)
  local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  button:SetSize(60, 20)
  button:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
  button:SetText("Scan")
  button:SetScript("OnClick", function()
    local ok, why = S.start()
    if not ok then say(why) end
    S.paint()
  end)
  local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("RIGHT", button, "LEFT", -6, 0)
  text:SetJustifyH("RIGHT")
  panel.text, panel.button = text, button
  S.paint()
end

function S.paint()
  if not panel then return end
  panel.text:SetText(C_GOLD .. "LootValue" .. R .. " " .. S.statusText())
  local busy = job.state == "reading" or job.state == "working" or job.state == "waiting"
  if panel.button.SetEnabled then panel.button:SetEnabled(not busy and S.wait() == 0) end
end

-- /lv scan [now]
function S.slash(arg)
  if arg == "now" then
    local ok, why = S.start()
    if not ok then say(why) return end
  end
  say(S.statusText())
end

local f = CreateFrame and CreateFrame("Frame")
if f then
  for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
    "AUCTION_ITEM_LIST_UPDATE" }) do
    pcall(f.RegisterEvent, f, e) -- an event this client lacks throws
  end
  local ticker = 0
  f:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
      if event == "PLAYER_LOGIN" then S.hook()
      elseif event == "AUCTION_HOUSE_SHOW" then S.ahOpen = true S.addPanel() S.paint()
      elseif event == "AUCTION_HOUSE_CLOSED" then
        S.ahOpen = false
        if job.state == "waiting" then setState("failed", { why = "the AH closed before the server sent the scan" }) end
      elseif event == "REPLICATE_ITEM_LIST_UPDATE" then S.onList()
      elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        -- Plain searches fire this too (50 rows a page); a full scan we
        -- did not see requested still shows by its size.
        if job.state == "waiting" or S.api.num() > S.FULL_ROWS then S.onList() end
      end
    end)
    if not ok and not S.reported then
      S.reported = true
      say("scan error: " .. tostring(err))
    end
  end)
  -- The "next full scan in" countdown.
  if f.SetScript then
    f:SetScript("OnUpdate", function(_, elapsed)
      ticker = ticker + (elapsed or 0)
      if ticker >= 1 then ticker = 0 if panel and S.ahOpen then S.paint() end end
    end)
  end
end
