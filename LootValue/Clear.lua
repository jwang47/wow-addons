-- LootValue clear bags: act on the tooltip advice for everything you carry.
--
-- One panel (/lv clear) with three lists, from the same numbers as the
-- tooltip line (LootValue.options):
--   Vendor      grey junk, and gear whose best option is the vendor. The
--               Sell button (at a merchant) sells the ticked rows.
--   Disenchant  gear whose best option is to disenchant it. A button
--               disenchants the next one; one click each (the game allows a
--               cast only on a real click).
--   Auction     unbound items the AH clearly pays more for. At the AH a
--               click puts the item into Auctionator's Selling tab.
--
-- What it never lists: quest items, epics and better, locked slots, and
-- anything that is not gear or grey in the Vendor and Disenchant lists
-- (cloth, potions, recipes and reagents stay yours).
--
-- A row is ticked (it will be sold or disenchanted) unless the item may be
-- an upgrade: its item level is at or above what you wear in that slot.
-- Click a row to tick or untick it; the choice is kept per item
-- (LootValueDB.clear.choice). One press of Sell sells at most 12 items that
-- are not grey, so each of them is still on the merchant's Buyback tab.
local LV = LootValue
local CL = {}
LV.clear = CL

local C_GOLD, C_GREY, C_GREEN = "|cffffd100", "|cff9d9d9d", "|cff40ff40"
local R = "|r"
local PREFIX = C_GOLD .. "LootValue:" .. R .. " "

CL.BUYBACK = 12   -- non-grey items sold per press: what the Buyback tab holds
CL.SELL_SECS = 0.2 -- one item per tick, as other sell addons do
CL.ROWS = 14      -- lines the panel shows; the mouse wheel scrolls the rest
CL.DISENCHANT = 13262

local BAGS = { 0, 1, 2, 3, 4 }
local function G(name) return rawget(_G, name) end

local function db()
  LootValueDB = LootValueDB or {}
  local d = LootValueDB
  d.clear = d.clear or {}
  local c = d.clear
  c.choice = c.choice or {}
  if c.auto == nil then c.auto = true end
  return c
end
CL.db = db

local function say(msg)
  local chat = G("DEFAULT_CHAT_FRAME")
  if chat then chat:AddMessage(PREFIX .. msg) else print(PREFIX .. msg) end
end

local function inCombat()
  local f = G("InCombatLockdown")
  return f and f() or false
end

---------------------------------------------------------------------------
-- What to do with each bag item
---------------------------------------------------------------------------

-- Inventory slots an equip location goes in.
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
  INVTYPE_RELIC = { 18 },
}

local function itemInfo(link)
  local info = C_Item and C_Item.GetItemInfo
  if not info then return nil end
  local ok, name, _, quality, ilvl, _, _, _, _, equipLoc, _, sell, classID = pcall(info, link)
  if not ok or not name then return nil end
  return name, quality, ilvl, equipLoc, sell, classID
end

-- The lowest item level you wear in the slots this equip location goes in;
-- 0 when a slot is empty or the location is unknown.
function CL.wornLevel(equipLoc)
  local slots = SLOTS[equipLoc or ""]
  local getLink = G("GetInventoryItemLink")
  if not slots or not getLink then return 0 end
  local low
  for _, slot in ipairs(slots) do
    local link = getLink("player", slot)
    local ilvl = link and select(3, itemInfo(link))
    ilvl = type(ilvl) == "number" and ilvl or 0
    if not low or ilvl < low then low = ilvl end
  end
  return low or 0
end

