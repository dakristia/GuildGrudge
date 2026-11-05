-- Minimal fake WoW client for running the addon outside the game (Lua 5.1).
-- Each client gets its own global environment; all clients share one clock
-- and one guild "network" that delivers addon messages between them.
local M = {}

M.now = 1000            -- GetTime() clock, shared by all clients
M.serverTime = 1800000000
M.clients = {}
M.log = { sent = 0, throttled = 0, tooLong = 0, delivered = 0 }

-- Throttle as documented for 10.2.7+: 10 messages per prefix, +1 per second.
local THROTTLE_MAX, THROTTLE_REGEN = 10, 1

local function strsplit(sep, s, limit)
  local out, start = {}, 1
  while true do
    if limit and #out == limit - 1 then out[#out + 1] = s:sub(start); break end
    local i = s:find(sep, start, true)
    if not i then out[#out + 1] = s:sub(start); break end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + #sep
  end
  return unpack(out)
end

local function band(a, b)
  local r, bitv = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
    a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
  end
  return r
end

-- Any method call on a stub succeeds and returns nil (or another stub for Create*).
local function stub(name)
  local t = { __name = name, scripts = {}, shown = false, text = "" }
  return setmetatable(t, { __index = function(_, k)
    return function(self, ...)
      if k == "SetScript" then local s, fn = ...; self.scripts[s] = fn
      elseif k == "Show" then self.shown = true
      elseif k == "Hide" then self.shown = false
      elseif k == "SetShown" then self.shown = ...
      elseif k == "IsShown" then return self.shown
      elseif k == "SetText" then self.text = ...
      elseif k == "GetText" then return self.text
      elseif k == "GetStringHeight" then return 10
      elseif k:find("^Create") then return stub(k) end
    end
  end })
end

function M.newClient(opts)
  local c = { name = opts.name, surname = opts.surname, realm = opts.realm,
              events = {}, timers = {}, throttle = {}, chat = {}, errors = {} }
  c.full = opts.full or (opts.surname and (opts.name .. " " .. opts.surname))
        or (opts.name .. (opts.realm and ("-" .. opts.realm) or ""))
  c.guid = "Player-" .. c.full
  c.class = opts.class or "WARRIOR"
  -- How the server spells this character in chat events and the guild roster.
  -- The live client sends "Ana Smith" for whispers and the roster. Tests still try "Ana-Smith" too.
  c.wire = opts.wire or c.full
  local forbidEvents = opts.forbidEvents or (opts.forever and { COMBAT_LOG_EVENT_UNFILTERED = true })
  local env = {}
  c.env = env

  local function register(frame, event)
    if forbidEvents and forbidEvents[event] then
      error("Frame:RegisterEvent(): " .. event .. " is restricted", 2)
    end
    c.events[event] = c.events[event] or {}
    table.insert(c.events[event], frame)
  end

  local api = {
    strsplit = strsplit,
    strjoin = function(sep, ...) return table.concat({ ... }, sep) end,
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
    strlower = string.lower,
    tostringall = function(...)
      local t = {}
      for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
      return unpack(t, 1, select("#", ...))
    end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    tinsert = table.insert,
    bit = { band = band },
    time = function() return M.serverTime end,
    GetTime = function() return M.now end,
    GetServerTime = function() return M.serverTime end,
    GetBuildInfo = function() return "1.60.1", "70755", "Nov 3 2026", 16001 end,
    COMBATLOG_OBJECT_TYPE_PLAYER = 0x400,
    COMBATLOG_OBJECT_REACTION_HOSTILE = 0x40,
    CombatLogGetCurrentEventInfo = opts.combatLogApi,
    RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" } },
    ChatTypeInfo = { RAID_WARNING = {} },
    SOUNDKIT = { RAID_WARNING = 8959 },
    PlaySound = function() end,
    RaidNotice_AddMessage = function(_, text) table.insert(c.chat, "RW: " .. text) end,
    RaidWarningFrame = stub("RaidWarningFrame"),
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(c.chat, msg) end },
    UIParent = stub("UIParent"),
    GameTooltip = stub("GameTooltip"),
    UISpecialFrames = {},
    SlashCmdList = {},
    Enum = { TooltipDataType = { Unit = 2 } },
    TooltipDataProcessor = { AddTooltipPostCall = function() end },
    GetRealZoneText = function() return opts.zone or "Barrens" end,
    GetSubZoneText = function() return opts.subzone or "" end,
    IsInGuild = function() return true end,
    GetNumGuildMembers = function() return #M.clients end,
    GetGuildRosterInfo = function(i)
      local o = M.clients[i]
      if o then return o.wire, nil, nil, nil, nil, nil, nil, nil, nil, nil, o.class end
    end,
    -- The real call answers asynchronously with GUILD_ROSTER_UPDATE.
    C_GuildInfo = { GuildRoster = function()
      table.insert(c.timers, { at = M.now + 0.5, fn = function() M.fire(c, "GUILD_ROSTER_UPDATE") end })
    end },
    Ambiguate = opts.ambiguate or function(full, ctx) return (strsplit("-", full)) end,
    UnitName = function(unit)
      if unit == "player" then return c.name, c.surname or c.realm end
      local u = c.units and c.units[unit]
      if u then return u.name, u.second end
    end,
    UnitIsPlayer = function(unit) return unit == "player" or (c.units and c.units[unit] ~= nil) end,
    UnitExists = function(unit) return unit == "player" or (c.units and c.units[unit] ~= nil) end,
    UnitClass = function(unit)
      if unit == "player" then return c.class, c.class end
      local u = c.units and c.units[unit]; if u then return u.class, u.class end
    end,
    UnitRace = function(unit) local u = c.units and c.units[unit]; if u then return u.race, u.raceFile end end,
    UnitSex = function(unit) local u = c.units and c.units[unit]; return u and u.sex or 1 end,
    UnitLevel = function(unit) local u = c.units and c.units[unit]; return u and u.level or 0 end,
    UnitGUID = function(unit)
      if unit == "player" then return c.guid end
      local u = c.units and c.units[unit]
      return u and u.guid
    end,
    GetPlayerInfoByGUID = function(guid)
      local u = M.guids[guid]
      if u then return u.class, u.class, u.race, u.race, 2, u.name, u.second or "" end
    end,
    SendChatMessage = function(msg, chan) table.insert(M.guildChat, msg) end,
    CreateFrame = function(kind, name)
      local f = stub(kind)
      f.RegisterEvent = register
      return f
    end,
    C_Timer = {
      After = function(d, fn) table.insert(c.timers, { at = M.now + d, fn = fn }) end,
      NewTicker = function(d, fn)
        local t = { at = M.now + d, fn = fn, every = d }
        t.Cancel = function() t.cancelled = true end
        table.insert(c.timers, t)
        return t
      end,
    },
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function() end,
      SendAddonMessage = function(prefix, msg, channel, target) return M.send(c, prefix, msg, channel, target) end,
    },
  }
  for k, v in pairs(api) do env[k] = v end
  -- Forever (build 1.60.1): two-part names, no combat log API, only the new
  -- raid-warning and chat functions, and send results as enum codes.
  if opts.forever then
    env.RegionalUniqueNamesEnabled = function() return true end
    env.CombatLogGetCurrentEventInfo = nil
    env.RaidNotice_AddMessage = nil
    env.SendChatMessage = nil
    env.RaidWarningUtil = { AddMessage = function(text) table.insert(c.chat, "RW: " .. text) end }
    env.C_ChatInfo.SendChatMessage = function(msg, chan) table.insert(M.guildChat, msg) end
    env.Enum.SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 }
  end
  if opts.override then for k, v in pairs(opts.override) do env[k] = v end end
  setmetatable(env, { __index = _G })
  env._G = env

  c.ns = {}
  for _, file in ipairs({ "Core.lua", "Sync.lua", "Detect.lua", "UI.lua", "Options.lua" }) do
    local chunk = assert(loadfile(M.addonDir .. "/" .. file))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "GuildGrudge", c.ns)
    if not ok then table.insert(c.errors, file .. ": " .. tostring(err)) end
  end
  table.insert(M.clients, c)
  return c
