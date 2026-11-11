-- Workbench logic: sort and price the recipes UpgradeFinder has saved. No
-- frames here, so the offline tests can load this file alone.
--
-- The recipes come from UpgradeFinderAPI.known(): each is { prof, name,
-- product, source ("known" or "trainer"), kind (the skill-up colour:
-- optimal, medium, easy, trivial), req, price, rank, max, cost, unknown,
-- sale, how, profit }. UpgradeFinder reads them when you open a profession
-- window or a trainer, so they are as old as your last visit.
local addonName, ns = ...
local L = {}
ns.logic = L

-- The chance that one craft gives a skill point, by colour. Orange always
-- does. The game does not give the yellow and green numbers (they fall as
-- your skill rises), so these are middle values: a guide, not a promise.
L.CHANCE = { optimal = 1, medium = 0.75, easy = 0.25, trivial = 0 }
L.COLOUR = { optimal = { 1, 0.5, 0.25 }, medium = { 1, 1, 0 }, easy = { 0.25, 0.75, 0.25 },
  trivial = { 0.5, 0.5, 0.5 } }

function L.money(copper)
  if not copper then return "?" end
  local neg = copper < 0
  copper = math.floor(math.abs(copper) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local text
  if g > 0 then text = s > 0 and string.format("%dg%ds", g, s) or (g .. "g")
  elseif s > 0 then text = (copper >= 1000 or c == 0) and (s .. "s") or string.format("%ds%dc", s, c)
  else text = c .. "c" end
  return (neg and "-" or "") .. text
end

-- The professions in the list: { { name, rank, max } }, by name.
function L.professions(known)
  local seen, out = {}, {}
  for _, r in ipairs(known or {}) do
    if r.prof and not seen[r.prof] then
      seen[r.prof] = { name = r.prof, rank = r.rank, max = r.max }
      table.insert(out, seen[r.prof])
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- What one skill point costs with this recipe, or nil when it gives none
-- or has no price. A craft costs its reagents less what the made item
-- sells for; a recipe that pays for itself costs nothing a point (the
-- value is then the profit of one craft, below zero).
function L.perPoint(r)
  local chance = L.CHANCE[r.kind or ""]
  if r.source == "trainer" then chance = chance or 1 end
  if not chance or chance <= 0 then return nil end
  if not r.cost or (r.cost == 0 and r.unknown) then return nil end
  local net = r.cost - (r.sale or 0)
  if net <= 0 then return net, chance end
  return net / chance, chance
end

-- Whether you can learn a trainer recipe now.
function L.canLearn(r)
  return r.source == "trainer" and (r.req == nil or (r.rank ~= nil and r.req <= r.rank))
end

-- The rows for the window. opts = { prof (name, or nil for all), view
-- ("profit" or "skill"), trainer (also the recipes you do not know) }.
--   profit: best profit first; recipes with no price for the made item last.
--   skill:  cheapest skill point first; grey recipes and trainer recipes
--           above your skill are left out.
function L.rows(known, opts)
  opts = opts or {}
  local out = {}
  for _, r in ipairs(known or {}) do
    local keep = (not opts.prof or r.prof == opts.prof) and (r.source == "known" or opts.trainer)
    if keep and opts.view == "skill" then
      local point, chance = L.perPoint(r)
      keep = point ~= nil and (r.source == "known" or L.canLearn(r))
      if keep then
        local row = {}
        for k, v in pairs(r) do row[k] = v end
        row.point, row.chance = point, chance
        table.insert(out, row)
      end
    elseif keep then
      table.insert(out, r)
    end
  end
  if opts.view == "skill" then
    table.sort(out, function(a, b)
      if a.point ~= b.point then return a.point < b.point end
      return a.name < b.name
    end)
  else
    table.sort(out, function(a, b)
      if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
      if a.profit and a.profit ~= b.profit then return a.profit > b.profit end
      return a.name < b.name
    end)
  end
  return out
end

-- The line under the buttons: "Tailoring 142/150: 31 recipes, 4 make a
-- profit, best +12s (Small Silk Pack)" or the cheapest skill point.
function L.summary(rows, opts, profs)
  opts = opts or {}
  local head = "All professions"
  for _, p in ipairs(profs or {}) do
    if p.name == opts.prof then
      head = p.name .. (p.rank and (" " .. p.rank .. (p.max and ("/" .. p.max) or "")) or "")
    end
  end
  if #rows == 0 then
    return head .. ": " .. (opts.view == "skill" and "no recipe gives a skill point" or "no recipes")
  end
  if opts.view == "skill" then
    local r = rows[1]
    return string.format("%s: cheapest point %s (%s)", head, r.point <= 0 and "free" or ("about " .. L.money(r.point)), r.name)
  end
  local wins = 0
  for _, r in ipairs(rows) do if r.profit and r.profit > 0 then wins = wins + 1 end end
  local best = rows[1].profit and rows[1].profit > 0 and rows[1] or nil
  return string.format("%s: %d recipe%s, %d make a profit%s", head, #rows, #rows == 1 and "" or "s", wins,
    best and (", best +" .. L.money(best.profit) .. " (" .. best.name .. ")") or "")
end

-- The texts of one row: name, cost, sale, last column, and the colour key.
function L.cells(r, view)
  local cost = (r.cost and (r.cost > 0 or not r.unknown)) and (L.money(r.cost) .. (r.unknown and "+?" or "")) or "?"
  local sale = r.sale and ((r.how == "vendor" and "" or "~") .. L.money(r.sale)) or "-"
  local last, good
  if view == "skill" then
    if r.point <= 0 then last, good = "free", true
    else last = L.money(r.point) .. (r.chance < 1 and "*" or "") end
  elseif r.profit then
    last, good = (r.profit >= 0 and "+" or "") .. L.money(r.profit), r.profit >= 0
  else
    last = "-"
  end
  local name = r.name
  if r.source == "trainer" then
    name = name .. (L.canLearn(r) and " (train" or (" (at " .. tostring(r.req)))
      .. (r.price and r.price > 0 and (", " .. L.money(r.price)) or "") .. ")"
  end
  return name, cost, sale, last, good
end