-- One bag item: it = { id, link, count, quality, bound, locked }. Returns
-- nil (not listed) or a row { kind = "vendor"|"de"|"ah", value (copper, the
-- whole stack), on (ticked), why (text when not ticked), grey }.
function CL.classify(it)
  if not it or it.locked or not it.link or not it.id then return nil end
  local name, quality, ilvl, equipLoc, sell, classID = itemInfo(it.link)
  if not name then return nil end
  quality = type(quality) == "number" and quality or it.quality or 1
  if classID == 12 or quality >= 4 then return nil end
  local count = it.count or 1
  local choice = db().choice[it.id]
  local row = { id = it.id, link = it.link, name = name, count = count, bag = it.bag, slot = it.slot }
  if quality == 0 then
    if type(sell) ~= "number" or sell <= 0 then return nil end
    row.kind, row.value, row.grey = "vendor", sell * count, true
    row.on = choice ~= "keep"
    row.why = not row.on and "kept" or nil
    return row
  end
  local gear = (classID == 2 or classID == 4) and LV.isGear(it.link)
  local options = LV.options(it.link, gear, { bound = it.bound and true or false })
  local best = options and options[1]
  if not best then return nil end
  row.value = best[2] * count
  if best[1] == "AH" then
    row.kind = "ah"
    row.note = best[3]
    row.on = choice ~= "keep"
    row.why = not row.on and "hidden" or nil
    return row
  end
  if not gear then return nil end
  if best[1] == "Disenchant" then
    if quality < 2 then return nil end
    row.kind = "de"
  else
    row.kind = "vendor"
  end
  -- Gear at or above what you wear in its slot may be an upgrade: not ticked
  -- until you tick it yourself.
  local worn = CL.wornLevel(equipLoc)
  local maybe = type(ilvl) == "number" and ilvl >= worn
  if choice == "sell" then row.on = true
  elseif choice == "keep" then row.on, row.why = false, "kept"
  elseif maybe then
    row.on = false
    row.why = worn > 0 and ("item level " .. ilvl .. ", you wear " .. worn) or "that slot is empty"
  else row.on = true end
  return row
end

local function bagItem(bag, slot)
  local C = C_Container
  local info = C and C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
  if type(info) ~= "table" or not info.itemID then return nil end
  local link = info.hyperlink or (C.GetContainerItemLink and C.GetContainerItemLink(bag, slot))
  return { id = info.itemID, link = link, count = info.stackCount or 1, quality = info.quality,
    bound = info.isBound, locked = info.isLocked, bag = bag, slot = slot }
end
CL.bagItem = bagItem

local ORDER = { vendor = 1, de = 2, ah = 3 }

-- Every listed bag item, by list (vendor, disenchant, AH), ticked rows
-- first, then the most valuable first. AH stacks of one item are one row.
function CL.scan()
  local rows, ahByID = {}, {}
  local C = C_Container
  if not C or not C.GetContainerNumSlots then return rows end
  for _, bag in ipairs(BAGS) do
    for slot = 1, C.GetContainerNumSlots(bag) or 0 do
      local row = CL.classify(bagItem(bag, slot))
      if row then
        local same = row.kind == "ah" and ahByID[row.id]
        if same then
          same.count, same.value = same.count + row.count, same.value + row.value
        else
          if row.kind == "ah" then ahByID[row.id] = row end
          table.insert(rows, row)
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.kind ~= b.kind then return ORDER[a.kind] < ORDER[b.kind] end
    if a.on ~= b.on then return a.on end
    if a.value ~= b.value then return a.value > b.value end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
  end)
  return rows
end

-- Ticked rows and their copper, per list: { vendor = { n, value }, ... }.
function CL.totals(rows)
  local t = { vendor = { n = 0, value = 0 }, de = { n = 0, value = 0 }, ah = { n = 0, value = 0 } }
  for _, row in ipairs(rows) do
    if row.on then
      local k = t[row.kind]
      k.n, k.value = k.n + 1, k.value + row.value
    end
  end
  return t
end

-- Tick or untick a row's item for good.
function CL.toggle(row)
  local c = db().choice
  if row.kind == "ah" or row.grey then
    c[row.id] = row.on and "keep" or nil
  else
    c[row.id] = row.on and "keep" or "sell"
  end
end

---------------------------------------------------------------------------
-- Selling to a merchant
---------------------------------------------------------------------------

