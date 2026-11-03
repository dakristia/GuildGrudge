-- Guild Grudge: spotting listed players nearby and auto-claiming bounties
local ADDON, GG = ...

local band = bit.band
local PLAYER  = COMBATLOG_OBJECT_TYPE_PLAYER
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE
local lastAlert, lastShare = {}, {}

function GG:Alert(e)
  if not self.db.settings.alerts then return end
  local head = self:ColorName(e) .. " is nearby!"
  local b = self:ActiveBounty(e)
  if b then head = head .. "  |cffffd100BOUNTY: " .. b.reward .. "|r" end
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, head, ChatTypeInfo["RAID_WARNING"])
  end
  if self.db.settings.sound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
  end
  self:Print(head)
  local notes = self:SortedNotes(e)
  for i = 1, math.min(3, #notes) do
    self:Print("  - " .. notes[i].text, "|cff999999(" .. notes[i].author .. ", " .. self:Age(notes[i].ts) .. ")|r")
  end
end

function GG:Spotted(name, realm, unit)
  local e, key = self:GetEntry(name, realm, false)
  if not e or not self:IsListed(e) then return end

  if unit then -- learn class/race/level when we have a real unit
    e.class = select(2, UnitClass(unit)) or e.class
    e.race  = UnitRace(unit) or e.race
    local lvl = UnitLevel(unit)
    if lvl and lvl > 0 then e.level = lvl end
  end
  e.lastSeen, e.lastSeenZone, e.lastSeenBy = self:Now(), self:Zone(), UnitName("player")

  local now = GetTime()
  if (lastAlert[key] or 0) + self.db.settings.alertCooldown > now then return end
  lastAlert[key] = now
  self:Alert(e)

  if self.db.settings.shareSpotted and IsInGuild() and (lastShare[key] or 0) + 120 < now then
    lastShare[key] = now
    self:SendSpotted(key, e, e.lastSeenZone)
  end
  self:Changed()
end

function GG:CheckUnit(unit)
  if UnitExists(unit) and UnitIsPlayer(unit) then
    local name, realm = UnitName(unit)
    if name then self:Spotted(name, realm or "", unit) end
  end
end

-- The combat log covers anyone fighting or casting near you (roughly 50 yards).
function GG:OnCombatLog(_, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags)
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
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:SetScript("OnEvent", function(_, event, arg1)
  if not GG.db or not next(GG.db.entries) then return end
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    GG:OnCombatLog(CombatLogGetCurrentEventInfo())
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    GG:CheckUnit(arg1)
  elseif event == "PLAYER_TARGET_CHANGED" then
    GG:CheckUnit("target")
  else
    GG:CheckUnit("mouseover")
  end
end)
