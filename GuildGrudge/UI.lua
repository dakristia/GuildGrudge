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

-- HookScript keeps the highlight handlers that the button templates already set.
local function Tip(button, text)
  button:HookScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
  end)
  button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local ICON = "Interface\\Icons\\"
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local TABS = { "Wanted", "Bounties", "Hunters" }
local EMPTY_TEXT = {
  "Nobody on the list yet. Target a ganker and click the crosshair button.",
  "No open bounties.",
  "No bounties claimed yet.",
}

local function ClassRGB(e)
  local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
  if c then return c.r, c.g, c.b end
  return 1, 0.25, 0.25
end

-- An unknown class (or no coordinate table) shows a question mark, like the old red name.
local function SetClassIcon(tex, e)
  local coords = e.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.class]
  if coords then
    tex:SetTexture(CLASS_CIRCLES)
    tex:SetTexCoord(unpack(coords))
  else
    tex:SetTexture(ICON .. "INV_Misc_QuestionMark")
    tex:SetTexCoord(0, 1, 0, 1)
  end
end

-- Bounties are free text, so a skull marks them instead of a gold coin.
-- SetRaidTargetIconTexture only sets the texture coordinates, so the sheet is set first, as the nameplate XML does.
local function SetSkull(tex)
  tex:SetTexture(RAID_ICONS)
  if SetRaidTargetIconTexture then
    SetRaidTargetIconTexture(tex, 8)
  else
    tex:SetTexCoord(0.75, 1, 0.25, 0.5)
  end
end

-- The class colour of a player who has posted a note or claimed a bounty, or nil when unknown.
local function AuthorColor(name)
  local class = name and GG.AuthorClass and GG:AuthorClass(name)
  return class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or nil
end

-- Colours a name inside a FontString text. Unknown players keep the grey of the surrounding font.
local function ColoredName(name)
  local c = AuthorColor(name)
  if not c then return name end
  local str = c.colorStr or ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
  return ("|c%s%s|r"):format(str, name)
end

local function SetHunterColor(fs, name)
  local c = AuthorColor(name)
  if c then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(1, 0.82, 0) end
end

local function Plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

local function InfoText(e)
  return strtrim(("%s %s"):format(e.level and ("lvl " .. e.level) or "", e.race or ""))
end