-- The ticked vendor rows one press sells: every grey one, then up to
-- BUYBACK others, so each item that is not junk can still be bought back.
-- Returns the queue and how many ticked rows wait for the next press.
function CL.sellQueue(rows)
  local queue, others, left = {}, 0, 0
  for _, row in ipairs(rows) do
    if row.kind == "vendor" and row.on and row.grey then table.insert(queue, row) end
  end
  for _, row in ipairs(rows) do
    if row.kind == "vendor" and row.on and not row.grey then
      if others < CL.BUYBACK then
        others = others + 1
        table.insert(queue, row)
      else
        left = left + 1
      end
    end
  end
  return queue, left
end

local selling -- { queue, sold, value, left }

-- Sell one queued row, if that slot still holds the same unlocked item.
local function sellOne(row)
  local now = bagItem(row.bag, row.slot)
  if not now or now.id ~= row.id or now.locked then return false end
  local use = C_Container and C_Container.UseContainerItem
  if not use then return false end
  use(row.bag, row.slot)
  return true
end

local function finishSelling()
  local s = selling
  selling = nil
  if not s then return end
  if s.ticker and s.ticker.Cancel then s.ticker:Cancel() end
  if s.sold > 0 then
    say(string.format("sold %d item%s for %s%s. The merchant's Buyback tab has the last 12.", s.sold,
      s.sold == 1 and "" or "s", LV.money(s.value),
      s.left > 0 and (", " .. s.left .. " more on the next press") or ""))
  end
  if CL.refresh then CL.refresh() end
end

function CL.sellStep()
  local s = selling
  if not s then return end
  local row = table.remove(s.queue, 1)
  if not row or not CL.atMerchant then finishSelling() return end
  if sellOne(row) then s.sold, s.value = s.sold + 1, s.value + row.value end
  if #s.queue == 0 then finishSelling() end
end

function CL.sell()
  if selling then return end
  if not CL.atMerchant then say("open a merchant first.") return end
  local queue, left = CL.sellQueue(CL.scan())
  if #queue == 0 then say("nothing ticked to sell.") return end
  selling = { queue = queue, sold = 0, value = 0, left = left }
  local timer = G("C_Timer")
  if timer and timer.NewTicker then
    selling.ticker = timer.NewTicker(CL.SELL_SECS, CL.sellStep)
  else
    while selling do CL.sellStep() end
  end
end

---------------------------------------------------------------------------
-- Auction House: put an item into Auctionator's Selling tab
---------------------------------------------------------------------------

-- What Auctionator does for its own bag shortcut (Selling/Hooks.lua,
-- SelectOwnItem, Auctionator 344). Its internals can change, so every step
-- is checked and a failure only prints a hint.
function CL.selectForAuction(row)
  local ok, err = pcall(function()
    local loc = ItemLocation:CreateFromBagAndSlot(row.bag, row.slot)
    assert(loc:IsValid() and C_AuctionHouse.IsSellItemValid(loc), "the Auction House does not take this item")
    local ah = AuctionHouseFrame
    ah.ItemSellFrame:SetItem(nil, nil, false)
    ah.CommoditiesSellFrame:SetItem(nil, nil, false)
    AuctionatorTabs_Selling:Click()
    local link = C_Item.GetItemLink(loc)
    AuctionatorBagCacheFrame:CacheLinkInfo(link, function()
      local info = Auctionator.Groups.Utilities.ToPostingItem(AuctionatorBagCacheFrame:GetByLinkInstant(link, true))
      info.itemLink, info.location = link, loc
      info.count = C_AuctionHouse.GetAvailablePostCount(loc)
      Auctionator.EventBus:RegisterSource(CL.selectForAuction, "LootValueClear")
      Auctionator.EventBus:Fire(CL.selectForAuction, Auctionator.Selling.Events.BagItemClicked, info)
    end)
  end)
  if not ok then
    say("could not hand " .. tostring(row.link) .. " to Auctionator (" .. tostring(err):gsub("^.-:%d+: ", "")
      .. "). Pick it in Auctionator's Selling tab.")
  end
  return ok
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local panel, lines, sellBtn, deBtn, title
local view = { mode = "all", offset = 0, rows = {}, shown = {} }
local W, LINE_H, PAD = 330, 16, 10

