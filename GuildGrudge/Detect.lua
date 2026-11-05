-- Guild Grudge: spotting listed players nearby and auto-claiming bounties
--
-- Forever runs the Retail (Midnight) API: addons cannot read the combat log,
-- so detection uses nameplates, target and mouseover, and bounty claims use
-- the PARTY_KILL event. The combat log path only loads on clients that still
-- have CombatLogGetCurrentEventInfo (Classic Era).
local ADDON, GG = ...

local lastSighting, lastShare = {}, {}

local lastGroup = {} -- full names in our group at the last roster update

local function raidWarning(self, head)
  local color = ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]
  if RaidWarningUtil and RaidWarningUtil.AddMessage then
    RaidWarningUtil.AddMessage(head, color)
  elseif RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, head, color)
  end
  if self.db.settings.sound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
  end
end

local function printTopNotes(self, e)
  local notes = self:SortedNotes(e)
  for i = 1, math.min(3, #notes) do
    self:Print("  - " .. notes[i].text, "|cff999999(" .. notes[i].author .. ", " .. self:Age(notes[i].ts) .. ")|r")
  end
end

local function tagText(self, e)
  local s = ""
  for _, tag in ipairs(self:EntryTags(e)) do s = s .. " |cffffcc00[" .. tag .. "]|r" end
  return s
end

function GG:Alert(e)
  if not self.db.settings.alerts then return end
  local head = self:ColorName(e) .. " is nearby!"
  local b = self:ActiveBounty(e)
  if b then head = head .. "  |cffffd100BOUNTY: " .. b.reward .. "|r" end
  raidWarning(self, head)
  self:Print(head)
  printTopNotes(self, e)
end

function GG:WatchAlert(e)
  local head = "|cffffcc00Watch list:|r " .. self:ColorName(e) .. " joined your group" .. tagText(self, e)
  raidWarning(self, head)
  self:Print(head)
  printTopNotes(self, e)
end

function GG:Spotted(name, unit)
  local e, key = self:GetEntry(name, false)
  if not e or not self:IsListed(e) then return end

  if unit then self:Learn(e, unit) end -- class/race/level/GUID when we have a real unit
  e.lastSeen, e.lastSeenZone, e.lastSeenBy = self:Now(), self:Zone(), self:Me()

  -- Every sighting restarts the cooldown, so a player who keeps running in and
  -- out of view alerts once, and again only after being unseen for a while.
  local now = GetTime()
  local quiet = (lastSighting[key] or -math.huge) + self.db.settings.alertCooldown <= now
  lastSighting[key] = now
  if self:IsWatch(e) then
    if not quiet then return end
    if self.db.settings.watchNearby then
      self:Print(self:ColorName(e) .. " from your watch list is nearby" .. tagText(self, e))
    end
    return self:Changed()
  end
  if not quiet then return end
  self:Alert(e)

  if self.db.settings.shareSpotted and IsInGuild() and (lastShare[key] or 0) + 120 < now then
    lastShare[key] = now
    self:SendSpotted(key, e, e.lastSeenZone)
  end
  self:Changed()
end

-- Warn once when a watch-list player joins the group; leaving and rejoining warns again.
function GG:CheckGroup()
  local current = {}
  local function add(unit)
    local full = self:UnitFullName(unit)
    if not full then return end
    current[full] = true
    if lastGroup[full] then return end
    local e = self:GetEntry(full, false)
    if e and self:IsWatch(e) and self:IsListed(e) then
      self:Learn(e, unit)
      if self.db.settings.watchGroup then self:WatchAlert(e) end
    end
  end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do add("raid" .. i) end
  else
    for i = 1, 4 do add("party" .. i) end
  end
  lastGroup = current
end

function GG:CheckUnit(unit)
  if UnitExists(unit) and UnitIsPlayer(unit) then
    local full = self:UnitFullName(unit)
    if full then self:Spotted(full, unit) end
  end
end

-- PARTY_KILL: someone in your group got a killing blow.
function GG:OnPartyKill(attackerGUID, targetGUID)
  self.sawPartyKill = true -- for /gg debug: proves the event fires at all
  if not attackerGUID or not targetGUID or self:Secret(attackerGUID, targetGUID) then return end
  if attackerGUID ~= UnitGUID("player") then return end
  local full = self.seenGUIDs[targetGUID]
  if not full and GetPlayerInfoByGUID then
    local _, _, _, _, _, name, second = GetPlayerInfoByGUID(targetGUID)
    if not self:Secret(name, second) then full = self:FullName(name, second) end
  end
  if full then self:TryClaim(full) end
end

-- Classic Era only. The combat log covers anyone fighting or casting near you (roughly 50 yards).
function GG:OnCombatLog(_, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags)
  local band, PLAYER, HOSTILE = bit.band, COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_REACTION_HOSTILE
  if srcName and srcFlags and band(srcFlags, PLAYER) > 0 and band(srcFlags, HOSTILE) > 0 then
    self:Spotted(srcName)
  end
  if dstName and dstFlags and band(dstFlags, PLAYER) > 0 and band(dstFlags, HOSTILE) > 0 then
    self:Spotted(dstName)
    if sub == "PARTY_KILL" and srcGUID == UnitGUID("player") then
      self:TryClaim(dstName)
    end
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
-- Registering an event the client does not know throws, so try these one by one.
pcall(f.RegisterEvent, f, "PARTY_KILL")
pcall(f.RegisterEvent, f, "GROUP_ROSTER_UPDATE")
if CombatLogGetCurrentEventInfo then
  pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
end
f:SetScript("OnEvent", function(_, event, arg1, arg2)
  if not GG.db then return end
  if event == "GROUP_ROSTER_UPDATE" then return GG:CheckGroup() end
  if not next(GG.db.entries) then return end
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    GG:OnCombatLog(CombatLogGetCurrentEventInfo())
  elseif event == "PARTY_KILL" then
    GG:OnPartyKill(arg1, arg2)
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    GG:CheckUnit(arg1)
  elseif event == "PLAYER_TARGET_CHANGED" then
    GG:CheckUnit("target")
  else
    GG:CheckUnit("mouseover")
  end
end)
