-- Offline tests for Guild Grudge. Run from the repo root:
--   lua5.1 tests/run.lua
package.path = "tests/?.lua;" .. package.path
local W = require("wow_mock")
W.addonDir = "GuildGrudge"

local passed, failed = 0, 0
local function test(name, fn)
  W.reset()
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg)
  if a ~= b then error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function noErrors(c) eq(#c.errors, 0, c.name .. " errors: " .. table.concat(c.errors, " | ")) end

-- Classic-style names ("Name-Realm") unless a test says otherwise.
local function guild(n)
  local cs = {}
  for i = 1, n do
    cs[i] = W.newClient({ name = "Player" .. i, realm = "Realm" })
    W.login(cs[i])
  end
  return cs
end

test("all files load and log in without errors", function()
  local a = guild(1)[1]
  noErrors(a)
  assert(a.ns.db, "DB initialised")
end)

test("note on target reaches a guildie", function()
  local a, b = unpack(guild(2))
  a.units = { target = { name = "Gankmaster", class = "WARRIOR", race = "Orc", level = 60 } }
  W.slash(a, "t camped me at the FP")
  W.advance(2)
  local e = b.ns.db.entries["gankmaster"]
  assert(e, "B has the entry")
  eq(#b.ns:SortedNotes(e), 1, "B note count")
  eq(b.ns:SortedNotes(e)[1].text, "camped me at the FP")
  eq(e.class, "WARRIOR")
  noErrors(a); noErrors(b)
end)

test("deleting your note syncs as a tombstone", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  W.advance(2)
  W.slash(a, "del Gankmaster")
  W.advance(2)
  eq(#b.ns:SortedNotes(b.ns.db.entries["gankmaster"]), 0, "B sees note deleted")
end)

test("bounty post and manual claim sync", function()
  local a, b = unpack(guild(2))
  W.slash(a, "bounty Gankmaster 50g")
  W.advance(2)
  assert(b.ns:ActiveBounty(b.ns.db.entries["gankmaster"]), "B sees bounty")
  W.advance(2)
  W.slash(b, "claim Gankmaster")
  W.advance(2)
  eq(a.ns.db.entries["gankmaster"].bounty.claimedBy, "Player2", "A sees claim")
  eq(#W.guildChat, 1, "claim announced in guild chat")
end)

test("note text with ^ and | is cleaned and messages stay <= 255 bytes", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster a^b|c " .. string.rep("ä", 100))
  W.advance(2)
  eq(W.log.tooLong, 0, "oversized messages")
  local n = b.ns:SortedNotes(b.ns.db.entries["gankmaster"])[1]
  assert(not n.text:find("[%^|]"), "separators stripped")
  assert(#n.text <= a.ns.MAX_NOTE, "note within MAX_NOTE")
end)

test("login sync: exactly one guildie answers and the newcomer gets everything", function()
  local cs = guild(3)
  local a = cs[1]
  for i = 1, 5 do W.slash(a, "add Target" .. i .. " note " .. i) end
  W.advance(10)
  -- cs[2] and cs[3] have it live; a new member joins later
  local d = W.newClient({ name = "Newbie", realm = "Realm" })
  W.login(d)
  W.advance(30)
  eq(count(d.ns.db.entries), 5, "newcomer entries")
  noErrors(d)
end)

test("login sync of 40 notes survives the per-prefix throttle", function()
  local a = guild(1)[1]
  for i = 1, 40 do W.slash(a, "add Target" .. i .. " note " .. i); W.advance(1.5) end
  local d = W.newClient({ name = "Newbie", realm = "Realm" })
  W.login(d)
  W.advance(120)
  eq(count(d.ns.db.entries), 40, "newcomer entries (throttled sends: " .. W.log.throttled .. ")")
end)

test("Forever names: target 'Ana Forever' is found again by /gg show Ana Forever", function()
  local a = W.newClient({ name = "Me", surname = "Myself", full = "Me Myself" })
  W.login(a)
  a.units = { target = { name = "Ana", second = "Forever" } } -- UnitName returns name, surname
  W.slash(a, "t camped me")
  a.chat = {}
  W.slash(a, "show Ana Forever")
  assert(not table.concat(a.chat, "\n"):find("not on the list"), "show found the target: " .. table.concat(a.chat, " / "))
end)

test("Forever names: /gg add Ana Forever <note> keeps the full name", function()
  local a = W.newClient({ name = "Me", surname = "Myself", full = "Me Myself" })
  W.login(a)
  W.slash(a, "add Ana Forever camped me")
  local e = a.ns:Find("Ana Forever")
  assert(e, "entry for Ana Forever exists; keys: " .. table.concat((function()
    local k = {}; for key in pairs(a.ns.db.entries) do k[#k + 1] = key end; return k end)(), ","))
  eq(a.ns:SortedNotes(e)[1].text, "camped me")
end)

test("Forever names: /gg del only removes notes by you, not by another 'Ana'", function()
  local a = W.newClient({ name = "Ana", surname = "Smith", full = "Ana Smith" })
  local b = W.newClient({ name = "Ana", surname = "Jones", full = "Ana Jones" })
  W.login(a); W.login(b)
  W.slash(a, "add Gankmaster from smith")
  W.advance(2)
  W.slash(b, "del Gankmaster")
  W.advance(2)
  eq(#a.ns:SortedNotes(a.ns.db.entries["gankmaster"]), 1, "Smith's note survives Jones's /gg del")
end)

local function nameplateAlert(opts)
  local a = W.newClient(opts)
  W.login(a)
  W.slash(a, "add Gankmaster camped me")
  a.units = { nameplate1 = { name = "Gankmaster" } }
  a.chat = {}
  W.fire(a, "NAME_PLATE_UNIT_ADDED", "nameplate1")
  return a, table.concat(a.chat, "\n"):find("is nearby") ~= nil
end

test("nameplate of a listed player raises an alert", function()
  local a, alerted = nameplateAlert({ name = "Me", realm = "Realm" })
  assert(alerted, "alert shown")
  noErrors(a)
end)

-- Forever: CombatLogGetCurrentEventInfo is nil and COMBAT_LOG_EVENT_UNFILTERED
-- is restricted. Whether RegisterEvent throws is unconfirmed, so this assumes it does.
test("Forever combat log: nameplate alerts still work without the combat log", function()
  local a, alerted = nameplateAlert({ name = "Me", realm = "Realm",
    forbidEvents = { COMBAT_LOG_EVENT_UNFILTERED = true } })
  assert(alerted, "alert shown; load errors: " .. table.concat(a.errors, " | "))
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
