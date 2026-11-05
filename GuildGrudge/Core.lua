-- Guild Grudge: core data, helpers and slash commands
local ADDON, GG = ...
_G.GuildGrudge = GG

GG.VERSION  = "0.3.0"
GG.PREFIX   = "GGRUDGE"   -- addon message prefix (max 16 chars)
GG.MAX_NOTE = 120         -- max note length in bytes (addon messages cap at 255)

local DEFAULTS = {
  alerts         = true,  -- raid-warning style alert when a listed player is near
  sound          = true,  -- play a sound with the alert
  shareSpotted   = true,  -- tell the guild when you spot someone on the list
  announceClaims = true,  -- post in guild chat when you claim a bounty
  alertCooldown  = 60,    -- seconds a player must be out of sight before they can alert you again
  minimapButton  = true,  -- show the minimap button
  minimapAngle   = 200,   -- where the minimap button sits, in degrees around the minimap
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function GG:Print(...)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff5533Grudge|r: " .. strjoin(" ", tostringall(...)))
end

function GG:Now()
  return GetServerTime and GetServerTime() or time()
end

-- Strip characters that break our message format or chat escapes.
function GG:Clean(text)
  text = (text or ""):gsub("[%^|\r\n]", " ")
  return strtrim(text)
end

-- Cut a string to maxBytes without leaving half a UTF-8 character at the end.
function GG:Cut(s, maxBytes)
  s = s or ""
  if maxBytes <= 0 then return "" end
  if #s <= maxBytes then return s end
  s = s:sub(1, maxBytes)
  return (s:gsub("[\192-\255][\128-\191]*$", ""))
end

---------------------------------------------------------------------------
-- Names
-- Forever is realmless: a character is "First Surname", unique per region,
-- and the second value of UnitName() is the surname, not a realm. Chat may
-- spell it "First-Surname". Without regional names we keep "Name-Realm".
---------------------------------------------------------------------------
function GG:Regional()
  return RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() or false
end

-- Any spelling of a character -> the form we store and compare.
function GG:NormalizeName(s)
  if type(s) ~= "string" then return nil end
  s = strtrim(s)
  if s == "" then return nil end
  if self:Regional() then
    local first, surname = s:match("^([^%s%-]+)[%s%-]+([^%s%-]+)")
    if first then return first .. " " .. surname end
  end
  return s
end

-- Full name from UnitName()-style parts: (name, surname) or (name, realm).
function GG:FullName(name, second)
  if type(name) ~= "string" or name == "" then return nil end
  if type(second) == "string" and second ~= "" then
    name = name .. (self:Regional() and " " or "-") .. second
  end
  return self:NormalizeName(name)
end

-- Midnight-era clients hide some unit data as "secret values" that addon code
-- can't compare, use as table keys or send. True if any argument is one.
function GG:Secret(...)
  if not issecretvalue then return false end
  for i = 1, select("#", ...) do
    if issecretvalue((select(i, ...))) then return true end
  end
  return false
end

function GG:UnitFullName(unit)
  local name, second = UnitName(unit)
  if self:Secret(name, second) then return nil end
  return self:FullName(name, second)
end

-- Our own name as it appears on notes, bounties and claims.
function GG:Me()
  if self:Regional() then return self:UnitFullName("player") end
  return (UnitName("player"))
end

-- A sender or guild roster name, in the same form as GG:Me().
function GG:Who(s)
  if self:Regional() then return self:NormalizeName(s) end
  return Ambiguate(s, "short")
end

-- Split "<name> <rest>". A Forever name is two words ("Ana Forever") or "Ana-Forever".
function GG:TakeName(msg)
  local first, rest = strsplit(" ", strtrim(msg or ""), 2)
  if self:Regional() and rest and not first:find("-", 1, true) then
    local surname
    surname, rest = strsplit(" ", strtrim(rest), 2)
    first = first .. " " .. surname
  end
  return self:NormalizeName(first), strtrim(rest or "")
end

-- "/gg add Ana camped me" makes "Ana Camped". If that is new and another Ana
-- is listed, the user probably forgot the surname, so say so.
function GG:HintNewName(name)
  if not self:Regional() or not name or self:GetEntry(name, false) then return end
  local other = self:Find(name:match("^[^%s%-]+"))
  if other then self:Print("New player", name .. ". Did you mean", other.name .. "? Use the full name.") end
end

function GG:MakeKey(full)
  return strlower(full)
end

function GG:Zone()
  local z = GetRealZoneText() or ""
  local sub = GetSubZoneText()
  if sub and sub ~= "" and sub ~= z then z = z .. " - " .. sub end
  return self:Cut(self:Clean(z), 40)
end

function GG:Age(ts)
  if not ts or ts == 0 then return "never" end
  local d = math.max(0, self:Now() - ts)
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

function GG:ColorName(e)
  local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
  local name = e.name
  if not c then return "|cffff4040" .. name .. "|r" end
  local hex = c.colorStr or ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
  return "|c" .. hex .. name .. "|r"
end

---------------------------------------------------------------------------
-- Data model
-- GuildGrudgeDB.entries[key] = {        -- key = lowercase full name
--   name, class, race, level,           -- name = "First Surname" (or "Name-Realm")
--   lastSeen, lastSeenZone, lastSeenBy,
--   notes  = { [id] = { id, author, ts, zone, text, deleted } },
--   bounty = { poster, reward, ts, claimedBy, claimedTs }   -- ts = last change
-- }
---------------------------------------------------------------------------
function GG:InitDB()
  GuildGrudgeDB = GuildGrudgeDB or {}
  local db = GuildGrudgeDB
  db.entries  = db.entries or {}
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  self.db = db
end

function GG:GetEntry(name, create)
  local full = self:NormalizeName(name)
  if not full then return end
  local key = self:MakeKey(full)
  local e = self.db.entries[key]
  if not e and create then
    e = { name = full, notes = {} }
    self.db.entries[key] = e
  end
  return e, key
end

-- Lenient lookup for slash commands: "ana" finds "Ana Forever" if she is the only Ana.
function GG:Find(input)
  local e, key = self:GetEntry(input, false)
  if e or not key or key:find("[%s%-]") then return e, key end
  local hit, hitKey
  for k, v in pairs(self.db.entries) do
    if k:match("^[^%s%-]+") == key then
      if hit then return nil, nil, true end -- third value: ambiguous
      hit, hitKey = v, k
    end
  end
  return hit, hitKey
end

function GG:NotFound(input, ambiguous)
  if ambiguous then return self:Print("More than one", input, "on the list. Use the full name.") end
  self:Print(input, "is not on the list.")
end

-- Remember what a real unit tells us about a player.
GG.seenGUIDs = {} -- GUID -> full name, this session only (for PARTY_KILL)
function GG:Learn(e, unit)
  e.name  = self:UnitFullName(unit) or e.name
  local _, class = UnitClass(unit)
  local race, lvl, guid = UnitRace(unit), UnitLevel(unit), UnitGUID(unit)
  if self:Secret(class, race, lvl, guid) then return end
  e.class = class or e.class
  e.race  = race or e.race
  if lvl and lvl > 0 then e.level = lvl end
  if guid then self.seenGUIDs[guid] = e.name end
end

function GG:SortedNotes(e)
  local list = {}
  for _, n in pairs(e.notes) do
    if not n.deleted then list[#list + 1] = n end
  end
  table.sort(list, function(a, b) return a.ts > b.ts end)
  return list
end

function GG:ActiveBounty(e)
  local b = e.bounty
  if b and (b.reward or "") ~= "" and (b.claimedBy or "") == "" then return b end
end

function GG:IsListed(e)
  if self:ActiveBounty(e) then return true end
  for _, n in pairs(e.notes) do
    if not n.deleted then return true end
  end
  return false
end

function GG:MergeNote(e, n)
  local old = e.notes[n.id]
  if old and old.ts >= n.ts then return false end
  e.notes[n.id] = n
  return true
end

function GG:MergeBounty(e, b)
  if e.bounty and e.bounty.ts >= b.ts then return false end
  e.bounty = b
  return true
end

-- Newest timestamp in our data; used to ask the guild only for what we lack.
function GG:MaxTs()
  local max = 0
  for _, e in pairs(self.db.entries) do
    for _, n in pairs(e.notes) do
      if n.ts > max then max = n.ts end
    end
    if e.bounty and e.bounty.ts > max then max = e.bounty.ts end
  end
  return max
end

function GG:Changed()
  if self.RefreshUI then self:RefreshUI() end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function GG:AddNote(name, text, unit)
  text = self:Cut(self:Clean(text), self.MAX_NOTE)
  if text == "" then return self:Print("Write a note, e.g. camped me at the Crossroads FP") end
  local e, key = self:GetEntry(name, true)
  if not e then return self:Print("Usage: /gg add <name> <note>") end
  if unit then self:Learn(e, unit) end
  local me = self:Me()
  local n = {
    id = me .. "-" .. self:Now() .. "-" .. math.random(1000, 9999),
    author = me, ts = self:Now(), zone = self:Zone(), text = text,
  }
  e.notes[n.id] = n
  self:SendNote(key, e, n, "GUILD")
  self:Print("Added", self:ColorName(e) .. ":", text)
  self:Changed()
end

function GG:DeleteMyNotes(input)
  local e, key, ambiguous = self:Find(input)
  if not e then return self:NotFound(input, ambiguous) end
  local me, count = self:Me(), 0
  for _, n in pairs(e.notes) do
    if n.author == me and not n.deleted then
      n.deleted, n.ts = true, self:Now()
      self:SendNote(key, e, n, "GUILD")
      count = count + 1
    end
  end
  self:Print("Removed", count, "of your notes on", self:ColorName(e))
  self:Changed()
end

function GG:SetBounty(input, reward)
  reward = self:Cut(self:Clean(reward), 100)
  if reward == "" then return self:Print("Usage: /gg bounty <name> <reward>") end
  local e, key = self:Find(input)
  if not e then e, key = self:GetEntry(input, true) end
  if not e then return self:Print("Usage: /gg bounty <name> <reward>") end
  e.bounty = { poster = self:Me(), reward = reward, ts = self:Now(), claimedBy = "", claimedTs = 0 }
  self:SendBounty(key, e, "GUILD")
  self:Print("Bounty posted on", self:ColorName(e) .. ":", reward)
  self:Changed()
end

function GG:ClearBounty(input)
  local e, key = self:Find(input)
  if not (e and e.bounty) then return self:Print("No bounty on", input) end
  e.bounty = { poster = self:Me(), reward = "", ts = self:Now(), claimedBy = "", claimedTs = 0 }
  self:SendBounty(key, e, "GUILD")
  self:Print("Bounty removed from", self:ColorName(e))
  self:Changed()
end

function GG:TryClaim(name, manual)
  local e, key
  if manual then e, key = self:Find(name) else e, key = self:GetEntry(name, false) end
  local b = e and self:ActiveBounty(e)
  if not b then
    if manual then self:Print("No open bounty on", name) end
    return
  end
  local me = self:Me()
  b.claimedBy, b.claimedTs, b.ts = me, self:Now(), self:Now()
  self:SendBounty(key, e, "GUILD")
  self:Print("|cffffd100Bounty claimed!|r", self:ColorName(e), "-", b.reward)
  if self.db.settings.announceClaims and IsInGuild() then
    -- Forever only has the global SendChatMessage as a deprecation shim.
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    send(("[Grudge] %s claimed the bounty on %s: %s"):format(me, e.name, b.reward), "GUILD")
  end
  self:Changed()
end

function GG:Show(input)
  local e, _, ambiguous = self:Find(input)
  if not e then return self:NotFound(input, ambiguous) end
  local info = strtrim(("%s %s %s"):format(e.level and ("lvl " .. e.level) or "", e.race or "", e.class and strlower(e.class) or ""))
  self:Print(self:ColorName(e), info ~= "" and ("(" .. info .. ")") or "")
  local b = self:ActiveBounty(e)
  if b then self:Print("  |cffffd100BOUNTY:|r", b.reward, "(posted by " .. b.poster .. ")") end
  if e.lastSeen then self:Print("  Last seen", self:Age(e.lastSeen), "in", e.lastSeenZone or "?", "by", e.lastSeenBy or "?") end
  for _, n in ipairs(self:SortedNotes(e)) do
    self:Print("  - " .. n.text, "|cff999999(" .. n.author .. ", " .. self:Age(n.ts) .. (n.zone ~= "" and (", " .. n.zone) or "") .. ")|r")
  end
end

function GG:Top()
  local wanted, hunters = {}, {}
  for _, e in pairs(self.db.entries) do
    local c = #self:SortedNotes(e)
    if c > 0 then wanted[#wanted + 1] = { e = e, c = c } end
    if e.bounty and (e.bounty.claimedBy or "") ~= "" then
      hunters[e.bounty.claimedBy] = (hunters[e.bounty.claimedBy] or 0) + 1
    end
  end
  table.sort(wanted, function(a, b) return a.c > b.c end)
  self:Print("|cffffd100Most wanted|r")
  for i = 1, math.min(5, #wanted) do
    self:Print(("  %d. %s - %d notes"):format(i, self:ColorName(wanted[i].e), wanted[i].c))
  end
  local hl = {}
  for name, c in pairs(hunters) do hl[#hl + 1] = { name = name, c = c } end
  table.sort(hl, function(a, b) return a.c > b.c end)
  self:Print("|cffffd100Top bounty hunters|r")
  for i = 1, math.min(5, #hl) do
    self:Print(("  %d. %s - %d bounties"):format(i, hl[i].name, hl[i].c))
  end
end

-- What the live client actually returns for the things we could only guess
-- before launch: name formats, the roster and addon message senders.
function GG:Debug()
  local function q(v) return v == nil and "nil" or ('"' .. tostring(v) .. '"') end
  local name, second = UnitName("player")
  self:Print(("UnitName(\"player\"): %s, %s -> me = %s"):format(q(name), q(second), q(self:Me())))
  self:Print("regional names: " .. tostring(self:Regional()))
  local first = GetNumGuildMembers() > 0 and GetGuildRosterInfo(1) or nil
  self:Print(("roster[1]: %s -> %s"):format(q(first), q(first and self:Who(first))))
  self:Print(("last sender: %s -> %s"):format(q(self.lastSender), q(self.lastSender and self:Who(self.lastSender))))
  local entries = 0
  for _ in pairs(self.db.entries) do entries = entries + 1 end
  self:Print(("interface: %s, combat log API: %s, PARTY_KILL seen: %s"):format(
    tostring(select(4, GetBuildInfo())), CombatLogGetCurrentEventInfo and "yes" or "no", tostring(self.sawPartyKill or false)))
  self:Print(("send queue: %d, entries: %d"):format(self:QueueLength(), entries))
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
  "/gg - open the list",
  "/gg t <note> - add a note on your current target",
  "/gg add <name> <note> - add a note by name",
  "/gg show <name> - print everything on a player",
  "/gg del <name> - remove your own notes on a player",
  "/gg bounty <name> <reward> - post a (fictive) bounty",
  "/gg unbounty <name> - remove a bounty",
  "/gg claim <name> - claim a bounty manually",
  "/gg top - most wanted and top bounty hunters",
  "/gg debug - print name formats and sync state (for bug reports)",
  "/gg sync | fullsync - pull data from online guildies",
  "/gg alerts | sound | spotted | claims - toggle options",
  "/gg options - open the settings panel",
  "/gg macro - put a /gg macro on your cursor",
  "<name> is the full name: Ana Forever or Ana-Forever (show/del/claim also take just Ana)",
}

local TOGGLES = { alerts = "alerts", sound = "sound", spotted = "shareSpotted", claims = "announceClaims" }

SLASH_GUILDGRUDGE1 = "/gg"
SLASH_GUILDGRUDGE2 = "/grudge"
SlashCmdList.GUILDGRUDGE = function(msg)
  local cmd, rest = strsplit(" ", strtrim(msg or ""), 2)
  cmd = strlower(cmd or "")
  rest = rest or ""

  if cmd == "" or cmd == "list" then
    GG:ToggleUI()
  elseif cmd == "t" or cmd == "target" then
    if not UnitIsPlayer("target") then return GG:Print("Target a player first.") end
    local name = GG:UnitFullName("target")
    if not name then return GG:Print("Can't read that player's name here. Use /gg add <name> <note>.") end
    GG:AddNote(name, rest, "target")
  elseif cmd == "add" then
    local name, note = GG:TakeName(rest)
    if not name then return GG:Print("Usage: /gg add <name> <note>") end
    GG:HintNewName(name)
    GG:AddNote(name, note)
  elseif cmd == "show" then
    GG:Show(rest)
  elseif cmd == "del" or cmd == "remove" then
    GG:DeleteMyNotes(rest)
  elseif cmd == "bounty" then
    local name, reward = GG:TakeName(rest)
    GG:HintNewName(name)
    GG:SetBounty(name, reward)
  elseif cmd == "unbounty" then
    GG:ClearBounty(rest)
  elseif cmd == "claim" then
    GG:TryClaim(rest, true)
  elseif cmd == "debug" then
    GG:Debug()
  elseif cmd == "options" or cmd == "config" then
    GG:OpenSettings()
  elseif cmd == "macro" then
    GG:MakeMacro()
  elseif cmd == "top" then
    GG:Top()
  elseif cmd == "sync" or cmd == "fullsync" then
    GG:RequestSync(cmd == "fullsync")
    GG:Print("Asked online guildies for updates.")
  elseif TOGGLES[cmd] then
    local k = TOGGLES[cmd]
    GG.db.settings[k] = not GG.db.settings[k]
    GG:Print(cmd, GG.db.settings[k] and "|cff40ff40on|r" or "|cffff4040off|r")
  else
    for _, line in ipairs(HELP) do GG:Print(line) end
  end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    GG:InitDB()
  elseif event == "PLAYER_LOGIN" then
    GG:InitSync()
    GG:Print("v" .. GG.VERSION .. " loaded. Type /gg help")
  end
end)
