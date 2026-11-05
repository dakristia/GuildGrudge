# Guild Grudge (v0.6.0)

A shared kill-on-sight list for your guild: notes on gankers, fictive bounties, guild sync and an alert when a listed player shows up near you. Built for World of Warcraft: Forever (interface 16001).

## Install
1. Unzip so you get a folder called `GuildGrudge` with `GuildGrudge.toc` inside.
2. Put it in `World of Warcraft/_forever_/Interface/AddOns/`.
3. Everyone in the guild needs it. Data only flows between people who have it.

## Commands
Forever names have two parts. Type them as `Ana Forever` or `Ana-Forever`. `show`, `del`, `unbounty` and `claim` also accept only the first name if one player on the list has it.

| Command | What it does |
|---|---|
| `/gg` | Open the Most Wanted window |
| `/gg t <note>` | Add a note on your current target (also records class, race, level) |
| `/gg add <first> <surname> <note>` | Add a note by name |
| `/gg nice <first> <surname>` | Add a funny character name to the guild's nice names list |
| `/gg show <name>` | Print everything on a player |
| `/gg del <name>` | Remove your own notes on a player |
| `/gg watch <first> <surname> <note>` | Add a note on the watch list |
| `/gg move <name>` | Move a player between the Wanted list and the watch list |
| `/gg bounty <first> <surname> <reward>` | Post a bounty (e.g. `50g and eternal glory`) |
| `/gg unbounty <name>` | Remove a bounty |
| `/gg claim <name>` | Claim a bounty manually |
| `/gg top` | Most wanted and top bounty hunters |
| `/gg sync` / `/gg fullsync` | Pull updates / everything from online guildies |
| `/gg alerts`, `sound`, `spotted`, `claims` | Toggle alerts, alert sound, sharing sightings, guild-chat claim announcements |
| `/gg options` | Open the settings panel |
| `/gg macro` | Put a `/gg` macro on your cursor, to drop on an action bar |
| `/gg debug` | Print name formats and sync state, for bug reports |

## Opening the window
- **Minimap button:** left-click opens the list, right-click opens settings, drag to move it. Turn it off in the settings.
- **Addon compartment:** the addons button under the clock lists Guild Grudge. Left-click opens the list, right-click opens settings.
- **Key binding:** Options -> Keybindings -> AddOns -> Guild Grudge.
- **Macro:** the Macro button in the window (or `/gg macro`) puts a macro on your cursor. Drop it on an action bar.

## How it works
- **Storage:** `SavedVariables` (`GuildGrudgeDB`), account-wide, so your alts share the list.
- **Sync:** hidden addon messages on the guild channel. New notes and bounties go out live. On login the addon asks the guild for anything newer than what it has, and one online guildie answers by whisper. Blizzard allows about 1 addon message per second, so a big sync takes a while (100 notes ≈ 2 minutes). Nothing is sent inside dungeons, raids or battlegrounds, where addon messages are blocked; the queue waits.
- **Detection:** nameplates, target and mouseover. Forever blocks addons from the combat log, so a ganker you never see a nameplate for is not detected. Turn enemy nameplates on (`V`). Alerts have a 60-second cooldown per player.
- **Bounties:** getting the killing blow on a player with an open bounty (the `PARTY_KILL` event) claims it and posts in guild chat.
- **Watch list:** for friendly players you want to keep an eye on (ninja looters, scammers). Pick the list when you add a player, and give a note a tag such as "Ninja looter". Watch-list players only warn you when they join your group (and optionally with a chat line when nearby), and they cannot have bounties.
- **Nice names:** a guild-shared list of funny character names, on the Names tab. No notes, alerts or bounties. Right-click a player's portrait and pick Add to nice names, or use `/gg nice`. Anyone can remove a name. It is kept apart from the grudge lists.
- **Name votes:** nice names can be voted up or down with the arrows at the right edge of a Names row, like notes. You can't vote on a name you added. Votes sync with the guild.
- **Sorting:** the dropdown next to the search box orders every tab by newest, oldest, A-Z or most votes. Hunters are ranked by their number of claims under "Most votes".
- **Mine only:** the checkbox next to the dropdown (also in the settings) shows only the players and names you added, noted, posted a bounty on or claimed.
- **Tooltip:** listed players get a "Grudge: N notes / Bounty" line.

## Check these first in game
1. **Errors:** `/console scriptErrors 1`.
2. **Sender names:** with two accounts in the guild, add a note on one and check that the other prints "<First Surname> added …". Then run `/gg debug` on the receiving account and send the output to the developer, whether it worked or not.
3. **Whisper sync:** log in the second account later and check that `/gg` shows the notes after about 20 seconds. If it doesn't, addon whispers may not work realmless. The fallback is to send the sync dump on `GUILD` (`DumpTo` in `Sync.lua`).
4. **Bounty claim:** kill a player with a bounty and check the claim. If it doesn't fire, `/eventtrace` and look for `PARTY_KILL`.

Development notes and tests: see the repo root (`tests/run.lua`, `docs/forever-api-findings.md`).

## Ideas for later
- Map pins for "last seen" locations
- Shared kill counter and seasonal leaderboards
- Export string for a Discord bot or website
