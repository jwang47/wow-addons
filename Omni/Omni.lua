-- Omni: one search box for items, places, people, spells, MageMentor
-- commands and (with Questie) NPCs and quests. Open it with the key binding
-- (Ctrl+Space by default, if free) or /omni.
local addonName, ns = ...
local M, S, A = ns.match, ns.sources, ns.actions
local call, api = ns.call, ns.api

local MAX_ROWS = 20
local ROW_H = 18
local WIDTH = 480

local frame, box, rows, footer
local lists = {}       -- the entry arrays searched, rebuilt on each open
-- rows: every result row (headers too); top: the first row on screen.
local view = { rows = {}, pick = 0, top = 1 }
ns.view = view
ns.MAX_ROWS = MAX_ROWS

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------
local reported = {}
function ns.rebuild()
  local npcs, quests, qitems = S.questieLists()
  -- One source that trips on unexpected data gives an empty group (and one
  -- chat line), not an error on every Ctrl+Space.
  local function safe(name, fn, ...)
    local ok, list = pcall(fn, ...)
    if ok and type(list) == "table" then return list end
    if not ok and not reported[name] then
      reported[name] = true
      ns.say(name .. " error: " .. tostring(list))
    end
    return {}
  end
  -- Order matters: the first source to give a key wins (owned items before
  -- Questie's copy of the same item; S.items keeps its Questie flag).
  lists = { safe("commands", S.commands), safe("quest log", S.questLog), safe("spells", S.spells),
    safe("items", S.items, qitems), safe("places", S.places), safe("dungeons", S.dungeons), safe("people", S.people), qitems or {},
    safe("nearby", S.nearby), npcs or {}, quests or {} }
  return lists
end

-- Keep the newest RECENT_KEPT keys, so SavedVariables does not grow forever.
ns.RECENT_KEPT = 200
function ns.trimRecent(recent)
  local keys = {}
  for k in pairs(recent) do table.insert(keys, k) end
  if #keys <= ns.RECENT_KEPT then return end
  table.sort(keys, function(a, b) return (recent[a] or 0) > (recent[b] or 0) end)
  for i = ns.RECENT_KEPT + 1, #keys do recent[keys[i]] = nil end
end

function ns.search(text)
  local only, q = M.parse(text)
  if only == "loot" then return (S.dungeonLoot(q)) end
  if only == "from" then return ns.sourcesFor(q) end
  if only == "recipe" then return (S.recipes(lists, q)) end
  return (M.search(lists, text, ns.db().recent))
end

-- "from: Silk Cloth": where to get the item. ns.fromID is the item Enter
-- was pressed on; a typed name looks the item up by its exact name.
-- With no rows, ns.emptyText says why.
function ns.sourcesFor(q)
  local id = ns.fromID and ns.fromName == q and ns.fromID
  local name
  if not id then
    -- The exact name, else the only item whose name starts with q.
    local prefix, many
    for _, src in ipairs(lists) do
      for _, e in ipairs(src) do
        if e.kind == "item" then
          if e.lname == q then id, name = e.id, e.name break end
          if q ~= "" and e.lname:sub(1, #q) == q then
            if prefix and prefix.id ~= e.id then many = true end
            prefix = prefix or e
          end
        end
      end
      if id then break end
    end
    if not id and prefix and not many then id, name = prefix.id, prefix.name end
  end
  if not id then
    local qs = S.questieState.state
    ns.emptyText = (qs == "busy" or qs == "idle") and "Questie is still loading; try again in a moment"
      or ("No item called \"" .. q .. "\" (Omni knows your items, the AH scan and Questie's items)")
    return {}
  end
  local groups = S.itemSources(id)
  if #groups == 0 then
    ns.emptyText = (S.questieDB() and "Questie has no drop, object or vendor for " or "Questie is off: no sources for ")
      .. (name or ns.db().itemNames[id] or ("item " .. id))
  end
  return groups
end

-- Shows where to get an item (Enter on an item row).
function ns.showSources(e)
  ns.fromID, ns.fromName = e.id, M.norm(e.name)
  ns.setText("from: " .. e.name)
end

-- Puts text in the box (the next refresh searches it).
function ns.setText(text)
  if box then box:SetText(text) end
end



-- Rows for the list: a header row per group, then its entries. All groups
-- are kept; the frame shows MAX_ROWS of them and scrolls (view.top).
function ns.layout(groups)
  local out = {}
  for _, g in ipairs(groups) do
    local title = g.title
    if g.more and g.more > 0 then title = title .. string.format("  |cff9d9d9d+%d more|r", g.more) end
    table.insert(out, { header = true, text = title })
    for _, e in ipairs(g.entries) do table.insert(out, { entry = e }) end
  end
  return out
end

-- Scrolls so the picked row (and its group header, when it fits) is on screen.
local function keepVisible()
  local n, p = #view.rows, view.pick
  if p > 0 then
    local want = p
    if p > 1 and view.rows[p - 1].header then want = p - 1 end
    if want < view.top then view.top = want end
    if p > view.top + MAX_ROWS - 1 then view.top = p - MAX_ROWS + 1 end
  end
  view.top = math.max(1, math.min(view.top, n - MAX_ROWS + 1))
end
ns.keepVisible = keepVisible

function ns.scroll(delta)
  view.top = view.top + delta
  keepVisible()
end

local function firstPick(list)
  for i, r in ipairs(list) do if r.entry then return i end end
  return 0
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
-- The game puts the "Equipped" comparison on the side of the item tooltip
-- with more room, which is often the left: on top of Omni's list. Move it to
-- the right of the item tooltip when it fits there, else below it.
local function shopping(tt)
  local list = type(tt.shoppingTooltips) == "table" and tt.shoppingTooltips
    or { rawget(_G, "ShoppingTooltip1"), rawget(_G, "ShoppingTooltip2") }
  local out = {}
  for _, s in ipairs(list) do
    if type(s) == "table" and s.IsShown and s:IsShown() then table.insert(out, s) end
  end
  return out
end

local function px(f, v) return (v or 0) * (call(f.GetEffectiveScale, f) or 1) end

-- Picks a layout whose whole box fits on screen: a row right of the item
-- tooltip, a row below it, or a column below it. Each comparison is
-- anchored to GameTooltip itself (never to the other comparison), so the
-- game's own layout, which anchors one comparison to the other, can't
-- form a loop with ours. Offsets are in each tooltip's own scale.
function ns.placeCompare()
  local tt = rawget(_G, "GameTooltip")
  if not (tt and frame and frame:IsShown() and tt.GetOwner and tt:GetOwner() == frame) then return end
  local list = shopping(tt)
  if #list == 0 then return end
  local GAP = 2
  local ui = rawget(_G, "UIParent")
  local screenW = px(ui, ui and call(ui.GetRight, ui) or call(rawget(_G, "GetScreenWidth")))
  local left, right = px(tt, call(tt.GetLeft, tt)), px(tt, call(tt.GetRight, tt))
  local bottom = px(tt, call(tt.GetBottom, tt))
  local sizes, rowW, colH, maxW, maxH = {}, 0, 0, 0, 0
  for i, sh in ipairs(list) do
    local w, h = px(sh, call(sh.GetWidth, sh)), px(sh, call(sh.GetHeight, sh))
    sizes[i] = { w = w, h = h }
    rowW, colH = rowW + w + GAP, colH + h + GAP
    maxW, maxH = math.max(maxW, w), math.max(maxH, h)
  end
  local layout
  if right + rowW <= screenW then layout = "right"
  elseif bottom - maxH - GAP >= 0 and left + rowW <= screenW then layout = "row"
  elseif bottom - colH >= 0 and left + maxW <= screenW then layout = "column"
  else return end -- nothing fits: keep the game's own layout
  local dx, dy = 0, 0 -- in screen pixels from the anchor point
  for i, sh in ipairs(list) do
    local scale = call(sh.GetEffectiveScale, sh) or 1
    sh:ClearAllPoints()
    if layout == "right" then
      sh:SetPoint("TOPLEFT", tt, "TOPRIGHT", (GAP + dx) / scale, 0)
      dx = dx + sizes[i].w + GAP
    elseif layout == "row" then
      sh:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", dx / scale, -GAP / scale)
      dx = dx + sizes[i].w + GAP
    else
      sh:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, -(GAP + dy) / scale)
      dy = dy + sizes[i].h + GAP
    end
  end
  return layout
end

local compareHooked = false
local function hookCompare()
  if compareHooked then return end
  compareHooked = true
  local hook = rawget(_G, "hooksecurefunc")
  if type(hook) ~= "function" then return end
  if type(rawget(_G, "GameTooltip_ShowCompareItem")) == "function" then
    hook("GameTooltip_ShowCompareItem", ns.placeCompare)
  end
  local mgr = rawget(_G, "TooltipComparisonManager")
  if type(mgr) == "table" and type(mgr.AnchorShoppingTooltips) == "function" then
    hook(mgr, "AnchorShoppingTooltips", ns.placeCompare)
  end
end

local function showTooltip()
  local tt = rawget(_G, "GameTooltip")
  local r = view.rows[view.pick]
  if not (tt and frame and frame:IsShown()) then return end
  if not (r and r.entry) then tt:Hide() return end
  tt:SetOwner(frame, "ANCHOR_NONE")
  tt:ClearAllPoints()
  tt:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
  local ok, err = pcall(A.tooltip, tt, r.entry)
  if not ok then ns.say("tooltip error: " .. tostring(err)) end
  hookCompare()
  pcall(ns.placeCompare)
  -- The game can place the comparison a frame later.
  call(api("C_Timer.After"), 0, function() pcall(ns.placeCompare) end)
end

local function iconFor(e)
  if e.kind == "item" then return call(api("C_Item.GetItemIconByID"), e.id) end
  if e.kind == "spell" then return e.icon or call(api("C_Spell.GetSpellTexture"), e.spellID) end
end

local function paint()
  if not rows then return end
  keepVisible()
  for i, row in ipairs(rows) do
    local at = view.top + i - 1
    local r = view.rows[at]
    if not r then
      row:Hide()
    else
      row:Show()
      row.data = r
      if r.header then
        row.left:SetText("|cffffd100" .. r.text .. "|r")
        row.right:SetText("")
        row.icon:Hide()
      else
        local e = r.entry
        row.left:SetText(e.name)
        local ok, d = pcall(A.detail, e)
        row.right:SetText(ok and d or "")
        local tex = iconFor(e)
        if tex then row.icon:SetTexture(tex) row.icon:Show() else row.icon:Hide() end
      end
      if at == view.pick then row.sel:Show() else row.sel:Hide() end
    end
  end
  local n = #view.rows
  frame:SetHeight(56 + math.max(math.min(n, MAX_ROWS), 1) * ROW_H)
  local r = view.rows[view.pick]
  local qs = S.questieState.state
  local status = qs == "busy" and "  |cff9d9d9d(reading Questie...)|r" or ""
  if n > view.top + MAX_ROWS - 1 then status = status .. "  |cff9d9d9d(more below)|r" end
  if n == 0 then
    footer:SetText((box:GetText() == "" and "Type to search items, places, people, spells, NPCs.  i: p: @ s: n: q:"
      or ns.emptyText or "No match") .. status)
  else
    footer:SetText("|cff9d9d9d" .. A.hint(r and r.entry) .. "|r" .. status)
  end
  showTooltip()
end

-- Typing: each search runs in a coroutine that yields after BUDGET_MS of
-- work and goes on next frame, so a keystroke never stalls the game. A new
-- keystroke drops the old search. A query that extends the last one looks
-- only at the last one's exact hits. Exact hits show at once; fuzzy ones
-- follow when their pass ends.
ns.BUDGET_MS = 4
local job
local last = {} -- { lists, only, q, matched } of the last finished exact pass
ns.perf = { ms = 0, frames = 0, text = "" }

local function clock()
  local f = rawget(_G, "debugprofilestop")
  return type(f) == "function" and f() or nil
end

local function narrowFor(text)
  local only, q = M.parse(text)
  if last.lists == lists and last.only == only and last.q and last.q ~= "" and q ~= ""
    and #q > #last.q and q:sub(1, #last.q) == last.q then
    return last.matched
  end
end

-- keep: the key of an entry to keep picked if it is still there (the fuzzy
-- hits of the same query arrive after the exact ones).
local function show(groups, keep)
  view.rows = ns.layout(groups)
  view.pick = firstPick(view.rows)
  if keep then
    for i, r in ipairs(view.rows) do
      if r.entry and r.entry.key == keep then view.pick = i break end
    end
  end
  view.top = 1
  paint()
end

local function step(my)
  if job ~= my then return end
  local t0 = clock()
  my.deadline = my.full and math.huge or (t0 and t0 + ns.BUDGET_MS)
  local ok, groups = coroutine.resume(my.co)
  local t1 = clock()
  if t0 and t1 then my.ms = my.ms + (t1 - t0) end
  my.frames = my.frames + 1
  if not ok then
    job = nil
    ns.say("search error: " .. tostring(groups))
  elseif coroutine.status(my.co) == "dead" then
    job = nil
    ns.perf = { ms = my.ms, frames = my.frames, text = my.text }
    local picked = my.shownExact and view.rows[view.pick]
    show(groups, picked and picked.entry and picked.entry.key)
  else
    call(api("C_Timer.After"), 0, function() step(my) end)
  end
end

-- "loot: bfd" lists a dungeon's drops. Item names the client has not
-- loaded yet show as "item 1234"; look again shortly (a few times).
ns.LOOT_RETRIES = 5
local lootTries = {}
local function showLoot(text, q, fn)
  job = nil
  local groups, loading = (fn or S.dungeonLoot)(q)
  show(groups)
  local n = (lootTries[text] or 0) + 1
  lootTries[text] = n
  if loading and n <= ns.LOOT_RETRIES then
    call(api("C_Timer.After"), 0.4, function()
      if frame and frame:IsShown() and box:GetText() == text then showLoot(text, q, fn) end
    end)
  end
end

function ns.startSearch(text)
  ns.emptyText = nil
  local only, q = M.parse(text)
  if only == "loot" then
    lootTries = {}
    return showLoot(text, q)
  end
  if only == "from" then
    job = nil
    return show(ns.sourcesFor(q))
  end
  if only == "recipe" then
    lootTries = {}
    return showLoot(text, q, function(query)
      local groups, loading = S.recipes(lists, query)
      if #groups == 0 then
        ns.emptyText = "No recipe matches. Omni knows the recipes in your bags, bank, mail and the AH scan."
      end
      return groups, loading
    end)
  end
  local my = { text = text, ms = 0, frames = 0 }
  job = my
  local narrow = narrowFor(text)
  local function remember(matched)
    last = { lists = lists, only = only, q = q, matched = matched }
  end
  my.co = coroutine.create(function()
    local groups, matched = M.search(lists, text, ns.db().recent, {
      narrow = narrow,
      tick = function()
        local t = my.deadline and clock()
        if t and t > my.deadline then coroutine.yield() end
      end,
      onExact = function(g, matched)
        remember(matched)
        my.shownExact = true
        show(g)
        coroutine.yield()
      end,
    })
    if matched then remember(matched) end
    return groups
  end)
  step(my)
end

function ns.cancelSearch() job = nil end

-- Runs a search still going to its end now (Enter acts on full results).
function ns.finishSearch()
  local my = job
  if not my then return end
  my.full = true
  while job == my do step(my) end
end

function ns.refresh()
  ns.startSearch(box and box:GetText() or "")
end

function ns.move(step)
  local n = #view.rows
  if n == 0 then return end
  local i = view.pick
  for _ = 1, n do
    i = i + step
    if i < 1 then i = n elseif i > n then i = 1 end
    if view.rows[i].entry then break end
  end
  view.pick = i
  paint()
end

-- Tab / Shift+Tab: the first entry of the next or previous group.
function ns.nextGroup(step)
  local heads, cur = {}, 1
  for i, r in ipairs(view.rows) do
    if r.header then
      table.insert(heads, i)
      if i <= view.pick then cur = #heads end
    end
  end
  if #heads == 0 then return end
  local g = (cur - 1 + step) % #heads + 1
  local r = view.rows[heads[g] + 1]
  if r and r.entry then view.pick = heads[g] + 1 end
  paint()
end

function ns.act(alt, index)
  -- Act on the entry that was picked or clicked, even if finishing the
  -- search moves it to another row.
  local before = view.rows[index or view.pick]
  local key = before and before.entry and before.entry.key
  ns.finishSearch()
  local r = view.rows[index or view.pick]
  if key and not (r and r.entry and r.entry.key == key) then
    r = nil
    for _, row in ipairs(view.rows) do
      if row.entry and row.entry.key == key then r = row break end
    end
    r = r or before -- gone from the new results: still the one you chose
  end
  if not (r and r.entry) then return end
  local e = r.entry
  local recent = ns.db().recent
  recent[e.key] = call(time) or 0
  ns.trimRecent(recent)
  local ok, close = pcall(A.run, e, alt)
  if not ok then ns.say("error: " .. tostring(close)) close = false end
  if close then ns.close() else ns.refresh() end
end

local function build()
  frame = CreateFrame("Frame", "OmniFrame", UIParent, rawget(_G, "BackdropTemplateMixin") and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, 80)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
  end
  frame:Hide()
  -- Escape (UISpecialFrames) and close both hide the frame: stop searching.
  frame:SetScript("OnHide", function() ns.cancelSearch() end)
  local special = rawget(_G, "UISpecialFrames")
  if type(special) == "table" then table.insert(special, "OmniFrame") end

  box = CreateFrame("EditBox", "OmniSearchBox", frame, "InputBoxTemplate")
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -10)
  box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
  box:SetHeight(24)
  box:SetAutoFocus(false)
  if box.SetAltArrowKeyMode then box:SetAltArrowKeyMode(false) end
  box:SetScript("OnTextChanged", function(self)
    -- The key that opened the box can arrive as a typed space.
    if self.justOpened and self:GetText() == " " then self:SetText("") return end
    ns.refresh()
  end)
  box:SetScript("OnEnterPressed", function() ns.act(IsShiftKeyDown and IsShiftKeyDown()) end)
  box:SetScript("OnEscapePressed", function() ns.close() end)
  box:SetScript("OnArrowPressed", function(_, key)
    if key == "UP" then ns.move(-1) elseif key == "DOWN" then ns.move(1) end
  end)
  box:SetScript("OnTabPressed", function() ns.nextGroup((IsShiftKeyDown and IsShiftKeyDown()) and -1 or 1) end)

  rows = {}
  for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -38 - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -38 - (i - 1) * ROW_H)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(0.9, 0.7, 0.3, 0.25)
    row.sel:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 2, ROW_H - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.left:SetPoint("LEFT", row, "LEFT", ROW_H + 4, 0)
    row.left:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetTextColor(0.7, 0.7, 0.7)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function()
      local at = view.top + i - 1
      if view.rows[at] and view.rows[at].entry then view.pick = at paint() end
    end)
    row:SetScript("OnClick", function(_, button)
      ns.act(button == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()), view.top + i - 1)
    end)
    rows[i] = row
  end
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta) ns.scroll(-delta * 3) paint() end)
  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 8)
  footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 8)
  footer:SetJustifyH("LEFT")
