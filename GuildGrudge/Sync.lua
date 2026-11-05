-- Guild Grudge: sharing data between guildies through hidden addon messages
--
-- Message formats (fields separated by ^, first field = type, second = protocol version):
--   N^1^key^name^^class^id^author^ts^deleted^zone^text^tag  a note (new, edited or deleted); tag is optional
--   B^1^key^name^^poster^ts^claimedBy^claimedTs^reward      a bounty (posted, claimed or removed)
--   V^1^key^name^^noteId^voter^v^ts                         a vote on a note (v = 1, -1 or 0 for removed)
--   G^1^key^name^^voter^v^ts                                a vote on a nice name (v = 1, -1 or 0 for removed)
--   S^1^key^name^^class^zone                                "I just spotted this player"
--   P^1^key^name^^class^raceFile^race^sex^level^ts          a player's class, race, sex and level (newest ts wins)
--   L^1^key^name^^list^ts                                   which list a player is on (list = wanted, watch or kudos; newest ts wins)
--   F^1^key^name^^by^ts^deleted^class^race^raceFile^sex^level  a nice name (added or removed; newest ts wins)
--   H^1^since                                               "send me everything newer than <since>"
--   D^1^requester                                           "I'm answering that request, others can relax"
-- The empty fifth field used to be the realm. Receivers rebuild the key from name.
local ADDON, GG = ...

local SEP, PROTO = "^", "1"
local queue, ticker = {}, nil
local roster = {}       -- guild members, as GG:Who() spells them
local rosterClass = {}  -- guild members -> class file name
local handled = {}      -- requester -> time someone started answering them
local lastSpotMsg = {}  -- key -> time we last printed a "spotted" message from a guildie
local lastProfileSend = {} -- key -> time we last sent a profile (P) for it
local PROFILE_INTERVAL = 300

local function join(...)
  local t = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    t[i] = v == nil and "" or tostring(v)
  end
  return table.concat(t, SEP)
end

local function nz(s) if s ~= "" then return s end end

---------------------------------------------------------------------------
-- Sending
-- Blizzard allows 10 addon messages per prefix and refills 1 per second, on
-- every channel. Anything past that is dropped, so send 1 per second and keep
-- a message queued until the server takes it.
---------------------------------------------------------------------------
local SEND_INTERVAL = 1

local function pump()
  local m = queue[1]
  if not m then
    if ticker then ticker:Cancel(); ticker = nil end
    return
  end
  -- Dungeons, raids and PvP matches block addon messages; wait them out.
  if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
  local result = C_ChatInfo.SendAddonMessage(GG.PREFIX, m[1], m[2], m[3])
  local R = Enum and Enum.SendAddonMessageResult
  if R and (result == R.AddonMessageThrottle or result == R.ChannelThrottle) then return end
  table.remove(queue, 1)
end

