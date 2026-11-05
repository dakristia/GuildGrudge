# Guild Grudge

A guild kill-on-sight list addon for World of Warcraft: Forever.

- `GuildGrudge/`: the addon itself. This folder goes in `Interface/AddOns/`. Its own [README](GuildGrudge/README.md) is for players.
- `tests/`: offline tests. `wow_mock.lua` fakes a WoW client: a shared guild network, the addon-message throttle, timers and Forever's two-part names. `run.lua` holds the tests.
- `docs/forever-api-findings.md`: what Forever's API does and doesn't allow, with sources.

## Installing
With WowUp:
1. Open "Get Addons".
2. Pick WoW Forever at the top.
3. Choose "Install from URL".
4. Paste `https://github.com/dakristia/GuildGrudge`.

WowUp then updates the addon like any other addon.

By hand:
1. Download `GuildGrudge-<version>-forever.zip` from the [Releases page](https://github.com/dakristia/GuildGrudge/releases).
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Check that the result is `AddOns\GuildGrudge\GuildGrudge.toc`.

Do not use `Extract to <folder name>`. It makes an extra folder level, and the game then does not find the addon.

For developers: pushing a tag `vX.Y.Z` builds the zip and publishes the release (`.github/workflows/release.yml`).

## Running the tests
WoW uses Lua 5.1. The tests run in a small Docker image that has it:

```sh
docker build -t gg-lua51 tests
docker run --rm -v "$PWD":/src:ro gg-lua51 lua5.1 tests/run.lua
```

The mock only knows what Blizzard's UI source and the beta API dump say. The live client may differ, especially for the sender and roster name formats (see "Still needs the live game" in the findings doc).
