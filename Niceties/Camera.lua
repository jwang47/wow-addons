-- Zoom the camera out as far as the client allows (what the "Max Camera
-- Distance" addon does). The Options slider stops at 2.0 on Forever; the
-- CVar can go higher, up to a cap the client keeps to itself.
local _, ns = ...

local CVAR = "cameraDistanceMaxZoomFactor"
-- Highest first. The client clamps or refuses a value above its cap, so
-- the first value that it keeps (or the clamped value it keeps) is the cap.
ns.ZOOM_TRY = { 4.0, 3.4, 2.6, 2.0 }

local function get()
  local v = (C_CVar and C_CVar.GetCVar or GetCVar)(CVAR)
  return tonumber(v)
end
local function set(v)
  local fn = C_CVar and C_CVar.SetCVar or SetCVar
  pcall(fn, CVAR, tostring(v))
end
local function default()
  local fn = C_CVar and C_CVar.GetCVarDefault or GetCVarDefault
  return fn and tonumber((fn(CVAR))) or 1
end

local function fmt(v) return ("%.1f"):format(v) end

-- Sets the CVar to the highest value the client keeps; returns it.
function ns.MaxZoom()
  local start = get() or default()
  for _, v in ipairs(ns.ZOOM_TRY) do
    if v <= start + 0.001 then set(start) return start end
    set(v)
    local got = get()
    if got and got >= v - 0.001 then return v end   -- kept
    if got and got > start + 0.001 then return got end -- clamped to the cap
  end
  set(start)
  return start
end

ns.Add({
  key = "zoom",
  name = "Max camera distance",
  help = "zoom the camera out as far as the game allows",
  apply = function(on, data)
    if on then
      local now = get()
      -- Keep the player's own setting once, to put it back on "off".
      if data.before == nil then data.before = now end
      data.max = ns.MaxZoom()
      return "factor " .. fmt(data.max) .. ", scroll out to use it"
    end
    local back = data.before or default()
    set(back)
    data.before = nil
    return "factor back to " .. fmt(get() or back)
  end,
  status = function(data) return data.max and ("factor " .. fmt(data.max)) or nil end,
})
