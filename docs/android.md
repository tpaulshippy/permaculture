# Android export + QA (issue #8)

Packaging-only: Godot 4 Android preset from the same shared branch.
No gameplay fork — `scripts/`, `scenes/`, `data/` are untouched
(`tools/validate_android_preset.py` enforces this).

## What was added

- `export_presets.cfg` — preset `Android`, gradle build, **APK** format
  (`build/android/permaculture.apk`) for direct device/QA install.
  For Play delivery flip `gradle_build/export_format` to `1` (AAB).
- `icons/` — launcher icon set rasterized from `icon.svg` with Godot itself:
  `android_main_192x192.png`, `android_adaptive_foreground_432x432.png`
  (glyph on transparency), `android_adaptive_background_432x432.png`
  (solid `#C9A86A`).
- `project.godot` — two packaging-only settings, desktop behavior unchanged:
  - `display/window/handheld/orientation=4` (sensor landscape; 1280x720
    landscape-first viewer).
  - `rendering/renderer/rendering_method.mobile="gl_compatibility"`
    (widest device/emulator GPU support; desktop stays Forward Plus).
- Permissions: **none requested** (all `permissions/*=false`, no custom
  permissions). App category: game (`app_category=2`), immersive mode on.
- ABIs: `arm64-v8a` (devices) + `x86_64` (emulator coverage); 32-bit ABIs
  off per 64-bit Play requirement. `version/code=1`, `version/name="0.1.0"`,
  `package/unique_name="com.tpaulshippy.permaculture"`.

## Prerequisites (one-time, machine setup — not committed)

1. Godot 4.7.2 export templates:
   `Godot_v4.7.2-stable_export_templates.tpz` from the Godot release page,
   unzipped to `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`.
2. Android SDK (`$HOME/Android/sdk`): cmdline-tools + `platform-tools`,
   `platforms;android-34`, `build-tools;34.0.0`, `emulator`,
   `system-images;android-34;google_apis;arm64-v8a` via `sdkmanager`.
3. JDK 17+ (`JAVA_HOME`) for the gradle build; debug signing uses the
   auto-generated debug keystore (no secrets in repo).
4. Point the editor/CLI at the SDK: Godot Editor Settings →
   `export/android/android_sdk_path` (or `ANDROID_HOME` env for CLI-adjacent
   tooling), `export/android/java_sdk_path`.

## Build

```sh
godot --headless --path . --export-debug "Android" build/android/permaculture.apk
```

Validate the preset without building:

```sh
python3 tools/validate_android_preset.py
```

## QA notes (real run, this machine)

- Target: Android emulator (see Evidence below); no physical device used.
- Install: `adb install -r build/android/permaculture.apk`
- Launch: `adb shell monkey -p com.tpaulshippy.permaculture 1`
- Result: app launches to the terrain MVP scene (seeded Sonoran heightmap,
  terrain render mode), holds stable, no crashes, no permission prompts
  (none requested). Touch input: the MVP scene is a static viewer with no
  camera/gameplay input on any platform — same shared code as desktop, so
  there is nothing touch-specific to exercise yet (orbit/place controls do
  not exist in the shared codebase; adding them is out of scope for this
  packaging issue).
- Perf: terrain mesh is a single 20x20-cell ArrayMesh; first-frame render on
  the emulator was smooth with no ANR. See `docs/evidence/8/`.

## Evidence

- `docs/evidence/8/demo.mp4` — real screen recording of the app running
  (emulator `screenrecord`), plus `still.png`.
- `docs/evidence/8/validator.log` — preset validator output.
- `docs/evidence/8/commands.log` — exact build/install/QA commands run.

Release signing (not done here): create a release keystore, set
`keystore/release_*` via environment/CI secrets — never commit it.
