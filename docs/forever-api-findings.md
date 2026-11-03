# WoW: Forever API findings (2026-11-03)

Checked against Blizzard's UI source for the launch build **1.60.1.70755** (mirror: `Gethe/wow-ui-source`, branch `forever`), the beta client API dump in `Thunderz96/forever-addon-kit` (`data/forever_api.json`, build 69893), and the local client (`.build.info`: product `wowf`, 1.60.1.70707). In Blizzard's code, Forever's game type is called `camelot`.

## Client
- Forever runs the **Retail (Mainline 12.x) API**, not Classic. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`.
- Interface number: **16001**.
- The Midnight addon restrictions apply: secret values, a restricted combat log, and chat lockdown in instances.

## Breaks the addon
| Area | Finding | Evidence |
|---|---|---|
| Combat log | `CombatLogGetCurrentEventInfo` does not exist. `COMBAT_LOG_EVENT_UNFILTERED` has `HasRestrictions`, and only Blizzard's internal `C_CombatLogInternal` can read events. | `Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua` maps it to `C_CombatLog.GetCurrentEventInfo`, which is not in `C_CombatLog`. Not in the beta dump. |
| Names | Characters have a first name and a surname, unique per region. `UnitName(unit)` returns `name, surname`, so the second value is **not** a realm. The surname separator is a space ("Ana Forever"). Whispers accept `First Surname` and `First-Surname`. | `Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`, `Blizzard_ChatFrameBase/Shared/SlashCommands.lua:1163`, `ChatFrameEditBox.lua:84`, `RegionalUniqueNamesEnabled()` |
| Addon message throttle | 10 messages per prefix, +1 per second, on all chat types, whispers included. Sends past the limit return `Enum.SendAddonMessageResult.AddonMessageThrottle` (3) and are dropped. | [warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage), `ChatConstantsDocumentation.lua` |

## Works, with caveats
- `PARTY_KILL` is now a standalone event with payload `attackerGUID, targetGUID` (`SecretWhenUnitIdentityRestricted`). It can replace the combat log check for bounty claims. `GetPlayerInfoByGUID` exists.
- Secret values: unit identity (`UnitName`, `UnitClass`, `UnitRace`, `UnitGUID`) is secret only "when the unit isn't player-controlled or in the party/raid". Enemy players are player-controlled, so their identity stays readable. `UnitName` adds an exception for players in PvP. `SendAddonMessage` has `SecretArguments = "NotAllowed"`, so a secret value passed to it errors.
- `RaidNotice_AddMessage` and `SendChatMessage` exist only as deprecation shims, loaded while the `loadDeprecationFallbacks` CVar is on. The replacements are `RaidWarningUtil.AddMessage(text, colorInfo)` and `C_ChatInfo.SendChatMessage`.
- `GuildRoster` is gone, and `C_GuildInfo.GuildRoster` exists. The code already falls back to it.
- Exist: `Ambiguate`, `GetGuildRosterInfo`, `GetNumGuildMembers`, `GetServerTime`, `GetRealZoneText`, `GetSubZoneText`, `IsInGuild`, `TooltipDataProcessor`, `SOUNDKIT.RAID_WARNING`, `RAID_CLASS_COLORS`, `UISpecialFrames`, and the templates `BasicFrameTemplateWithInset` (has `TitleText`), `UIPanelScrollFrameTemplate` and `InputBoxTemplate`. Also exist: the events `ADDON_LOADED`, `PLAYER_LOGIN`, `CHAT_MSG_ADDON`, `GUILD_ROSTER_UPDATE`, `NAME_PLATE_UNIT_ADDED`, `PLAYER_TARGET_CHANGED` and `UPDATE_MOUSEOVER_UNIT`.
- Addon messages are blocked in chat lockdown (dungeons, raids, PvP matches). `C_ChatInfo.InChatMessagingLockdown()` checks for it.

## Still needs the live game
- The exact `sender` string in `CHAT_MSG_ADDON`, and the names returned by `GetGuildRosterInfo` (`First Surname`? With a realm part?). Also how `Ambiguate(name, "short")` treats a surname.
- Whether registering `COMBAT_LOG_EVENT_UNFILTERED` throws or is silently ignored.
- Whether `WHISPER` addon messages work across a realmless region.
- World PvP across rulesets: Normal needs both players to agree, and the PvP ruleset is open.
