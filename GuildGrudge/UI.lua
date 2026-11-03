-- Guild Grudge: list window and tooltip line
local ADDON, GG = ...
local frame

local function Build()
  local f = CreateFrame("Frame", "GuildGrudgeFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 480)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "GuildGrudgeFrame") -- Escape closes it

  local title = f.TitleText
  if not title then
    title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
  end
  title:SetText("Guild Grudge - Most Wanted")

  local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  search:SetSize(200, 20)
  search:SetPoint("TOPLEFT", 20, -32)
  search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function() GG:RefreshUI() end)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  f.search = search

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", search, "RIGHT", 8, 0)
  hint:SetText("search names and notes")

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -60)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(370, 10)
  scroll:SetScrollChild(child)

  local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", 4, -4)
  text:SetWidth(362)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  f.text, f.child = text, child

  f:SetScript("OnShow", function() GG:RefreshUI() end)
  f:Hide()
  return f
end

function GG:ToggleUI()
  frame = frame or Build()
  frame:SetShown(not frame:IsShown())
end

function GG:RefreshUI()
  if not frame or not frame:IsShown() then return end
  local filter = strlower(strtrim(frame.search:GetText() or ""))
  local list = {}
  for key, e in pairs(self.db.entries) do
    local notes = self:SortedNotes(e)
    if #notes > 0 or self:ActiveBounty(e) then
      local match = filter == "" or key:find(filter, 1, true)
      if not match then
        for _, n in ipairs(notes) do
          if strlower(n.text):find(filter, 1, true) then match = true; break end
        end
      end
      if match then list[#list + 1] = { e = e, notes = notes } end
    end
  end

  table.sort(list, function(a, b)
    local ab = GG:ActiveBounty(a.e) and 1 or 0
    local bb = GG:ActiveBounty(b.e) and 1 or 0
    if ab ~= bb then return ab > bb end
    if #a.notes ~= #b.notes then return #a.notes > #b.notes end
    return (a.e.lastSeen or 0) > (b.e.lastSeen or 0)
  end)

  local out = {}
  for i = 1, math.min(#list, 150) do
    local e, notes = list[i].e, list[i].notes
    local info = strtrim(("%s %s"):format(e.level and ("lvl " .. e.level) or "", e.race or ""))
    out[#out + 1] = ("%s  |cff999999%s[%d note%s]|r"):format(
      self:ColorName(e), info ~= "" and (info .. "  ") or "", #notes, #notes == 1 and "" or "s")
    local b = self:ActiveBounty(e)
    if b then out[#out + 1] = "   |cffffd100BOUNTY: " .. b.reward .. "|r  |cff999999(by " .. b.poster .. ")|r" end
    if e.lastSeen then
      out[#out + 1] = ("   |cff999999Seen %s in %s by %s|r"):format(self:Age(e.lastSeen), e.lastSeenZone or "?", e.lastSeenBy or "?")
    end
    for j = 1, math.min(3, #notes) do
      out[#out + 1] = ("   - %s |cff999999(%s, %s)|r"):format(notes[j].text, notes[j].author, self:Age(notes[j].ts))
    end
    if #notes > 3 then out[#out + 1] = ("   |cff999999...and %d more (/gg show %s)|r"):format(#notes - 3, e.name) end
    out[#out + 1] = " "
  end
  if #out == 0 then
    out[1] = filter == "" and "Nobody on the list yet.\n\nTarget a ganker and type:\n/gg t camped me at the flight path"
                          or "No matches."
  end

  frame.text:SetText(table.concat(out, "\n"))
  frame.child:SetHeight(frame.text:GetStringHeight() + 10)
end

-- Tooltip line on listed players
local function OnTooltipUnit(tt)
  if tt ~= GameTooltip or not GG.db then return end
  local _, unit = tt:GetUnit()
  if not unit or not UnitIsPlayer(unit) then return end
  local e = GG:GetEntry(GG:UnitFullName(unit), false)
  if not e or not GG:IsListed(e) then return end
  local n = #GG:SortedNotes(e)
  tt:AddLine(("|cffff5533Grudge:|r %d note%s"):format(n, n == 1 and "" or "s"))
  local b = GG:ActiveBounty(e)
  if b then tt:AddLine("|cffffd100Bounty: " .. b.reward .. "|r") end
  tt:Show()
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipUnit)
else
  GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipUnit)
end
