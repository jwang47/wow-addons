-- UpgradeFinder window: a short ranked list of gear that beats what you wear.
-- Each row is one line (icon, name, slot, gain, price or dungeon); hover for
-- the details.
local _, ns = ...
local S, Scan = ns.score, ns.scan
local call, api = ns.call, ns.api

local ROWS, ROW_H, W = 14, 20, 484
local frame, rows, status, title, buttons = nil, {}, nil, nil, {}
local view = { list = {}, top = 1, all = {} }
ns.view = view

-- The Auction House window: AuctionHouseFrame on newer clients,
-- AuctionFrame on the classic UI that Forever loads.
function ns.ahFrame()
  for _, name in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
    local f = rawget(_G, name)
    if type(f) == "table" then return f, name end
  end
end

local function say(msg)
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  if f then f:AddMessage("|cff69ccf0Upgrades:|r " .. msg) end
end
ns.say = say

function ns.money(copper)
  copper = math.floor(copper or 0)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return string.format("%dg %02ds", g, s) end
  if s > 0 then return string.format("%ds %02dc", s, c) end
  return c .. "c"
end

local function opts()
  local o = ns.db().opts
  return { group = S.GROUPS[o.group or 1], level = call(UnitLevel, "player") or 1, ahead = o.ahead or 0,
    money = call(GetMoney) or 0, affordable = o.affordable, sort = o.sort, from = o.from }
end

