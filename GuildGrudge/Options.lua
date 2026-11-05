-- Guild Grudge: settings panel, minimap button, addon compartment entry, macro helper
local ADDON, GG = ...

local ICON       = "Interface\\Icons\\Ability_Hunter_SniperShot"
local MACRO_NAME = "Guild Grudge"

BINDING_HEADER_GUILDGRUDGE      = "Guild Grudge"
BINDING_NAME_GUILDGRUDGE_TOGGLE = "Toggle Guild Grudge window"

---------------------------------------------------------------------------
-- Shared click and tooltip behaviour (minimap button and addon compartment)
---------------------------------------------------------------------------
local function HandleClick(button)
  if button == "RightButton" then
    GG:OpenSettings()
  else
    GG:ToggleUI()
  end
end

local function ShowTooltip(anchor)
  if not GameTooltip then return end
  GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
  GameTooltip:AddLine("Guild Grudge")
  GameTooltip:AddLine("Left-click: open list", 1, 1, 1)
  GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
  GameTooltip:Show()
end

local function HideTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

-- The client calls these by name from the TOC fields. The second argument of
-- the click handler is the mouse button name.
function GuildGrudge_OnCompartmentClick(_, buttonName)
  HandleClick(buttonName)
end

function GuildGrudge_OnCompartmentEnter(_, anchor)
  if anchor then ShowTooltip(anchor) end
end

function GuildGrudge_OnCompartmentLeave()
  HideTooltip()
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local button

local function PlaceButton()
  local angle = math.rad(GG.db.settings.minimapAngle or 200)
  local radius = Minimap:GetWidth() / 2 + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  GG.db.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
  PlaceButton()
end

local function CreateButton()
  button = CreateFrame("Button", "GuildGrudgeMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  -- The border texture's ring sits in its top-left part, so it stays anchored
  -- TOPLEFT at 50x50 while the background and icon are centered in the ring.
  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(24, 24)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("CENTER")

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetPoint("CENTER")

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(50, 50)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, mouseButton) HandleClick(mouseButton) end)
  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", DragUpdate) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self) ShowTooltip(self) end)
  button:SetScript("OnLeave", HideTooltip)
end

function GG:UpdateMinimapButton()
  if not Minimap then return end
  if not button then CreateButton() end
  PlaceButton()
  if self.db.settings.minimapButton then button:Show() else button:Hide() end
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
local category

local function RegisterSettings()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
  local s = GG.db.settings
  category = Settings.RegisterVerticalLayoutCategory("Guild Grudge")

  local function Checkbox(key, label, tooltip, onChange)
    local setting = Settings.RegisterAddOnSetting(category, "GUILDGRUDGE_" .. key:upper(), key, s,
      Settings.VarType.Boolean, label, true)
    if onChange then setting:SetValueChangedCallback(onChange) end
    Settings.CreateCheckbox(category, setting, tooltip)
  end

  Checkbox("alerts", "Proximity alerts", "Show a warning when a listed player is near you.")
  Checkbox("sound", "Alert sound", "Play a sound with the proximity alert.")
  Checkbox("shareSpotted", "Share sightings with the guild", "Tell guildmates when you spot someone on the list.")
  Checkbox("announceClaims", "Announce bounty claims in guild chat", "Post in guild chat when you claim a bounty.")
  Checkbox("watchNearby", "Watch list: nearby chat line",
    "Print a chat line when someone from your watch list is near you. There is no warning on screen.")
  Checkbox("watchGroup", "Watch list: warn when they join your group",
    "Show a warning when someone from your watch list joins your party or raid.")
  Checkbox("minimapButton", "Show minimap button", "Show the Guild Grudge button on the minimap.",
    function() GG:UpdateMinimapButton() end)

  if Settings.CreateSlider and Settings.CreateSliderOptions then
    local setting = Settings.RegisterAddOnSetting(category, "GUILDGRUDGE_ALERTCOOLDOWN", "alertCooldown", s,
      Settings.VarType.Number, "Alert cooldown (seconds)", 60)
    local options = Settings.CreateSliderOptions(15, 300, 15)
    if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
      options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value) return ("%d s"):format(value) end)
    end
    Settings.CreateSlider(category, setting, options,
      "Seconds a listed player must be out of sight before they can alert you again.")
  end

  if Settings.RegisterAddOnCategory then Settings.RegisterAddOnCategory(category) end
end

function GG:OpenSettings()
  if not (category and Settings and Settings.OpenToCategory) then
    return self:Print("The settings panel is not available.")
  end
  Settings.OpenToCategory(category:GetID())
end

---------------------------------------------------------------------------
-- Macro
---------------------------------------------------------------------------
function GG:MakeMacro()
  if not (CreateMacro and GetMacroInfo and GetNumMacros and PickupMacro) then
    return self:Print("Macros are not available.")
  end
  if InCombatLockdown and InCombatLockdown() then
    return self:Print("You can't create a macro in combat.")
  end
  local max = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or 120
  local index
  for i = 1, max do
    if GetMacroInfo(i) == MACRO_NAME then index = i break end
  end
  if not index then
    if (GetNumMacros()) >= max then
      return self:Print("Your account macro slots are full. Delete a macro and try again.")
    end
    index = CreateMacro(MACRO_NAME, 134400, "/gg", false)
  end
  if not index then return self:Print("Could not create the macro.") end
  PickupMacro(index)
  self:Print("Guild Grudge macro is on your cursor. Drop it on an action bar.")
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  RegisterSettings()
  GG:UpdateMinimapButton()
end)
