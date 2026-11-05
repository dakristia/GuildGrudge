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

test("a nameplate sighting of a listed player stores raceFile and sex", function()
  local a = forever("Me", "Myself")
  W.slash(a, "bounty Ana Forever 50g")
  a.units = { nameplate1 = { name = "Ana", second = "Forever", race = "Undead", raceFile = "Scourge", sex = 3 } }
  W.fire(a, "NAME_PLATE_UNIT_ADDED", "nameplate1")
  local e = a.ns:Find("Ana Forever")
  eq(e.raceFile, "Scourge")
  eq(e.sex, 3)
  noErrors(a)
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

test("a player running in and out of view alerts once, until unseen for the cooldown", function()
  local a = nameplateAlert({ name = "Me", surname = "Myself", forever = true })
  local function alertsAfter(seconds)
    W.advance(seconds)
    a.chat = {}
    W.fire(a, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    return table.concat(a.chat, "\n"):find("is nearby") ~= nil
  end
  assert(not alertsAfter(40), "no alert 40s after the first")
  assert(not alertsAfter(40), "no alert 80s after the first, seen 40s ago")
  assert(alertsAfter(61), "alert again after 61s out of view")
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

---------------------------------------------------------------------------
-- Note votes
---------------------------------------------------------------------------
local function firstNote(c, key)
  return c.ns:SortedNotes(c.ns.db.entries[key])[1]
end

test("a vote syncs to a second online guildie and changes its score", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  local id = firstNote(a, "gankmaster").id
  b.ns:Vote("Gankmaster", id, 1)
  W.advance(2)
  eq(a.ns:NoteScore(a.ns.db.entries["gankmaster"].notes[id]), 1, "A score")
  eq(b.ns:MyVote(b.ns.db.entries["gankmaster"].notes[id]), 1, "B own vote")
  eq(a.ns:MyVote(a.ns.db.entries["gankmaster"].notes[id]), 0, "A has not voted")
  noErrors(a); noErrors(b)
end)

test("a guildie who logs in later receives votes through the login dump", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  local id = firstNote(a, "gankmaster").id
  b.ns:Vote("Gankmaster", id, -1)
  W.advance(2)
  local d = W.newClient({ name = "Newbie", realm = "Realm" })
  W.login(d)
  W.advance(40)
  local n = d.ns.db.entries["gankmaster"].notes[id]
  eq(d.ns:NoteScore(n), -1, "newcomer score")
  noErrors(d)
end)

test("the newer vote per voter wins and a 0 vote removes the effect", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  local id = firstNote(a, "gankmaster").id
  local an = a.ns.db.entries["gankmaster"].notes[id]
  b.ns:Vote("Gankmaster", id, 1)
  W.advance(2)
  eq(a.ns:NoteScore(an), 1, "after up")
  b.ns:Vote("Gankmaster", id, -1)
  W.advance(2)
  eq(a.ns:NoteScore(an), -1, "after down")
  -- an older vote arriving late must not win
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "V^1^gankmaster^Gankmaster^^" .. id .. "^Player2^1^" .. (W.serverTime - 100), "GUILD")
  b.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "V^1^gankmaster^Gankmaster^^" .. id .. "^Player2^1^" .. (W.serverTime - 100), "GUILD")
  eq(a.ns:NoteScore(an), -1, "stale vote ignored")
  b.ns:Vote("Gankmaster", id, 0)
  W.advance(2)
  eq(a.ns:NoteScore(an), 0, "after removal")
  eq(an.votes["Player2"].v, 0, "removal record kept")
  noErrors(a); noErrors(b)
end)

test("voting on your own note is refused and sends nothing", function()
  local a = guild(2)[1]
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  local id = firstNote(a, "gankmaster").id
  local sent = W.log.sent
  a.chat = {}
  a.ns:Vote("Gankmaster", id, 1)
  W.advance(2)
  eq(W.log.sent, sent, "messages sent")
  assert(table.concat(a.chat, " "):find("You can't vote on your own note.", 1, true), "message: " .. table.concat(a.chat, " / "))
  eq(a.ns:NoteScore(a.ns.db.entries["gankmaster"].notes[id]), 0, "score")
end)

test("SortedNotes orders by score, then newest on a tie", function()
  local a = guild(1)[1]
  local e = a.ns:GetEntry("Gankmaster", true)
  e.notes.old  = { id = "old",  author = "X", ts = 10, text = "old",  votes = {} }
  e.notes.new  = { id = "new",  author = "X", ts = 20, text = "new",  votes = {} }
  e.notes.best = { id = "best", author = "X", ts = 5,  text = "best", votes = { Y = { v = 1, ts = 6 } } }
  e.notes.bad  = { id = "bad",  author = "X", ts = 30, text = "bad",  votes = { Y = { v = -1, ts = 31 } } }
  local ids = {}
  for i, n in ipairs(a.ns:SortedNotes(e)) do ids[i] = n.id end
  eq(table.concat(ids, ","), "best,new,old,bad")
end)

---------------------------------------------------------------------------
-- Author class colours
---------------------------------------------------------------------------
test("after a roster update AuthorClass returns the guildie's class", function()
  local a = W.newClient({ name = "Player1", realm = "Realm", class = "MAGE" })
  W.login(a)
  local b = W.newClient({ name = "Player2", realm = "Realm", class = "PRIEST" })
  W.login(b)
  W.advance(2)
  eq(a.ns:AuthorClass("Player2"), "PRIEST", "guildie class")
  eq(a.ns:AuthorClass("Player1"), "MAGE", "own class")
  eq(a.ns:AuthorClass("Nobody"), nil, "unknown")
  noErrors(a); noErrors(b)
end)

---------------------------------------------------------------------------
-- Profile sync (class, race, sex, level)
---------------------------------------------------------------------------
local function sight(c, unit)
  c.units = { nameplate1 = unit }
  W.fire(c, "NAME_PLATE_UNIT_ADDED", "nameplate1")
end
local ana = { name = "Gankmaster", race = "Undead", raceFile = "Scourge", sex = 3, level = 42, class = "MAGE" }

test("a sighting of a listed player shares race, sex and level with a guildie", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  sight(a, ana)
  W.advance(2)
  local e = b.ns.db.entries["gankmaster"]
  eq(e.raceFile, "Scourge"); eq(e.race, "Undead"); eq(e.sex, 3); eq(e.level, 42); eq(e.class, "MAGE")
  assert(e.profileTs, "profileTs set")
  noErrors(a); noErrors(b)
end)

test("a guildie who logs in later gets the profile through the login dump", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  sight(a, ana)
  W.advance(2)
  local d = W.newClient({ name = "Newbie", realm = "Realm" })
  W.login(d)
  W.advance(40)
  local e = d.ns.db.entries["gankmaster"]
  assert(e, "newcomer has the entry")
  eq(e.raceFile, "Scourge"); eq(e.sex, 3); eq(e.level, 42)
  noErrors(d)
end)

test("a second sighting within 300 seconds sends no new profile", function()
  local a = guild(2)[1]
  W.slash(a, "add Gankmaster rude")
  W.advance(30) -- past the login sync, which would add dumps to the count
  sight(a, ana)
  W.advance(2)
  eq(W.log.types.P, 1, "profiles after first sighting")
  sight(a, { name = "Gankmaster", race = "Undead", raceFile = "Scourge", sex = 3, level = 43, class = "MAGE" })
  W.advance(2)
  eq(W.log.types.P, 1, "profiles after second sighting")
  W.advance(301)
  sight(a, { name = "Gankmaster", race = "Undead", raceFile = "Scourge", sex = 3, level = 44, class = "MAGE" })
  W.advance(2)
  eq(W.log.types.P, 2, "profiles after the cooldown")
end)

test("an older profile does not overwrite newer local data", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  sight(a, ana)
  W.advance(2)
  local e = b.ns.db.entries["gankmaster"]
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "P^1^gankmaster^Gankmaster^^PRIEST^Orc^Orc^2^10^" .. (W.serverTime - 1000), "GUILD")
  eq(e.raceFile, "Scourge"); eq(e.level, 42); eq(e.class, "MAGE")
  -- a newer one with empty fields only updates what it carries
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "P^1^gankmaster^Gankmaster^^^^^^50^" .. (W.serverTime + 100), "GUILD")
  eq(e.level, 50); eq(e.raceFile, "Scourge"); eq(e.class, "MAGE")
  noErrors(b)
