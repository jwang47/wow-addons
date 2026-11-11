-- CPU tracker: which addon takes the frame time, and when. The game's own
-- addon profiler (C_AddOnProfiler, the "AddOn Usage" line in the AddOn
-- list) counts, for each addon, the frames where it ran longer than 5, 10,
-- 50 ... ms. It shows only totals since the last /reload. This feature
-- reads those counters once a second and keeps a history in NicetiesDB:
-- each slow frame (a spike) with the time, the zone and what was open, and
-- a per-minute record of the busiest addons. /cpu shows it.
-- (In Spare2.lua so that it loads with /reload; rename it in a release.)
local _, ns = ...

local cpu = {}
ns.cpu = cpu

cpu.TICK = 1            -- seconds between reads
cpu.SPIKE_MS = 50       -- a frame where one addon ran this long is a spike
cpu.KEEP_SPIKES = 300
cpu.KEEP_MINUTES = 24 * 60
cpu.LOADING_SECS = 15   -- spikes this soon after a loading screen are "loading"

-- Enum.AddOnProfilerMetric; the numbers are the fallback when the client
-- has no Enum entry.
local METRIC = {
  SessionAverageTime = 0, RecentAverageTime = 1, LastTime = 3, PeakTime = 4,
  CountTimeOver5Ms = 6, CountTimeOver50Ms = 8, CountTimeOver100Ms = 9, CountTimeOver500Ms = 10,
}
local function metric(name)
  local e = Enum and Enum.AddOnProfilerMetric
  return (e and e[name]) or METRIC[name]
end

-- Windows worth naming when a spike happens.
cpu.PANELS = {
  { "TradeSkillFrame", "profession" }, { "CraftFrame", "craft" },
  { "AuctionFrame", "auction house" }, { "AuctionHouseFrame", "auction house" },
  { "MerchantFrame", "vendor" }, { "MailFrame", "mail" }, { "BankFrame", "bank" },
  { "QuestLogFrame", "quest log" }, { "WorldMapFrame", "map" },
  { "CharacterFrame", "character" }, { "LootFrame", "loot" },
  { "UpgradeFinderFrame", "UpgradeFinder" }, { "BazaarFrame", "Bazaar" },
}

local function now() return time and time() or 0 end
local function clock() return GetTime and GetTime() or now() end

function cpu.available()
  local p = C_AddOnProfiler
  if not (p and p.GetAddOnMetric) then return false end
  if p.IsEnabled then
    local ok, on = pcall(p.IsEnabled)
    if ok and on == false then return false end
  end
  return true
end

local function read(addon, name)
  local ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, addon, metric(name))
  return ok and tonumber(v) or 0
end
local function readApp(name)
  local p = C_AddOnProfiler
  local fn = p.GetApplicationMetric
  if not fn then return nil end
  local ok, v = pcall(fn, metric(name))
  return ok and tonumber(v) or nil
end
local function readAll(name)
  local fn = C_AddOnProfiler.GetOverallMetric
  if not fn then return nil end
  local ok, v = pcall(fn, metric(name))
  return ok and tonumber(v) or nil
end

