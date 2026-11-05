# Status (2026-11-03, v0.2.0)

**Where we are:** the addon is ported to the Forever API, and the offline tests pass (28/28). Nothing has run in the real game yet. Forever launches on 4 November; first in-game testing is planned for **5 November**.

The addon is installed by symlink: `~/source/repos/wow/_forever_/Interface/AddOns/GuildGrudge` → `GuildGrudge/` in this repo. After an edit, `/reload` in game. No copying.

## Resume on 5 November
1. Start the game. On the character screen, open **AddOns** and check that Guild Grudge is listed and enabled. If it is missing, the symlink isn't followed: replace it with a copy of `GuildGrudge/`.
2. In game: `/console scriptErrors 1`, then `/reload`. Look for "Grudge: v0.2.0 loaded".
3. Run `/gg debug` and save the output. Do the same on a second account in the same guild after step 4.
4. Do the checks in [`GuildGrudge/README.md`](GuildGrudge/README.md) → "Check these first in game". They need two accounts in one guild, and the bounty check needs a PvP kill on the PvP ruleset.
5. Paste the `/gg debug` output and anything odd to Claude, together with this file. Then fix the mock in `tests/wow_mock.lua` first, so it matches the real client, and only then fix the addon.

## Proven (offline, by `tests/run.lua` and static checks)
- Every API, event and frame template the addon uses exists in Forever build 1.60.1.70755. Checked against Blizzard's UI source and the beta API dump. Details: [`docs/forever-api-findings.md`](docs/forever-api-findings.md).
- All files compile in Lua 5.1. The only globals the addon writes are `GuildGrudgeDB` and the two slash command names.
- With the mock client:
  - notes, deletes, bounties and claims sync between guildies
  - a guildie who logs in later gets everything, 40 notes in full despite the 1-message-per-second limit
  - two-part names work as `Ana Forever`, `Ana-Forever` and `ana forever`
  - two guildies called Ana can't delete each other's notes
  - nameplate alerts use the new raid-warning API
  - `PARTY_KILL` claims a bounty, and a kill by someone else doesn't
  - chat escape codes in incoming messages are stripped

## Proven in the live game (5 November, one account)
- The addon loads through the symlink, and `/gg debug` runs without errors.
- `UnitName("player")` returns the first name and the surname as two values. Roster names are `First Surname` with a space.
- An addon whisper to `First Surname` arrives, and its sender is `First Surname`. A whisper to yourself is delivered too.
- A `GUILD` addon message is sent (result 0) but is not echoed back to the sender.
- The combat log guard is correct (`combat log API: no`).

## Unproven (needs the live game)
These are ordered by risk. The `/gg debug` line that answers each one is in brackets.

1. **`GUILD` sender format.** No echo means this needs a second player. It is very likely `First Surname`, the same as whispers. [`last sender` on the receiving account]
2. **Login sync end to end.** A self-whisper works, so a whisper to a guildie very likely works too. [`entries` on the newcomer stays 0]
3. **`PARTY_KILL` in open-world PvP.** Unknown whether it fires for your own kills. Without it, bounties need `/gg claim`. [`PARTY_KILL seen`]
4. **`GetPlayerInfoByGUID` name parts.** This is the fallback for a kill on someone you never had a nameplate for. Its 7th return value may be empty, a surname or a realm.
5. **Registering `COMBAT_LOG_EVENT_UNFILTERED`.** The addon skips it on Forever, so this only matters if the guard is wrong. [`combat log API: no`]
6. **The symlink.** Whether the game loads an addon through one (step 1 above).
7. **The UI window and tooltip line.** No test can render frames. Open `/gg`, type in the search box, and mouse over a listed player.

## Known limits (by design)
- No combat log in Forever, so a ganker you never see a nameplate for is not detected. Enemy nameplates (`V`) help.
- A sync of 100 notes takes about 2 minutes, because of the 1-message-per-second limit.
- `/gg add Ana camped me` creates the player "Ana Camped". Two words are always the name, and the addon prints "Did you mean …?" when another Ana is listed.
- No addon messages in dungeons, raids or battlegrounds. The send queue waits until you leave.

## Ideas for later
In the [addon README](GuildGrudge/README.md): clickable rows, minimap button, map pins, seasonal leaderboards, an export string for Discord.
