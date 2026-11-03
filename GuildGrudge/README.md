# Guild Grudge (v0.1.0, untested starter)

A shared kill-on-sight list for your guild: notes on gankers, fictive bounties, guild sync and an alert when a listed player shows up near you.

## Install
1. Unzip so you get a folder called `GuildGrudge` with `GuildGrudge.toc` inside.
2. Put it in your WoW Forever AddOns folder (`World of Warcraft/_<forever folder>_/Interface/AddOns/`).
3. Everyone in the guild needs it. Data only flows between people who have it.

## Commands
| Command | What it does |
|---|---|
| `/gg` | Open the Most Wanted window |
| `/gg t <note>` | Add a note on your current target (also records class, race, level) |
| `/gg add <name> <note>` | Add a note by name |
| `/gg show <name>` | Print everything on a player |
| `/gg del <name>` | Remove your own notes on a player |
| `/gg bounty <name> <reward>` | Post a bounty (e.g. `50g and eternal glory`) |
| `/gg unbounty <name>` | Remove a bounty |
| `/gg claim <name>` | Claim a bounty manually |
| `/gg top` | Most wanted and top bounty hunters |
| `/gg sync` / `/gg fullsync` | Pull updates / everything from online guildies |
| `/gg alerts`, `sound`, `spotted`, `claims` | Toggle alerts, alert sound, sharing sightings, guild-chat claim announcements |

## How it works
- **Storage:** `SavedVariables` (`GuildGrudgeDB`), account-wide, so your alts share the list.
- **Sync:** hidden addon messages on the guild channel. New notes and bounties go out live. On login the addon asks the guild for anything newer than what it has; one online guildie answers by whisper.
- **Detection:** combat log (hostile players fighting or casting within ~50 yards), nameplates, target and mouseover. Alerts have a 60-second cooldown per player.
- **Bounties:** killing a player with an open bounty (killing blow, via `PARTY_KILL`) auto-claims it and posts in guild chat.
- **Tooltip:** listed players get a "Grudge: N notes / Bounty" line.

## Check these first when Forever is live
1. **Interface number.** Run `/dump select(4, GetBuildInfo())` in game and put the number in `## Interface:` in the .toc. Until then, tick "Load out of date AddOns".
2. **Names in a realmless game.** Run `/dump UnitName("target")` on an enemy player and look at how names appear in the combat log. If the format differs from `Name` or `Name-Realm`, adjust `SplitName`/`MakeKey` in `Core.lua`.
3. **Whisper sync.** Sync replies use addon whispers. If those don't reach people, switch `DumpTo` in `Sync.lua` to the `GUILD` channel.
4. **Error messages.** Turn on `/console scriptErrors 1` during testing.

## Ideas for v0.2
- Clickable list rows with an edit box instead of text
- Minimap button
- Map pins for "last seen" locations
- Shared kill counter and seasonal leaderboards
- Export string for a Discord bot or website
