# DarkMode for STAR WARS Galactic Racer

The game's menus are bright white. This mod makes them dark.

| Before | After |
|---|---|
| ![main menu before](docs/img/compare/main_campaign_tab_before.jpg) | ![main menu after](docs/img/compare/main_campaign_tab_after.jpg) |

More in [Screenshots](#screenshots).

## What it changes

- **3D backdrops:** the white photo studio behind the main menu becomes a dark teal wall with a dark
  brown floor, and the white backdrop behind vehicle select and loadout in the planet hubs becomes dark
  teal.
- **Menus and dialogs:** white panels, cards and backgrounds become dark grey (panels inside panels a
  shade lighter, so the layout stays readable), and dark text on them becomes the game's own cream text
  color.
- **Left alone:** artwork, character portraits, icons, colored highlights and the in-race HUD.

It recolors the shared building blocks (panels, cards, text) rather than individual screens, so menus
that weren't tested should be covered too.

## Requirements

STAR WARS Galactic Racer on Steam, plus UE4SS. Either of these works:

- **[UE4SS Galactic Racer Edition](https://www.nexusmods.com/starwarsgalacticracer/mods/2)** (Nexus Mods,
  a UE4SS fork for this game). The easiest option until the official release supports the game: extract
  it into `STAR WARS Galactic Racer\Griffin\Binaries\Win64`.
- **Official [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) v4.0.0** with the Galactic Racer
  signatures: copy the
  [`UE4SS_Signatures` folder](https://github.com/xob0t/RE-UE4SS/tree/add-star-wars-galactic-racer-config/assets/CustomGameConfigs/Star%20Wars%20Galactic%20Racer)
  next to `UE4SS.dll`. Once [UE4SS PR #1502](https://github.com/UE4SS-RE/RE-UE4SS/pull/1502) is merged and
  released, this step goes away.

## Install

1. Download `DarkMode-vX.Y.Z.zip` from [Releases](../../releases).
2. Extract it into `STAR WARS Galactic Racer\Griffin\Binaries\Win64`. This creates
   `ue4ss\Mods\DarkMode`.
3. Start the game.

To update, extract the new version over the old one. To uninstall, delete `ue4ss\Mods\DarkMode`.

## Changing the colors

Open the files in `ue4ss\Mods\DarkMode\Scripts` in a text editor. Colors are linear RGB values from 0 to 1.

- `main.lua`, `CONFIG`: the backdrop (`wall`, `floor`) and how much the light is dimmed
  (`sun_scale`). Set `ui = false` to darken only the backdrop and leave the menus as they are.
- `ui.lua`, `CFG`: the menus (`panel`, `raised`, `outline`, `text`).

## Good to know

- The first time you open a screen the mod hasn't seen before, it may show white for a moment. The mod
  remembers it (in `Scripts\learned.txt`) and the screen opens dark from then on.
- It costs about 0.1 ms per frame.

## Screenshots

Before on the left, after on the right.

| Before | After |
|---|---|
| ![Main menu: Scenarios before](docs/img/compare/main_scenarios_tab_before.jpg)<br>Main menu: Scenarios | ![Main menu: Scenarios after](docs/img/compare/main_scenarios_tab_after.jpg)<br>Main menu: Scenarios |
| ![Main menu: Arcade before](docs/img/compare/main_arcade_tab_before.jpg)<br>Main menu: Arcade | ![Main menu: Arcade after](docs/img/compare/main_arcade_tab_after.jpg)<br>Main menu: Arcade |
| ![Main menu: Multiplayer before](docs/img/compare/main_multiplayer_tab_before.jpg)<br>Main menu: Multiplayer | ![Main menu: Multiplayer after](docs/img/compare/main_multiplayer_tab_after.jpg)<br>Main menu: Multiplayer |
| ![Settings: Gameplay before](docs/img/compare/settings_gameplay_before.jpg)<br>Settings: Gameplay | ![Settings: Gameplay after](docs/img/compare/settings_gameplay_after.jpg)<br>Settings: Gameplay |
| ![Settings: Visuals before](docs/img/compare/settings_visuals_before.jpg)<br>Settings: Visuals | ![Settings: Visuals after](docs/img/compare/settings_visuals_after.jpg)<br>Settings: Visuals |
| ![Logbook before](docs/img/compare/logbook_before.jpg)<br>Logbook | ![Logbook after](docs/img/compare/logbook_after.jpg)<br>Logbook |
| ![Quit dialog before](docs/img/compare/quit_dialog_before.jpg)<br>Quit dialog | ![Quit dialog after](docs/img/compare/quit_dialog_after.jpg)<br>Quit dialog |
| ![Vehicle select (planet hub) before](docs/img/compare/vehicle_select_hub_before.jpg)<br>Vehicle select (planet hub) | ![Vehicle select (planet hub) after](docs/img/compare/vehicle_select_hub_after.jpg)<br>Vehicle select (planet hub) |
| ![Loadout before](docs/img/compare/loadout_before.jpg)<br>Loadout | ![Loadout after](docs/img/compare/loadout_after.jpg)<br>Loadout |

## How it works

The game has no dark theme or color palette to switch, so the mod classifies widgets by type (panel,
outline, text, artwork) and recolors them. To avoid white flashes it also patches the templates new
screens are built from, and hooks the game's color setters to catch hover and focus changes. Details,
findings and UE4SS notes are in [docs/FINDINGS.md](docs/FINDINGS.md).
