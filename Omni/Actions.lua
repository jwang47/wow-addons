-- What Enter (and Shift+Enter) does for each kind of result. Nothing here
-- casts, uses an item or sends a key: the game blocks that for addons, and
-- Omni only opens the map, the chat box, a whisper, an invite or a search.
local _, ns = ...
local A = {}
ns.actions = A
local call, api = ns.call, ns.api

local function say(msg)
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  if f then f:AddMessage("|cff69ccf0Omni:|r " .. msg) end
end
ns.say = say

local function itemLink(id)
  local _, link = call(api("C_Item.GetItemInfo"), id)
  return link or ("item:" .. id)
end
A.itemLink = itemLink

-- Puts a link into the open chat box, or opens chat with it.
local function insertLink(link)
  if call(rawget(_G, "ChatEdit_InsertLink"), link) then return true end
  return call(rawget(_G, "ChatFrame_OpenChat"), link) ~= false
end

local function auctionHouseOpen()
  for _, name in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
    local f = rawget(_G, name)
    if type(f) == "table" and f.IsShown and f:IsShown() then return true end
  end
  return false
end

-- Another map addon can take over OpenWorldMap and show nothing, so if
-- the map is still hidden after it, toggle it open and set the map.
function A.openMap(mapID)
  local f = rawget(_G, "WorldMapFrame")
  local function shown() return type(f) == "table" and f.IsShown and f:IsShown() and true or false end
  local open = api("C_Map.OpenWorldMap")
  if open then call(open, mapID) end
  if not f then return open ~= nil end
  if not shown() then
    if not call(rawget(_G, "ToggleWorldMap")) and not shown() then call(rawget(_G, "ShowUIPanel"), f) end
  end
  if f.SetMapID then call(f.SetMapID, f, mapID) end
  return true
end

-- A point on mapID, moved up to the first map (itself or a parent) that
-- takes a user pin. City and small maps can refuse one.
local function pinPoint(mapID, x, y)
  local can = api("C_Map.CanSetUserWaypointOnMap")
  local id, px, py = mapID, x, y
  for _ = 1, 4 do
    if call(can, id) then return id, px, py end
    local info = call(api("C_Map.GetMapInfo"), id)
    local parent = type(info) == "table" and info.parentMapID
    if not parent or parent == 0 then return nil end
    local left, right, top, bottom = call(api("C_Map.GetMapRectOnMap"), id, parent)
    if not (left and right and top and bottom) then return nil end
    id, px, py = parent, left + px * (right - left), top + py * (bottom - top)
  end
end
A.pinPoint = pinPoint

-- Opens the map at a Questie spawn and sets the game's own map pin there.
-- spawns: { [areaID] = { { x, y }, ... } } with x and y from 0 to 100.
function A.showSpawn(label, spawns)
  local _, loader = ns.sources.questieDB()
  local zdb = loader and select(2, pcall(loader.ImportModule, loader, "ZoneDB"))
  if type(spawns) ~= "table" or type(zdb) ~= "table" or type(zdb.GetUiMapIdByAreaId) ~= "function" then
    say(label .. ": no location in Questie")
    return false
  end
  local here = call(api("C_Map.GetBestMapForUnit"), "player")
  local pick
  for area, points in pairs(spawns) do
    local mapID = call(zdb.GetUiMapIdByAreaId, zdb, area)
    local p = type(points) == "table" and points[1]
    if mapID and p then
      local cand = { mapID = mapID, x = p[1], y = p[2] }
      if not pick or mapID == here then pick = cand end
      if mapID == here then break end
    end
  end
  if not pick then say(label .. ": no location in Questie") return false end
  return A.showPick(label, pick)
end