end)

---------------------------------------------------------------------------
-- Watch list and tags
---------------------------------------------------------------------------
local function chatHas(c, text) return table.concat(c.chat, "\n"):find(text, 1, true) ~= nil end

test("a tagged note syncs with its tag", function()
  local a, b = unpack(guild(2))
  a.ns:AddNote("Gankmaster", "took all the loot", nil, { tag = "Ninja looter" })
  W.advance(2)
  eq(firstNote(b, "gankmaster").tag, "Ninja looter")
  eq(firstNote(b, "gankmaster").text, "took all the loot")
  eq(W.log.tooLong, 0, "oversized messages")
  noErrors(a); noErrors(b)
end)

test("a tag alone is enough for a note", function()
  local a, b = unpack(guild(2))
  a.ns:AddNote("Gankmaster", "", nil, { tag = "Scammer" })
  W.advance(2)
  eq(firstNote(b, "gankmaster").tag, "Scammer")
end)

test("an old-format 12-field N message still parses and has no tag", function()
  local a, b = unpack(guild(2))
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "N^1^gankmaster^Gankmaster^^WARRIOR^id1^Player1^" .. W.serverTime .. "^0^Barrens^rude", "GUILD")
  local n = firstNote(b, "gankmaster")
  eq(n.text, "rude")
  eq(n.tag, nil)
  noErrors(b)