---------------------------------------------------------------------------
-- Data for the three tabs
---------------------------------------------------------------------------
local function WantedList(bountiesOnly)
  local list = {}
  for key, e in pairs(GG.db.entries) do
    local notes = GG:SortedNotes(e)
    local bounty = GG:ActiveBounty(e)
    if (#notes > 0 or bounty) and (bounty or not bountiesOnly) then
      list[#list + 1] = { kind = "player", key = key, e = e, notes = notes, bounty = bounty }
    end
  end
  table.sort(list, function(a, b)
    local ab = a.bounty and 1 or 0
    local bb = b.bounty and 1 or 0
    if ab ~= bb then return ab > bb end
    if #a.notes ~= #b.notes then return #a.notes > #b.notes end
    return (a.e.lastSeen or 0) > (b.e.lastSeen or 0)
  end)
  return list
end

-- Same counting as GG:Top(), plus the claimed entries so the detail panel can list them.
local function HunterList()
  local byName, list = {}, {}
  for _, e in pairs(GG.db.entries) do
    local b = e.bounty
    if b and (b.claimedBy or "") ~= "" then
      local h = byName[b.claimedBy]
      if not h then
        h = { kind = "hunter", key = b.claimedBy, name = b.claimedBy, claims = {} }
        byName[b.claimedBy] = h
        list[#list + 1] = h
      end
      h.claims[#h.claims + 1] = { e = e, bounty = b }
    end
  end
  for _, h in ipairs(list) do
    h.count = #h.claims
    table.sort(h.claims, function(a, b) return (a.bounty.claimedTs or 0) > (b.bounty.claimedTs or 0) end)
  end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  return list
end

local function Matches(el, filter)
  if filter == "" then return true end
  if el.kind == "hunter" then return strlower(el.name):find(filter, 1, true) ~= nil end
  if el.key:find(filter, 1, true) then return true end
  for _, n in ipairs(el.notes) do
    if strlower(n.text):find(filter, 1, true) then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- List rows
---------------------------------------------------------------------------
local function CreateRowRegions(row)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0.04)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(28, 28)
  row.icon:SetPoint("LEFT", 6, 0)
  row.hunterIcon = row:CreateTexture(nil, "ARTWORK")
  row.hunterIcon:SetSize(28, 28)
  row.hunterIcon:SetPoint("LEFT", 6, 0)
  row.hunterIcon:SetAtlas("friends-icon-favorites")

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
  row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.info:SetPoint("LEFT", row.name, "RIGHT", 6, 0)

  row.note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
  row.note:SetJustifyH("LEFT")
  row.note:SetWordWrap(false)

  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.count:SetPoint("TOPRIGHT", -6, -6)
  row.reward = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.reward:SetPoint("BOTTOMRIGHT", -6, 5)
  row.skull = row:CreateTexture(nil, "ARTWORK")
  row.skull:SetSize(14, 14)
  row.skull:SetPoint("RIGHT", row.reward, "LEFT", -2, 0)
  SetSkull(row.skull)

  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      ShowRowMenu(self)
    else
      frame.selected = self.key
      GG:RefreshUI()
    end
  end)
  Tip(row, "Click for details, right-click for actions")
end

local function SetRowHunter(row, data)
  row.icon:Hide()
  row.hunterIcon:Show()
  row.name:SetText(("%d. %s"):format(data.index, data.name))
  SetHunterColor(row.name, data.name)
  row.info:SetText("")
  row.note:SetWidth(250)
  row.note:SetText(data.count == 1 and "1 bounty claimed" or (data.count .. " bounties claimed"))
  row.count:SetText("")
  row.skull:Hide()
  row.reward:SetText("")
end

local function SetRowPlayer(row, data)
  local e = data.e
  row.icon:Show()
  row.hunterIcon:Hide()
  SetClassIcon(row.icon, e)
  row.name:SetText(e.name)
  row.name:SetTextColor(ClassRGB(e))
  row.info:SetText(InfoText(e))
  row.note:SetText(data.notes[1] and data.notes[1].text or "")
  row.count:SetText(Plural(#data.notes, "note"))
  if data.bounty then
    row.note:SetWidth(170)
    row.skull:Show()
    row.reward:SetText(data.bounty.reward)
  else
    row.note:SetWidth(250)
    row.skull:Hide()
    row.reward:SetText("")
  end
end

local function InitRow(row, data)
  if not row.created then
    row.created = true
    CreateRowRegions(row)
  end
  row.key, row.entry = data.key, data.e
  row.bg:SetShown(data.index % 2 == 0)
  if data.kind == "hunter" then SetRowHunter(row, data) else SetRowPlayer(row, data) end
  if frame.selected == data.key then row:LockHighlight() else row:UnlockHighlight() end
end

---------------------------------------------------------------------------
-- Detail panel
---------------------------------------------------------------------------
local DETAIL_W = 296
local PAD = 10
local CONTENT_W = DETAIL_W - 2 * PAD
local NOTE_W = 256 -- the note list is 264 wide, minus 4px of padding on each side
local VOTE_W = 24 -- the right edge of a note block belongs to the vote control
local TEXT_W = NOTE_W - VOTE_W
local STAR_W = 16 -- the first place star shifts that note's text right
local ARROW_UP, ARROW_DOWN = "minimal-scrollbar-arrow-top", "minimal-scrollbar-arrow-bottom"

local function SetShown(widgets, shown)
  for _, w in ipairs(widgets) do w:SetShown(shown) end
end

-- Measures with a hidden FontString of the same font and width, so row heights match what is drawn.
local function TextHeight(fs, text)
  fs:SetText(text)
  return fs:GetStringHeight() or 0
end

-- opts: voting (reserve the vote column), first (star before the text), plus the vote fields for InitNote.
local function NoteBlock(d, text, meta, opts)
  opts = opts or {}
  local textW = opts.voting and TEXT_W or NOTE_W
  if opts.first then textW = textW - STAR_W end
  d.measureText:SetWidth(textW)
  d.measureMeta:SetWidth(opts.voting and TEXT_W or NOTE_W)
  local height = TextHeight(d.measureText, text) + TextHeight(d.measureMeta, meta ~= "" and meta or "X") + 8
  -- The up arrow, score and down arrow need about 32px.
  if opts.voting then height = math.max(height, 32) end
  local block = { text = text, meta = meta, height = height }
  for k, v in pairs(opts) do block[k] = v end
  return block
end

local function NoteScore(n)
  return GG.NoteScore and GG:NoteScore(n) or 0
end

local function PlayerBlocks(d, e, notes)
  local blocks = {}
  local me = GG:Me()
  local voting = GG.Vote ~= nil
  for i, n in ipairs(notes) do
    local parts = { ColoredName(n.author), GG:Age(n.ts) }
    if n.zone and n.zone ~= "" then parts[#parts + 1] = n.zone end
    local score = NoteScore(n)
    blocks[#blocks + 1] = NoteBlock(d, n.text, table.concat(parts, " - "), {
      voting = voting,
      entryName = e.name,
      note = n,
      score = score,
      myVote = GG.MyVote and GG:MyVote(n) or 0,
      own = n.author == me,
      first = i == 1 and #notes >= 2 and score > 0,
    })
  end
  if #blocks == 0 then blocks[1] = NoteBlock(d, "No notes.", "") end
  return blocks
end

local function ClaimBlocks(d, claims)
  local blocks = {}
  for _, c in ipairs(claims) do
    blocks[#blocks + 1] = NoteBlock(d, ("%s  |cffffd100%s|r"):format(GG:ColorName(c.e), c.bounty.reward),
      GG:Age(c.bounty.claimedTs))
  end
  return blocks
end

local function SetNotes(d, heading, blocks)
  d.notesHeading:SetText(heading)
  local dp = CreateDataProvider()
  for i, block in ipairs(blocks) do
    block.index = i
    dp:Insert(block)
  end
  d.notesBox:SetDataProvider(dp, ScrollBoxConstants.RetainScrollPosition)
end

-- Each visible section hangs below the one above it, so a hidden section leaves no gap.
local function Relayout(d, hasButtons)
  local prev = d.header
  for _, section in ipairs({ d.bountySec, d.seenSec, d.notesSec }) do
    if section:IsShown() then
      section:ClearAllPoints()
      section:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
      prev = section
    end
  end
  d.notesSec:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, hasButtons and 38 or 10)
end

-- A portrait can only be drawn for a unit that exists right now, so look for one the player can see.
local PORTRAIT_UNITS = { "target", "focus", "mouseover" }
for i = 1, 40 do PORTRAIT_UNITS[#PORTRAIT_UNITS + 1] = "nameplate" .. i end

local function FindUnit(key)
  if not UnitExists or not UnitIsPlayer then return nil end
  for _, token in ipairs(PORTRAIT_UNITS) do
    if UnitExists(token) and UnitIsPlayer(token) then
      local full = GG:UnitFullName(token)
      if full and GG:MakeKey(full) == key then return token end
    end
  end
end

-- Without a visible unit (or without SetPortraitTexture) the class icon stays, as before.
local function UpdatePortrait(d)
  local e = d.entry
  local token = e and SetPortraitTexture and FindUnit(GG:MakeKey(e.name))
  if token then
    SetPortraitTexture(d.portrait, token)
    d.portrait:Show()
    d.icon:Hide()
    -- The portrait already hides the class, so the badge adds it back; an unknown class gets no badge.
    if e.class then
      SetClassIcon(d.badge, e)
      d.badge:Show()
    else
      d.badge:Hide()
    end
  else
    d.portrait:Hide()
    d.badge:Hide()
    d.icon:Show()
  end
end

local function UpdateDetailPlayer(d, el)
  local e, b = el.e, el.bounty
  d.entry = e
  SetClassIcon(d.icon, e)
  UpdatePortrait(d)
  d.name:SetText(e.name)
  d.name:SetTextColor(ClassRGB(e))
  d.info:SetText(strtrim(("%s %s %s"):format(
    e.level and ("lvl " .. e.level) or "", e.race or "", e.class and strlower(e.class) or "")))

  local claimed = e.bounty and (e.bounty.claimedBy or "") ~= "" and e.bounty
  d.bountySec:SetShown((b or claimed) and true or false)
  if b then
    d.reward:SetText(b.reward)
    d.bountyMeta:SetText("Posted by " .. ColoredName(b.poster))
  elseif claimed then
    d.reward:SetText(claimed.reward)
    d.bountyMeta:SetText(("Claimed by %s, %s"):format(ColoredName(claimed.claimedBy), GG:Age(claimed.claimedTs)))
  end

  d.seenSec:SetShown(e.lastSeen and true or false)
  if e.lastSeen then
    d.seenLine:SetText(("%s by %s"):format(GG:Age(e.lastSeen), ColoredName(e.lastSeenBy or "?")))
    d.seenZone:SetText(e.lastSeenZone or "?")
  end

  SetNotes(d, ("Notes (%d)"):format(#el.notes), PlayerBlocks(d, e, el.notes))
  d.bountyButton:SetText(b and "Remove bounty" or "Post bounty")
  if b then d.claimButton:Enable() else d.claimButton:Disable() end
  SetShown(d.playerOnly, true)
end

local function UpdateDetailHunter(d, el)
  d.entry = nil
  d.icon:SetAtlas("friends-icon-favorites")
  UpdatePortrait(d)
  d.name:SetText(el.name)
  SetHunterColor(d.name, el.name)
  d.info:SetText(el.count == 1 and "1 bounty claimed" or (el.count .. " bounties claimed"))
  d.bountySec:Hide()
  d.seenSec:Hide()
  SetNotes(d, ("Claimed bounties (%d)"):format(el.count), ClaimBlocks(d, el.claims))
  SetShown(d.playerOnly, false)
end

local function UpdateDetail(d, el)
  if not el then
    d.entry = nil
    SetShown(d.always, false)
    SetShown(d.playerOnly, false)
    d.bountySec:Hide()
    d.seenSec:Hide()
    d.hint:Show()
    return
  end
  d.hint:Hide()
  SetShown(d.always, true)
  if el.kind == "hunter" then UpdateDetailHunter(d, el) else UpdateDetailPlayer(d, el) end
  Relayout(d, el.kind ~= "hunter")
end

---------------------------------------------------------------------------
-- Window pieces
---------------------------------------------------------------------------
local function AddIconButton(f, anchor, tip, icon, atlas, onClick)
  local b = CreateFrame("Button", nil, f, "SquareIconButtonTemplate")
  b:SetSize(26, 26)
  if anchor then b:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0) else b:SetPoint("TOPRIGHT", -12, -29) end
  if icon and b.SetIcon then b:SetIcon(icon) end
  if atlas and b.SetAtlas then b:SetAtlas(atlas) end
  b:SetScript("OnClick", onClick)
  Tip(b, tip)
  return b
end

local function BuildToolbar(f)
  local search = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
  search:SetSize(200, 20)
  search:SetPoint("TOPLEFT", 72, -32)
  search:SetAutoFocus(false)
  search:HookScript("OnTextChanged", function() GG:RefreshUI() end)
  f.search = search

  -- Created right to left, so the settings button sits at the edge.
  local b = AddIconButton(f, nil, "Settings", nil, "questlog-icon-setting", function()
    if GG.OpenSettings then GG:OpenSettings() end
  end)
  b = AddIconButton(f, b, "Put a /gg macro on your cursor", ICON .. "INV_Misc_Book_09", nil, function()
    if GG.MakeMacro then GG:MakeMacro() end
  end)
  b = AddIconButton(f, b, "Add a player by name", nil, "communities-icon-addchannelplus", function()
    GG:PromptAddPlayer()
  end)
  AddIconButton(f, b, "Note your target", ICON .. "Ability_Hunter_SniperShot", nil, function()
    local full = UnitIsPlayer("target") and GG:UnitFullName("target")
    if full then GG:PromptNote(full, "target") else GG:Print("Target a player first.") end
  end)
end

local function BuildList(f)
  local inset = f.Inset
  inset:ClearAllPoints()
  inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -60)
  inset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 26)
  inset:SetWidth(330)

  local box = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -14, 4)
  local bar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 2, 0)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 2, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(40)
  view:SetElementInitializer("Button", InitRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  if ScrollUtil.AddManagedScrollBarVisibilityBehavior then
    ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar)
  end
  f.box = box

  -- On the ScrollBox, because regions of the window itself draw under the Inset.
  local empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  empty:SetPoint("CENTER")
  empty:SetWidth(260)
  empty:SetJustifyH("CENTER")
  f.empty = empty
end

local function Label(parent, font, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetWidth(width)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function CreateSection(d, height)
  local s = CreateFrame("Frame", nil, d)
  s:SetSize(DETAIL_W, height)
  return s
end

local function CreateHeader(d)
  local h = CreateSection(d, 60)
  h:SetPoint("TOPLEFT")
  d.header = h
  d.icon = h:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(40, 40)
  d.icon:SetPoint("TOPLEFT", PAD, -PAD)
  d.portrait = h:CreateTexture(nil, "ARTWORK")
  d.portrait:SetSize(40, 40)
  d.portrait:SetPoint("TOPLEFT", PAD, -PAD)
  d.portrait:Hide()
  -- OVERLAY draws above ARTWORK, so the badge sits on top of the portrait corner.
  d.badge = h:CreateTexture(nil, "OVERLAY")
  d.badge:SetSize(16, 16)
  d.badge:SetPoint("TOPRIGHT", d.portrait, "TOPRIGHT", 4, 4)
  d.badge:Hide()
  d.name = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -2)
  d.name:SetWidth(CONTENT_W - 48)
  d.name:SetJustifyH("LEFT")
  d.name:SetWordWrap(false)
  d.info = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.info:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
  d.info:SetWidth(CONTENT_W - 48)
  d.info:SetJustifyH("LEFT")
  d.info:SetWordWrap(false)
end

local function CreateBountySection(d)
  local s = CreateSection(d, 48)
  d.bountySec = s
  Label(s, "GameFontNormal", PAD, 0, CONTENT_W):SetText("Bounty")
  d.skull = s:CreateTexture(nil, "ARTWORK")
  d.skull:SetSize(14, 14)
  d.skull:SetPoint("TOPLEFT", PAD, -17)
  SetSkull(d.skull)
  d.reward = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d.reward:SetPoint("LEFT", d.skull, "RIGHT", 4, 0)
  d.reward:SetWidth(CONTENT_W - 18)
  d.reward:SetJustifyH("LEFT")
  d.reward:SetWordWrap(false)
  d.bountyMeta = Label(s, "GameFontDisableSmall", PAD, -34, CONTENT_W)
end

local function CreateSeenSection(d)
  local s = CreateSection(d, 44)
  d.seenSec = s
  Label(s, "GameFontNormal", PAD, 0, CONTENT_W):SetText("Last seen")
  d.seenLine = Label(s, "GameFontHighlightSmall", PAD, -16, CONTENT_W)
  d.seenZone = Label(s, "GameFontDisableSmall", PAD, -30, CONTENT_W)
end

local function SendVote(el, value)
  if not GG.Vote or not GG.MyVote or not el.note then return end
  if GG:MyVote(el.note) == value then value = 0 end -- clicking your own vote again takes it back
  GG:Vote(el.entryName, el.note.id, value)
  GG:RefreshUI()
end

-- The current vote shows at full strength and tinted, the other arrow dims.
local function StyleArrow(button, active, r, g, b)
  local tex = button:GetNormalTexture()
  if tex then
    if active then tex:SetVertexColor(r, g, b) else tex:SetVertexColor(1, 1, 1) end
  end
  button:SetAlpha(active and 1 or 0.85)
end

local function CreateArrow(parent, atlas, value, el)
  local b = CreateFrame("Button", nil, parent)
  -- The arrow art is 17x11, so a smaller button blurs it.
  b:SetSize(17, 11)
  if b.SetNormalAtlas then b:SetNormalAtlas(atlas) end
  if b.SetHighlightAtlas then b:SetHighlightAtlas(atlas) end
  b:SetScript("OnClick", function() SendVote(el, value) end)
  Tip(b, value == 1 and "Vote up" or "Vote down")
  return b
end

local function CreateVoteControl(el)
  local v = CreateFrame("Frame", nil, el)
  v:SetWidth(VOTE_W - 2)
  v:SetPoint("TOPRIGHT", -2, -1)
  v:SetPoint("BOTTOMRIGHT", -2, 1)
  v.up = CreateArrow(v, ARROW_UP, 1, el)
  v.up:SetPoint("TOP")
  v.down = CreateArrow(v, ARROW_DOWN, -1, el)
  v.down:SetPoint("BOTTOM")
  v.score = v:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  v.score:SetPoint("CENTER")
  v.score:SetWidth(VOTE_W - 2)
  v.score:SetJustifyH("CENTER")
  return v
end

local function SetScoreColor(fs, score)
  if score > 0 then fs:SetTextColor(0.4, 1, 0.4)
  elseif score < 0 then fs:SetTextColor(1, 0.4, 0.4)
  else fs:SetTextColor(0.5, 0.5, 0.5) end
end

local function UpdateVote(el, data)
  el.vote:SetShown(data.voting and true or false)
  if not data.voting then return end
  el.vote.score:SetText(data.score)
  SetScoreColor(el.vote.score, data.score)
  -- Your own note cannot be voted on, but its score still shows.
  el.vote.up:SetShown(not data.own)
  el.vote.down:SetShown(not data.own)
  StyleArrow(el.vote.up, data.myVote == 1, 0.4, 1, 0.4)
  StyleArrow(el.vote.down, data.myVote == -1, 1, 0.4, 0.4)
end

local function InitNote(el, data)
  if not el.created then
    el.created = true
    el.bg = el:CreateTexture(nil, "BACKGROUND")
    el.bg:SetAllPoints()
    el.bg:SetColorTexture(1, 1, 1, 0.04)
    el.text = el:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    el.text:SetJustifyH("LEFT")
    el.text:SetJustifyV("TOP")
    el.meta = el:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    el.meta:SetJustifyH("LEFT")
    el.meta:SetWordWrap(false)
    el.star = el:CreateTexture(nil, "ARTWORK")
    el.star:SetSize(14, 14)
    el.star:SetPoint("TOPLEFT", 4, -3)
    el.star:SetAtlas("friends-icon-favorites")
    el.vote = CreateVoteControl(el)
  end
  el.note, el.entryName = data.note, data.entryName
  el.bg:SetShown(data.index % 2 == 0)
  -- The star pushes only this note's text right; the meta line stays under the left edge.
  local shift = data.first and STAR_W or 0
  local width = data.voting and TEXT_W or NOTE_W
  el.star:SetShown(data.first and true or false)
  el.text:ClearAllPoints()
  el.text:SetPoint("TOPLEFT", 4 + shift, -3)
  el.text:SetWidth(width - shift)
  el.meta:ClearAllPoints()
  el.meta:SetPoint("TOPLEFT", el.text, "BOTTOMLEFT", -shift, -1)
  el.meta:SetWidth(width)
  el.text:SetText(data.text)
  el.meta:SetText(data.meta)
  UpdateVote(el, data)
end

local function CreateNotesSection(d)
  local s = CreateFrame("Frame", nil, d)
  s:SetWidth(DETAIL_W)
  d.notesSec = s
  d.notesHeading = Label(s, "GameFontNormal", PAD, 0, CONTENT_W)
  local line = s:CreateTexture()
  line:SetColorTexture(1, 1, 1, 0.15)
  line:SetPoint("TOPLEFT", PAD, -16)
  line:SetPoint("TOPRIGHT", -PAD, -16)
  line:SetHeight(1)

  local box = CreateFrame("Frame", nil, s, "WowScrollBoxList")
  box:SetPoint("TOPLEFT", PAD, -20)
  box:SetPoint("BOTTOMRIGHT", -22, 0)
  local bar = CreateFrame("EventFrame", nil, s, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 2, 0)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 2, 0)
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("Frame", InitNote)
  view:SetElementExtentCalculator(function(_, el) return el.height end)
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  if ScrollUtil.AddManagedScrollBarVisibilityBehavior then
    ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar)
  end
  d.notesBox = box

  d.measureText = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.measureText:SetWidth(NOTE_W)
  d.measureText:SetJustifyH("LEFT")
  d.measureText:Hide()
  d.measureMeta = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  d.measureMeta:SetWidth(NOTE_W)
  d.measureMeta:SetWordWrap(false)
  d.measureMeta:Hide()