-- Opens the map at pick = { mapID, x, y } (x and y from 0 to 100; -1 for
-- an instance) and pins the point.
function A.showPick(label, pick)
  A.openMap(pick.mapID)
  local info = call(api("C_Map.GetMapInfo"), pick.mapID)
  local zone = info and info.name or ("map " .. pick.mapID)
  if pick.x and pick.x >= 0 then
    local point, pinned = api("UiMapPoint.CreateFromCoordinates"), false
    local id, px, py = pinPoint(pick.mapID, pick.x / 100, pick.y / 100)
    local set = api("C_Map.SetUserWaypoint")
    if point and id and type(set) == "function" then
      local ok, wasSet = pcall(set, call(point, id, px, py))
      -- Older builds return nothing; only an explicit false is a refusal.
      pinned = ok and wasSet ~= false
      -- Tracked: the pin also shows on the minimap and at the screen edge.
      if pinned then call(api("C_SuperTrack.SetSuperTrackedUserWaypoint"), true) end
    end
    say(string.format("%s: %s (%.0f, %.0f)%s", label, zone, pick.x, pick.y,
      pinned and ", map pin set" or ", no map pin here"))
  else
    say(label .. ": " .. zone)
  end
  return true
end

local function questieQuery(kind, id, key)
  local qdb = ns.sources.questieDB()
  local fn = qdb and ({ npc = qdb.QueryNPCSingle, quest = qdb.QueryQuestSingle, item = qdb.QueryItemSingle })[kind]
  return call(fn, id, key)
end
A.questieQuery = questieQuery

local function firstNpc(list)
  if type(list) ~= "table" then return nil end
  for _, id in ipairs(list) do if type(id) == "number" then return id end end
end

-- Questie's own map icon for the NPC, as its search window does. It draws
-- on the map even where the game's user pin does not show. ShowNPC adds
-- new frames each call, so Omni keeps its icons in its own type and clears
-- them first: only the last NPC you picked has one.
A.QUESTIE_TYPE = "omni"
local function questiePin(id)
  local loader = rawget(_G, "QuestieLoader")
  if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return false end
  local ok, qmap = pcall(loader.ImportModule, loader, "QuestieMap")
  if not ok or type(qmap) ~= "table" or type(qmap.ShowNPC) ~= "function" then return false end
  if type(qmap.ResetManualFrames) == "function" then pcall(qmap.ResetManualFrames, qmap, A.QUESTIE_TYPE) end
  return (pcall(qmap.ShowNPC, qmap, id, nil, nil, nil, nil, nil, A.QUESTIE_TYPE))
end
A.questiePin = questiePin

local function showNpc(id, label)
  questiePin(id)
  return A.showSpawn(label or questieQuery("npc", id, "name") or ("NPC " .. id), questieQuery("npc", id, "spawns"))
end

-- Opens the quest log at a quest. The log may have changed since the box
-- opened, so find the quest again by ID (or title).
function A.openQuestLog(e)
  local index, title = e.index, rawget(_G, "GetQuestLogTitle")
  for i = 1, call(rawget(_G, "GetNumQuestLogEntries")) or 0 do
    local t, _, _, h, _, _, _, id = call(title, i)
    if not h and ((e.questID and id == e.questID) or (not e.questID and t == e.name)) then index = i break end
  end
  local f = rawget(_G, "QuestLogFrame")
  if not f then
    call(api("C_QuestLog.SetSelectedQuest"), e.questID)
    call(rawget(_G, "ToggleQuestLog"))
    return true
  end
  call(rawget(_G, "SelectQuestLogEntry"), index)
  if not f:IsShown() then call(rawget(_G, "ShowUIPanel"), f) end
  -- Scroll so the quest is in view (the list shows a few rows).
  local bar = rawget(_G, "QuestLogListScrollFrameScrollBar")
  if bar and bar.SetValue then
    call(bar.SetValue, bar, math.max(0, index - 3) * (rawget(_G, "QUESTLOG_QUEST_HEIGHT") or 16))
  end
  call(rawget(_G, "QuestLog_SetSelection"), index)
  call(rawget(_G, "QuestLog_Update"))
  return true
end