end

function ns.open(text)
  if not frame then build() end
  ns.rebuild()
  local function again()
    ns.rebuild()
    if frame:IsShown() then ns.refresh() end
  end
  S.buildQuestie(function()
    again()
    S.buildNearby(again)
  end)
  S.buildNearby(again)
  frame:Show()
  box.justOpened = true
  box:SetText(text or "")
  box:SetFocus()
  call(api("C_Timer.After"), 0, function() box.justOpened = false end)
  ns.refresh()
end

function ns.close()
  ns.cancelSearch()
  if frame then frame:Hide() end
  if box then box:ClearFocus() end
  local tt = rawget(_G, "GameTooltip")
  if tt and tt.GetOwner and tt:GetOwner() == frame then tt:Hide() end
end

function Omni_Toggle()
  local ok, err = pcall(function()
    if frame and frame:IsShown() then ns.close() else ns.open() end
  end)
  if not ok then ns.say("error: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- Key binding (Bindings.xml) and /omni
---------------------------------------------------------------------------
BINDING_HEADER_OMNI = "Omni"
BINDING_NAME_OMNI_TOGGLE = "Open the search box"
ns.DEFAULT_KEY = "CTRL-SPACE"

-- Binds Ctrl+Space once, only when nothing uses it and Omni has no key.
function ns.defaultBinding()
  local db = ns.db()
  if db.boundOnce or call(GetBindingKey, "OMNI_TOGGLE") then return false end
  db.boundOnce = true
  local used = call(GetBindingAction, ns.DEFAULT_KEY)
  if used and used ~= "" then
    ns.say("Ctrl+Space is taken (" .. used .. "). Use /omni bind KEY, for example /omni bind ALT-F.")
    return false
  end
  return ns.bind(ns.DEFAULT_KEY)
end

function ns.bind(key)
  if call(rawget(_G, "InCombatLockdown")) then ns.say("key bindings change only out of combat") return false end
  key = tostring(key):upper()
  if not call(SetBinding, key, "OMNI_TOGGLE") then ns.say("could not bind " .. key) return false end
  call(SaveBindings, call(GetCurrentBindingSet) or 1)
  ns.say("open the search box with " .. key)
  return true
end

local HELP = {
  "/omni [text] - open the search box (or press your key binding)",
  "/omni bind KEY - set the key, for example /omni bind CTRL-SPACE",
  "Filters: i: items, p: places, @ people, s: spells, n: NPCs, q: quests, c: commands",
  "Up/Down move, Tab jumps to the next group, Enter acts, Shift+Enter (or right click) does the other action, Esc closes.",
}

function ns.slash(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower()
  if cmd == "help" then for _, l in ipairs(HELP) do ns.say(l) end
  elseif cmd == "bind" and rest ~= "" then ns.bind(rest)
  elseif cmd == "perf" then
    local p = ns.perf
    ns.say(string.format("last search \"%s\": %.1f ms of work over %d frame(s)", p.text, p.ms, p.frames))
  else ns.open(msg) end
end
SLASH_OMNI1 = "/omni"
SlashCmdList.OMNI = function(msg)
  local ok, err = pcall(ns.slash, msg)
  if not ok then ns.say("error: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- Events: save bank and mail contents while they are open; remember whispers.
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
ns.events = events
local bankOpen, mailOpen, bankQueued = false, false, false

local function scanBankSoon()
  if bankQueued then return end
  bankQueued = true
  call(api("C_Timer.After"), 0.5, function()
    bankQueued = false
    if bankOpen then S.scanBank() end
  end)
end

-- LootValue cannot warn about itself: the game does not load it without
-- Auctionator (its .toc "## Dependencies"). Omni says it once per login.
function ns.checkAuctionator()
  local addons = api("C_AddOns") or {}
  local name = call(addons.GetAddOnInfo or rawget(_G, "GetAddOnInfo"), "LootValue")
  local loaded = call(addons.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded"), "Auctionator")
  if name and not loaded then
    ns.say("LootValue needs the Auctionator addon, which is not on. Install it from CurseForge (or WowUp) "
      .. "and turn it on in the AddOns list.")
    return true
  end
  return false
end

local handlers = {
  PLAYER_LOGIN = function()
    ns.db()
    ns.defaultBinding()
    ns.checkAuctionator()
  end,
  BANKFRAME_OPENED = function() bankOpen = true S.scanBank() end,
  BANKFRAME_CLOSED = function() bankOpen = false end,
  BAG_UPDATE = function() if bankOpen then scanBankSoon() end end,
  PLAYERBANKSLOTS_CHANGED = function() if bankOpen then scanBankSoon() end end,
  MAIL_SHOW = function() mailOpen = true end,
  MAIL_INBOX_UPDATE = function() if mailOpen then S.scanMail() end end,
  MAIL_CLOSED = function() mailOpen = false end,
  -- Whisper events pass (text, sender, ...).
  CHAT_MSG_WHISPER = function(_, _, name) S.noteWhisper(name) end,
  CHAT_MSG_WHISPER_INFORM = function(_, _, name) S.noteWhisper(name) end,
}
ns.handlers = handlers
for ev in pairs(handlers) do events:RegisterEvent(ev) end
events:SetScript("OnEvent", function(_, ev, ...)
  local ok, err = pcall(handlers[ev], ev, ...)
  if not ok then ns.say(ev .. " error: " .. tostring(err)) end
end)
ns.addonName = addonName
