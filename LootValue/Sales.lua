-- LootValue sales: how well your own auctions sell, per item.
--
-- The AH shows what is listed, never what sells. Your own mail does say it:
-- "Auction successful: X" when an auction sells, "Auction expired: X" when
-- it does not. LootValue counts those mails, and the auctions you post, for
-- each item name, and the item tooltip says
-- "Your AH sales: sold 18 of 20 (90%), ~1s15c each, 2 up, last 3h ago".
-- A low rate (under half of 4+ finished auctions) also makes the AH advice
-- count the market as slow (LootValue.marketInfo).
--
-- The counts are account-wide (LootValueDB.sales, by item name). Each
-- character's inbox is read when the mailbox opens, so a mail counts once:
-- LootValue remembers each auction mail by subject and expiry time (per
-- character) until the mail itself would have expired.
--
-- Posting: hooks PostAuction and StartAuction (the stack AH) and
-- C_AuctionHouse.PostItem and PostCommodity (the modern AH), whichever the
-- client has. A post that the game refuses still counts; the sell-through
-- rate uses only the mails, so it stays exact.
local LV = LootValue
local S = {}
LV.sales = S

local C_GOLD, C_GREY = "|cffffd100", "|cff9d9d9d"
local R = "|r"
local PREFIX = C_GOLD .. "LootValue:" .. R .. " "

S.SLOW_MIN = 4       -- finished auctions before the rate counts
S.SLOW_RATE = 0.5    -- sold share under which the market counts as slow
S.MATCH = 120        -- seconds of slack when matching a mail's expiry time

local function now() return time and time() or 0 end

local function db()
  LootValueDB = LootValueDB or {}
  local d = LootValueDB
  d.sales = d.sales or {}
  d.mailSeen = d.mailSeen or {}
  return d
end
S.db = db

local function record(name)
  local d = db()
  local r = d.sales[name]
  if not r then
    r = { posted = 0, sold = 0, expired = 0, cancelled = 0, soldItems = 0, net = 0 }
    d.sales[name] = r
  end
  return r
end

-- The item name in a link ("|h[Linen Cloth]|h"), or the game's name for it.
function S.itemName(link)
  if type(link) ~= "string" then return nil end
  local name = link:match("|h%[(.-)%]|h")
  if name and name ~= "" then return name end
  if C_Item and C_Item.GetItemInfo then
    local ok, n = pcall(C_Item.GetItemInfo, link)
    if ok and type(n) == "string" then return n end
  end
  return nil
end

---------------------------------------------------------------------------
-- Mail subjects.
---------------------------------------------------------------------------

-- A Lua pattern from a game format string such as "Auction successful: %s".
local function subjectPattern(fmt)
  local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0"):gsub("%%%%s", "(.+)")
  return "^" .. p .. "$"
end

local KINDS = {
  { "sold", "AUCTION_SOLD_MAIL_SUBJECT", "Auction successful: %s" },
  { "expired", "AUCTION_EXPIRED_MAIL_SUBJECT", "Auction expired: %s" },
  { "cancelled", "AUCTION_REMOVED_MAIL_SUBJECT", "Auction cancelled: %s" },
}

-- kind ("sold", "expired", "cancelled"), item name, stack size from the
-- subject (nil when it has none); or nil for any other mail.
function S.parseSubject(subject)
  if type(subject) ~= "string" then return nil end
  for _, k in ipairs(KINDS) do
    local fmts = { k[3] }
    local g = rawget(_G, k[2])
    if type(g) == "string" and g ~= k[3] then table.insert(fmts, 1, g) end
    for _, fmt in ipairs(fmts) do
      local name = subject:match(subjectPattern(fmt))
      if name then
        -- A stack adds " (20)" to the item name.
        local base, count = name:match("^(.-) %((%d+)%)$")
        if base then return k[1], base, tonumber(count) end
        return k[1], name, nil
      end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Counting mails.
---------------------------------------------------------------------------

function S.charKey()
  local name = UnitName and UnitName("player") or "?"
  local realm = GetRealmName and GetRealmName() or "?"
  return realm .. "-" .. name
end

-- Adds one auction mail to the counts.
function S.count(kind, name, items, money)
  local r = record(name)
  r[kind] = r[kind] + 1
  if kind == "sold" then
    r.soldItems = r.soldItems + (items or 1)
    r.net = r.net + (money or 0)
    r.last = now()
  end
end