end

function M.fire(c, event, ...)
  for _, f in ipairs(c.events[event] or {}) do
    local fn = f.scripts.OnEvent
    if fn then
      local ok, err = pcall(fn, f, event, ...)
      if not ok then table.insert(c.errors, event .. ": " .. tostring(err)) end
    end
  end
end

function M.login(c)
  M.fire(c, "ADDON_LOADED", "GuildGrudge")
  M.fire(c, "PLAYER_LOGIN")
end

function M.send(c, prefix, msg, channel, target)
  M.log.sent = M.log.sent + 1
  if #msg > 255 then M.log.tooLong = M.log.tooLong + 1; return 2 end
  local th = c.throttle[prefix] or { left = THROTTLE_MAX, at = M.now }
  th.left = math.min(THROTTLE_MAX, th.left + (M.now - th.at) * THROTTLE_REGEN)
  th.at = M.now
  c.throttle[prefix] = th
  if th.left < 1 then M.log.throttled = M.log.throttled + 1; return 3 end
  th.left = th.left - 1
  for _, other in ipairs(M.clients) do
    local hit
    -- The live client doesn't echo GUILD messages to the sender, but does deliver a whisper to yourself.
    if channel == "GUILD" then hit = other ~= c
    elseif channel == "WHISPER" then hit = target == other.wire or target == other.full end
    if hit and other.online ~= false then
      M.log.delivered = M.log.delivered + 1
      M.fire(other, "CHAT_MSG_ADDON", prefix, msg, channel, c.wire, target or "", 0, 0)
    end
  end
  return 0
end

-- Advance the shared clock, running due timers on every client.
function M.advance(seconds, step)
  step = step or 0.05
  local stop = M.now + seconds
  while M.now < stop do
    M.now = M.now + step
    M.serverTime = M.serverTime + step
    for _, c in ipairs(M.clients) do
      local due = {}
      for i = #c.timers, 1, -1 do
        local t = c.timers[i]
        if t.cancelled then table.remove(c.timers, i)
        elseif t.at <= M.now then
          if t.every then t.at = t.at + t.every else table.remove(c.timers, i) end
          table.insert(due, t)
        end
      end
      for _, t in ipairs(due) do
        local ok, err = pcall(t.fn)
        if not ok then table.insert(c.errors, "timer: " .. tostring(err)) end
      end
    end
  end
  M.serverTime = math.floor(M.serverTime)
end

function M.slash(c, msg) c.env.SlashCmdList.GUILDGRUDGE(msg) end

function M.reset()
  M.clients = {}
  M.guids = {}
  M.log = { sent = 0, throttled = 0, tooLong = 0, delivered = 0 }
  M.guildChat = {}
end

return M