end

local function CreateDetailWidgets(d)
  CreateHeader(d)
  CreateBountySection(d)
  CreateSeenSection(d)
  CreateNotesSection(d)

  d.hint = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  d.hint:SetPoint("CENTER")
  d.hint:SetText("Select a player to see all notes.")

  d.always = { d.header, d.notesSec }
  d.playerOnly = {}
end

local function AddDetailButton(d, x, width, label, onClick)
  local b = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetPoint("BOTTOMLEFT", x, 10)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  d.playerOnly[#d.playerOnly + 1] = b
  return b
end

local function BuildDetail(f)
  local d = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  d:SetPoint("TOPLEFT", f.Inset, "TOPRIGHT", 4, 0)
  d:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -60)
  d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 26)
  CreateDetailWidgets(d)

  -- 80 + 112 + 80 plus two 6px gaps is 284, so the row starts 6px in from the left edge.
  d.addButton = AddDetailButton(d, 6, 80, "Add note", function()
    if d.entry then GG:PromptNote(d.entry.name) end
  end)
  d.bountyButton = AddDetailButton(d, 92, 112, "Post bounty", function()
    local e = d.entry
    if not e then return end
    if GG:ActiveBounty(e) then GG:ClearBounty(e.name) else GG:PromptBounty(e.name) end
  end)
  d.claimButton = AddDetailButton(d, 210, 80, "Claim", function()
    if d.entry then GG:TryClaim(d.entry.name, true) end
  end)
  f.detail = d