local HEAD = { vendor = "Vendor", de = "Disenchant", ah = "Auction House" }

-- The lines the panel shows for a mode ("merchant": vendor and disenchant;
-- "ah": the AH list; "all"): a header per list that has rows, then its rows.
function CL.display(rows, mode)
  local want = { vendor = mode ~= "ah", de = mode ~= "ah", ah = mode ~= "merchant" }
  local totals = CL.totals(rows)
  local out, last = {}, nil
  for _, row in ipairs(rows) do
    if want[row.kind] then
      if row.kind ~= last then
        last = row.kind
        local t = totals[row.kind]
        table.insert(out, { header = string.format("%s: %d item%s, %s%s", HEAD[row.kind], t.n, t.n == 1 and "" or "s",
          row.kind == "vendor" and "" or "~", LV.money(t.value)) .. (row.kind == "ah" and " after the cut" or "") })
      end
      table.insert(out, { row = row })
    end
  end
  return out
end

local function lineText(row)
  local count = row.count > 1 and (" x" .. row.count) or ""
  if row.on then
    return (row.kind == "ah" and "  " or (C_GREEN .. "+ " .. R)) .. tostring(row.link) .. count
  end
  return C_GREY .. "- " .. tostring(row.name) .. count .. "  (" .. tostring(row.why) .. ")" .. R
end

-- The first ticked disenchant row.
function CL.nextDisenchant(rows)
  for _, row in ipairs(rows) do
    if row.kind == "de" and row.on then return row end
  end
end

local function spellName()
  local get = C_Spell and C_Spell.GetSpellName
  local ok, name = false, nil
  if get then ok, name = pcall(get, CL.DISENCHANT) end
  return ok and type(name) == "string" and name or "Disenchant"
end

function CL.disenchantMacro(row)
  if not row then return "" end
  return "/cast " .. spellName() .. "\n/use " .. row.bag .. " " .. row.slot
end

local function build()
  if panel then return panel end
  local parent = G("UIParent")
  panel = CreateFrame("Frame", "LootValueClearFrame", parent, G("BackdropTemplateMixin") and "BackdropTemplate" or nil)
  panel:SetSize(W, PAD * 2 + 22 + CL.ROWS * LINE_H + 30)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("HIGH")
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0, 0, 0, 0.9)
  end
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) if not inCombat() then self:StartMoving() end end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint(1)
    db().pos = { point, rel, x, y }
  end)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta)
    view.offset = math.max(0, math.min(math.max(0, #view.shown - CL.ROWS), view.offset - delta * 3))
    CL.draw()
  end)
  title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", PAD, -PAD)
  title:SetText("LootValue: clear bags")
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() CL.hide() end)

  lines = {}
  for i = 1, CL.ROWS do
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(W - PAD * 2, LINE_H)
    b:SetPoint("TOPLEFT", PAD, -(PAD + 22 + (i - 1) * LINE_H))
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.08)
    b.left = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.left:SetPoint("LEFT", 2, 0)
    b.left:SetWidth(W - PAD * 2 - 70)
    b.left:SetJustifyH("LEFT")
    if b.left.SetWordWrap then b.left:SetWordWrap(false) end
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetPoint("RIGHT", -2, 0)
    b:SetScript("OnClick", function(self, button) CL.onRowClick(self.row, button) end)
    b:SetScript("OnEnter", function(self) CL.rowTooltip(self) end)
    b:SetScript("OnLeave", function() local t = G("GameTooltip") if t then t:Hide() end end)
    lines[i] = b
  end

  sellBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  sellBtn:SetSize(130, 22)
  sellBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
  sellBtn:SetScript("OnClick", function() CL.sell() end)

  -- A cast needs a secure button. On Forever it works only on the down
  -- click with pressAndHoldAction (README, "Forever client notes").
  deBtn = CreateFrame("Button", "LootValueDisenchantButton", panel, "SecureActionButtonTemplate,UIPanelButtonTemplate")
  deBtn:SetSize(170, 22)
  deBtn:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  deBtn:RegisterForClicks("AnyDown")
  deBtn:SetAttribute("pressAndHoldAction", true)
  deBtn:SetAttribute("type", "macro")
  deBtn:SetAttribute("macrotext", "")
  deBtn:HookScript("OnEnter", function(self)
    local t = G("GameTooltip")
    if not t or not view.de then return end
    t:SetOwner(self, "ANCHOR_RIGHT")
    if t.SetBagItem then t:SetBagItem(view.de.bag, view.de.slot) end
    t:AddLine("Click: disenchant this item. It is destroyed.", 1, 0.3, 0.3)
    t:Show()
  end)
  deBtn:HookScript("OnLeave", function() local t = G("GameTooltip") if t then t:Hide() end end)
  panel:Hide()
  return panel