function GG:Send(msg, channel, target)
  channel = channel or "GUILD"
  if channel == "GUILD" and not IsInGuild() then return end
  queue[#queue + 1] = { msg, channel, target }
  if not ticker then ticker = C_Timer.NewTicker(SEND_INTERVAL, pump) end
end

function GG:QueueLength() return #queue end

function GG:SendNote(key, e, n, channel, target)
  local head = join("N", PROTO, key, e.name, "", e.class, n.id, n.author, n.ts, n.deleted and 1 or 0, n.zone, "")
  local tag = n.deleted and "" or n.tag or ""
  -- The tag is the last field. Clean() strips ^ from text, so old clients read the text and ignore the tag.
  self:Send(head .. self:Cut(n.deleted and "" or n.text, 250 - #head - #tag - 1) .. SEP .. tag, channel, target)
end

function GG:SendList(key, e, channel, target)
  self:Send(join("L", PROTO, key, e.name, "", e.list or "wanted", e.listTs), channel, target)
end

function GG:SendNiceName(key, n, channel, target)
  self:Send(join("F", PROTO, key, n.name, "", n.by, n.ts, n.deleted and 1 or 0, n.class, n.race, n.raceFile, n.sex, n.level),
    channel, target)
end

function GG:SendBounty(key, e, channel, target)
  local b = e.bounty
  local head = join("B", PROTO, key, e.name, "", b.poster, b.ts, b.claimedBy, b.claimedTs, "")
  self:Send(head .. self:Cut(b.reward, 250 - #head), channel, target)
end

function GG:SendVote(key, e, n, voter, channel, target)
  local vote = n.votes[voter]
  self:Send(join("V", PROTO, key, e.name, "", n.id, voter, vote.v, vote.ts), channel, target)
end

function GG:SendNameVote(key, n, voter, channel, target)
  local vote = n.votes[voter]
  self:Send(join("G", PROTO, key, n.name, "", voter, vote.v, vote.ts), channel, target)
end

function GG:SendSpotted(key, e, zone)
  self:Send(join("S", PROTO, key, e.name, "", e.class, zone), "GUILD")
end

function GG:SendProfile(key, e, channel, target)
  self:Send(join("P", PROTO, key, e.name, "", e.class, e.raceFile, e.race, e.sex, e.level, e.profileTs), channel, target)
end

-- Called by GG:Learn when a profile field changed. Nameplates re-learn constantly, so send at most once per interval.
function GG:ShareProfile(e)
  if not (self:IsListed(e) and IsInGuild()) then return end
  local key = self:MakeKey(e.name)
  if lastProfileSend[key] and GetTime() - lastProfileSend[key] < PROFILE_INTERVAL then return end
  lastProfileSend[key] = GetTime()
  self:SendProfile(key, e, "GUILD")
end

function GG:RequestSync(full)
  -- Ask for a day of overlap so small gaps heal themselves.
  local since = full and 0 or math.max(0, self:MaxTs() - 86400)
  self:Send(join("H", PROTO, since), "GUILD")
end

function GG:DumpTo(target, since)
  for key, e in pairs(self.db.entries) do
    for _, n in pairs(e.notes) do
      if n.ts > since then self:SendNote(key, e, n, "WHISPER", target) end
    end
    if e.bounty and e.bounty.ts > since then self:SendBounty(key, e, "WHISPER", target) end
    -- Profiles go after the notes, because the receiver ignores profiles of players it doesn't know.
    if (e.profileTs or 0) > since then self:SendProfile(key, e, "WHISPER", target) end
    -- The list goes after the notes for the same reason.
    if (e.listTs or 0) > since then self:SendList(key, e, "WHISPER", target) end
    -- Votes go after the notes, because the receiver ignores votes on notes it doesn't know.
    for _, n in pairs(e.notes) do
      for voter, vote in pairs(n.votes or {}) do
        if vote.ts > since then self:SendVote(key, e, n, voter, "WHISPER", target) end
      end
    end
  end
  for key, n in pairs(self.db.names) do
    if n.ts > since then self:SendNiceName(key, n, "WHISPER", target) end
  end
  -- Name votes go after the names, because the receiver ignores votes on names it doesn't know.
  for key, n in pairs(self.db.names) do
    for voter, vote in pairs(n.votes or {}) do
      if vote.ts > since then self:SendNameVote(key, n, voter, "WHISPER", target) end
    end
  end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function entryFor(name, class)
  local e, key = GG:GetEntry(name, true)
  if e and nz(class) and not e.class then e.class = class end
  return e, key
end

local handlers = {}

handlers.N = function(t, channel, sender)
  local e = entryFor(t[4], t[6])
  local ts = tonumber(t[9])
  if not e or not nz(t[7]) or not ts then return end
  local n = { id = t[7], author = t[8], ts = ts, deleted = t[10] == "1" or nil, zone = t[11] or "", text = t[12] or "", tag = nz(t[13]) }
  if GG:MergeNote(e, n) then
    if channel == "GUILD" and not n.deleted and GG:Now() - ts < 300 then
      GG:Print(n.author, "added", GG:ColorName(e) .. ":", (n.tag and ("|cffffcc00[" .. n.tag .. "]|r ") or "") .. n.text)
    end
    GG:Changed()
  end
end

handlers.B = function(t, channel, sender)
  local e = entryFor(t[4])
  local ts = tonumber(t[7])
  if not e or not ts then return end
  local b = { poster = t[6], ts = ts, claimedBy = t[8] or "", claimedTs = tonumber(t[9]) or 0, reward = t[10] or "" }
  if GG:MergeBounty(e, b) then
    if channel == "GUILD" and GG:Now() - ts < 300 then
      if b.claimedBy ~= "" then
        GG:Print("|cffffd100" .. b.claimedBy .. " claimed the bounty on|r", GG:ColorName(e))
      elseif b.reward ~= "" then
        GG:Print("|cffffd100New bounty|r on", GG:ColorName(e) .. ":", b.reward, "(by " .. b.poster .. ")")
      end
    end
    GG:Changed()
  end
end

handlers.V = function(t)
  local e = GG:GetEntry(t[4], false)
  local n = e and e.notes[t[6]]
  local voter, v, ts = nz(t[7]), tonumber(t[8]), tonumber(t[9])
  if not n or not voter or not ts or (v ~= 1 and v ~= -1 and v ~= 0) then return end
  if voter == n.author then return end
  n.votes = n.votes or {}
  local old = n.votes[voter]
  if old and old.ts >= ts then return end
  n.votes[voter] = { v = v, ts = ts }
  GG:Changed()
end

handlers.G = function(t)
  local full = GG:NormalizeName(t[4])
  local n = full and GG.db.names[GG:MakeKey(full)]
  local voter, v, ts = nz(t[6]), tonumber(t[7]), tonumber(t[8])
  if not n or not voter or not ts or (v ~= 1 and v ~= -1 and v ~= 0) then return end
  if voter == n.by then return end
  n.votes = n.votes or {}
  local old = n.votes[voter]
  if old and old.ts >= ts then return end
  n.votes[voter] = { v = v, ts = ts }
  GG:Changed()
end

handlers.P = function(t)
  local e = GG:GetEntry(t[4], false)
  local ts = tonumber(t[11])
  if not e or not ts or ts <= (e.profileTs or 0) then return end
  -- Empty fields never overwrite what we know.
  if nz(t[6]) then e.class = t[6] end
  if nz(t[7]) then e.raceFile = t[7] end
  if nz(t[8]) then e.race = t[8] end
  local sex, level = tonumber(t[9]), tonumber(t[10])
  if sex == 2 or sex == 3 then e.sex = sex end
  if level and level > 0 then e.level = level end
  e.profileTs = ts
  GG:Changed()
end

handlers.L = function(t)
  local e = GG:GetEntry(t[4], false)
  local list, ts = t[6], tonumber(t[7])
  if not e or not ts or ts <= (e.listTs or 0) then return end
  if list ~= "watch" and list ~= "kudos" and list ~= "wanted" then return end
  e.list = list ~= "wanted" and list or nil
  e.listTs = ts
  GG:Changed()
end

handlers.F = function(t)
  local full, ts = GG:NormalizeName(t[4]), tonumber(t[7])
  if not full or not ts then return end
  local key = GG:MakeKey(full)
  local n = GG.db.names[key]
  if n and ts <= n.ts then return end
  if not n then
    n = { name = full }
    GG.db.names[key] = n
  end
  n.by = nz(t[6]) or n.by or "?"
  n.ts = ts
  n.deleted = t[8] == "1" or nil
  -- Empty fields never overwrite what we know.
  if nz(t[9]) then n.class = t[9] end
  if nz(t[10]) then n.race = t[10] end
  if nz(t[11]) then n.raceFile = t[11] end
  local sex, level = tonumber(t[12]), tonumber(t[13])
  if sex == 2 or sex == 3 then n.sex = sex end
  if level and level > 0 then n.level = level end
  GG:Changed()
end

handlers.S =function(t, channel, sender)
  local e, key = GG:GetEntry(t[4], false)
  if not e or not GG:IsListed(e) then return end
  if nz(t[6]) and not e.class then e.class = t[6] end
  local who = GG:Who(sender)
  e.lastSeen, e.lastSeenZone, e.lastSeenBy = GG:Now(), t[7] or "", who
  if GG.db.settings.alerts and (lastSpotMsg[key] or 0) + 120 < GetTime() then
    lastSpotMsg[key] = GetTime()
    GG:Print(GG:ColorName(e), "spotted in", e.lastSeenZone, "by", who)
  end
  GG:Changed()
end

handlers.H = function(t, channel, sender)
  local since = tonumber(t[3]) or 0
  if GG:MaxTs() <= since then return end
  local who = GG:Who(sender)
  -- Wait a random moment; whoever answers first tells the others to stand down.
  C_Timer.After(1 + math.random() * 5, function()
    if handled[who] and GetTime() - handled[who] < 30 then return end
    handled[who] = GetTime()
    GG:Send(join("D", PROTO, who), "GUILD")
    GG:DumpTo(sender, since)
  end)
end

handlers.D = function(t)
  if nz(t[3]) then handled[t[3]] = GetTime() end
end

function GG:OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= self.PREFIX or not self.db then return end
  -- Recorded before the self-check so one account can see its own echo in /gg debug.
  self.lastSender = sender
  local who = self:Who(sender)
  if not who or who == self:Me() then return end
  -- Only listen to guildies (guild channel, or whispers from roster members).
  if channel ~= "GUILD" and not roster[who] then return end
  local t = { strsplit(SEP, msg) }
  if t[2] ~= PROTO then return end
  -- A tampered client could send chat escape codes (fake links, textures).
  for i = 3, #t do t[i] = self:Clean(t[i]) end
  local h = handlers[t[1]]
  if h then h(t, channel, sender) end
end

function GG:UpdateRoster()
  wipe(roster)
  wipe(rosterClass)
  for i = 1, GetNumGuildMembers() do
    local name, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
    local who = name and self:Who(name)
    if who then
      roster[who] = true
      rosterClass[who] = classFile
    end
  end
end

-- Class file name ("MAGE") of a guildie or ourselves, nil if unknown.
function GG:AuthorClass(name)
  if name and name == self:Me() then return (select(2, UnitClass("player"))) end
  return name and rosterClass[name] or nil
end

function GG:InitSync()
  C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("GUILD_ROSTER_UPDATE")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then GG:OnAddonMessage(...) else GG:UpdateRoster() end
  end)
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
  elseif GuildRoster then GuildRoster() end
  C_Timer.After(15, function() GG:RequestSync(false) end)
end
