# Findings

Notes from reverse engineering the front end (game build 26133805).

## Main-menu 3D scene (`/Game/Griffin/Maps/L_FrontEnd`)

What makes it white, in order of importance:

1. **`SM_FrontEndStudio_01`** (2 actors): a photo-studio cyclorama.
   - slot 0: `MI_FrontendFloor_Lit` (lit, `Param` = 0.307 0.276 0.232)
   - slot 1: `MI_FrontendFloor_Unlit` (unlit, `Param` = 0.950 0.831 0.665) – the white wall
2. **Sky atmosphere** behind it: also renders near-white. Hiding only the studio shows a blue sky.
3. `SM_LiminalSphereBackground` (6 actors, unlit cream) and `Plane` (unlit floor): mostly hidden
   behind the studio; hiding them alone changes almost nothing.
4. `BP_FogPlane_VFX_C` (10 actors): soft white haze cards.

Everything uses `M_FrontendFloor_Unlit` as the base material, with a single vector parameter `Param`
(base/emissive color). Tinting through a `MaterialInstanceDynamic` works.

Other facts:

- Lighting rig `BP_GlobalLighting_HDRI_Base`: DirectionalLight 250, SkyLight 40 (HDRI cubemap
  `TC_studio_small_09`), ExponentialHeightFog (density 0.02, **hidden by default**), SkyAtmosphere,
  hidden `SM_Sky_Dome_01`. Plus about 16 spot and point lights for the vehicle.
- Turning the height fog on with a dim sky light gives a brown fog look, but it hides the vehicle.
- `LevelSequenceActor`s (`LS_SplashScreen_01`) are not playing on the main menu.
- Dimming lights does not darken the wall, because it's unlit.

Variants tried (screenshots in `docs/img`):

- `after.jpg`: wall teal, floor brown (current default)
- `after_teal_floor.jpg`: wall and floor teal
- `black_void.jpg`: studio set hidden plus atmosphere hidden: a black background with the vehicle fully
  lit, but the floor has black gaps between the sand pieces

## UI (UMG)

- The game's widget framework is "Fuse": `FuseImage`, `FuseBorder`, `FuseTextBlock`, `FuseOverlay`, ...
  These are subclasses of the UMG widgets.
- Panels are mostly `Image`/`Border` brushes using procedural materials (`MI_UI_Squircle_*`,
  `MI_UI_Pill_*`, `MI_UI_*Backing*`) tinted by the widget's color. The cream "paper" color is roughly
  (0.59 0.57 0.53) to (0.94 0.90 0.86) linear.
- Text is mostly a plain `FuseTextBlock` with `ColorAndOpacity` set directly (near black `0.01–0.02`
  on paper, cream `0.78 0.73 0.67` on dark). A few use CommonUI style classes such as
  `BP_Style_Body_Default_Dark_Text`.
- The main-menu backdrop UI image `Img_Background` uses `MI_UI_Background_Dial_Right` (the faint dial
  circles) with a dark 40% tint. Don't remove it.
- The bottom hint bar is `WBP_ActionBar` → `WBP_Input_Dark_Btn` → `Text_ActionName`. "Dark" here means
  dark text for light backgrounds, not a dark theme. There's no native dark theme: no theme, palette
  or UI color-scheme assets in the pak index, and no UI theme option in `GameUserSettings.ini`.
- UI material parameter collections: only HUD ones (`MPC_HUD_Colors`, `MPC_HUD_Parameters`) and
  `MPC_UI_CommonParametters` (no colors).

## UE4SS notes

- Blueprint `RegisterHook` does not work in this game (ProcessLocalScriptFunction is inlined),
  so everything is polled with `LoopInGameThreadWithDelay` and applied idempotently.
- Iterating every `Actor` and touching components caused crashes. Iterate specific classes
  (`StaticMeshActor`, ...) and check `IsValid()` before each step.
- `ExecuteConsoleCommand` `ShowFlag.*` toggles were unreliable for testing; use component visibility.
