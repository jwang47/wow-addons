-- GroupUp: a small panel that helps you decide whether to group up. It
-- shows which quests in your log a group speeds up, your measured XP per
-- hour solo and grouped at about your level, and how kill XP is split in a
-- group. When someone invites you, it puts a two-line summary in chat.
-- /gu for the commands.
local addonName, ns = ...
GroupUp = ns                        -- global, for /dump
ns.VERSION = "0.1.0"
local M = ns.logic
local call, plain = M.call, M.plain

local defaults = {
  shown = false,
  onInvite = true,       -- chat summary when someone invites you
  point = nil,           -- saved position { point, x, y }
  chars = {},            -- [name-realm] = { levels = { [level][size] = bucket } }
}

local function say(msg)
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  if f then f:AddMessage("|cff9cd0ffGroupUp|r: " .. tostring(msg)) end
end
ns.say = say

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
ns.st = {}               -- tracker: last, size, level, xp, max

local function now() return plain(call(rawget(_G, "GetTime"))) or 0 end
local function level() return plain(call(rawget(_G, "UnitLevel"), "player")) or 1 end

function ns.groupSize()
  local n = plain(call(rawget(_G, "GetNumGroupMembers"))) or 0
  return M.clampSize(n)
end

-- Unit ids of the other members (party only; in a raid, your own party is
-- unknown here, so the first four raid members are not guessed).
function ns.units()
  local out = {}
  if call(rawget(_G, "IsInRaid")) then return out end
  for i = 1, 4 do
    if call(rawget(_G, "UnitExists"), "party" .. i) then table.insert(out, "party" .. i) end
  end
  return out
end

function ns.memberLevels()
  local me = level()
  local out = { me }
  for _, u in ipairs(ns.units()) do
    table.insert(out, plain(call(rawget(_G, "UnitLevel"), u)) or me)
  end
  return out
end

local function charKey()
  local name = call(rawget(_G, "UnitName"), "player")
  local realm = call(rawget(_G, "GetRealmName"))
  return tostring(name or "?") .. "-" .. tostring(realm or "?")
end

function ns.levels()
  local db = ns.db
  local key = charKey()
  db.chars[key] = db.chars[key] or { levels = {} }
  return db.chars[key].levels
end

function ns.tick()
  if not ns.db then return end
  M.tick(ns.st, ns.levels(), now(), ns.groupSize(), level())
end

local function current()
  ns.tick()
  return M.bucket(ns.levels(), ns.st.level or level(), ns.st.size or 1)
end

function ns.onXP()
  ns.tick()
  local d = M.xpDelta(ns.st, plain(call(rawget(_G, "UnitXP"), "player")), plain(call(rawget(_G, "UnitXPMax"), "player")))
  if d > 0 then
    local b = M.bucket(ns.levels(), ns.st.level, ns.st.size)
    b.xp = b.xp + d
  end
end

function ns.onKill(msg)
  local xp, rested = M.parseKill(msg)
  if not xp then return end
  local b = current()
  b.kills = b.kills + 1
  b.killxp = b.killxp + xp
  b.rested = b.rested + (rested or 0)
end

function ns.onQuest(xp)
  xp = plain(xp)
  if not xp or xp <= 0 then return end
  local b = current()
  b.quest = b.quest + xp
end

-- The measured totals at about your level: solo, all group sizes, and each size.
function ns.rates()
  ns.tick()
  local lv, levels = level(), ns.levels()
  local out = { solo = M.sum(levels, lv, { 1 }), grouped = M.sum(levels, lv, { 2, 3, 4, 5 }), size = {} }
  for s = 2, M.MAX_SIZE do out.size[s] = M.sum(levels, lv, { s }) end
  return out
end

function ns.summary()
  local r = ns.rates()
  return M.summary(M.quests(ns.units()), r.solo, r.grouped)
end

---------------------------------------------------------------------------
-- Panel: the Glance "floating minimal" style, see-through, small text.
---------------------------------------------------------------------------
local W, LINE, PAD = 380, 14, 6
local panel
local lines = {}
local SIZE_NAMES = { "Solo", "Duo", "Trio", "Group of 4", "Group of 5" }
local VERDICT = {
  need = { "needs a group", 1, 0.55, 0.2 },
  faster = { "kills count for all", 0.35, 0.8, 0.35 },
  maybe = { "drops or clicks", 0.85, 0.85, 0.5 },
  same = { "talk or explore", 0.6, 0.6, 0.6 },
  done = { "ready to turn in", 0.6, 0.6, 0.6 },
}