end

function CL.rowTooltip(line)
  local row, t = line.row, G("GameTooltip")
  if not row or not t then return end
  t:SetOwner(line, "ANCHOR_RIGHT")
  if t.SetBagItem then t:SetBagItem(row.bag, row.slot) elseif t.SetHyperlink then t:SetHyperlink(row.link) end
  if row.kind == "ah" then
    if row.note then t:AddLine("AH: " .. row.note, 0.62, 0.62, 0.62) end
    t:AddLine(CL.atAuction and "Click: put it in Auctionator's Selling tab" or "At the Auction House, click to post it",
      0.25, 1, 0.25)
    t:AddLine("Right-click: " .. (row.on and "hide this item" or "show it again"), 0.62, 0.62, 0.62)
  else
    local verb = row.kind == "de" and "disenchant" or "sell"
    t:AddLine("Click: " .. (row.on and "keep it" or (verb .. " it")), 0.25, 1, 0.25)
  end
  t:Show()
end

function CL.onRowClick(row, button)
  if not row then return end
  if row.kind == "ah" and button ~= "RightButton" then
    if not row.on then return end
    if CL.atAuction then CL.selectForAuction(row) else say("open the Auction House to post " .. tostring(row.link) .. ".") end
    return
  end
  CL.toggle(row)
  CL.refresh()
end

function CL.draw()
  if not panel then return end
  for i = 1, CL.ROWS do
    local entry = view.shown[view.offset + i]
    local line = lines[i]
    line.row = entry and entry.row or nil
    if not entry then
      line:Hide()
    else
      if entry.header then
        line.left:SetText(C_GOLD .. entry.header .. R)
        line.right:SetText("")
      else
        local row = entry.row
        line.left:SetText(lineText(row))
        line.right:SetText((row.on and "" or C_GREY) .. (row.kind == "vendor" and "" or "~") .. LV.money(row.value)
          .. (row.on and "" or R))
      end
      line:Show()
    end
  end
  local more = #view.shown - CL.ROWS
  title:SetText("LootValue: clear bags" .. (more > 0 and (C_GREY .. "  (scroll: " .. more .. " more)" .. R) or ""))
end

