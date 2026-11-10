-- Glance chat: Blizzard's chat windows in the Glance look. A faint dark
-- panel, tabs that show only under the mouse, no side buttons, a plain edit
-- box, and text that fades after a quiet spell. Only looks change; the chat
-- itself is Blizzard's.
local addonName, ns = ...

local ch = {}
ns.chat = ch

local function kill(f)
  if type(f) ~= "table" then return end
  ns.safe("chat part", function()
    f:Hide()
    if f.HookScript and not f.glanceKilled then
      f.glanceKilled = true
      f:HookScript("OnShow", function(self) self:Hide() end)
    end
  end)
end

local function blank(tex)
  if type(tex) == "table" and tex.SetAlpha then tex:SetAlpha(0) end
end

local TAB_PARTS = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
  "HighlightLeft", "HighlightMiddle", "HighlightRight" }
local EDIT_PARTS = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

function ch.style(cf)
  if not cf or cf.glanceStyled then return end
  cf.glanceStyled = true
  local name = cf:GetName()
  if FCF_SetWindowAlpha then pcall(FCF_SetWindowAlpha, cf, 0.25, true) end
  if cf.SetFading then
    cf:SetFading(true)
    cf:SetTimeVisible(30)
    cf:SetFadeDuration(3)
  end
  if cf.SetShadowOffset then
    cf:SetShadowColor(0, 0, 0, 0.9)
    cf:SetShadowOffset(1, -1)
  end
  kill(cf.buttonFrame or _G[name .. "ButtonFrame"])

  local tab = _G[name .. "Tab"]
  if tab then
    for _, k in ipairs(TAB_PARTS) do
      blank(tab[k])
      blank(_G[name .. "Tab" .. k])
    end
  end

  local eb = cf.editBox or _G[name .. "EditBox"]
  if eb then
    for _, k in ipairs(EDIT_PARTS) do blank(_G[name .. "EditBox" .. k]) end
    if not eb.glanceBg then
      eb.glanceBg = eb:CreateTexture(nil, "BACKGROUND")
      eb.glanceBg:SetPoint("TOPLEFT", 2, -4)
      eb.glanceBg:SetPoint("BOTTOMRIGHT", -2, 4)
      eb.glanceBg:SetColorTexture(0, 0, 0, 0.5)
    end
  end
end

function ch.styleAll()
  local n = NUM_CHAT_WINDOWS or 10
  for i = 1, n do ch.style(_G["ChatFrame" .. i]) end
end

ns.module("chat", function()
  -- Tabs: hidden until the mouse is over the chat.
  CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0
  CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0
  ch.styleAll()
  for _, f in ipairs({ ChatFrameMenuButton, ChatFrameChannelButton,
      ChatFrameToggleVoiceDeafenButton, ChatFrameToggleVoiceMuteButton, QuickJoinToastButton }) do
    kill(f)
  end
  -- Whisper and new windows come later.
  if hooksecurefunc and FCF_OpenTemporaryWindow then
    hooksecurefunc("FCF_OpenTemporaryWindow", function() ns.safe("chat", ch.styleAll) end)
  end
end)
