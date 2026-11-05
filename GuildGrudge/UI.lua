-- Guild Grudge: list window and tooltip line
local ADDON, GG = ...
local frame

-- Text input popup. The callback lives in the popup data so one dialog serves every caller.
if StaticPopupDialogs then
  StaticPopupDialogs["GUILDGRUDGE_INPUT"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 200,
    OnAccept = function(dialog, data)
      local text = strtrim(dialog:GetEditBox():GetText() or "")
      if text ~= "" and data then data(text) end
    end,
    EditBoxOnEnterPressed = function(editBox, data)
      local dialog = editBox:GetParent()
      local text = strtrim(editBox:GetText() or "")
      dialog:Hide()
      if text ~= "" and data then data(text) end
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    OnShow = function(dialog) dialog:GetEditBox():SetFocus() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
  StaticPopupDialogs["GUILDGRUDGE_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(dialog, data) if data then data() end end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

function GG:Prompt(title, onAccept, initialText)
  if not StaticPopup_Show then return end
  local dialog = StaticPopup_Show("GUILDGRUDGE_INPUT", title, nil, onAccept)
  if dialog and initialText then dialog:GetEditBox():SetText(initialText) end
end

function GG:PromptNote(name, unit)
  self:Prompt("Note on " .. name .. ":", function(text) GG:AddNote(name, text, unit) end)
end

function GG:PromptBounty(name)
  self:Prompt("Bounty reward on " .. name .. " (e.g. 50g):", function(text) GG:SetBounty(name, text) end)
end

function GG:PromptAddPlayer()
  self:Prompt("Name and note, e.g. Ana Forever camped me at the FP:", function(text)
    local name, note = GG:TakeName(text)
    if not name then
      GG:Print("Write the full name, then the note, e.g. Ana Forever camped me at the FP")
      return
    end
    GG:HintNewName(name)
    GG:AddNote(name, note)
  end)
end

local function HasMyNote(e)
  local me = GG:Me()
  for _, n in ipairs(GG:SortedNotes(e)) do
    if n.author == me then return true end
  end
end

local function ShowRowMenu(row)
  local e = row.entry
  if not e or not MenuUtil or not MenuUtil.CreateContextMenu then return end
  MenuUtil.CreateContextMenu(row, function(_, root)
    root:CreateTitle(e.name)
    root:CreateButton("Show all notes", function() GG:Show(e.name) end)
    root:CreateButton("Add note...", function() GG:PromptNote(e.name) end)
    if GG:ActiveBounty(e) then
      root:CreateButton("Remove bounty", function() GG:ClearBounty(e.name) end)
      root:CreateButton("Claim bounty", function() GG:TryClaim(e.name, true) end)
    else
      root:CreateButton("Post bounty...", function() GG:PromptBounty(e.name) end)
    end
    if HasMyNote(e) then
      root:CreateButton("Delete my notes", function()
        if not StaticPopup_Show then return end
        StaticPopup_Show("GUILDGRUDGE_CONFIRM", ("Delete your notes on %s?"):format(e.name), nil,
          function() GG:DeleteMyNotes(e.name) end)
      end)
    end
  end)
end

local function Tip(button, text)
  button:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function AddToolbarButton(f, label, tip, x, onClick)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(92, 22)
  b:SetPoint("TOPLEFT", x, -58)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  Tip(b, tip)
end

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

  AddToolbarButton(f, "Note target", "Add a note on your current target", 20, function()
    local full = UnitIsPlayer("target") and GG:UnitFullName("target")
    if full then GG:PromptNote(full, "target") else GG:Print("Target a player first.") end
  end)
  AddToolbarButton(f, "Add player", "Add a note on a player by name", 116, function() GG:PromptAddPlayer() end)
  AddToolbarButton(f, "Macro", "Put a macro that opens this window on your cursor", 212, function()
    if GG.MakeMacro then GG:MakeMacro() end
  end)
  AddToolbarButton(f, "Settings", "Open the Guild Grudge settings", 308, function()
    if GG.OpenSettings then GG:OpenSettings() end
  end)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -88)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(370, 10)
  scroll:SetScrollChild(child)

  local empty = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  empty:SetPoint("TOPLEFT", 4, -4)
  empty:SetWidth(362)
  empty:SetJustifyH("LEFT")
  empty:SetJustifyV("TOP")
  f.empty, f.child, f.rows = empty, child, {}

  f:SetScript("OnShow", function() GG:RefreshUI() end)
  f:Hide()
  return f
end

local function GetRow(f, i)
  local row = f.rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, f.child)
  row:SetWidth(370)
  row:RegisterForClicks("AnyUp")
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("TOPLEFT", 4, -4)
  row.text:SetWidth(362)
  row.text:SetJustifyH("LEFT")
  row.text:SetJustifyV("TOP")
  row:SetScript("OnClick", ShowRowMenu)
  Tip(row, "Right-click for actions")
  f.rows[i] = row
  return row
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

  local shown = math.min(#list, 150)
  local y = 0
  for i = 1, shown do
    local e, notes = list[i].e, list[i].notes
    local out = {}
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
    if #notes > 3 then out[#out + 1] = ("   |cff999999...and %d more (right-click: Show all notes)|r"):format(#notes - 3) end

    local row = GetRow(frame, i)
    row.entry = e
    row.text:SetText(table.concat(out, "\n"))
    local h = (row.text:GetStringHeight() or 0) + 8
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 0, -y)
    row:Show()
    y = y + h
  end
  for i = shown + 1, #frame.rows do
    frame.rows[i].entry = nil
    frame.rows[i]:Hide()
  end

  if shown == 0 then
    frame.empty:SetText(filter == "" and "Nobody on the list yet.\n\nTarget a ganker and type:\n/gg t camped me at the flight path"
                                     or "No matches.")
    frame.empty:Show()
    y = (frame.empty:GetStringHeight() or 0) + 4
  else
    frame.empty:Hide()
  end
  frame.child:SetHeight(y + 10)
end

-- Right-click menu on unit frames and portraits
local MENU_TAGS = { "MENU_UNIT_TARGET", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_FRIEND",
  "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FOCUS" }

local function AddUnitMenuItems(_, root, ctx)
  if not ctx or not GG.db then return end
  local unit, name = ctx.unit, nil
  if unit and UnitIsPlayer(unit) then
    name = GG:UnitFullName(unit)
  elseif ctx.name then
    unit = nil
    name = GG:FullName(ctx.name, ctx.surname)
  end
  if not name or name == GG:Me() then return end
  root:CreateDivider()
  root:CreateTitle("Guild Grudge")
  root:CreateButton("Add grudge note...", function() GG:PromptNote(name, unit) end)
  root:CreateButton("Post bounty...", function() GG:PromptBounty(name) end)
end

if Menu and Menu.ModifyMenu then
  for _, tag in ipairs(MENU_TAGS) do Menu.ModifyMenu(tag, AddUnitMenuItems) end
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