-- keep: stay at the same scroll place (the list grows while items load).
function ns.apply(keep)
  view.list = S.rank(view.all, opts())
  view.top = keep and math.max(1, math.min(view.top, #view.list - ROWS + 1)) or 1
  ns.paint()
end

local function qualityColor(id)
  local q = call(api("C_Item.GetItemQualityByID"), id)
  local r, g, b = call(api("C_Item.GetItemQualityColor"), q or 1)
  if r then return r, g, b end
  return 1, 1, 1
end

local function labels()
  local o = ns.db().opts
  buttons.slot:SetText("Slot: " .. S.GROUPS[o.group or 1][1])
  buttons.level:SetText((o.ahead or 0) > 0 and ("Up to +" .. o.ahead .. " lvl") or "Usable now")
  buttons.sort:SetText(o.sort == "pergold" and "Per gold" or "Biggest gain")
  buttons.money:SetText(o.affordable and "Can afford" or "Any price")
  buttons.from:SetText(ns.FROM_LABEL[o.from or "all"])
end

function ns.paint()
  if not frame then return end
  labels()
  local _, _, spec = ns.weightKey()
  local wname = ns.weightsName()
  local sub = spec and wname and (spec .. ", " .. wname) or spec or wname
  title:SetText(sub and ("Upgrades |cff9d9d9d(" .. sub .. ")|r") or "Upgrades")
  local level = call(UnitLevel, "player") or 1
  for i, row in ipairs(rows) do
    local r = view.list[view.top + i - 1]
    row.data = r
    if r then
      row:Show()
      row.icon:SetTexture(call(api("C_Item.GetItemIconByID"), r.id) or 134400)
      -- Free elsewhere (quest, dungeon, vendor): a short tag after the name.
      local tag = r.source ~= "dungeon" and ns.where.tag(ns.where.of(r.id)) or nil
      if r.recipe then tag = "craft" end -- a pattern: the row is the item it makes
      row.name:SetText(tag and (r.name .. "  |cff8cc7ff" .. tag .. "|r") or r.name)
      row.name:SetTextColor(qualityColor(r.id))
      local gain = string.format("+%.1f", r.gain)
      if (r.reqLevel or 0) > level then gain = "|cff9d9d9d" .. gain .. " @" .. r.reqLevel .. "|r" end
      row.slot:SetText(S.groupName(r.loc) or "")
      row.gain:SetText(gain)
      row.price:SetText(r.source == "AH" and (r.price and ns.money(r.price) or "|cff9d9d9d?|r")
        or r.source == "dungeon" and r.drop and ("|cff8cc7ff" .. r.drop.short .. "|r")
        or "|cff40ff40" .. r.source .. "|r")
    else
      row:Hide()
    end
  end
  local st = Scan.state
  if st.gearLoading and #view.all == 0 then
    local w = Scan.worn()
    status:SetText("Loading your own gear" .. (w.missingSlot and (" (" .. w.missingSlot .. ")") or "") .. "...")
  elseif st.busy then
    status:SetText(string.format("Checking items... %d / %d", st.done, st.total))
  elseif #view.all == 0 and not st.ran then
    status:SetText("Open to scan your Auctionator prices, bags and dungeon drops.")
  else
    local more = #view.list > ROWS and string.format("  (scroll for %d more)", #view.list - ROWS) or ""
    status:SetText(string.format("%d upgrade%s%s", #view.list, #view.list == 1 and "" or "s", more)
      .. (st.pending and st.pending > 0 and string.format(st.loading and "  |cff9d9d9dloading %d more...|r"
        or "  |cff9d9d9d%d did not load (Rescan)|r", st.pending) or "")
      .. ((st.skipped or 0) > 0 and not st.loading
        and string.format("  |cff9d9d9d%d skipped (Rescan)|r", st.skipped) or ""))
  end
end

function ns.rescan()
  local first = true
  Scan.run(function() ns.paint() end, function(all)
    Scan.state.ran = true
    view.all = all
    ns.apply(not first)
    first = false
  end)
  ns.paint()
end

-- Tooltip: the item, then what it replaces and the numbers.
local function showDetails(row)
  local r = row.data
  local tt = rawget(_G, "GameTooltip")
  if not (r and tt) then return end
  tt:SetOwner(row, "ANCHOR_RIGHT")
  tt:SetHyperlink("item:" .. r.id)
  -- One entry per line: the label on the left, the number on the right.
  local function section(title, list)
    if #list == 0 then return end
    tt:AddLine(title, 1, 0.82, 0)
    for _, e in ipairs(list) do
      tt:AddDoubleLine("  " .. e[1], e[2], 0.9, 0.9, 0.9, e[3] and 0.25 or 1, e[3] and 1 or 0.38, 0.25)
    end
  end
  tt:AddLine(" ")
  tt:AddDoubleLine(string.format("Upgrade +%.1f", r.gain), string.format("score %.1f vs %.1f worn", r.value, r.value - r.gain),
    0.25, 1, 0.25, 0.6, 0.6, 0.6)
  if r.recipe then tt:AddLine("Crafted: " .. r.recipe .. (r.craft and (" (" .. r.craft .. ")") or ""), 1, 0.82, 0) end
  if r.note then tt:AddLine(r.note, 1, 0.82, 0) end
  -- What it changes (Stats.lua): stats, then offense and defense.
  local ok, d, off, def = pcall(ns.stats.forRow, r)
  if ok and d and next(d) then
    tt:AddLine(" ")
    section("Stats", ns.stats.statList(d))
    section("Offense", off)
    section("Defense", def)
    tt:AddLine(" ")
  end
  -- The "Get it:" lines come from the item tooltip hook (Where.lua).
  local where = ns.where.of(r.id)
  local drop = r.drop
  if drop then
    tt:AddLine(string.format("Drops from %s in %s (levels %d-%d)", drop.boss, drop.name, drop.min, drop.max), 0.55, 0.78, 1)
    if r.source == "AH" then tt:AddLine("You may not need to buy it", 0.55, 0.78, 1) end
  elseif r.source == "AH" and where and (where.quests[1] or where.dungeon) then
    tt:AddLine(where.quests[1] and "A quest gives it: you may not need to buy it"
      or ("Drops in " .. where.dungeon .. ": you may not need to buy it"), 0.55, 0.78, 1)
  end
  if r.perGold then tt:AddLine(string.format("%.2f per gold", r.perGold), 0.7, 0.7, 0.7) end
  if (r.reqLevel or 0) > (call(UnitLevel, "player") or 1) then tt:AddLine("Needs level " .. r.reqLevel, 1, 0.5, 0.3) end
  tt:AddLine(r.source == "AH" and "Click: search the AH   Shift-click: link"
    or r.source == "dungeon" and "Dungeon drop   Shift-click: link"
    or "In your bags   Shift-click: link", 0.6, 0.6, 0.6)
  tt:AddLine("Alt-click: try it in the Build window", 0.6, 0.6, 0.6)
  tt:Show()
end

ns.showDetails = showDetails

local function click(row)
  local r = row.data
  if not r then return end
  if call(rawget(_G, "IsAltKeyDown")) then ns.rowToBuild(r) return end
  if IsShiftKeyDown and IsShiftKeyDown() then
    local _, link = call(api("C_Item.GetItemInfo"), r.id)
    if link and not call(rawget(_G, "ChatEdit_InsertLink"), link) then call(rawget(_G, "ChatFrame_OpenChat"), link) end
    return
  end
  if r.source == "dungeon" and r.drop then
    say(string.format("%s drops from %s in %s.", r.name, r.drop.boss, r.drop.name))
    return
  end
  local search = api("Auctionator.API.v1.MultiSearchExact")
  local ah = ns.ahFrame()
  if search and ah and ah.IsShown and ah:IsShown() then call(search, "UpgradeFinder", { r.name })
  else say(r.name .. ": open the Auction House to search for it.") end
end

-- The source filter: all, then AH only, dungeon drops only, bags only.
ns.FROM_LABEL = { all = "All sources", AH = "AH only", dungeon = "Dungeons", bags = "Bags only" }
ns.FROM_NEXT = { all = "AH", AH = "dungeon", dungeon = "bags", bags = nil }

local function cycle(key)
  local o = ns.db().opts
  if key == "slot" then o.group = (o.group or 1) % #S.GROUPS + 1
  elseif key == "level" then o.ahead = ((o.ahead or 0) == 0) and 2 or 0
  elseif key == "sort" then o.sort = (o.sort == "pergold") and "gain" or "pergold"
  elseif key == "money" then o.affordable = not o.affordable
  elseif key == "from" then o.from = ns.FROM_NEXT[o.from or "all"] end
  ns.apply()
end
ns.cycle = cycle

local function build()
  frame = CreateFrame("Frame", "UpgradeFinderFrame", UIParent, rawget(_G, "BackdropTemplateMixin") and "BackdropTemplate" or nil)
  ns.frame = frame
  frame:SetSize(W, 92 + ROWS * ROW_H)
  frame:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
  end
  local special = rawget(_G, "UISpecialFrames")
  if type(special) == "table" then table.insert(special, "UpgradeFinderFrame") end

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
  title:SetText("Upgrades")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  local again = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  again:SetSize(64, 18)
  again:SetPoint("RIGHT", close, "LEFT", -2, 0)
  again:SetText("Rescan")
  -- Keeps the saved scores; tries the items that did not load again.
  again:SetScript("OnClick", function() ns.db().missing = {} ns.rescan() end)
  local wbtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  wbtn:SetSize(64, 18)
  wbtn:SetPoint("RIGHT", again, "LEFT", -4, 0)
  wbtn:SetText("Weights")
  wbtn:SetScript("OnClick", function() ns.toggleWeights() end)
  ns.weightsButton = wbtn
  local bbtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  bbtn:SetSize(54, 18)
  bbtn:SetPoint("RIGHT", wbtn, "LEFT", -4, 0)
  bbtn:SetText("Build")
  bbtn:SetScript("OnClick", function() ns.toggleBuild() end)
  ns.buildButton = bbtn

  -- Five toggle buttons in one row: slot, level, sort, price, source.
  local x = 10
  for _, spec in ipairs({ { "slot", 100 }, { "level", 92 }, { "sort", 86 }, { "money", 80 }, { "from", 84 } }) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(spec[2], 20)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -32)
    b:SetScript("OnClick", function() cycle(spec[1]) end)
    if spec[1] == "slot" then
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b:SetScript("OnClick", function(_, button)
        local o = ns.db().opts
        o.group = button == "RightButton" and ((o.group or 1) - 2) % #S.GROUPS + 1 or (o.group or 1) % #S.GROUPS + 1
        ns.apply()
      end)
    end
    buttons[spec[1]] = b
    x = x + spec[2] + 4
  end

  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -58 - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -58 - (i - 1) * ROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.9, 0.7, 0.3, 0.18)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 2, ROW_H - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.price:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.price:SetWidth(64)
    row.price:SetJustifyH("RIGHT")
    row.gain = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.gain:SetPoint("RIGHT", row.price, "LEFT", -6, 0)
    row.gain:SetWidth(62)
    row.gain:SetJustifyH("RIGHT")
    row.gain:SetTextColor(0.25, 1, 0.25)
    row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.slot:SetPoint("RIGHT", row.gain, "LEFT", -6, 0)
    row.slot:SetWidth(56)
    row.slot:SetJustifyH("LEFT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.slot, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter", showDetails)
    row:SetScript("OnLeave", function() local tt = rawget(_G, "GameTooltip") if tt then tt:Hide() end end)
    row:SetScript("OnClick", click)
    rows[i] = row
  end
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    view.top = math.max(1, math.min(view.top - delta * 3, math.max(1, #view.list - ROWS + 1)))
    ns.paint()
  end)
  status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
  status:SetJustifyH("LEFT")
end

function ns.open()
  if not frame then build() end
  frame:Show()
  if #view.all == 0 and not Scan.state.busy then ns.rescan()
  elseif Scan.state.busy then ns.paint()
  else ns.apply() end -- gear, bags or money may have changed while it was closed
end

function ns.toggle()
  if frame and frame:IsShown() then frame:Hide() else ns.open() end
end
UpgradeFinder_Toggle = ns.toggle

-- A button on the Auction House window.
local ahButton
function ns.addAHButton(tries)
  if ahButton then return end
  local ah, name = ns.ahFrame()
  if not ah then
    -- The window's addon can load just after the event: look again.
    if (tries or 0) < 5 then call(api("C_Timer.After"), 0.2, function() ns.addAHButton((tries or 0) + 1) end) end
    return
  end
  ahButton = CreateFrame("Button", nil, ah, "UIPanelButtonTemplate")
  ahButton:SetSize(84, 22)
  if name == "AuctionFrame" then
    ahButton:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -40, -14) -- left of the close button
  else
    ahButton:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -60, -1)
  end
  ahButton:SetFrameLevel((ah.GetFrameLevel and ah:GetFrameLevel() or 0) + 10)
  ahButton:SetText("Upgrades")
  ahButton:SetScript("OnClick", ns.toggle)
end

---------------------------------------------------------------------------
-- /uf and events
---------------------------------------------------------------------------
local HELP = {
  "/uf - open the list (also a button on the Auction House)",
  "/uf config - the Weights panel (also the Weights button on the window)",
  "/uf weights - your stat weights; /uf weight STAT N to change one, /uf weight STAT default to undo it",
  "/uf weight reset - back to the default weights for your spec",
  "/uf save NAME - save your weights as a preset; /uf load NAME, /uf presets, /uf delete NAME",
  "/uf reset - forget the saved item scores (they are kept between sessions)",
  "/uf where - turn the \"Get it:\" lines on item tooltips on or off (needs Questie)",
  "/uf dungeons - turn the dungeon drops in the list on or off (the From button filters them)",
  "/uf build - the Build window: try items in each slot, save builds, compare them (Alt-click a row to add it)",
  "/uf calib - the Forever formulas measured from your client (crit per Int and Agi, your spells); /uf calib reset; /uf calib log turns on the combat log (Forever blocks it)",
}
local function copy(t) local c = {} for k, v in pairs(t or {}) do c[k] = v end return c end

-- The name of the weights in use: a preset, "custom", or nil (the defaults).
function ns.weightsName()
  local db, key = ns.db(), ns.weightKey()
  if db.active[key] then return db.active[key] end
  if next(db.weights[key] or {}) then return "custom" end
end

-- New weights: score the items again (the weights are in the cache key),
-- and show them in the Weights panel.
function ns.reweigh(text)
  if text then say(text) end
  if frame and frame:IsShown() then ns.rescan() else view.all = {} end -- closed: the next open scans
  if ns.paintWeights then ns.paintWeights() end
end

function ns.statList()
  local s = {}
  for k in pairs(S.STATS) do table.insert(s, k) end
  table.sort(s)
  return s
end

-- Weights and presets. The slash commands and the Weights panel both use these.
-- value nil = back to the default for that stat.
function ns.setWeight(stat, value)
  local db, key = ns.db(), ns.weightKey()
  if not S.STATS[stat] then return false end
  if value == nil then
    local w = db.weights[key]
    if w then w[stat] = nil if not next(w) then db.weights[key] = nil end end
  else
    db.weights[key] = db.weights[key] or {}
    db.weights[key][stat] = value
  end
  db.active[key] = nil
  return true
end
function ns.resetWeights()
  local db, key = ns.db(), ns.weightKey()
  db.weights[key], db.active[key] = nil, nil
end
function ns.presetNames()
  local names = {}
  for n in pairs(ns.db().presets[ns.class()] or {}) do table.insert(names, n) end
  table.sort(names)
  return names
end
function ns.savePreset(name)
  local db, key, class = ns.db(), ns.weightKey()
  db.presets[class] = db.presets[class] or {}
  db.presets[class][name] = copy(ns.weights())
  db.active[key] = name
end
function ns.loadPreset(name)
  local db, key, class = ns.db(), ns.weightKey()
  local p = (db.presets[class] or {})[name]
  if not p then return false end
  db.weights[key], db.active[key] = copy(p), name
  return true
end
function ns.deletePreset(name)
  local db, _, class = ns.db(), ns.weightKey()
  if not (db.presets[class] or {})[name] then return false end
  db.presets[class][name] = nil
  for k, n in pairs(db.active) do if n == name and k:match("^[^:]+") == class then db.active[k] = "custom" end end
  return true
end

function ns.slash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, a, b = msg:match("^(%S*)%s*(%S*)%s*(%S*)")
  local key, class, spec = ns.weightKey()
  if cmd == "help" then for _, l in ipairs(HELP) do say(l) end say("Stats: " .. table.concat(ns.statList(), " "))
  elseif cmd == "weights" and a == "" then
    local parts = {}
    for k, v in pairs(ns.weights()) do table.insert(parts, k .. " " .. v) end
    table.sort(parts)
    say(class:lower() .. (spec and (" (" .. spec .. ")") or "") .. ", " .. (ns.weightsName() or "default") .. ": "
      .. table.concat(parts, ", "))
    if class == "MAGE" and rawget(_G, "MageMentorAPI") then say("(MageMentor's weights are used for a mage: /mm weight)") end
  elseif cmd == "presets" then
    local names, active = ns.presetNames(), ns.db().active[key]
    for i, n in ipairs(names) do if n == active then names[i] = n .. " (in use)" end end
    say(#names > 0 and ("presets for " .. class:lower() .. ": " .. table.concat(names, ", ")) or "no presets yet: /uf save NAME")
  elseif cmd == "save" and a ~= "" then
    ns.savePreset(a)
    say("saved your weights as \"" .. a .. "\"; /uf load " .. a .. " brings them back")
    if ns.paintWeights then ns.paintWeights() end
  elseif cmd == "load" and a ~= "" then
    if not ns.loadPreset(a) then say("no preset \"" .. a .. "\" (/uf presets lists them)") return end
    ns.reweigh("weights: preset \"" .. a .. "\"")
  elseif cmd == "delete" and a ~= "" then
    if not ns.deletePreset(a) then say("no preset \"" .. a .. "\"") return end
    say("deleted preset \"" .. a .. "\" (the weights in use stay)")
    if ns.paintWeights then ns.paintWeights() end
  elseif cmd == "reset" then
    Scan.forget()
    ns.db().missing = {}
    say("saved item scores cleared; Rescan reads every item again")
  elseif cmd == "where" then
    local o = ns.db().opts
    o.where = o.where == false
    say("\"Get it:\" lines on item tooltips " .. (o.where and "on" or "off"))
  elseif cmd == "build" then
    ns.toggleBuild(true)
  elseif cmd == "calib" and a == "log" then
    ns.calib.setLog(not ns.calib.logOn())
    say("combat log for spell calibration " .. (ns.calib.logOn() and "on (if the game blocks it, turn it off again)" or "off"))
  elseif cmd == "calib" and a == "reset" then
    ns.calib.reset()
    say("calibration data for your class cleared")
  elseif cmd == "calib" then
    pcall(ns.calib.snap)
    for _, l in ipairs(ns.calib.report()) do say(l) end
  elseif cmd == "dungeons" then
    local o = ns.db().opts
    o.dungeons = o.dungeons == false
    say("dungeon drops in the list " .. (o.dungeons and "on" or "off"))
    if frame and frame:IsShown() then ns.rescan() else view.all = {} end
  elseif cmd == "weight" and a == "reset" then
    ns.resetWeights()
    ns.reweigh("weights back to the default for " .. (spec or class:lower()))
  elseif cmd == "weight" and a ~= "" and not S.STATS[a] then
    say("unknown stat \"" .. a .. "\". Stats: " .. table.concat(ns.statList(), " "))
  elseif cmd == "weight" and b == "default" then
    ns.setWeight(a, nil)
    ns.reweigh(a .. " back to its default (" .. tostring(ns.weights()[a] or 0) .. ")")
  elseif cmd == "weight" and tonumber(b) then
    ns.setWeight(a, tonumber(b))
    ns.reweigh(a .. " = " .. b)
  elseif cmd == "config" then
    ns.open() ns.toggleWeights(true)
  else ns.toggle() end
end
SLASH_UPGRADEFINDER1 = "/uf"
SLASH_UPGRADEFINDER2 = "/upgrades"
SlashCmdList.UPGRADEFINDER = function(msg)
  local ok, err = pcall(ns.slash, msg)
  if not ok then say("error: " .. tostring(err)) end
end

BINDING_HEADER_UPGRADEFINDER = "UpgradeFinder"
BINDING_NAME_UPGRADEFINDER_TOGGLE = "Show gear upgrades"

function ns.refresh()
  if not Scan.lastSources or Scan.state.busy then return end
  view.all = Scan.refresh()
  if frame and frame:IsShown() then ns.apply(true) end
end

function ns.specCheck()
  if not Scan.key or Scan.key == ns.weightKey() then return end
  Scan.state.gen = (Scan.state.gen or 0) + 1 -- stops a scan with the old weights
  Scan.state.busy, Scan.state.loading = false, false
  Scan.forget()
  view.all, Scan.key = {}, nil
  Scan.state.ran = false
  if frame and frame:IsShown() then ns.rescan() end
end

local events = CreateFrame("Frame")
ns.events = events
local handlers = {
  AUCTION_HOUSE_SHOW = function() ns.addAHButton() end,
  -- Newer clients open the AH through the interaction manager (Auctionator
  -- listens to both).
  PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind)
    if kind ~= nil and kind == api("Enum.PlayerInteractionType.Auctioneer") then ns.addAHButton() end
  end,
  -- What you wear or carry changed: the stored item values stay, the gains
  -- and the bag items change. During a scan its end rereads both.
  PLAYER_EQUIPMENT_CHANGED = function() ns.refresh() end,
  BAG_UPDATE_DELAYED = function() ns.refresh() end,
  -- New talent points can change your spec, and so the weights.
  CHARACTER_POINTS_CHANGED = function() ns.specCheck() end,
  PLAYER_TALENT_UPDATE = function() ns.specCheck() end,
  PLAYER_LEVEL_UP = function() if frame and frame:IsShown() then ns.apply() end end,
  -- The game stopped one of our calls: say which, and keep the last few
  -- (UpgradeFinderDB.blocked) so a bug report can name it.
  ADDON_ACTION_BLOCKED = function(addon, fn) ns.blocked(addon, fn, "blocked") end,
  ADDON_ACTION_FORBIDDEN = function(addon, fn) ns.blocked(addon, fn, "forbidden") end,
}
function ns.blocked(addon, fn, kind)
  if addon ~= "UpgradeFinder" then return end
  local db = ns.db()
  db.blocked = db.blocked or {}
  local stack = call(rawget(_G, "debugstack"), 3, 6, 0)
  table.insert(db.blocked, { fn = tostring(fn), kind = kind, time = call(rawget(_G, "time")), stack = stack })
  while #db.blocked > 5 do table.remove(db.blocked, 1) end
  say(kind .. ": " .. tostring(fn) .. " (please send this line)")
  -- On Forever the combat log is what gets forbidden: turn it off for good.
  if ns.calib and ns.calib.logOn() then
    ns.calib.setLog(false)
    say("combat log turned off again: this client does not allow it")
  end
end
ns.handlers = handlers
for ev in pairs(handlers) do pcall(events.RegisterEvent, events, ev) end -- unknown events throw
events:SetScript("OnEvent", function(_, ev, ...)
  local ok, err = pcall(handlers[ev], ...)
  if not ok then say(ev .. " error: " .. tostring(err)) end
end)