local function line(i)
  local l = lines[i]
  if not l then
    l = {}
    l.left = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.left:SetJustifyH("LEFT")
    l.left:SetWordWrap(false)
    l.right = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.right:SetJustifyH("RIGHT")
    l.left:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * LINE)
    l.right:SetPoint("TOPRIGHT", -PAD, -PAD - (i - 1) * LINE)
    l.left:SetPoint("RIGHT", l.right, "LEFT", -6, 0)
    lines[i] = l
  end
  return l
end

-- The panel text as rows { left, right, r, g, b }: built apart from the
-- frames so the tests can read it.
function ns.rows()
  local out = {}
  local function add(left, right, r, g, b) table.insert(out, { left = left, right = right or "", r = r or 1, g = g or 1, b = b or 1 }) end
  local lv = level()
  local rt = ns.rates()
  local quests = M.quests(ns.units())
  local c = M.count(quests)
  local soloRate, groupRate = M.perHour(rt.solo), M.perHour(rt.grouped)
  local way, why = M.lean(c, soloRate, groupRate)
  local head = way == "group" and "Leans group" or way == "solo" and "Leans solo" or "About even"
  add(head, #why > 0 and table.concat(why, ", ") or "", 1, 0.85, 0.25)

  add(" ")
  add("XP per hour, levels " .. math.max(1, lv - M.LEVELS_BACK) .. "-" .. lv, "no rested XP", 0.6, 0.8, 1)
  local function rateRow(label, t)
    local r = M.perHour(t)
    local bits = { M.mins(t.secs) }
    local pk, kpm = M.perKill(t), M.killsPerMin(t)
    if pk then table.insert(bits, M.short(pk) .. " a kill") end
    if kpm then table.insert(bits, string.format("%.1f kills/min", kpm)) end
    local qs = M.questShare(t)
    if qs and qs > 0 then table.insert(bits, M.pct(qs) .. " from quests") end
    add("  " .. label .. "  " .. (r and (M.short(r) .. "/h") or "not enough yet"), table.concat(bits, ", "), r and 1 or 0.6, r and 1 or 0.6, r and 1 or 0.6)
  end
  rateRow("Solo", rt.solo)
  local any = false
  for s = 2, M.MAX_SIZE do
    if rt.size[s].secs > 0 then rateRow(SIZE_NAMES[s], rt.size[s]) any = true end
  end
  if not any then add("  Grouped: no data yet. Play in a group to measure it.", "", 0.6, 0.6, 0.6) end

  add(" ")
  add("Kill XP in a group", "", 0.6, 0.8, 1)
  local members = ns.memberLevels()
  if #members > 1 then
    add("  This group: " .. M.splitLine(lv, members))
    local greys, top = M.highMemberGreys(lv, members)
    if greys then add("  Level " .. top .. " in the group: mobs at your level give no XP", "", 1, 0.4, 0.3) end
  else
    local parts = {}
    for n = 2, M.MAX_SIZE do
      local same = {}
      for i = 1, n do same[i] = lv end
      local s = M.share(lv, same)
      table.insert(parts, n .. ": " .. M.pct(s))
    end
    add("  Your share per kill (same levels)", table.concat(parts, "   "))
    add("  Break even only if a group kills that much faster.", "", 0.6, 0.6, 0.6)
  end
  add("  Quest XP is never split: each member gets all of it.", "", 0.6, 0.6, 0.6)

  add(" ")
  add("Your quests", string.format("%d need, %d faster, %d drops", c.need, c.faster, c.maybe), 0.6, 0.8, 1)
  local shown = 0
  for _, q in ipairs(quests) do
    if shown >= 12 then break end
    if q.verdict ~= "done" then
      shown = shown + 1
      local v = VERDICT[q.verdict]
      local label = (q.tag and ("[" .. q.tag .. "] ") or "") .. q.name
      local right = v[1]
      if #q.shared > 0 then right = right .. "  +" .. table.concat(q.shared, ", ") end
      add("  " .. label, right, v[2], v[3], v[4])
    end
  end
  if shown == 0 then add("  No open quests.", "", 0.6, 0.6, 0.6) end
  return out
end

function ns.refresh()
  if not (panel and panel:IsShown()) then return end
  local rows = ns.rows()
  for i, r in ipairs(rows) do
    local l = line(i)
    l.left:SetText(r.left)
    l.left:SetTextColor(r.r, r.g, r.b)
    l.right:SetText(r.right)
    l.right:SetTextColor(0.75, 0.75, 0.75)
    l.left:Show() l.right:Show()
  end
  for i = #rows + 1, #lines do lines[i].left:Hide() lines[i].right:Hide() end
  panel:SetHeight(PAD * 2 + #rows * LINE)
end

local function build()
  if panel then return panel end
  panel = CreateFrame("Frame", "GroupUpFrame", UIParent)
  panel:SetWidth(W)
  panel:SetHeight(100)
  panel:SetFrameStrata("MEDIUM")
  panel:SetClampedToScreen(true)
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)
  local p = ns.db.point
  if p then panel:SetPoint(p[1], UIParent, p[1], p[2], p[3])
  else panel:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(f) f:StartMoving() end)
  panel:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint()
    ns.db.point = { point, x, y }
  end)
  panel:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then ns.show(false) end end)
  panel:Hide()
  return panel
