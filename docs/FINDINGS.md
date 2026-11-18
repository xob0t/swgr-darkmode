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
- The CommonUI text style classes (`BP_Style_*`) already use cream/white. Dark text comes from
  per-widget `ColorAndOpacity`, `Border.ContentColorAndOpacity` tint wrappers (`B_TextTint`), and the
  rich-text tables (`DT_RichText_Body`, `_Body_Dark_Italic`, `_Body_Map`, `_Display_A`).

## UI rule engine (`ui.lua`)

There is no global palette, so the mod recolors by **component type**, never by menu. Every on-screen
root (`WBP_*` in the viewport) is walked, and what's behind each widget is tracked
(Overlay paint order, Border backgrounds):

| Component | Detected by | Becomes |
|---|---|---|
| paper panel | Image/Border, light + unsaturated, resource or widget name looks like a panel (`Squircle`, `Pill`, `Backing`, `TileButton`, `_Fill`, `Grunge`, `Img_Tile_Base`, `Img_Backer`, ...) | dark panel |
| screen layer | widget name `Background`/`Vignette`/`ColorFill`/..., resource `Vignette`/`Gradient`/`Blur`; counts even at low alpha (scrims) | dark if light |
| outline | `Stroke`/`Outline`, light + unsaturated | muted outline |
| decor | `Deco`, `Swoop`, `Line`, `Dial`, `Barcode`, title graphics | untouched; never a background |
| artwork | thumbnails, portraits, icons, textures, colored panels | untouched; text on it untouched |
| text | `TextBlock` color too dark on a dark/darkened background | cream |
| tint wrapper | `Border.ContentColorAndOpacity` / `UserWidget.ColorAndOpacity` too dark | cream |
| rich text | `RichTextBlock.DefaultTextStyle` too dark | `SetDefaultColorAndOpacity(cream)` |

Details that mattered:

- List and tile views (`ListViewBase`) generate their entries: walk `GetDisplayedEntryWidgets()`.
- The button-hint bar (`WBP_ActionBar` → `FuseBoundActionBar`, a `DynamicEntryBoxBase`) also pools its
  entries (`WBP_Input_Dark_Btn`): walk `GetAllEntries()`. They have no panel children, so without this the
  hints stay dark grey on the darkened pill.
- `RetainerBox` caches its content in a render target. Call `RequestRender()` after recoloring inside it.
- The card frames on Logbook/Parts are the `Img_Tile_Stroke*` outline images, not the grunge fill.
- "Background" in a *texture* name is not a backdrop: `T_UI_Insignia_Background_*` are player banners.
- Blank keyboard key caps (`T_UI_Cntrl_*Blank*`, used for letter keys such as C) are drawn as an image
  plus a text letter; they become a cream cap with a dark letter, matching the textured input icons
  (whose glyphs are cut-outs that show the darkened bar, about sRGB 60).

### Getting the colors in before the first frame

A scan pass only runs every ~90 frames (sooner when widgets are created) and takes ~15 frames, so
anything it fixes is visible in its original white first. Three mechanisms remove that:

1. **Template learning.** A UserWidget's tree is copied from its class's template tree
   (`<class>:WidgetTree.<name>`) when it initializes. Every recolor decision is also recorded for the
   template it came from (`learned.txt`, shipped with ~160 entries from a menu tour, extended at
   runtime), and a class's learned templates are patched from the `NotifyOnNewObject` callback,
   before the new instance copies them. Screens then come up dark from their first frame.
   - A widget class that inherits another widget Blueprint without its own tree uses its parent's tree
     (`WBP_PausePaddock_C` → `WBP_Pause_C`). Walk `GetSuperStruct()` to the class that owns one.
   - The CDO/archetype flags check (`HasAnyFlags(CDO | Archetype | NeedLoad | WasLoaded)`) keeps the
     callback away from objects being loaded.
2. **Setter hooks.** Hover/focus states and reactivated screens recolor widgets at runtime through the
   native setters (`TextBlock/Image/UserWidget:SetColorAndOpacity`, `Border:SetBrushColor`,
   `SetContentColorAndOpacity`, `RichTextBlock:SetDefaultColorAndOpacity`). Native `RegisterHook`
   works for these (also when called from Blueprints), and a post-hook re-applies our color in the same
   frame for known targets and learned templates. About 40 calls/s in menus, ~1/s in gameplay.
   Re-applying is conditional on the new color (only light+grey panels are darkened, only too-dark
   text is lightened), so the game's accent and highlight colors pass through.