-- Read the bags again and redraw. The secure button's macro changes only
-- out of combat.
function CL.refresh()
  if not panel or not panel:IsShown() then return end
  view.rows = CL.scan()
  view.shown = CL.display(view.rows, view.mode)
  view.offset = math.max(0, math.min(view.offset, math.max(0, #view.shown - CL.ROWS)))
  local queue, left = CL.sellQueue(view.rows)
  local value = 0
  for _, row in ipairs(queue) do value = value + row.value end
  if #queue > 0 then
    sellBtn:SetText(string.format("Sell %d (%s)", #queue, LV.money(value)))
  else
    sellBtn:SetText("Nothing to sell")
  end
  sellBtn:SetEnabled(#queue > 0 and CL.atMerchant == true and not selling)
  view.left = left
  if not inCombat() then
    view.de = view.mode ~= "ah" and CL.nextDisenchant(view.rows) or nil
    deBtn:SetAttribute("macrotext", CL.disenchantMacro(view.de))
    if view.de then
      deBtn:SetText("Disenchant " .. tostring(view.de.name))
      deBtn:Show()
    else
      deBtn:Hide()
    end
  end
  CL.draw()
end

-- Beside the merchant or Auction House window when one is open, else where
-- you dragged it.
local function place(mode)
  local anchor = mode == "merchant" and G("MerchantFrame") or mode == "ah" and G("AuctionHouseFrame") or nil
  panel:ClearAllPoints()
  if anchor and anchor.IsShown and anchor:IsShown() then
    panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    return
  end
  local pos = db().pos
  if pos then panel:SetPoint(pos[1], G("UIParent"), pos[2], pos[3], pos[4]) else panel:SetPoint("CENTER") end
end

function CL.show(mode, auto)
  if inCombat() then
    if not auto then say("not in combat.") end
    return false
  end
  build()
  view.mode, view.offset, view.auto = mode or "all", 0, auto or false
  place(view.mode)
  panel:Show()
  CL.refresh()
  return true
end

function CL.hide()
  if panel and panel:IsShown() and not inCombat() then panel:Hide() end
end

-- Open by itself at a merchant or the AH only when a list has a ticked row.
function CL.autoShow(mode)
  if not db().auto or inCombat() then return end
  local t = CL.totals(CL.scan())
  local any = mode == "ah" and t.ah.n > 0 or mode == "merchant" and (t.vendor.n + t.de.n) > 0
  if any then CL.show(mode, true) end
end

function CL.slash(rest)
  local sub = (rest or ""):lower():match("^%s*(%S*)")
  if sub == "auto" then
    local c = db()
    c.auto = not c.auto
    say("the clear-bags panel " .. (c.auto and "opens by itself at a merchant and the Auction House."
      or "opens only with /lv clear."))
  elseif sub == "reset" then
    local c = db()
    c.choice, c.pos = {}, nil
    say("forgot every ticked and kept item, and the panel's place.")
    CL.refresh()
  elseif sub == "" then
    if panel and panel:IsShown() then CL.hide() else
      CL.show(CL.atMerchant and "merchant" or CL.atAuction and "ah" or "all")
    end
  else
    say("/lv clear shows what to sell, disenchant and auction. /lv clear auto: open by itself or not. "
      .. "/lv clear reset: forget your ticks.")
  end
end

local f = CreateFrame and CreateFrame("Frame")
if f then
  for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED" }) do
    f:RegisterEvent(e)
  end
  local function later(secs, fn)
    local timer = G("C_Timer")
    if timer and timer.After then timer.After(secs, fn) else fn() end
  end
  f:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
      if event == "MERCHANT_SHOW" then
        CL.atMerchant = true
        -- A moment later: another addon may sell the grey junk first.
        later(0.6, function() if CL.atMerchant then CL.autoShow("merchant") end end)
      elseif event == "MERCHANT_CLOSED" then
        CL.atMerchant = false
        if view.auto and view.mode == "merchant" then CL.hide() else CL.refresh() end
      elseif event == "AUCTION_HOUSE_SHOW" then
        CL.atAuction = true
        -- The AH window loads on demand: place the panel once it is there.
        later(0.3, function() if CL.atAuction then CL.autoShow("ah") end end)
      elseif event == "AUCTION_HOUSE_CLOSED" then
        CL.atAuction = false
        if view.auto and view.mode == "ah" then CL.hide() else CL.refresh() end
      elseif event == "BAG_UPDATE_DELAYED" then
        CL.refresh()
      elseif event == "PLAYER_REGEN_DISABLED" then
        -- The panel holds a secure button, so it cannot hide once combat
        -- has begun; this event still comes before the lock.
        if panel and panel:IsShown() then panel:Hide() end
      end
    end)
    if not ok and not CL.reported then
      CL.reported = true
      say("clear-bags error: " .. tostring(err))
    end
  end)
end