end

local function BuildTabs(f)
  f.tab = 1
  for i, label in ipairs(TABS) do
    local t = CreateFrame("Button", "GuildGrudgeFrameTab" .. i, f, "PanelTabButtonTemplate")
    t:SetID(i)
    t:SetText(label)
    if i == 1 then t:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 5, 2) end
    t:SetScript("OnClick", function(self)
      f.tab = self:GetID()
      PanelTemplates_SetTab(f, f.tab)
      f.selected = nil
      GG:RefreshUI()
    end)
  end
  PanelTemplates_SetNumTabs(f, #TABS)
  PanelTemplates_SetTab(f, 1)
end

local function Build()
  local f = CreateFrame("Frame", "GuildGrudgeFrame", UIParent, "ButtonFrameTemplate")
  f:SetSize(640, 480)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "GuildGrudgeFrame") -- Escape closes it

  if f.SetTitle then f:SetTitle("Guild Grudge") end
  if f.SetPortraitToAsset then f:SetPortraitToAsset(ICON .. "Ability_Hunter_SniperShot") end
  -- Icon files carry their own border, so crop it to sit centred in the round mask.
  if f.SetPortraitTexCoord then f:SetPortraitTexCoord(0.08, 0.92, 0.08, 0.92) end

  BuildToolbar(f)
  BuildList(f)
  BuildDetail(f)
  BuildTabs(f)

  f:SetScript("OnShow", function() GG:RefreshUI() end)

  -- Only the portrait depends on these events, so the list is not rebuilt.
  local watcher = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_PORTRAIT_UPDATE" }) do
    pcall(watcher.RegisterEvent, watcher, event)
  end
  watcher:SetScript("OnEvent", function()
    if f:IsShown() and f.detail.entry then UpdatePortrait(f.detail) end
  end)
  f:Hide()
  return f
end

function GG:ToggleUI()
  frame = frame or Build()
  frame:SetShown(not frame:IsShown())
end

function GG:RefreshUI()
  if not frame or not frame:IsShown() then return end
  local tab = frame.tab
  local all = tab == 3 and HunterList() or WantedList(tab == 2)

  -- The selection survives a search that hides it, but not a deleted or claimed entry.
  local selected
  for _, el in ipairs(all) do
    if el.key == frame.selected then selected = el; break end
  end
  if not selected then frame.selected = nil end

  local filter = strlower(strtrim(frame.search:GetText() or ""))
  local list = {}
  for _, el in ipairs(all) do
    if Matches(el, filter) then
      list[#list + 1] = el
      el.index = #list
    end
  end

  local dp = CreateDataProvider()
  for _, el in ipairs(list) do dp:Insert(el) end
  frame.box:SetDataProvider(dp, ScrollBoxConstants.RetainScrollPosition)

  if #list == 0 then
    frame.empty:SetText(filter ~= "" and "No matches." or EMPTY_TEXT[tab])
    frame.empty:Show()
  else
    frame.empty:Hide()
  end
  UpdateDetail(frame.detail, selected)
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
