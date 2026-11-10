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
-- Status and progress show under the AH window on every tab. /lv scan
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
S.MIN_DT = 120        -- a scan this soon after the last one is ignored
S.KEEP = 3 * 86400    -- compare results kept per item
S.KEEP_N = 12
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
    table.insert(parts, string.format("last full scan %s (%d auctions)", LV.ago(d.snap.t), d.snap.n or 0))
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

-- Compares one item's auctions: prev and new are lists of
-- { owner, count, buyout, band }; dt is seconds between the scans.
-- Returns sold, gone, listed, posted (items), value, valueItems (the
-- buyout of the sold ones that had a buyout) and the sold auctions.
function S.compare(prev, new, dt)
  local before, after = {}, {}
  for _, e in ipairs(prev) do
    local k = e[1] .. "|" .. e[2] .. "|" .. e[3]
    before[k] = before[k] or {}
    table.insert(before[k], e)
  end
  local listed = 0
  for _, e in ipairs(new) do
    local k = e[1] .. "|" .. e[2] .. "|" .. e[3]
    after[k] = (after[k] or 0) + 1
    listed = listed + e[2]
  end
  -- New auctions by seller and stack: a seller who cancels and posts the
  -- same stack at another price did not sell it.
  local posted, newBy = 0, {}
  for _, e in ipairs(new) do
    local k = e[1] .. "|" .. e[2] .. "|" .. e[3]
    local had = before[k] and #before[k] or 0
    if (after[k] or 0) > had then
      after[k] = after[k] - 1 -- count each new one once
      posted = posted + e[2]
      if e[1] ~= "" then
        local by = e[1] .. "|" .. e[2]
        newBy[by] = (newBy[by] or 0) + 1
      end
    end
  end
  -- after[k] now holds the kept count per key.
  local sold, gone, value, valueItems, soldN = 0, 0, 0, 0, 0
  for k, list in pairs(before) do
    local kept = after[k] or 0
    local vanished = #list - kept
    if vanished > 0 then
      -- The ones with the least time left are the likeliest to expire.
      table.sort(list, function(a, b) return a[4] < b[4] end)
      for i = 1, vanished do
        local e = list[i]
        gone = gone + e[2]
        if dt < (S.MIN_LEFT[e[4]] or math.huge) then
          local by = e[1] .. "|" .. e[2]
          if e[1] ~= "" and (newBy[by] or 0) > 0 then
            newBy[by] = newBy[by] - 1 -- a repost
          else
            sold, soldN = sold + e[2], soldN + 1
            if e[3] > 0 then value, valueItems = value + e[3], valueItems + e[2] end
          end
        end
      end
    end
  end
  return sold, gone, listed, posted, value, valueItems, soldN
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
  local text = string.format("full scan read: %d auctions of %d items.", snap.n, snap.itemCount)
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
  local snap = { t = t, owners = owners, items = {}, n = 0, itemCount = 0 }
  local ownerIdx = {}
  for i, o in ipairs(owners) do ownerIdx[o] = i end
  local soldAuctions = 0
  for i, id in ipairs(ids) do
    local new = rows[id] or {}
    if #new > 0 then
      local parts = {}
      for j, e in ipairs(new) do
        parts[j] = (ownerIdx[e[1]] or 0) .. "," .. e[2] .. "," .. e[3] .. "," .. e[4]
      end
      snap.items[id] = table.concat(parts, ";")
      snap.n = snap.n + #new
      snap.itemCount = snap.itemCount + 1
    end
    if prev and prev.items then
      local old = S.decode(prev.items[id], prev.owners or {})
      local sold, gone, listed, posted, value, vi, soldN = S.compare(old, new, dt)
      soldAuctions = soldAuctions + soldN
      local hist = d.market[id] or {}
      hist[#hist + 1] = string.format("%d,%d,%d,%d,%d,%d,%d,%d", t, dt, sold, gone, listed, posted, value, vi)
      while #hist > S.KEEP_N or (hist[1] and tonumber(hist[1]:match("^(%d+)")) < t - S.KEEP) do
        table.remove(hist, 1)
      end
      d.market[id] = #hist > 0 and hist or nil
    end
    job.done = i
    if i % S.SLICE == 0 and S.deadline() then coroutine.yield() end
  end
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
      list[#list + 1] = { owner, tonumber(count) or 1, tonumber(buyout) or 0, tonumber(tl) or 4 }
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
function S.stats(id)
  local hist = id and db().market[id]
  if not hist or #hist == 0 then return nil end
  local t = now()
  local r = { sold = 0, gone = 0, value = 0, vi = 0, scans = 0, span = 0 }
  for _, line in ipairs(hist) do
    local at, dt, sold, gone, listed, _, value, vi = line:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)")
    at = tonumber(at)
    if at and at >= t - S.SHOW then
      r.sold = r.sold + tonumber(sold)
      r.gone = r.gone + tonumber(gone)
      r.value, r.vi = r.value + tonumber(value), r.vi + tonumber(vi)
      r.scans = r.scans + 1
      r.span = r.span + tonumber(dt)
      r.listed = tonumber(listed)
    end
  end
  if r.scans == 0 then return nil end
  r.each = r.vi > 0 and r.value / r.vi or nil
  return r
end

local function span(s)
  if s >= 86400 then return math.floor(s / 86400 + 0.5) .. "d" end
  return math.max(1, math.floor(s / 3600 + 0.5)) .. "h"
end

function S.line(link)
  local s = S.stats(tonumber(link and link:match("item:(%d+)")))
  if not s then return nil end
  local parts = { (s.sold > 0 and ("~" .. s.sold .. " sold") or "none sold") .. " in " .. span(s.span) }
  table.insert(parts, (s.listed or 0) .. " listed")
  if s.each then table.insert(parts, "~" .. LV.money(s.each) .. " each") end
  return C_GOLD .. "  AH market:" .. R .. " " .. C_GREY .. table.concat(parts, ", ") .. R
end
LV.marketLine = S.line

-- "none sold in 1d" when the scans saw 10+ listed and no sales, else nil.
function S.slowNote(link)
  local s = S.stats(tonumber(link and link:match("item:(%d+)")))
  if s and s.sold == 0 and (s.listed or 0) >= 10 and s.span >= 6 * 3600 then
    return "none sold in " .. span(s.span)
  end
  return nil
end

---------------------------------------------------------------------------
-- Status under the AH window, on every tab.
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
  -- Below the window, on the right (the tabs hang on the left), so it
  -- stays the same on every tab.
  panel = CreateFrame("Frame", nil, ah)
  panel:SetSize(420, 24)
  panel:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", name == "AuctionFrame" and -10 or 0, name == "AuctionFrame" and 8 or -2)
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
        -- Plain searches fire this too; only a full scan request counts.
        if job.state == "waiting" then S.onList() end
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