-- Where a quest stands for you: "log" (in your quest log, even under a
-- collapsed header), "done" (turned in), or nil (not taken).
function A.questStatus(id)
  if type(id) ~= "number" then return nil end
  local on = api("C_QuestLog.IsOnQuest")
  if on then
    if call(on, id) then return "log" end
  else
    local idx = call(rawget(_G, "GetQuestLogIndexByID"), id)
    if type(idx) == "number" and idx > 0 then return "log" end
  end
  local flagged = api("C_QuestLog.IsQuestFlaggedCompleted") or rawget(_G, "IsQuestFlaggedCompleted")
  if call(flagged, id) then return "done" end
  return nil
end

-- A quest under a collapsed header is not in the list, so open every header
-- first, then find it by ID.
local function openLoggedQuest(id, name)
  call(rawget(_G, "ExpandQuestHeader"), 0)
  return A.openQuestLog({ questID = id, name = name })
end

-- Returns the hint for the footer: "Enter: ...  Shift+Enter: ...".
function A.hint(e)
  if not e then return "" end
  local k = e.kind
  if k == "item" then
    if auctionHouseOpen() and api("Auctionator.API.v1.MultiSearchExact") then return "Enter: search the AH   Shift+Enter: link" end
    if e.questie and not e.owned then return "Enter: where it drops   Shift+Enter: link" end
    return "Enter: link in chat"
  elseif k == "place" then return "Enter: open the map"
  elseif k == "person" then return "Enter: whisper   Shift+Enter: invite"
  elseif k == "spell" then return "Enter: put on the cursor   Shift+Enter: link"
  elseif k == "command" then return "Enter: run"
  elseif k == "npc" or k == "near" then return "Enter: show on the map"
  elseif k == "quest" then
    if A.questStatus(e.id) == "log" then return "Enter: open in the quest log   Shift+Enter: where it starts" end
    return "Enter: show where it starts"
  elseif k == "log" then return "Enter: open in the quest log   Shift+Enter: link"
  end
  return ""
end

-- Runs the action. alt = Shift was held. Returns true to close the box.
function A.run(e, alt)
  local k = e.kind
  if k == "item" then
    if not alt and auctionHouseOpen() then
      local search = api("Auctionator.API.v1.MultiSearchExact")
      if search then call(search, "Omni", { e.name }) return false end
    end
    if not alt and e.questie and not e.owned then
      local npc = firstNpc(questieQuery("item", e.id, "npcDrops"))
      if npc then return showNpc(npc, e.name .. " (drops from " .. (questieQuery("npc", npc, "name") or "?") .. ")") end
    end
    insertLink(itemLink(e.id))
    return true
  elseif k == "place" then
    return A.openMap(e.id)
  elseif k == "person" then
    if alt then
      local invite = api("C_PartyInfo.InviteUnit") or rawget(_G, "InviteUnit")
      call(invite, e.full)
      say("invited " .. e.name)
      return true
    end
    local tell = rawget(_G, "ChatFrame_SendTell")
    if type(tell) == "function" then call(tell, e.full)
    else call(rawget(_G, "ChatFrame_OpenChat"), "/w " .. e.full .. " ") end
    return true
  elseif k == "spell" then
    if alt then
      local link = call(api("C_Spell.GetSpellLink"), e.spellID)
      if link then insertLink(link) end
      return true
    end
    if call(rawget(_G, "InCombatLockdown")) then
      say("spells go on the cursor only out of combat")
      return false
    end
    local pick = api("C_Spell.PickupSpell")
    if pick then call(pick, e.spellID)
    else call(api("C_SpellBook.PickupSpellBookItem"), e.slot, api("Enum.SpellBookSpellBank.Player") or 0) end
    return true
  elseif k == "command" then
    call(api("SlashCmdList.MAGEMENTOR"), e.args)
    return true
  elseif k == "npc" then
    return showNpc(e.id, e.name)
  elseif k == "near" then
    questiePin(e.id)
    return A.showPick(e.name, { mapID = e.mapID, x = e.x * 100, y = e.y * 100 })
  elseif k == "log" then
    if alt then
      -- A quest link where the client has them, else the name (as the log does).
      insertLink(e.questID and call(rawget(_G, "GetQuestLink"), e.questID) or e.name)
      return true
    end
    return A.openQuestLog(e)
  elseif k == "quest" then
    if not alt and A.questStatus(e.id) == "log" then return openLoggedQuest(e.id, e.name) end
    local by = questieQuery("quest", e.id, "startedBy")
    local npc = type(by) == "table" and firstNpc(by[1])
    if npc then return showNpc(npc, e.name .. " (from " .. (questieQuery("npc", npc, "name") or "?") .. ")") end
    say(e.name .. ": Questie has no start NPC (it may start from an object or an item)")
    return false
  end
  return false