end)

test("a new watch entry syncs its list live", function()
  local a, b = unpack(guild(2))
  W.slash(a, "watch Gankmaster took the loot")
  W.advance(3)
  assert(a.ns:IsWatch(a.ns.db.entries["gankmaster"]), "A watches")
  assert(b.ns:IsWatch(b.ns.db.entries["gankmaster"]), "B watches")
  eq(b.ns.db.entries["gankmaster"].listTs, a.ns.db.entries["gankmaster"].listTs)
  noErrors(a); noErrors(b)
end)

test("the list reaches a guildie who logs in later", function()
  local a = guild(2)[1]
  W.slash(a, "watch Gankmaster took the loot")
  W.advance(3)
  local d = W.newClient({ name = "Newbie", realm = "Realm" })
  W.login(d)
  W.advance(40)
  assert(d.ns:IsWatch(d.ns.db.entries["gankmaster"]), "newcomer has the watch entry")
  noErrors(d)
end)

test("/gg move switches lists and syncs; an older L is ignored", function()
  local a, b = unpack(guild(2))
  W.slash(a, "watch Gankmaster took the loot")
  W.advance(3)
  W.serverTime = W.serverTime + 10
  W.slash(a, "move Gankmaster")
  W.advance(3)
  assert(not b.ns:IsWatch(b.ns.db.entries["gankmaster"]), "B back on Wanted")
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE", "L^1^gankmaster^Gankmaster^^watch^" .. (W.serverTime - 100), "GUILD")
  assert(not b.ns:IsWatch(b.ns.db.entries["gankmaster"]), "stale L ignored")
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE", "L^1^gankmaster^Gankmaster^^bogus^" .. (W.serverTime + 100), "GUILD")
  assert(not b.ns:IsWatch(b.ns.db.entries["gankmaster"]), "unknown list ignored")
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE", "L^1^unknown^Unknown^^watch^" .. W.serverTime, "GUILD")
  eq(b.ns.db.entries["unknown"], nil, "L does not create entries")
end)

test("SetBounty is refused on a watch entry", function()
  local a = guild(1)[1]
  W.slash(a, "watch Gankmaster took the loot")
  a.chat = {}
  W.slash(a, "bounty Gankmaster 50g")
  eq(a.ns:ActiveBounty(a.ns.db.entries["gankmaster"]), nil, "no bounty")
  assert(chatHas(a, "Bounties are only for the Wanted list."), "message: " .. table.concat(a.chat, " / "))
end)

test("moving to the watch list is refused with an open bounty", function()
  local a = guild(1)[1]
  W.slash(a, "bounty Gankmaster 50g")
  a.chat = {}
  W.slash(a, "move Gankmaster")
  assert(not a.ns:IsWatch(a.ns.db.entries["gankmaster"]), "still wanted")
  assert(chatHas(a, "first. Bounties are only for the Wanted list."), "message: " .. table.concat(a.chat, " / "))
end)