end

function ns.show(on)
  build()
  ns.db.shown = on
  if on then panel:Show() ns.refresh() else panel:Hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
ns.events = events
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN",
  "QUEST_TURNED_IN", "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT", "PARTY_INVITE_REQUEST",
  "QUEST_LOG_UPDATE" }) do
  events:RegisterEvent(e)
end

local pending = false
local function soon()
  if pending then return end
  pending = true
  local after = M.api("C_Timer.After")
  if after then after(0.5, function() pending = false ns.refresh() end)
  else pending = false ns.refresh() end
end

events:SetScript("OnEvent", function(_, event, a, b)
  if event == "ADDON_LOADED" then
    if a ~= addonName then return end
    GroupUpDB = type(GroupUpDB) == "table" and GroupUpDB or {}
    for k, v in pairs(defaults) do if GroupUpDB[k] == nil then GroupUpDB[k] = (type(v) == "table") and {} or v end end
    ns.db = GroupUpDB
    return
  end
  if not ns.db then return end
  if event == "PLAYER_ENTERING_WORLD" then
    -- At login the stretch starts here; after a loading screen it goes on.
    ns.tick()
    if not ns.st.xp then
      M.xpDelta(ns.st, plain(call(rawget(_G, "UnitXP"), "player")), plain(call(rawget(_G, "UnitXPMax"), "player")))
    end
    if ns.db.shown then ns.show(true) end
  elseif event == "PLAYER_XP_UPDATE" then
    ns.onXP() soon()
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    ns.onKill(a)
  elseif event == "QUEST_TURNED_IN" then
    ns.onQuest(b) soon()
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_LOGOUT" then
    ns.tick()
    if event == "PLAYER_LEVEL_UP" then ns.st.level = plain(a) or ns.st.level end
    soon()
  elseif event == "PARTY_INVITE_REQUEST" then
    if ns.db.onInvite then
      local q, x = ns.summary()
      say((type(a) == "string" and (a .. " invites you. ") or "") .. q)
      say(x .. "  /gu for details")
    end
  elseif event == "QUEST_LOG_UPDATE" then
    soon()
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_GROUPUP1, SLASH_GROUPUP2 = "/gu", "/groupup"
SlashCmdList.GROUPUP = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not ns.db then return end
  if msg == "" or msg == "show" then
    ns.show(not (panel and panel:IsShown()))
  elseif msg == "sum" or msg == "summary" then
    local q, x = ns.summary()
    say(q) say(x)
  elseif msg == "invite on" or msg == "invite off" then
    ns.db.onInvite = msg == "invite on"
    say("summary on invite " .. (ns.db.onInvite and "on" or "off"))
  elseif msg == "reset" then
    ns.db.point = nil
    if panel then panel:ClearAllPoints() panel:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
    say("panel moved back")
  elseif msg == "clear" then
    ns.db.chars[charKey()] = nil
    ns.st.last = nil
    ns.tick()
    say("XP data for this character cleared")
    ns.refresh()
  else
    say("/gu: show or hide the panel   /gu sum: summary in chat   /gu invite on|off   /gu reset   /gu clear (forget this character's XP data)")
  end
end
