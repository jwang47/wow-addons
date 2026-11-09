-- Glance keyboard map: which key holds which action slot. No frames here,
-- so the offline tests can check it.
--
-- At the first login (and on /glance import) Glance reads each key's
-- normal binding. A key that fires an action button keeps that button's
-- slot, so your spells show up on the keys they are already on. A free key
-- gets an empty slot that you can drop a spell on. Movement keys and keys
-- bound to other commands (Tab: target, and so on) stay as they are.
local addonName, ns = ...
local K = {}
ns.keys = K

-- The left hand of a keyboard. x is the key's left edge in key widths,
-- as on a real keyboard (Tab is 1.5 wide, Caps Lock 1.75, Shift 2.25).
K.ROWS = {
  { x = 1,    keys = { "1", "2", "3", "4", "5", "6" } },
  { x = 1.5,  keys = { "Q", "W", "E", "R", "T" }, lead = "TAB" },
  { x = 1.75, keys = { "A", "S", "D", "F", "G" } },
  -- C, V and B stay with the game (character pane, nameplates, bags).
  { x = 2.25, keys = { "Z", "X" } },
}
K.MODS = { "", "SHIFT-" }   -- layers: plain and Shift

K.MOVE = {
  MOVEFORWARD = "up", MOVEBACKWARD = "down", STRAFELEFT = "left",
  STRAFERIGHT = "right", TURNLEFT = "left", TURNRIGHT = "right",
  JUMP = "jump", TOGGLEAUTORUN = "run",
}

-- First slot of each multi-action bar (MULTIACTIONBARnBUTTONm = first + m - 1).
local MULTI = { [1] = 61, [2] = 49, [3] = 25, [4] = 37, [5] = 145, [6] = 157, [7] = 169 }

-- The action slot a binding command fires, or nil.
function K.slotOf(cmd)
  if not cmd or cmd == "" then return nil end
  local n = cmd:match("^ACTIONBUTTON(%d+)$")
  if n then return tonumber(n) end
  local bar, b = cmd:match("^MULTIACTIONBAR(%d+)BUTTON(%d+)$")
  if bar and MULTI[tonumber(bar)] then return MULTI[tonumber(bar)] + tonumber(b) - 1 end
  -- Bartender4: button N is action slot N.
  n = cmd:match("^CLICK BT4Button(%d+):")
  if n then return tonumber(n) end
  return nil
end

-- What a binding command is: "slot", n | "move", dir | "command", cmd | "free".
function K.classify(cmd)
  if not cmd or cmd == "" then return "free" end
  local slot = K.slotOf(cmd)
  if slot then return "slot", slot end
  if K.MOVE[cmd] then return "move", K.MOVE[cmd] end
  -- Our own buttons (from an earlier session) count as free.
  if cmd:match("^CLICK GlanceKey") then return "free" end
  return "command", cmd
end

-- Kept keys stay with their command: /glance take never moves them, and
-- their Shift layer stays free too. The bag keys (OPENALLBAGS,
-- TOGGLEBACKPACK, TOGGLEBAG1 ...) and the character pane (C).
local KEEP = { TOGGLECHARACTER0 = true }
function K.isKept(cmd)
  if type(cmd) ~= "string" or cmd:match("^CLICK ") then return false end
  return KEEP[cmd] or cmd:find("BAG") ~= nil
end

-- Every key the bar shows, in row order.
function K.allKeys()
  local out = {}
  for _, row in ipairs(K.ROWS) do
    if row.lead then table.insert(out, row.lead) end
    for _, key in ipairs(row.keys) do table.insert(out, key) end
  end
  return out
end

-- Slots we may hand to a free key: unused by any binding, empty, and not
-- on a visible Blizzard page. Highest first: 73-120 are the class stance
-- pages, which a mage never sees.
local function freeSlots(used, hasAction)
  local list = {}
  for s = 120, 13, -1 do
    if not used[s] and not hasAction(s) then table.insert(list, s) end
  end
  return list
end