end

-- The right-hand text of a row, worked out only for rows on screen.
function A.detail(e)
  local k = e.kind
  if k == "item" then
    local parts = {}
    for _, w in ipairs({ "bags", "bank", "mail" }) do
      if e.where and e.where[w] then table.insert(parts, w .. " " .. e.where[w]) end
    end
    local price = call(api("Auctionator.API.v1.GetAuctionPriceByItemID"), "Omni", e.id)
    if type(price) == "number" and price > 0 then table.insert(parts, "AH " .. ns.money(price)) end
    if #parts == 0 and e.questie then table.insert(parts, "quest item") end
    return table.concat(parts, "  ")
  elseif k == "place" then
    local d = e.detail or ""
    if e.levels then d = (e.fits and "|cff40ff40" or "|cff9d9d9d") .. e.levels .. "|r  " .. d end
    return d
  elseif k == "npc" then
    local sub = questieQuery("npc", e.id, "subName")
    return type(sub) == "string" and sub or ""
  elseif k == "near" then
    local d = e.sub or ""
    local mapID, px, py = ns.sources.playerPos()
    local yd = mapID == e.mapID and px and py and ns.sources.yards(mapID, px, py, e.x, e.y)
    if yd then d = string.format("|cffffd100%d yd|r", math.floor(yd + 0.5)) .. (d ~= "" and ("  " .. d) or "") end
    return d
  elseif k == "log" then
    local d = (e.level and ("level " .. e.level) or "") .. (e.zone and ("  " .. e.zone) or "")
    if e.done then d = "|cff40ff40done|r  " .. d end
    return d
  elseif k == "quest" then
    local lvl = questieQuery("quest", e.id, "questLevel")
    local d = type(lvl) == "number" and ("level " .. lvl) or ""
    local status = A.questStatus(e.id)
    if status == "log" then return "|cffffd100in your log|r  " .. d end
    if status == "done" then return "|cff9d9d9ddone|r  " .. d end
    local req = questieQuery("quest", e.id, "requiredLevel")
    local me = call(rawget(_G, "UnitLevel"), "player")
    if type(req) == "number" and type(me) == "number" and req > me then
      return "|cffff6060needs level " .. req .. "|r  " .. d
    end
    return "|cff40ff40not taken|r  " .. d
  end
  return e.detail or ""
end

-- Fills GameTooltip for the selected row.
function A.tooltip(tt, e)
  local k = e.kind
  if k == "item" and tt.SetHyperlink then
    tt:SetHyperlink("item:" .. e.id)
  elseif k == "spell" and tt.SetSpellByID then
    tt:SetSpellByID(e.spellID)
  else
    tt:SetText(e.name)
    local d = A.detail(e)
    if d ~= "" then tt:AddLine(d, 1, 1, 1) end
    if e.note then tt:AddLine("MageMentor: " .. e.note, 0.41, 0.8, 0.94, true) end
  end
  tt:AddLine(A.hint(e), 0.6, 0.6, 0.6)
  tt:Show()
end
