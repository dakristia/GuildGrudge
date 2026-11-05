# Status (2026-11-05, v0.3.0)

**Where we are:** the addon works in the live game between two players. Releases are public on GitHub, and testers install them with WowUp or from the Releases page. The offline tests pass (29/29).

The addon is installed locally by symlink: `~/source/repos/wow/_forever_/Interface/AddOns/GuildGrudge` → `GuildGrudge/` in this repo. After an edit, `/reload` in game. Because the game loads from `main`, changes go straight on `main`.

## Releasing
1. Raise the version in `GuildGrudge/Core.lua` (`GG.VERSION`), `GuildGrudge/GuildGrudge.toc` and the title of `GuildGrudge/README.md`.
2. Commit on `main`, push, then push a tag `vX.Y.Z`.
3. `.github/workflows/release.yml` builds `GuildGrudge-vX.Y.Z-forever.zip` and publishes the release. WowUp picks it up.

## Proven in the live game (5 November, two players)
- The addon loads through the symlink and through a WowUp install.
- Names: `UnitName("player")` returns the first name and the surname as two values. Roster names, whisper senders and `GUILD` senders are all `First Surname` with a space.
- A `GUILD` addon message is not echoed back to the sender. An addon whisper to yourself is delivered.
- Sync: notes, bounties and deletes reach a guildie who is online. A guildie who logs in later gets the missing notes by whisper.
- Nobody can delete another player's notes.
- Detection: a real listed player raised the nameplate alert. The tooltip line shows on listed players.
- `PARTY_KILL` fires on Forever. The combat log guard is correct.
- UI (v0.3.0): clickable rows with a right-click menu, the toolbar buttons, the text-box popups, the portrait menu entry, the minimap button, the addon compartment entry, the key binding, the macro button and the Settings panel.

## Unproven
- **Bounty claim on a real PvP kill.** `PARTY_KILL` fires, but no one has claimed a bounty from a player kill yet. Without it, bounties need `/gg claim`.
- **`GetPlayerInfoByGUID` name parts.** This is the fallback for a kill on someone you never had a nameplate for. Its 7th return value may be empty, a surname or a realm.
- **The alert cooldown fix (v0.2.1)** in a real "runs in and out of view" case. The offline test covers it.

## Known limits
- No combat log in Forever, so a ganker you never see a nameplate for is not detected. Enemy nameplates (`V`) help.
- A sync of 100 notes takes about 2 minutes, because of the 1-message-per-second limit.
- `/gg add Ana camped me` creates the player "Ana Camped". Two words are always the name, and the addon prints "Did you mean …?" when another Ana is listed.
- No addon messages in dungeons, raids or battlegrounds. The send queue waits until you leave.
- The minimap icon sits slightly off center in its ring. This is cosmetic, and centering it in code did not fully fix it.

## Ideas for later
In the [addon README](GuildGrudge/README.md): map pins, seasonal leaderboards, an export string for Discord.
