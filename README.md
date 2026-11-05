# Warcraft Simulator

A Warcraft III real-time strategy game that runs inside World of Warcraft (Classic Era and WoW Forever), drawn with WoW's own 3D models.

- The Human Alliance, the Orcish Horde, the Undead Scourge and the Night Elf Sentinels, with the Warcraft III units, buildings, upgrades and tech tiers
- Heroes that level up, learn abilities and carry items; neutral Tavern heroes
- Creep camps, shops, day and night, upkeep
- Blizzard's 1v1 melee maps, with high ground
- A computer opponent (Easy, Normal, Hard)
- 1v1 multiplayer between two players with the addon (lockstep over addon whispers)

## Playing

`/warsim` (or `/skirmish`, or the minimap button) opens the game. Pick a race and a difficulty and press **Play**. **Options** has the map, fog of war and other settings; **Multiplayer** invites another player.

## Layout

- `Engine/` – the game itself (units, combat, races, AI). No WoW API calls, so it runs in plain Lua 5.1 for testing.
- `UI/` – drawing, input, the interface and multiplayer (`UI/Net.lua`).
- Unit, ability and upgrade numbers come from Warcraft III's game data.

## Releasing

Tag a version (`git tag v0.17.0 && git push --tags`). The `.pkgmeta` packages the `WarcraftSimulator` folder for CurseForge.