-- The loaded addons, by folder name.
function cpu.addons()
  local A = C_AddOns or {}
  local num = A.GetNumAddOns or GetNumAddOns
  local info = A.GetAddOnInfo or GetAddOnInfo
  local loaded = A.IsAddOnLoaded or IsAddOnLoaded
  local out = {}
  if not (num and info and loaded) then return out end
  for i = 1, num() do
    local name = info(i)
    if name and loaded(name) then out[#out + 1] = name end
  end
  return out
end

function cpu.context()
  local open = {}
  for _, p in ipairs(cpu.PANELS) do
    local f = _G[p[1]]
    if type(f) == "table" and f.IsShown and f:IsShown() then
      local seen = false
      for _, o in ipairs(open) do if o == p[2] then seen = true end end
      if not seen then open[#open + 1] = p[2] end
    end
  end
  local ctx = {
    zone = GetRealZoneText and GetRealZoneText() or nil,
    combat = InCombatLockdown and InCombatLockdown() and true or nil,
    open = #open > 0 and table.concat(open, ", ") or nil,
  }
  if cpu.loadedAt and clock() - cpu.loadedAt <= cpu.LOADING_SECS then ctx.loading = true end
  return ctx
end

local function trim(list, keep)
  local extra = #list - keep
  if extra <= 0 then return end
  for i = 1, #list do list[i] = list[i + extra] end
end

local function addSpike(data, s)
  data.spikes = data.spikes or {}
  data.spikes[#data.spikes + 1] = s
  trim(data.spikes, cpu.KEEP_SPIKES)
end

-- The minute being built: per addon the sum of RecentAverageTime reads,
-- the slow frames and the worst single frame.
local function flushMinute(data)
  local m = cpu.minute
  if not m or m.reads == 0 then return end
  local rows = {}
  for addon, a in pairs(m.addons) do
    local avg = a.sum / m.reads
    if avg >= 0.05 or a.slow > 0 then
      rows[#rows + 1] = { a = addon, ms = math.floor(avg * 100 + 0.5) / 100, slow = a.slow > 0 and a.slow or nil,
        peak = a.peak >= cpu.SPIKE_MS and math.floor(a.peak + 0.5) or nil }
    end
  end
  table.sort(rows, function(x, y) return x.ms > y.ms end)
  for i = #rows, 6, -1 do if not rows[i].slow then table.remove(rows, i) end end
  local entry = { t = m.t, top = rows }
  if m.app and m.app > 0 and m.all then entry.pct = math.floor(m.all / m.app * 100 + 0.5) end
  data.minutes = data.minutes or {}
  data.minutes[#data.minutes + 1] = entry
  trim(data.minutes, cpu.KEEP_MINUTES)
end

-- One read of every addon. t is the wall clock (time()), for tests.
function cpu.tick(data, t)
  if not cpu.available() then return end
  t = t or now()
  local minuteStart = t - t % 60
  if cpu.minute and cpu.minute.t ~= minuteStart then
    flushMinute(data)
    cpu.minute = nil
  end
  cpu.minute = cpu.minute or { t = minuteStart, reads = 0, addons = {} }
  local m = cpu.minute
  m.reads = m.reads + 1
  local all, app = readAll("RecentAverageTime"), readApp("RecentAverageTime")
  if all and app then
    m.all, m.app = (m.all or 0) + all, (m.app or 0) + app
  end
  cpu.last = cpu.last or {}
  local ctx
  for _, addon in ipairs(cpu.addons()) do
    local c50 = read(addon, "CountTimeOver50Ms")
    local peak = read(addon, "PeakTime")
    local recent = read(addon, "RecentAverageTime")
    local c500 = read(addon, "CountTimeOver500Ms")
    local prev = cpu.last[addon]
    local slow = 0
    if prev then
      slow = c50 - prev.c50
      if slow < 0 then slow = c50 end   -- the counters restarted
    else
      slow = c50                        -- first read: whatever happened while loading
    end
    local rose = peak >= cpu.SPIKE_MS and (not prev or peak > prev.peak + 0.5)
    if slow > 0 or rose then
      ctx = ctx or cpu.context()
      local s = { t = t, a = addon, n = slow > 0 and slow or nil, zone = ctx.zone, combat = ctx.combat,
        open = ctx.open, loading = ctx.loading }
      if rose then s.peak = math.floor(peak + 0.5) end
      if prev and c500 > prev.c500 then s.huge = c500 - prev.c500 end
      addSpike(data, s)
    end
    cpu.last[addon] = { c50 = c50, peak = peak, c500 = c500 }
    local a = m.addons[addon]
    if not a then a = { sum = 0, slow = 0, peak = 0 } m.addons[addon] = a end
    a.sum = a.sum + recent
    a.slow = a.slow + slow
    if rose and peak > a.peak then a.peak = peak end
  end
end

-- What the game shows now, per addon, busiest first.
function cpu.snapshot()
  local rows = {}
  if not cpu.available() then return rows end
  local app = readApp("RecentAverageTime")
  for _, addon in ipairs(cpu.addons()) do
    local r = {
      a = addon,
      recent = read(addon, "RecentAverageTime"),
      session = read(addon, "SessionAverageTime"),
      peak = read(addon, "PeakTime"),
      slow = read(addon, "CountTimeOver50Ms"),
      over5 = read(addon, "CountTimeOver5Ms"),
    }
    if app and app > 0 then r.pct = r.recent / app * 100 end
    rows[#rows + 1] = r
  end
  table.sort(rows, function(x, y)
    if x.recent ~= y.recent then return x.recent > y.recent end
    return x.peak > y.peak
  end)
  return rows
end

-- Formatting ---------------------------------------------------------------

local function stamp(t)
  if not date then return tostring(t) end
  if now() - t > 20 * 3600 then return date("%m-%d %H:%M", t) end
  return date("%H:%M:%S", t)
end
cpu.stamp = stamp

local function ms(v)
  if v >= 100 then return ("%d ms"):format(math.floor(v + 0.5)) end
  if v >= 10 then return ("%.1f ms"):format(v) end
  return ("%.2f ms"):format(v)
end
cpu.ms = ms

function cpu.spikeLine(s)
  local what = {}
  if s.n then what[#what + 1] = s.n .. (s.n == 1 and " slow frame" or " slow frames") end
  if s.peak then what[#what + 1] = "new peak " .. s.peak .. " ms" end
  if s.huge then what[#what + 1] = s.huge .. " over 500 ms" end
  local where = {}
  if s.loading then where[#where + 1] = "loading" end
  if s.combat then where[#where + 1] = "combat" end
  if s.open then where[#where + 1] = s.open end
  if s.zone and s.zone ~= "" then where[#where + 1] = s.zone end
  return ("%s  |cffffd200%s|r  %s%s"):format(stamp(s.t), s.a, table.concat(what, ", "),
    #where > 0 and ("|cff999999 (" .. table.concat(where, "; ") .. ")|r") or "")
end

function cpu.minuteLine(e)
  local parts = {}
  for i, r in ipairs(e.top or {}) do
    if i > 3 and not r.slow then break end
    local p = r.a .. " " .. ms(r.ms)
    if r.slow then p = p .. " |cffff6060" .. r.slow .. " slow|r" end
    parts[#parts + 1] = p
  end
  if #parts == 0 then parts[1] = "quiet" end
  return ("%s  %s%s"):format(date and date("%H:%M", e.t) or e.t,
    e.pct and ("addons " .. e.pct .. "%  ") or "", table.concat(parts, ", "))
end

-- Totals per addon over the saved spikes: who spikes most.
function cpu.offenders(data, since)
  local by, list = {}, {}
  for _, s in ipairs(data.spikes or {}) do
    if not since or s.t >= since then
      local o = by[s.a]
      if not o then o = { a = s.a, n = 0, peak = 0, loading = 0, last = 0 } by[s.a] = o list[#list + 1] = o end
      o.n = o.n + (s.n or 0)
      if s.loading then o.loading = o.loading + (s.n or 0) end
      if (s.peak or 0) > o.peak then o.peak = s.peak end
      if s.t > o.last then o.last = s.t end
    end
  end
  table.sort(list, function(x, y)
    if x.n - x.loading ~= y.n - y.loading then return x.n - x.loading > y.n - y.loading end
    return x.peak > y.peak
  end)
  return list
end

-- Chat output --------------------------------------------------------------

local function say(line) DEFAULT_CHAT_FRAME:AddMessage(line) end

local function showTop(n)
  local rows = cpu.snapshot()
  ns.say("CPU now (average over the last frames, session peak, frames over 50 ms):")
  for i = 1, math.min(n or 8, #rows) do
    local r = rows[i]
    say(("  %s  %s%s, peak %s, %d slow"):format(r.a, ms(r.recent),
      r.pct and (" (" .. math.floor(r.pct + 0.5) .. "%)") or "", ms(r.peak), r.slow))
  end
end

local function showSpikes(data, n)
  local list = data.spikes or {}
  if #list == 0 then ns.say("no spikes yet (a spike is one frame where an addon ran " .. cpu.SPIKE_MS .. " ms or more)") return end
  ns.say(("last %d spikes (frames where one addon ran %d ms or more):"):format(math.min(n, #list), cpu.SPIKE_MS))
  for i = math.max(1, #list - n + 1), #list do say("  " .. cpu.spikeLine(list[i])) end
end

local function showWorst(data, hours)
  local since = hours and (now() - hours * 3600) or nil
  local list = cpu.offenders(data, since)
  if #list == 0 then ns.say("no spikes " .. (hours and ("in the last " .. hours .. " h") or "saved")) return end
  ns.say("who spikes most" .. (hours and (" (last " .. hours .. " h)") or "") .. ":")
  for i = 1, math.min(8, #list) do
    local o = list[i]
    say(("  |cffffd200%s|r  %d slow frames%s, worst %s, last %s"):format(o.a, o.n,
      o.loading > 0 and (" (" .. o.loading .. " while loading)") or "",
      o.peak > 0 and (o.peak .. " ms") or "-", stamp(o.last)))
  end
end

local function showHistory(data, n)
  local list = data.minutes or {}
  if #list == 0 then ns.say("no history yet; it saves one line a minute") return end
  ns.say(("last %d minutes, busiest addons (average per frame):"):format(math.min(n, #list)))
  for i = math.max(1, #list - n + 1), #list do say("  " .. cpu.minuteLine(list[i])) end
end

-- Window -------------------------------------------------------------------

local win
local function paint()
  if not (win and win:IsShown()) then return end
  local rows = cpu.snapshot()
  local cols = { {}, {}, {}, {} }
  local head = { "Addon", "Now", "Peak", ">50 ms" }
  for c = 1, 4 do cols[c][1] = "|cffffd200" .. head[c] .. "|r" end
  for i = 1, math.min(12, #rows) do
    local r = rows[i]
    cols[1][#cols[1] + 1] = r.a
    cols[2][#cols[2] + 1] = ms(r.recent)
    cols[3][#cols[3] + 1] = ms(r.peak)
    cols[4][#cols[4] + 1] = tostring(r.slow)
  end
  for c = 1, 4 do win.cols[c]:SetText(table.concat(cols[c], "\n")) end
  local data = ns.Data("cpu")
  local lines = { "|cffffd200Recent spikes|r" }
  local list = data.spikes or {}
  for i = #list, math.max(1, #list - 9), -1 do lines[#lines + 1] = cpu.spikeLine(list[i]) end
  if #list == 0 then lines[2] = "|cff999999none yet|r" end
  win.spikes:SetText(table.concat(lines, "\n"))
end

local function makeWindow()
  local f = CreateFrame("Frame", "NicetiesCPUFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(520, 420)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Addon CPU  |cff999999(/cpu spikes, /cpu worst, /cpu history)|r")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  local x = { 12, 230, 320, 410 }
  local justify = { "LEFT", "RIGHT", "RIGHT", "RIGHT" }
  f.cols = {}
  for c = 1, 4 do
    local s = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s:SetPoint("TOPLEFT", x[c], -34)
    if c > 1 then s:SetWidth(80) end
    s:SetJustifyH(justify[c])
    f.cols[c] = s
  end
  f.spikes = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.spikes:SetPoint("TOPLEFT", 12, -230)
  f.spikes:SetWidth(496)
  f.spikes:SetJustifyH("LEFT")
  f:SetScript("OnShow", paint)
  if UISpecialFrames then table.insert(UISpecialFrames, "NicetiesCPUFrame") end
  return f
end

function cpu.toggleWindow()
  win = win or makeWindow()
  if win:IsShown() then win:Hide() else win:Show() paint() end
end

-- Feature ------------------------------------------------------------------

local ticker
local function start(data)
  if ticker or not (C_Timer and C_Timer.NewTicker) then return end
  ticker = C_Timer.NewTicker(cpu.TICK, function()
    local ok, err = pcall(cpu.tick, data)
    if not ok and not cpu.warned then cpu.warned = true ns.say("CPU tracker: " .. tostring(err)) end
    paint()
  end)
end
local function stop()
  if ticker then ticker:Cancel() ticker = nil end
end

ns.Add({
  key = "cpu",
  name = "CPU tracker",
  help = "keeps a history of addon CPU spikes; /cpu shows it",
  apply = function(on, data, why)
    if not on then stop() return "stopped; the history stays" end
    if not cpu.available() then return "the game's addon profiler is off on this client" end
    cpu.loadedAt = clock()   -- each loading screen: the next spikes are "loading"
    if why == "toggle" or not cpu.started then
      data.sessions = data.sessions or {}
      data.sessions[#data.sessions + 1] = now()
      trim(data.sessions, 50)
      cpu.started = true
    end
    start(data)
    return why == "toggle" and "/cpu shows it" or nil
  end,
  status = function(data)
    return (#(data.spikes or {})) .. " spikes, " .. (#(data.minutes or {})) .. " minutes saved"
  end,
})

SLASH_NICETIESCPU1, SLASH_NICETIESCPU2 = "/cpu", "/nicecpu"
SlashCmdList.NICETIESCPU = function(text)
  local cmd, arg = (text or ""):lower():match("^%s*(%S*)%s*(%S*)")
  local data = ns.Data("cpu")
  local n = tonumber(arg)
  if cmd == "" then cpu.toggleWindow()
  elseif cmd == "top" or cmd == "now" then showTop(n or 8)
  elseif cmd == "spikes" then showSpikes(data, n or 15)
  elseif cmd == "worst" then showWorst(data, n)
  elseif cmd == "history" then showHistory(data, n or 30)
  elseif cmd == "reset" then
    data.spikes, data.minutes = {}, {}
    ns.say("CPU history cleared")
  else
    ns.say("/cpu: window. /cpu top: now. /cpu spikes [N]: last spikes. /cpu worst [hours]: who spikes most. "
      .. "/cpu history [minutes]: busiest per minute. /cpu reset. /nice cpu off stops it.")
  end
  if not ns.IsOn("cpu") and cmd ~= "" then ns.say("|cffff6060the tracker is off|r (/nice cpu on)") end
end