-- Reads the whole inbox and counts each auction mail not seen before.
function S.scanInbox()
  if not GetInboxNumItems or not GetInboxHeaderInfo then return 0 end
  local d = db()
  local key = S.charKey()
  local seen = d.mailSeen[key] or {}
  d.mailSeen[key] = seen
  local t = now()
  -- Forget mails that have expired by now.
  for subject, list in pairs(seen) do
    for i = #list, 1, -1 do
      if list[i] < t - 86400 then table.remove(list, i) end
    end
    if #list == 0 then seen[subject] = nil end
  end
  local used, added = {}, 0
  for i = 1, GetInboxNumItems() or 0 do
    local _, _, _, subject, money, _, daysLeft, hasItem = GetInboxHeaderInfo(i)
    local kind, name, subjectCount = S.parseSubject(subject)
    if kind and type(daysLeft) == "number" then
      local expires = t + daysLeft * 86400
      -- Each mail matches one remembered expiry time at most.
      local list = seen[subject] or {}
      used[subject] = used[subject] or {}
      local match
      for j, e in ipairs(list) do
        if not used[subject][j] and math.abs(e - expires) <= S.MATCH then match = j break end
      end
      if match then
        used[subject][match] = true
      else
        table.insert(list, expires)
        seen[subject] = list
        used[subject][#list] = true
        local items = subjectCount
        if kind == "sold" and GetInboxInvoiceInfo then
          local ok, _, _, _, _, _, _, _, _, _, n = pcall(GetInboxInvoiceInfo, i)
          if ok and type(n) == "number" and n > 0 then items = n end
        elseif kind ~= "sold" and hasItem and GetInboxItem then
          local ok, _, _, _, n = pcall(GetInboxItem, i, 1)
          if ok and type(n) == "number" and n > 0 then items = n end
        end
        local r = record(name)
        S.count(kind, name, items or r.stack or 1, type(money) == "number" and money or 0)
        added = added + 1
      end
    end
  end
  return added
end

---------------------------------------------------------------------------
-- Counting posts.
---------------------------------------------------------------------------

function S.posted(name, auctions, stack)
  if not name or not auctions or auctions < 1 then return end
  local r = record(name)
  r.posted = r.posted + auctions
  if stack and stack > 0 then r.stack = stack end
end

-- Stack AH: the item in the sell slot, posted numStacks times.
local function onPostAuction(_, _, _, stackSize, numStacks)
  if not GetAuctionSellItemInfo then return end
  local name, _, count = GetAuctionSellItemInfo()
  if type(name) ~= "string" then return end
  S.posted(name, tonumber(numStacks) or 1, tonumber(stackSize) or tonumber(count) or 1)
end

local function locationName(location)
  if not location or not C_Item or not C_Item.GetItemName then return nil end
  local ok, name = pcall(C_Item.GetItemName, location)
  return ok and type(name) == "string" and name or nil
end

function S.hookPosting()
  if S.hooked or not hooksecurefunc then return end
  S.hooked = true
  for _, fn in ipairs({ "PostAuction", "StartAuction" }) do
    if rawget(_G, fn) then
      hooksecurefunc(fn, function(...) pcall(onPostAuction, ...) end)
    end
  end
  local ah = rawget(_G, "C_AuctionHouse")
  if type(ah) == "table" then
    -- PostItem(item, duration, quantity, bid, buyout): quantity auctions of one.
    if ah.PostItem then
      hooksecurefunc(ah, "PostItem", function(item, _, quantity)
        pcall(S.posted, locationName(item), tonumber(quantity) or 1, 1)
      end)
    end
    -- PostCommodity(item, duration, quantity, unitPrice): one listing.
    if ah.PostCommodity then
      hooksecurefunc(ah, "PostCommodity", function(item, _, quantity)
        pcall(S.posted, locationName(item), 1, tonumber(quantity) or 1)
      end)
    end
  end
end

---------------------------------------------------------------------------
-- What the counts say.
---------------------------------------------------------------------------

-- { sold, finished, rate, each, up, last } for an item name, or nil.
function S.stats(name)
  local r = name and db().sales[name]
  if not r then return nil end
  local finished = r.sold + r.expired
  return {
    sold = r.sold, expired = r.expired, posted = r.posted, finished = finished,
    rate = finished > 0 and r.sold / finished or nil,
    each = r.soldItems > 0 and r.net / r.soldItems or nil,
    up = math.max(0, r.posted - finished - r.cancelled),
    last = r.last,
  }
end

-- "sold 1 of 6" when your own auctions of the item mostly do not sell, else nil.
function S.slowNote(name)
  local s = S.stats(name)
  if s and s.finished >= S.SLOW_MIN and s.rate < S.SLOW_RATE then
    return "you sold " .. s.sold .. " of " .. s.finished
  end
  return nil
end

-- The tooltip line, or nil when you never sold or posted the item.
function S.line(link)
  local s = S.stats(S.itemName(link))
  if not s or (s.finished == 0 and s.up == 0) then return nil end
  local parts = {}
  if s.finished > 0 then
    table.insert(parts, string.format("sold %d of %d (%d%%)", s.sold, s.finished, math.floor(s.rate * 100 + 0.5)))
  end
  if s.each then table.insert(parts, "~" .. LV.money(s.each) .. " each") end
  if s.up > 0 then table.insert(parts, s.up .. " up") end
  if s.last then table.insert(parts, "last " .. LV.ago(s.last)) end
  return C_GOLD .. "  Your AH sales:" .. R .. " " .. C_GREY .. table.concat(parts, ", ") .. R
end
LV.salesLine = S.line

local function say(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) else print(PREFIX .. msg) end end

-- /lv sales: the items you sold most, with their rates. /lv sales reset.
function S.slash(arg)
  if arg == "reset" then
    local d = db()
    d.sales = {}
    say("sales counts cleared.")
    return
  end
  local list = {}
  for name in pairs(db().sales) do
    local s = S.stats(name)
    if s.finished > 0 then table.insert(list, { name, s }) end
  end
  if #list == 0 then say("no auction mails counted yet. Open your mailbox after a sale.") return end
  table.sort(list, function(a, b)
    if a[2].sold ~= b[2].sold then return a[2].sold > b[2].sold end
    return a[1] < b[1]
  end)
  local parts = {}
  for i = 1, math.min(10, #list) do
    local name, s = list[i][1], list[i][2]
    table.insert(parts, string.format("%s %d/%d%s", name, s.sold, s.finished,
      s.each and (" ~" .. LV.money(s.each)) or ""))
  end
  say("sold/finished auctions: " .. table.concat(parts, ", ") .. ". /lv sales reset clears them.")
end

local f = CreateFrame and CreateFrame("Frame")
if f then
  f:RegisterEvent("PLAYER_LOGIN")
  f:RegisterEvent("MAIL_INBOX_UPDATE")
  f:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
      if event == "PLAYER_LOGIN" then S.hookPosting()
      elseif event == "MAIL_INBOX_UPDATE" then S.scanInbox() end
    end)
    if not ok and not S.reported then
      S.reported = true
      say("sales error: " .. tostring(err))
    end
  end)
end