3. **Keeping targets** across screens until the next GC (CommonUI keeps deactivated screens around).

UMG animations write properties through native C++ setters, not the hookable UFunctions, and they run
after the mod's tick. `WBP_Background_Blur`'s `Anim_In` only animates `BlurStrength` and the tint's
`RenderOpacity`, so it's harmless once the tint itself is dark.

CommonUI creates a new pause screen (`WBP_PausePaddock_C_<n>`) every time you come back from the Logbook
or Settings; with the template patched it is dark from its first frame.

Performance: cost is dominated by reflection calls. Type facts are cached per class and names per
object address. Root candidates are the top-level UserWidgets, recorded through `NotifyOnNewObject`
(widgets whose outer isn't a `WidgetTree`), seeded once with `FindAllOf`. A cycle (roots, walk, merge,
apply) is time-sliced over frames with a 1 ms budget. Measured in the hub: ~0.1 ms per frame on
average, 3-6 ms worst single frame. Before the optimizations a single walk was about 190 ms.

- `StaticFindObject` and `FindFirstOf`/`FindAllOf` scan the whole object array in this game (UE4SS
  logs "FUObjectHashTables unavailable"): 2 ms per hit, 8.6 ms per miss, 10 ms per `FindFirstOf`. Never
  call them in a loop; cache what they return and re-check it with `IsValid()`.
- This game garbage-collects every ~10 s. Freed addresses are reused right away by new objects, often
  of the same class, so address-keyed caches (names, class facts, targets) must be dropped after a GC.
  A canary object (`StaticConstructObject` of a plain `Object`, unreferenced) tells us when one ran:
  `IsValid()` on it turns false.

## UE4SS notes

- Blueprint `RegisterHook` does not work in this game (ProcessLocalScriptFunction is inlined),
  so everything is polled from frame/timer loops and applied idempotently.
- UE4SS can't call into the engine from Lua **coroutines** ("lua state has no instance"). Use explicit
  work stacks for time slicing.
- **Call `IsValid()` before every call on an object, every time.** Lua `pcall` does not catch access
  violations; they crash the game. Two cases bit us (both crashed on Continue Campaign):
  - UE4SS wraps a null pointer in a non-nil userdata (e.g. `GetOuter()` of an object with no outer);
    `if outer then outer:GetClass()` reads address 0x10.
  - Anything kept from an earlier frame may have been destroyed (a time-sliced cycle spans ~15 frames,
    and a level change can happen in between). `IsValid()` does track garbage collection correctly.
- `NotifyOnNewObject` callbacks run inside object construction (on the game thread; UE4SS queues ones
  from other threads). Keep them short and check every object with `IsValid()`.
- Native `RegisterHook` (UFunctions implemented in C++) works, including when Blueprints call them.
- A callback that returns `true` unregisters itself (`NotifyOnNewObject`).
- UE4SS returns a new Lua userdata per object access, so key tables by `obj:GetAddress()`, not by the
  userdata.
- `IsA("/Script/...")` with a string path is slow; resolve the UClass once with `StaticFindObject`.
- Iterating every `Actor` and touching components caused crashes. Iterate specific classes
  (`StaticMeshActor`, ...) and check `IsValid()` before each step.
- `ExecuteConsoleCommand` `ShowFlag.*` toggles were unreliable for testing; use component visibility.

## Screens checked (dark, readable)

Main menu (Campaign, Scenarios, Arcade, Multiplayer tabs), Settings (all six tabs), Logbook (Main,
Parts, Abilities), Scenario details, Arcade event details, Customize, Customize Vehicle / Edit Vehicle,
Customize Player Banner, Party panel, Quit and Exit dialogs, and in the campaign hub: Pause, Build, Map,
Exit to Main Menu dialog, Hibi's Shop (garage) and its upgrade picker. Button-hint bars on all of these.
Continue Campaign / Exit to Main Menu round trips (4x) without crashes. Logbook/Settings → Pause and
gameplay → Pause recorded at 30 fps with no light frames.

Not checked: race loading screens, the in-race HUD/pause and post-race results (starting a race would
change campaign or arcade stats), online multiplayer lobbies.
