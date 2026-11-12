-- UpgradeFinder: what the score leaves out, and how long an item lasts.
-- (In Spare2.lua so it loads with /reload; rename before a release.)
local _, ns = ...
local S = ns.score
local call = ns.call

---------------------------------------------------------------------------
-- Effects the score does not count
---------------------------------------------------------------------------
-- The score is a sum of stats. An item can also have an effect that is not
-- a stat: a "Use:" or "Chance on hit:" effect (most trinkets), an "Equip:"
-- line no pattern reads, a resistance, a set bonus (it needs the other
-- pieces), and for a caster the damage of a wand. These count for nothing,
-- so the list marks the item with a star and the tooltip names the lines:
-- you judge them yourself.
local function scored(line)
  for _, p in ipairs(S.PATTERNS) do if line:match(p[2]) then return true end end
  return false
end

local WAND = { INVTYPE_RANGEDRIGHT = true, INVTYPE_WAND = true }

-- The lines of an item the score does not count. loc: its equip location;
-- w: the weights in use (a wand's damage counts as scored when they give
-- weapon damage a weight).
function S.unscored(lines, loc, w)
  local out = {}
  for i = 2, #lines do
    local line = lines[i]
    if S.isSetLine(line) then
      table.insert(out, line)
    elseif line:match("^Use:") or line:match("^Chance on hit:") or line:match("^Equip:") then
      if not line:match("^Use: Teaches") and not scored(line) then table.insert(out, line) end
    elseif line:match("^%+%d+ [%a ]+ Resistance$") then
      table.insert(out, line)
    elseif WAND[loc or ""] and ((w and w.dps) or 0) == 0 and line:match("^%(([%d%.]+) damage per second%)") then
      table.insert(out, "Wand damage " .. line)
    end
  end
  return out
end

---------------------------------------------------------------------------
-- How long an item lasts
---------------------------------------------------------------------------
-- An upgrade you buy today is a poor buy when a better item for the same
-- slot comes within a few levels. The scan already knows every item on the
-- AH, in your bags and in the dungeons with its score and level, so the
-- row tooltip names the first better one in the next LEVELS levels.
local L = {}
ns.lasts = L
L.LEVELS = 5

-- The first better item for r's slot that needs a level above yours, within
-- L.LEVELS: the lowest level, then the best score. rows: every scanned row.
function L.next(r, rows, level)
  local group = S.groupName(r.loc)
  if not group or not r.value then return nil end
  local best
  for _, o in ipairs(rows or {}) do
    local req = o.reqLevel or 0
    if o.id ~= r.id and not o.unusable and o.value and o.value > r.value + 0.05
      and req > level and req <= level + L.LEVELS and S.groupName(o.loc) == group then
      if not best or req < (best.reqLevel or 0) or (req == best.reqLevel and o.value > best.value) then best = o end
    end
  end
  return best
end

local FROM = { AH = "on the AH", dungeon = "a dungeon drop", bags = "in your bags" }

-- Tooltip lines { text, r, g, b } for a row that needs no level above yours.
function L.lines(r, rows, level)
  level = level or call(rawget(_G, "UnitLevel"), "player") or 1
  rows = rows or (ns.view and ns.view.all) or {}
  if (r.reqLevel or 0) > level or not r.value then return {} end
  local o = L.next(r, rows, level)
  if not o then
    return { { string.format("Lasts: nothing better known for this slot up to level %d", level + L.LEVELS), 0.6, 0.6, 0.6 } }
  end
  local n = o.reqLevel - level
  local where = o.drop and ("drops in " .. (o.drop.short or o.drop.name)) or FROM[o.source] or ""
  local text = string.format("Lasts %d level%s: %s is better at level %d (+%.1f, %s)", n, n == 1 and "" or "s",
    o.name, o.reqLevel, o.value - r.value, where)
  -- Orange when you would pay gold for it.
  if r.source == "AH" then return { { text, 1, 0.5, 0.3 } } end
  return { { text, 0.6, 0.6, 0.6 } }
end
