-- Guild Grudge: core data, helpers and slash commands
local ADDON, GG = ...
_G.GuildGrudge = GG

GG.VERSION  = "0.1.0"
GG.PREFIX   = "GGRUDGE"   -- addon message prefix (max 16 chars)
GG.MAX_NOTE = 120         -- max note length in bytes (addon messages cap at 255)

local DEFAULTS = {
  alerts         = true,  -- raid-warning style alert when a listed player is near
  sound          = true,  -- play a sound with the alert
  shareSpotted   = true,  -- tell the guild when you spot someone on the list
  announceClaims = true,  -- post in guild chat when you claim a bounty
  alertCooldown  = 60,    -- seconds before the same player can alert you again
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

function GG:SplitName(full)
  local name, realm = strsplit("-", full or "", 2)
  if realm == "" then realm = nil end
  return name, realm
end

function GG:MakeKey(name, realm)
  local key = strlower(name)
  if realm and realm ~= "" then key = key .. "-" .. strlower(realm) end
  return key
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
  local name = e.name .. (e.realm and ("-" .. e.realm) or "")
  if not c then return "|cffff4040" .. name .. "|r" end
  local hex = c.colorStr or ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
  return "|c" .. hex .. name .. "|r"
end

---------------------------------------------------------------------------
-- Data model
-- GuildGrudgeDB.entries[key] = {
--   name, realm, class, race, level,
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

function GG:GetEntry(name, realm, create)
  if not name or name == "" then return end
  if not realm then name, realm = self:SplitName(name) end
  if realm == "" then realm = nil end
  local key = self:MakeKey(name, realm)
  local e = self.db.entries[key]
  if not e and create then
    e = { name = name, realm = realm, notes = {} }
    self.db.entries[key] = e
  end
  return e, key
end

-- Lenient lookup for slash commands: "gankmaster" finds "Gankmaster-SomeRealm".
function GG:Find(input)
  local e, key = self:GetEntry(input, nil, false)
  if e then return e, key end
  if not input:find("-", 1, true) then
    local want = strlower(input)
    for k, v in pairs(self.db.entries) do
      if strlower(v.name) == want then return v, k end
    end
  end
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
function GG:AddNote(name, realm, text, unit)
  text = self:Cut(self:Clean(text), self.MAX_NOTE)
  if text == "" then return self:Print("Write a note, e.g. camped me at the Crossroads FP") end
  local e, key = self:GetEntry(name, realm, true)
  if unit then
    e.class = select(2, UnitClass(unit)) or e.class
    e.race  = UnitRace(unit) or e.race
    local lvl = UnitLevel(unit)
    if lvl and lvl > 0 then e.level = lvl end
  end
  local me = UnitName("player")
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
  local e, key = self:Find(input)
  if not e then return self:Print(input, "is not on the list.") end
  local me, count = UnitName("player"), 0
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
  if not e then e, key = self:GetEntry(input, nil, true) end
  e.bounty = { poster = UnitName("player"), reward = reward, ts = self:Now(), claimedBy = "", claimedTs = 0 }
  self:SendBounty(key, e, "GUILD")
  self:Print("Bounty posted on", self:ColorName(e) .. ":", reward)
  self:Changed()
end

function GG:ClearBounty(input)
  local e, key = self:Find(input)
  if not (e and e.bounty) then return self:Print("No bounty on", input) end
  e.bounty = { poster = UnitName("player"), reward = "", ts = self:Now(), claimedBy = "", claimedTs = 0 }
  self:SendBounty(key, e, "GUILD")
  self:Print("Bounty removed from", self:ColorName(e))
  self:Changed()
end

function GG:TryClaim(name, manual)
  local e, key
  if manual then e, key = self:Find(name) else e, key = self:GetEntry(name, nil, false) end
  local b = e and self:ActiveBounty(e)
  if not b then
    if manual then self:Print("No open bounty on", name) end
    return
  end
  local me = UnitName("player")
  b.claimedBy, b.claimedTs, b.ts = me, self:Now(), self:Now()
  self:SendBounty(key, e, "GUILD")
  self:Print("|cffffd100Bounty claimed!|r", self:ColorName(e), "-", b.reward)
  if self.db.settings.announceClaims and IsInGuild() then
    SendChatMessage(("[Grudge] %s claimed the bounty on %s: %s"):format(me, e.name, b.reward), "GUILD")
  end
  self:Changed()
end

function GG:Show(input)
  local e = self:Find(input)
  if not e then return self:Print(input, "is not on the list.") end
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
  "/gg sync | fullsync - pull data from online guildies",
  "/gg alerts | sound | spotted | claims - toggle options",
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
    local name, realm = UnitName("target")
    GG:AddNote(name, realm, rest, "target")
  elseif cmd == "add" then
    local name, note = strsplit(" ", rest, 2)
    if not name or name == "" then return GG:Print("Usage: /gg add <name> <note>") end
    GG:AddNote(name, nil, note)
  elseif cmd == "show" then
    GG:Show(rest)
  elseif cmd == "del" or cmd == "remove" then
    GG:DeleteMyNotes(rest)
  elseif cmd == "bounty" then
    local name, reward = strsplit(" ", rest, 2)
    GG:SetBounty(name or "", reward)
  elseif cmd == "unbounty" then
    GG:ClearBounty(rest)
  elseif cmd == "claim" then
    GG:TryClaim(rest, true)
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
