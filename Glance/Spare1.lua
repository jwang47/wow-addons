-- Resting: a "Zzz" on your own unit frame while you rest (in an inn or a
-- city), like the default player portrait. You gain rested XP there.
local _, ns = ...

local rest = {}
ns.rest = rest

function rest.update()
  local f = ns.units and ns.units.frames and ns.units.frames.player
  if not f then return end
  if not rest.mark then
    rest.mark = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rest.mark:SetPoint("RIGHT", f.level, "LEFT", -4, 0)
    rest.mark:SetText("Zzz")
    rest.mark:SetTextColor(0.6, 0.75, 1)
  end
  local resting = IsResting and ns.plain(IsResting())
  rest.mark:SetShown(resting == true)
  -- Keep a long name clear of the mark.
  f.name:SetPoint("TOPRIGHT", resting == true and -46 or -22, 0)
end

ns.module("rest", function()
  rest.update()
  for _, ev in ipairs({ "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" }) do
    ns.on(ev, function() ns.safe("rest", rest.update) end)
  end
end)