test("a watch entry near you gives no raid warning, and a chat line only with watchNearby", function()
  local a = guild(1)[1]
  W.slash(a, "watch Gankmaster took the loot")
  a.chat = {}
  sight(a, { name = "Gankmaster" })
  eq(#a.chat, 0, "silent by default")
  a.ns.db.settings.watchNearby = true
  W.advance(100)
  sight(a, { name = "Gankmaster" })
  assert(chatHas(a, "from your watch list is nearby"), "chat line: " .. table.concat(a.chat, " / "))
  assert(not chatHas(a, "RW: "), "no raid warning")
  assert(not chatHas(a, "is nearby!"), "no alert")
  eq(W.log.types.S, nil, "nothing shared with the guild")
  noErrors(a)
end)

test("a watch player joining the group warns once, and again after rejoining", function()
  local a = guild(1)[1]
  W.slash(a, "watch Gankmaster took the loot")
  a.chat = {}
  a.units = { party1 = { name = "Gankmaster", class = "WARRIOR" } }
  W.fire(a, "GROUP_ROSTER_UPDATE")
  assert(chatHas(a, "RW: |cffffcc00Watch list:|r"), "raid warning: " .. table.concat(a.chat, " / "))
  assert(chatHas(a, "joined your group"), "joined")
  a.chat = {}
  W.fire(a, "GROUP_ROSTER_UPDATE")
  eq(#a.chat, 0, "no second warning")
  a.units = {}
  W.fire(a, "GROUP_ROSTER_UPDATE")
  a.units = { party1 = { name = "Gankmaster", class = "WARRIOR" } }
  W.fire(a, "GROUP_ROSTER_UPDATE")
  assert(chatHas(a, "joined your group"), "warns again after rejoining")
  noErrors(a)
end)

test("a wanted player joining the group gives no watch warning; raids are scanned too", function()
  local a = guild(1)[1]
  W.slash(a, "add Gankmaster rude")
  W.slash(a, "watch Thief took the loot")
  a.chat = {}
  a.inRaid, a.groupSize = true, 2
  a.units = { raid1 = { name = "Gankmaster" }, raid2 = { name = "Thief" } }
  W.fire(a, "GROUP_ROSTER_UPDATE")
  local out = table.concat(a.chat, "\n")
  assert(out:find("Thief", 1, true) and out:find("joined your group", 1, true), "Thief warned: " .. out)
  assert(not out:find("Gankmaster", 1, true), "Gankmaster not warned")
  noErrors(a)
end)

test("KnownTags lists the suggestions first, then custom tags from notes", function()
  local a, b = unpack(guild(2))
  eq(#b.ns:KnownTags("watch"), #b.ns.TAGS.watch, "only suggestions")
  a.ns:AddNote("Gankmaster", "spams", nil, { tag = "Annoying", list = "watch" })
  W.advance(2)
  local tags = b.ns:KnownTags("watch")
  eq(tags[1], "Ninja looter", "suggestions first")
  eq(tags[#tags], "Annoying", "custom tag last")
  eq(b.ns:EntryTags(b.ns.db.entries["gankmaster"])[1], "Annoying")
end)

---------------------------------------------------------------------------
-- Kudos list
---------------------------------------------------------------------------
test("a kudos note syncs with its tag and list", function()
  local a, b = unpack(guild(2))
  W.slash(a, "kudos Helper healed us through the whole run")
  a.ns:AddNote("Helper", "", nil, { tag = "Great healer" })
  W.advance(3)
  local e = b.ns.db.entries["helper"]
  assert(b.ns:IsKudos(e), "B has her on the kudos list")
  eq(b.ns:ListOf(e), "kudos")
  eq(e.listTs, a.ns.db.entries["helper"].listTs)
  eq(firstNote(b, "helper").tag, "Great healer")
  eq(W.log.types.L, 1, "one L message")
  noErrors(a); noErrors(b)
end)

test("an unknown list in an L message is ignored, kudos is accepted", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE", "L^1^gankmaster^Gankmaster^^kudos^" .. (W.serverTime + 10), "GUILD")
  eq(b.ns:ListOf(b.ns.db.entries["gankmaster"]), "kudos")
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE", "L^1^gankmaster^Gankmaster^^bogus^" .. (W.serverTime + 20), "GUILD")
  eq(b.ns:ListOf(b.ns.db.entries["gankmaster"]), "kudos", "bogus list ignored")
end)

test("SetBounty is refused on a kudos entry", function()
  local a = guild(1)[1]
  W.slash(a, "kudos Helper healed us")
  a.chat = {}
  W.slash(a, "bounty Helper 50g")
  eq(a.ns:ActiveBounty(a.ns.db.entries["helper"]), nil, "no bounty")
  assert(chatHas(a, "Bounties are only for the Wanted list."), "message: " .. table.concat(a.chat, " / "))
end)

test("SetList moves between all three lists and syncs", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  for _, list in ipairs({ "kudos", "watch", "kudos", "wanted" }) do
    W.serverTime = W.serverTime + 10
    a.ns:SetList("Gankmaster", list)
    W.advance(2)
    eq(a.ns:ListOf(a.ns.db.entries["gankmaster"]), list, "A on " .. list)
    eq(b.ns:ListOf(b.ns.db.entries["gankmaster"]), list, "B on " .. list)
  end
  eq(a.ns.db.entries["gankmaster"].list, nil, "Wanted is stored as nil")
  a.chat = {}
  a.ns:SetList("Gankmaster", "bogus")
  assert(chatHas(a, "Usage: /gg move"), "usage: " .. table.concat(a.chat, " / "))
end)

test("moving off Wanted is refused with an open bounty, for watch and kudos", function()
  local a = guild(1)[1]
  W.slash(a, "bounty Gankmaster 50g")
  for _, list in ipairs({ "watch", "kudos" }) do
    a.chat = {}
    a.ns:SetList("Gankmaster", list)
    eq(a.ns:ListOf(a.ns.db.entries["gankmaster"]), "wanted", "still wanted after " .. list)
    assert(chatHas(a, "first. Bounties are only for the Wanted list."), "message: " .. table.concat(a.chat, " / "))
  end
end)

test("/gg move <name> kudos works, and with no list still toggles Wanted and watch", function()
  local a, b = unpack(guild(2))
  W.slash(a, "add Gankmaster rude")
  W.advance(2)
  W.serverTime = W.serverTime + 10
  W.slash(a, "move Gankmaster kudos")
  W.advance(2)
  assert(a.ns:IsKudos(a.ns.db.entries["gankmaster"]), "A on kudos")
  assert(b.ns:IsKudos(b.ns.db.entries["gankmaster"]), "B on kudos")
  W.serverTime = W.serverTime + 10
  W.slash(a, "move Gankmaster")
  eq(a.ns:ListOf(a.ns.db.entries["gankmaster"]), "wanted", "kudos with no list goes to Wanted")
  W.serverTime = W.serverTime + 10
  W.slash(a, "move Gankmaster")
  eq(a.ns:ListOf(a.ns.db.entries["gankmaster"]), "watch", "Wanted toggles to watch")
  a.chat = {}
  W.slash(a, "move Gankmaster nonsense")
  assert(chatHas(a, "Usage: /gg move"), "usage: " .. table.concat(a.chat, " / "))
  eq(a.ns:ListOf(a.ns.db.entries["gankmaster"]), "watch", "unchanged")
  noErrors(a); noErrors(b)
end)

test("/gg move <first> <surname> <list> parses a two-part name", function()
  local a = forever("Me", "Myself")
  W.slash(a, "add Ana Forever rude")
  W.slash(a, "move Ana Forever kudos")
  eq(a.ns:ListOf(a.ns:Find("Ana Forever")), "kudos")
  noErrors(a)
end)

test("KnownTags('kudos') gives the kudos presets and custom kudos tags, but no watch tags", function()
  local a, b = unpack(guild(2))
  eq(#b.ns:KnownTags("kudos"), #b.ns.TAGS.kudos, "only suggestions")
  a.ns:AddNote("Helper", "", nil, { tag = "Cheerful", list = "kudos" })
  a.ns:AddNote("Gankmaster", "", nil, { tag = "Annoying", list = "watch" })
  a.ns:AddNote("Thief", "", nil, { tag = "Sneaky" })
  W.advance(4)
  local tags = b.ns:KnownTags("kudos")
  eq(tags[1], "Helpful", "presets first")
  eq(tags[#tags], "Cheerful", "custom kudos tag last")
  eq(#tags, #b.ns.TAGS.kudos + 1, "no watch or wanted tags")
  local watch = b.ns:KnownTags("watch")
  eq(watch[#watch], "Annoying", "custom watch tag")
  eq(#watch, #b.ns.TAGS.watch + 1, "no kudos or wanted tags")
  for _, tag in ipairs(watch) do assert(tag ~= "Cheerful" and tag ~= "Helpful", "kudos tag in watch: " .. tag) end
end)

test("a kudos player joining the group gives a friendly chat line and no raid warning", function()
  local a = guild(1)[1]
  a.ns:AddNote("Helper", "healed us", nil, { tag = "Great healer", list = "kudos" })
  a.chat = {}
  a.units = { party1 = { name = "Helper", class = "WARRIOR" } }
  W.fire(a, "GROUP_ROSTER_UPDATE")
  assert(chatHas(a, "|cff4dff66Kudos:|r"), "kudos line: " .. table.concat(a.chat, " / "))
  assert(chatHas(a, "joined your group"), "joined")
  assert(chatHas(a, "|cff4dff66[Great healer]|r"), "green tag")
  assert(not chatHas(a, "RW: "), "no raid warning")
  a.chat = {}
  W.fire(a, "GROUP_ROSTER_UPDATE")
  eq(#a.chat, 0, "no second line")
  noErrors(a)
end)

test("a kudos player joining the group gives nothing with kudosGroup off", function()
  local a = guild(1)[1]
  a.ns:AddNote("Helper", "healed us", nil, { list = "kudos" })
  a.ns.db.settings.kudosGroup = false
  a.chat = {}
  a.units = { party1 = { name = "Helper", class = "WARRIOR" } }
  W.fire(a, "GROUP_ROSTER_UPDATE")
  eq(#a.chat, 0, "silent")
  noErrors(a)
end)

test("a kudos player nearby gives nothing, even with watchNearby on", function()
  local a = guild(1)[1]
  a.ns:AddNote("Helper", "healed us", nil, { list = "kudos" })
  a.ns.db.settings.watchNearby = true
  a.chat = {}
  sight(a, { name = "Helper" })
  eq(#a.chat, 0, "no chat line, no raid warning")
  eq(W.log.types.S, nil, "nothing shared with the guild")
  noErrors(a)
end)

test("Top only counts Wanted entries", function()
  local a = guild(1)[1]
  W.slash(a, "add Gankmaster rude")
  a.ns:AddNote("Helper", "healed us", nil, { list = "kudos" })
  a.chat = {}
  W.slash(a, "top")
  local out = table.concat(a.chat, "\n")
  assert(out:find("Gankmaster", 1, true), "wanted listed")
  assert(not out:find("Helper", 1, true), "kudos not listed")
end)

test("the kudosGroup setting defaults to on", function()
  eq(guild(1)[1].ns.db.settings.kudosGroup, true)
end)

test("MaxTs counts listTs", function()
  local a = guild(1)[1]
  local e = a.ns:GetEntry("Gankmaster", true)
  e.listTs = W.serverTime + 5000
  eq(a.ns:MaxTs(), W.serverTime + 5000)
end)

---------------------------------------------------------------------------
-- Nice names
---------------------------------------------------------------------------
local anaUnit = { name = "Anaconda", race = "Undead", raceFile = "Scourge", sex = 3, level = 12, class = "WARRIOR" }

test("adding a nice name from a target syncs to a guildie with its class", function()
  local a, b = unpack(guild(2))
  a.units = { target = anaUnit }
  a.ns:AddNiceName("Anaconda", "target")
  W.advance(2)
  local n = b.ns.db.names["anaconda"]
  assert(n, "B has the name")
  eq(n.name, "Anaconda"); eq(n.by, "Player1"); eq(n.class, "WARRIOR")
  eq(n.raceFile, "Scourge"); eq(n.race, "Undead"); eq(n.sex, 3); eq(n.level, 12)
  eq(#b.ns:NiceNames(), 1, "B live names")
  noErrors(a); noErrors(b)
end)

test("/gg nice adds by name", function()
  local a, b = unpack(guild(2))
  W.slash(a, "nice Funny Name")
  W.advance(2)
  assert(b.ns.db.names["funny name"] or b.ns.db.names["funny"], "B has the name")
  noErrors(b)
end)

test("a duplicate nice name is refused and sends nothing", function()
  local a = guild(2)[1]
  a.ns:AddNiceName("Anaconda")
  W.advance(2)
  local sent = W.log.sent
  a.chat = {}
  a.ns:AddNiceName("anaconda")
  W.advance(2)
  eq(W.log.sent, sent, "messages sent")
  assert(chatHas(a, "Anaconda is already on the nice names list."), "message: " .. table.concat(a.chat, " / "))
end)

test("removing a nice name syncs as a tombstone, and it can be added again", function()
  local a, b = unpack(guild(2))
  a.ns:AddNiceName("Anaconda")
  W.advance(2)
  W.advance(2)
  b.ns:RemoveNiceName("Anaconda")
  W.advance(2)
  assert(a.ns.db.names["anaconda"].deleted, "A sees it removed")
  eq(#a.ns:NiceNames(), 0, "A live names")
  W.advance(2)
  a.ns:AddNiceName("Anaconda")
  W.advance(2)
  eq(#b.ns:NiceNames(), 1, "B sees it again")
  eq(b.ns.db.names["anaconda"].deleted, nil)
end)

test("a login sync delivers nice names to a newcomer", function()
  local a = guild(2)[1]
  a.ns:AddNiceName("Anaconda")
  W.advance(2)
  a.ns:AddNiceName("Bananas")
  W.advance(2)
  local d = W.newClient({ name = "Newbie", realm = "Realm" })
  W.login(d)
  W.advance(40)
  eq(#d.ns:NiceNames(), 2, "newcomer names")
  noErrors(d)
end)

test("an older F does not overwrite a newer one, and empty fields keep class data", function()
  local a, b = unpack(guild(2))
  a.units = { target = anaUnit }
  a.ns:AddNiceName("Anaconda", "target")
  W.advance(2)
  local n = b.ns.db.names["anaconda"]
  local ts = n.ts
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "F^1^anaconda^Anaconda^^Other^" .. (ts - 100) .. "^1^PRIEST^Orc^Orc^2^5", "GUILD")
  eq(n.ts, ts); eq(n.deleted, nil); eq(n.class, "WARRIOR"); eq(n.by, "Player1")
  a.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "F^1^anaconda^Anaconda^^Other^" .. (ts + 100) .. "^0^^^^^", "GUILD")
  eq(n.ts, ts + 100); eq(n.by, "Other"); eq(n.class, "WARRIOR"); eq(n.raceFile, "Scourge"); eq(n.level, 12)
  noErrors(b)
end)

test("MaxTs counts nice names", function()
  local a = guild(1)[1]
  a.ns.db.names["x"] = { name = "X", by = "Y", ts = W.serverTime + 7000 }
  eq(a.ns:MaxTs(), W.serverTime + 7000)
end)

test("nice names never show up as grudge entries", function()
  local a, b = unpack(guild(2))
  a.units = { target = anaUnit }
  a.ns:AddNiceName("Anaconda", "target")
  W.advance(2)
  for _, c in ipairs({ a, b }) do
    eq(count(c.ns.db.entries), 0, c.name .. " entries")
    eq(c.ns:Find("Anaconda"), nil, c.name .. " Find")
    eq(c.ns:GetEntry("Anaconda", false), nil, c.name .. " GetEntry")
  end
  local e = a.ns:GetEntry("Anaconda", true)
  assert(not a.ns:IsListed(e), "not listed")
  noErrors(a); noErrors(b)
end)

---------------------------------------------------------------------------
-- Name votes
---------------------------------------------------------------------------
test("a name vote syncs to the guild and changes its score", function()
  local a, b = unpack(guild(2))
  a.ns:AddNiceName("Anaconda")
  W.advance(2)
  b.ns:VoteName("Anaconda", 1)
  W.advance(2)
  local n = a.ns.db.names["anaconda"]
  eq(a.ns:NameScore(n), 1, "A score")
  eq(b.ns:MyNameVote(b.ns.db.names["anaconda"]), 1, "B own vote")
  eq(a.ns:MyNameVote(n), 0, "A has not voted")
  b.ns:VoteName("Anaconda", 0)
  W.advance(2)
  eq(a.ns:NameScore(n), 0, "after removal")
  eq(n.votes["Player2"].v, 0, "removal record kept")
  noErrors(a); noErrors(b)
end)

test("voting on a name you added is refused and sends nothing", function()
  local a = guild(2)[1]
  a.ns:AddNiceName("Anaconda")
  W.advance(2)
  local sent = W.log.sent
  a.chat = {}
  a.ns:VoteName("Anaconda", 1)
  W.advance(2)
  eq(W.log.sent, sent, "messages sent")
  assert(chatHas(a, "You can't vote on a name you added."), "message: " .. table.concat(a.chat, " / "))
  eq(a.ns:NameScore(a.ns.db.names["anaconda"]), 0, "score")
end)

test("voting on a missing or removed name says it is gone", function()
  local a = guild(1)[1]
  a.ns:VoteName("Nobody", 1)
  assert(chatHas(a, "That name is gone."), "missing: " .. table.concat(a.chat, " / "))
  a.ns.db.names["anaconda"] = { name = "Anaconda", by = "Other", ts = W.serverTime, deleted = true }
  a.chat = {}
  a.ns:VoteName("Anaconda", 1)
  assert(chatHas(a, "That name is gone."), "removed: " .. table.concat(a.chat, " / "))
end)

test("a name vote survives a login sync", function()
  local a, b = unpack(guild(2))
  a.ns:AddNiceName("Anaconda")
  W.advance(2)
  b.ns:VoteName("Anaconda", -1)
  W.advance(2)
  local d = W.newClient({ name = "Newbie", realm = "Realm" })
  W.login(d)
  W.advance(40)
  eq(d.ns:NameScore(d.ns.db.names["anaconda"]), -1, "newcomer score")
  noErrors(d)
end)

test("an older G is ignored, a newer one wins, and the adder's own G is ignored", function()
  local a, b = unpack(guild(2))
  a.ns:AddNiceName("Anaconda")
  W.advance(2)
  b.ns:VoteName("Anaconda", -1)
  W.advance(2)
  local n = a.ns.db.names["anaconda"]
  b.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "G^1^anaconda^Anaconda^^Player2^1^" .. (W.serverTime - 100), "GUILD")
  eq(a.ns:NameScore(n), -1, "stale vote ignored")
  b.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "G^1^anaconda^Anaconda^^Player2^1^" .. (W.serverTime + 100), "GUILD")
  eq(a.ns:NameScore(n), 1, "newer vote wins")
  b.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "G^1^anaconda^Anaconda^^Player1^1^" .. (W.serverTime + 100), "GUILD")
  eq(n.votes["Player1"], nil, "no vote from the adder")
  b.env.C_ChatInfo.SendAddonMessage("GGRUDGE",
    "G^1^unknown^Unknown^^Player2^1^" .. W.serverTime, "GUILD")
  eq(a.ns.db.names["unknown"], nil, "G does not create names")
  noErrors(a)
end)

test("MaxTs counts name votes", function()
  local a = guild(1)[1]
  a.ns.db.names["x"] = { name = "X", by = "Y", ts = W.serverTime, votes = { Z = { v = 1, ts = W.serverTime + 9000 } } }
  eq(a.ns:MaxTs(), W.serverTime + 9000)
end)

---------------------------------------------------------------------------
-- Sorting and the mine filter
---------------------------------------------------------------------------
local function order(list)
  local names = {}
  for i, el in ipairs(list) do names[i] = el.name or el.e.name end
  return table.concat(names, ",")
end

-- Three players: Bob has the newest activity, Amy the best score, Cat the oldest.
local function playerElements(ns)
  local function player(name, notes, bounty)
    local e = ns:GetEntry(name, true)
    for i, n in ipairs(notes) do
      n.id, n.author = name .. i, n.author or "X"
      e.notes[n.id] = n
    end
    e.bounty = bounty
    return { kind = "player", key = ns:MakeKey(name), e = e }
  end
  return {
    player("Cat", { { ts = 100, text = "c" } }),
    player("Bob", { { ts = 200, text = "b" } }),
    player("Amy", { { ts = 150, text = "a", votes = { Y = { v = 1, ts = 1 }, Z = { v = 1, ts = 1 } } },
                    { ts = 120, text = "a2", deleted = true } }),
  }
end

test("SortElements orders players by newest, oldest, A-Z and most votes", function()
  local ns = guild(1)[1].ns
  local list = playerElements(ns)
  eq(order(ns:SortElements(list, "newest")), "Bob,Amy,Cat")
  eq(order(ns:SortElements(list, "oldest")), "Cat,Amy,Bob")
  eq(order(ns:SortElements(list, "name")), "Amy,Bob,Cat")
  eq(order(ns:SortElements(list, "votes")), "Amy,Bob,Cat", "score 2, then a tie sorted A-Z")
  eq(order(ns:SortElements(list, nil)), "Bob,Amy,Cat", "unknown mode counts as newest")
end)

test("a bounty counts as player activity, and a deleted note does not", function()
  local ns = guild(1)[1].ns
  local list = playerElements(ns)
  list[1].e.bounty = { poster = "X", reward = "50g", ts = 500, claimedBy = "", claimedTs = 0 } -- Cat
  list[3].e.notes.Amy2.ts = 900 -- Amy's deleted note
  eq(order(ns:SortElements(list, "newest")), "Cat,Bob,Amy")
end)

test("SortElements names ties A-Z and ignores case", function()
  local ns = guild(1)[1].ns
  local list = {
    { kind = "name", key = "b", e = { name = "bravo", ts = 5 } },
    { kind = "name", key = "a", e = { name = "Alpha", ts = 5 } },
    { kind = "name", key = "c", e = { name = "Charlie", ts = 5 } },
  }
  eq(order(ns:SortElements(list, "newest")), "Alpha,bravo,Charlie")
  eq(order(ns:SortElements(list, "name")), "Alpha,bravo,Charlie")
end)

test("SortElements sorts names by score and hunters by claims", function()
  local ns = guild(1)[1].ns
  local names = {
    { kind = "name", key = "a", e = { name = "Alpha", ts = 1, votes = { X = { v = -1, ts = 1 } } } },
    { kind = "name", key = "b", e = { name = "Bravo", ts = 2, votes = { X = { v = 1, ts = 1 } } } },
    { kind = "name", key = "c", e = { name = "Charlie", ts = 3 } },
  }
  eq(order(ns:SortElements(names, "votes")), "Bravo,Charlie,Alpha")
  local function hunter(name, ...)
    local claims = {}
    for i, ts in ipairs({ ... }) do claims[i] = { bounty = { claimedTs = ts } } end
    return { kind = "hunter", key = name, name = name, claims = claims }
  end
  local hunters = { hunter("Zed", 10, 20), hunter("Ann", 30), hunter("Max", 5, 6, 7) }
  eq(order(ns:SortElements(hunters, "votes")), "Max,Zed,Ann")
  eq(order(ns:SortElements(hunters, "newest")), "Ann,Zed,Max")
  eq(order(ns:SortElements(hunters, "oldest")), "Max,Zed,Ann")
  eq(order(ns:SortElements(hunters, "name")), "Ann,Max,Zed")
end)

test("IsMine on players: your live note, a bounty you posted, or a bounty you claimed", function()
  local ns = guild(1)[1].ns -- Me() is Player1
  local function player(name, setup)
    local e = ns:GetEntry(name, true)
    setup(e)
    return { kind = "player", e = e }
  end
  assert(ns:IsMine(player("A", function(e) e.notes.n = { id = "n", author = "Player1", ts = 1, text = "x" } end)), "own note")
  assert(not ns:IsMine(player("B", function(e) e.notes.n = { id = "n", author = "Player1", ts = 1, text = "x", deleted = true } end)),
    "own deleted note")
  assert(not ns:IsMine(player("C", function(e) e.notes.n = { id = "n", author = "Other", ts = 1, text = "x" } end)), "other's note")
  assert(ns:IsMine(player("D", function(e) e.bounty = { poster = "Player1", reward = "50g", ts = 1, claimedBy = "" } end)), "own bounty")
  assert(not ns:IsMine(player("E", function(e) e.bounty = { poster = "Player1", reward = "", ts = 1, claimedBy = "" } end)),
    "own removed bounty")
  assert(ns:IsMine(player("F", function(e) e.bounty = { poster = "Other", reward = "50g", ts = 1, claimedBy = "Player1" } end)),
    "claimed by you")
  assert(not ns:IsMine(player("G", function(e) e.bounty = { poster = "Other", reward = "50g", ts = 1, claimedBy = "Other" } end)),
    "claimed by another")
end)

test("IsMine on names and hunters", function()
  local ns = guild(1)[1].ns
  assert(ns:IsMine({ kind = "name", e = { name = "A", by = "Player1" } }), "own name")
  assert(not ns:IsMine({ kind = "name", e = { name = "B", by = "Other" } }), "other's name")
  assert(ns:IsMine({ kind = "hunter", name = "Player1", claims = {} }), "yourself as hunter")
  assert(not ns:IsMine({ kind = "hunter", name = "Other", claims = {} }), "another hunter")
end)

test("the sort and mine settings have defaults", function()
  local a = guild(1)[1]
  eq(a.ns.db.settings.sortMode, "newest")
  eq(a.ns.db.settings.mineOnly, false)
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