-- Build the map. getBinding(key) gives the key's normal binding command,
-- hasAction(slot) whether a slot holds something, allBindings() every
-- (key, command) pair the game knows (to find slots in use elsewhere).
-- take: keys the player gave to Glance with /glance take. prev: the last
-- map, so a free key keeps the slot (and the spell) it had.
-- Returns map[modKey] = { kind = "slot"|"move"|"command", slot, cmd, dir }.
function K.build(getBinding, hasAction, allBindings, take, prev)
  take, prev = take or {}, prev or {}
  local used = {}
  for _, cmd in ipairs(allBindings()) do
    local s = K.slotOf(cmd)
    if s then used[s] = true end
  end
  local map, wantFree = {}, {}
  for _, key in ipairs(K.allKeys()) do
    local plainKind
    local bagKey = K.isKept(getBinding(key))
    for _, mod in ipairs(K.MODS) do
      local mk = mod .. key
      local kind, v = K.classify(getBinding(mk))
      if take[mk] and kind ~= "slot" and not bagKey then kind = "free" end
      if bagKey and mod ~= "" and kind ~= "slot" then kind = "skip" end
      if mod == "" then plainKind = kind end
      -- A free Shift layer only on a key that is a spell key itself, so
      -- Shift+W still walks and Shift+Tab still does what Tab does.
      if mod ~= "" and kind == "free" and plainKind ~= "slot" and plainKind ~= "free"
          and not take[mk] then
        kind = "skip"
      end
      if kind == "skip" then
        -- leave this key alone
      elseif kind == "slot" then
        map[mk] = { kind = "slot", slot = v }
        used[v] = true
      elseif kind == "move" then
        map[mk] = { kind = "move", dir = v }
      elseif kind == "command" then
        map[mk] = { kind = "command", cmd = v }
      else
        table.insert(wantFree, mk)
      end
    end
  end
  local rest = {}
  for _, mk in ipairs(wantFree) do
    local old = prev[mk]
    if old and old.kind == "slot" and old.fresh and not used[old.slot] then
      map[mk] = { kind = "slot", slot = old.slot, fresh = true }
      used[old.slot] = true
    else
      table.insert(rest, mk)
    end
  end
  local pool = freeSlots(used, hasAction)
  for _, mk in ipairs(rest) do
    local s = table.remove(pool, 1)
    if s then map[mk] = { kind = "slot", slot = s, fresh = true } end
  end
  K.markDuplicates(map, getBinding)
  return map
end

-- The key a stock binding puts on ACTIONBUTTONn: 1-9, 0, -, =.
local STOCK = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
  ["7"] = 7, ["8"] = 8, ["9"] = 9, ["0"] = 10, ["-"] = 11, ["="] = 12 }

-- When two plain keys fire the same slot (you bound Q to action button 5
-- and 5 still has its stock binding), the spell shows once: on the key
-- you chose. The stock key gets dupOf = that key and is drawn dim.
function K.markDuplicates(map, getBinding)
  local byslot = {}
  for _, key in ipairs(K.allKeys()) do
    local e = map[key]
    if e and e.kind == "slot" then
      byslot[e.slot] = byslot[e.slot] or {}
      table.insert(byslot[e.slot], key)
    end
  end
  for slot, keys in pairs(byslot) do
    if #keys > 1 then
      local keep
      for _, key in ipairs(keys) do
        if not (STOCK[key] == slot and getBinding(key) == "ACTIONBUTTON" .. slot) then
          keep = keep or key
        end
      end
      keep = keep or keys[1]
      for _, key in ipairs(keys) do
        if key ~= keep then map[key].dupOf = keep end
      end
    end
  end
end

-- A short label for a command key ("Target" for TARGETNEARESTENEMY).
function K.label(cmd)
  local name = _G["BINDING_NAME_" .. cmd]
  if type(name) == "string" and name ~= "" then
    return (name:gsub("^Target Nearest Enemy$", "Target"))
  end
  return cmd:sub(1, 6)
end
