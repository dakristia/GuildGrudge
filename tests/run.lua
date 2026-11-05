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
  eq(#b.ns:KnownTags(), #b.ns.TAGS, "only suggestions")
  a.ns:AddNote("Gankmaster", "spams", nil, { tag = "Annoying" })
  W.advance(2)
  local tags = b.ns:KnownTags()
  eq(tags[1], "Ninja looter", "suggestions first")
  eq(tags[#tags], "Annoying", "custom tag last")
  eq(b.ns:EntryTags(b.ns.db.entries["gankmaster"])[1], "Annoying")
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

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
