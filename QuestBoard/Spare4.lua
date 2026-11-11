-- QuestBoard red quests (in a spare file so it loads with /reload; rename it
-- RedQuests.lua before a release, AGENTS.md).
--
-- A red quest (5 or more levels over you) gets 0 XP per minute (D.finish):
-- you cannot do it without a carry. This file says which red quests in your
-- log are safe to drop, and drops them one by one, each after you click
-- Abandon on the game's own confirm box. It never drops a quest by itself.
local _, ns = ...
local D = ns.data
local call = D.call

-- Safe to drop: an NPC or an object gives it (so you can take it again from
-- the same giver) and you have no progress on it. Returns ok, why-not.
function D.safeToAbandon(e)
  if not (e and e.red and e.kind == "log" and not e.done) then return false, "not a red quest in your log" end
  if (e.frac or 0) > 0 then return false, "you have progress on it" end
  local qdb = D.module("QuestieDB")
  local quest = qdb and call(qdb.GetQuest, e.id)
  local starts = type(quest) == "table" and quest.Starts or nil
  if not starts then return false, "Questie does not know who gives it" end
  if not (starts.NPC or starts.GameObject) then
    return false, starts.Item and "it starts from an item, which you may not get again" or "Questie does not know who gives it"
  end
  return true
end

-- The red quests in your log: safe ones and the rest (each with why).
function ns.redQuests(st)
  local safe, keep, seen = {}, {}, {}
  for _, kind in ipairs({ "active", "nearby", "log" }) do
    for _, e in ipairs(st and st[kind] or {}) do
      if e.red and e.kind == "log" and not seen[e.id] then
        seen[e.id] = true
        local ok, why = D.safeToAbandon(e)
        if ok then table.insert(safe, e) else e.keepWhy = why table.insert(keep, e) end
      end
    end
  end
  return safe, keep
end

-- One line for the tooltip of a red quest.
function ns.redNote(e)
  if not e.red then return nil end
  local ok, why = D.safeToAbandon(e)
  if ok then return "Red: 0 XP per minute. Safe to drop, you can take it again (/qb abandon)" end
  return "Red: 0 XP per minute. Keep it: " .. (why or "")
end

-- The log index of a quest by its id (the index moves when the log changes).
local function logIndex(id)
  local f = rawget(_G, "GetQuestLogIndexByID") or (rawget(_G, "C_QuestLog") and C_QuestLog.GetLogIndexForQuestID)
  local i = f and call(f, id)
  return type(i) == "number" and i > 0 and i or nil
end

-- Drops one quest, the way the game's own Abandon button does.
function ns.abandon(e)
  local q = rawget(_G, "C_QuestLog")
  if q and q.SetSelectedQuest and q.SetAbandonQuest and q.AbandonQuest then
    call(q.SetSelectedQuest, e.id)
    call(q.SetAbandonQuest)
    call(q.AbandonQuest)
    return true
  end
  local i = logIndex(e.id) or e.index
  if not (i and rawget(_G, "SelectQuestLogEntry") and rawget(_G, "SetAbandonQuest") and rawget(_G, "AbandonQuest")) then return false end
  call(SelectQuestLogEntry, i)
  call(SetAbandonQuest)
  call(AbandonQuest)
  return true
end

-- /qb red: list them.
function ns.listRed()
  local safe, keep = ns.redQuests(ns.state())
  if #safe + #keep == 0 then return ns.say("no red quests in your log") end
  local names = {}
  for _, e in ipairs(safe) do table.insert(names, e.name .. " (" .. e.level .. ")") end
  if #safe > 0 then ns.say("safe to drop: " .. table.concat(names, ", ") .. ". /qb abandon asks for each one") end
  for _, e in ipairs(keep) do ns.say("keep " .. e.name .. " (" .. e.level .. "): " .. (e.keepWhy or "")) end
end

-- /qb abandon: the game's confirm box for each safe red quest, one by one.
-- Abandon drops it and asks for the next one; Keep skips to the next one.
local queue = {}
function ns.abandonNext()
  local e = table.remove(queue, 1)
  if not e then return end
  local show = rawget(_G, "StaticPopup_Show")
  if not show then return end
  call(show, "QUESTBOARD_ABANDON", e.name, e.level, e)
end

function ns.abandonRed()
  local safe = ns.redQuests(ns.state())
  if #safe == 0 then return ns.say("no red quest is safe to drop (/qb red says why)") end
  local dialogs = rawget(_G, "StaticPopupDialogs")
  if dialogs and not dialogs.QUESTBOARD_ABANDON then
    dialogs.QUESTBOARD_ABANDON = {
      text = "Abandon %s (level %s, red)?\nYou can take it again from its giver.",
      button1 = "Abandon", button2 = "Keep",
      OnAccept = function(_, e)
        if e and ns.abandon(e) then ns.say("dropped " .. e.name) end
        ns.abandonNext()
      end,
      OnCancel = function(_, _, reason) if reason == "clicked" then ns.abandonNext() end end,
      timeout = 0, whileDead = true, hideOnEscape = true,
    }
  end
  queue = {}
  for _, e in ipairs(safe) do table.insert(queue, e) end
  ns.abandonNext()
end
