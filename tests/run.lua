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

test("received text is cleaned of chat escape codes", function()
  local a, b = unpack(guild(2))
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "N^1^evil^Evil|Hx|h^^WARRIOR^id1^Bad|Tguy^" .. W.serverTime .. "^0^Zone|r^hi |cffff0000red|Hitem:1|h[link]|h",
    "GUILD")
  assert(next(b.ns.db.entries), "message was received")
  for k, entry in pairs(b.ns.db.entries) do
    assert(not k:find("|", 1, true), "key has |: " .. k)
    assert(not entry.name:find("|", 1, true), "name has |")
    for _, n in pairs(entry.notes) do
      for _, field in ipairs({ "text", "author", "zone" }) do
        assert(not n[field]:find("|", 1, true), field .. " has |: " .. n[field])
      end
    end
  end
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

---------------------------------------------------------------------------
-- Forever (realmless, two-part names, Retail API)
---------------------------------------------------------------------------
local function keys(c)
  local k = {}; for key in pairs(c.ns.db.entries) do k[#k + 1] = key end; return table.concat(k, ",")
end
local function forever(name, surname, wire)
  local c = W.newClient({ name = name, surname = surname, wire = wire, forever = true })
  W.login(c)
  return c
end

test("Forever: all files load without errors", function()
  noErrors(forever("Me", "Myself"))
end)

test("Forever names: target 'Ana Forever' is found again by /gg show Ana Forever", function()
  local a = forever("Me", "Myself")
  a.units = { target = { name = "Ana", second = "Forever" } } -- UnitName returns name, surname
  W.slash(a, "t camped me")
  a.chat = {}
  W.slash(a, "show Ana Forever")
  local out = table.concat(a.chat, " / ")
  assert(not out:find("not on the list"), "show found the target: " .. out)
  assert(out:find("Ana Forever", 1, true), "full name displayed: " .. out)
end)

test("Forever names: /gg add Ana Forever <note> keeps the full name", function()
  local a = forever("Me", "Myself")
  W.slash(a, "add Ana Forever camped me")
  local e = a.ns:Find("Ana Forever")
  assert(e, "entry for Ana Forever exists; keys: " .. keys(a))
  eq(a.ns:SortedNotes(e)[1].text, "camped me")
end)

test("Forever names: Ana-Forever, ana forever and Ana Forever are the same player", function()
  local a = forever("Me", "Myself")
  W.slash(a, "add Ana-Forever one")
  W.slash(a, "add ana forever two")
  eq(keys(a), "ana forever")
  eq(#a.ns:SortedNotes(a.ns:Find("Ana Forever")), 2)
end)

test("Forever names: /gg show Ana finds Ana Forever when she is the only Ana", function()
  local a = forever("Me", "Myself")
  W.slash(a, "add Ana Forever camped me")
  assert(a.ns:Find("ana"), "lenient first-name lookup")
  W.slash(a, "add Ana Other also rude")
  assert(not a.ns:Find("ana"), "ambiguous first name finds nothing")
end)

test("Forever names: /gg add Ana <note> hints at the listed Ana", function()
  local a = forever("Me", "Myself")
  W.slash(a, "add Ana Forever camped me")
  a.chat = {}
  W.slash(a, "add Ana camped again")
  assert(table.concat(a.chat, " "):find("Did you mean Ana Forever", 1, true), "hint: " .. table.concat(a.chat, " / "))
end)

test("Forever names: an ambiguous first name says so", function()
  local a = forever("Me", "Myself")
  W.slash(a, "add Ana Forever one")
  W.slash(a, "add Ana Other two")
  a.chat = {}
  W.slash(a, "show Ana")
  assert(table.concat(a.chat, " "):find("More than one", 1, true), "ambiguity message: " .. table.concat(a.chat, " / "))
end)

test("Forever names: bounty on a two-part name keeps the whole reward", function()
  local a = forever("Me", "Myself")
  W.slash(a, "bounty Ana Forever 50g and glory")
  eq(a.ns:ActiveBounty(a.ns:Find("Ana Forever")).reward, "50g and glory")
end)

for _, style in ipairs({ "space", "dash" }) do
  local function wire(n, s) return style == "space" and (n .. " " .. s) or (n .. "-" .. s) end

  test("Forever sync (" .. style .. " sender names): note syncs with the full author name", function()
    local a = forever("Ana", "Smith", wire("Ana", "Smith"))
    local b = forever("Bob", "Stone", wire("Bob", "Stone"))
    W.slash(a, "add Gankmaster Kills camped me")
    W.advance(2)
    local e = b.ns:Find("Gankmaster Kills")
    assert(e, "B has the entry; keys: " .. keys(b))
    eq(b.ns:SortedNotes(e)[1].author, "Ana Smith")
    eq(count(a.ns.db.entries), 1, "A ignored its own echo")
    noErrors(a); noErrors(b)
  end)

  test("Forever sync (" .. style .. " sender names): /gg del only removes your notes, not another Ana's", function()
    local a = forever("Ana", "Smith", wire("Ana", "Smith"))
    local b = forever("Ana", "Jones", wire("Ana", "Jones"))
    W.slash(a, "add Gankmaster Kills from smith")
    W.advance(2)
    W.slash(b, "del Gankmaster Kills")
    W.advance(2)
    eq(#a.ns:SortedNotes(a.ns:Find("Gankmaster Kills")), 1, "Smith's note survives Jones's /gg del")
  end)

  test("Forever sync (" .. style .. " sender names): login sync of 40 notes arrives in full", function()
    local a = forever("Ana", "Smith", wire("Ana", "Smith"))
    for i = 1, 40 do W.slash(a, "add Target Number" .. i .. " note " .. i) end
    W.advance(60)
    local d = forever("New", "Bie", wire("New", "Bie"))
    W.advance(120)
    eq(count(d.ns.db.entries), 40, "newcomer entries (throttled sends: " .. W.log.throttled .. ")")
    noErrors(a); noErrors(d)
  end)
end

test("Forever kill: PARTY_KILL on a listed player you saw claims the bounty", function()
  local a = forever("Me", "Myself")
  W.slash(a, "bounty Ana Forever 50g")
  a.units = { nameplate1 = { name = "Ana", second = "Forever", guid = "Player-X1" } }
  W.fire(a, "NAME_PLATE_UNIT_ADDED", "nameplate1")
  W.fire(a, "PARTY_KILL", a.guid, "Player-X1")
  eq(a.ns:Find("Ana Forever").bounty.claimedBy, "Me Myself")
  eq(#W.guildChat, 1, "claim announced through C_ChatInfo.SendChatMessage")
  noErrors(a)
end)

test("Forever kill: PARTY_KILL resolves an unseen GUID with GetPlayerInfoByGUID", function()
  local a = forever("Me", "Myself")
  W.slash(a, "bounty Ana Forever 50g")
  W.guids["Player-X2"] = { name = "Ana", second = "Forever", class = "WARRIOR" }
  W.fire(a, "PARTY_KILL", a.guid, "Player-X2")
  eq(a.ns:Find("Ana Forever").bounty.claimedBy, "Me Myself")
end)

test("Forever: /gg debug prints the name formats the live client uses", function()
  local a = forever("Ana", "Smith", "Ana-Smith")
  local b = forever("Bob", "Stone", "Bob-Stone")
  W.slash(a, "add Gank Master rude")
  W.advance(2)
  b.chat = {}
  W.slash(b, "debug")
  local out = table.concat(b.chat, "\n")
  for _, want in ipairs({ 'UnitName%("player"%): "Bob", "Stone"', "regional names: true",
                          'roster%[1%]: "Ana%-Smith"', 'last sender: "Ana%-Smith" %-> "Ana Smith"',
                          "combat log API: no", "send queue: 0" }) do
    assert(out:find(want), "missing " .. want .. " in:\n" .. out)
  end
  noErrors(b)
end)

test("Forever kill: someone else's kill does not claim", function()
  local a = forever("Me", "Myself")
  W.slash(a, "bounty Ana Forever 50g")
  W.guids["Player-X2"] = { name = "Ana", second = "Forever" }
  W.fire(a, "PARTY_KILL", "Player-Other", "Player-X2")
  eq(a.ns:Find("Ana Forever").bounty.claimedBy, "")
end)

local function nameplateAlert(opts)
  local a = W.newClient(opts)
  W.login(a)
  if opts.forever then
    W.slash(a, "add Gank Master camped me")
    a.units = { nameplate1 = { name = "Gank", second = "Master" } }
  else
    W.slash(a, "add Gankmaster camped me")
    a.units = { nameplate1 = { name = "Gankmaster" } }
  end
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
-- is restricted. Whether RegisterEvent throws is unconfirmed, so the mock throws.
test("Forever combat log: nameplate alerts use the new raid-warning API", function()
  local a, alerted = nameplateAlert({ name = "Me", surname = "Myself", forever = true })
  assert(alerted, "alert shown; load errors: " .. table.concat(a.errors, " | "))
  assert(table.concat(a.chat, "\n"):find("RW: ", 1, true), "raid warning shown")
  noErrors(a)
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
