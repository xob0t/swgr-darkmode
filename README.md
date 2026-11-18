# DarkMode for STAR WARS Galactic Racer

A UE4SS Lua mod that makes the game's very bright, white front end dark.

Work in progress. So far only the main-menu **3D scene** is done; the UI widgets (panels, text) are next.

| Before | After |
|---|---|
| ![before](docs/img/before.jpg) | ![after](docs/img/after.jpg) |

## Requirements

- STAR WARS Galactic Racer (Steam build 26133805, UE 5.7.4)
- Official [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) v4.0.0 plus the Galactic Racer custom config
  ([UE4SS PR #1502](https://github.com/UE4SS-RE/RE-UE4SS/pull/1502)): copy the five
  `UE4SS_Signatures/*.lua` files next to `UE4SS.dll`.

## Install

Copy `mod/DarkMode` into `Griffin/Binaries/Win64/ue4ss/Mods/` and create an empty `enabled.txt` in it
(or add `DarkMode : 1` to `mods.txt`).

## What it does now

The menus are drawn over a white "photo studio" set in the `L_FrontEnd` level. The mod tints that set
instead of removing it (removing it leaves black holes in the floor):

- `SM_FrontEndStudio_01` slot 1 (unlit cyclorama wall) → dark teal
- `SM_FrontEndStudio_01` slot 0 (lit floor) → dark brown
- `SM_LiminalSphereBackground` (unlit cream spheres) and `BP_FogPlane_VFX_C` (white haze cards) → hidden
- the lighting rig's directional light → 20%

No Blueprint hooks are used, so it isn't affected by
[UE4SS #1503](https://github.com/UE4SS-RE/RE-UE4SS/issues/1503).

Colors are in `CONFIG` at the top of `mod/DarkMode/Scripts/main.lua` (linear RGB).

## Repo layout

- `mod/DarkMode` – the mod
- `dev/` – development tooling (not needed to play):
  - `DarkModeDev` – loader mod that hot-reloads `dev/live.lua` every 0.5 s and runs its `tick()`
  - `live.lua` – the experiment harness used to find what makes the scene white
  - `DarkProbe` – read-only probe that dumps on-screen widget trees, colors, brushes and materials
  - `tools/` – screenshot runner, brightness measurement, contact sheets, game restart
- `docs/FINDINGS.md` – notes on how the scene and UI are built
