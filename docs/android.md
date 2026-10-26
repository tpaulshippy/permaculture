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
4. Android build template (generated, gitignored under `android/` — install
   once per checkout, same as the editor's Project menu does):
   ```sh
   TDIR="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
   mkdir -p android/build && unzip -q -o "$TDIR/android_source.zip" -d android/build
   touch android/build/.gdignore
   printf '4.7.2.stable\n' > android/.build_version
   ```
   Layout must be `android/build/build.gradle` (that is what the exporter
   checks) with the template identifier in `android/.build_version`
   (else: "no version info for it exists"), plus
   `rendering/textures/vram_compression/import_etc2_astc=true` in
   `project.godot` (already committed — without it the export stops with
   "ETC2/ASTC texture compression is required"). Note: `project.godot`
   comments must use `;` (Godot cfg has no `#` comments — a `#` line silently
   glues onto the next key and disables it; the validator guards this).
4. Point the editor/CLI at the SDK: Godot Editor Settings →
   `export/android/android_sdk_path` (or `ANDROID_HOME` env for CLI-adjacent
   tooling), `export/android/java_sdk_path`.

## Build

```sh
godot --headless --path . --export-debug "Android" build/android/permaculture.apk
```

Play delivery (AAB, release-signed) from the same preset: flip
`gradle_build/export_format` to `1` (AAB), then export to a separate path
so the debug APK evidence build is never overwritten:

```sh
godot --headless --path . --export-release "Android" build/android/permaculture.aab
```

Release signing (not done here): create a release keystore, set
`keystore/release_*` via environment/CI secrets — never commit it.

Validate the preset without building:

```sh
python3 tools/validate_android_preset.py
```

## QA notes (real run, this machine, 2026-10-26)

- Target: Android emulator, AVD `perma8` (sdk_gphone64_arm64, headless,
  `emulator-5554`); no physical device used.
- Build: `godot --headless --path . --export-debug "Android"
  build/android/permaculture.apk` → 163 MB debug-signed APK, `adb install`
  reports `Success`.
- Launch: `adb shell monkey -p com.tpaulshippy.permaculture 1`; process
  confirmed via `adb shell pidof`.
- Result: app launches to the terrain MVP scene (seeded Sonoran heightmap,
  terrain render mode), holds stable, no crashes, no ANR, no permission
  prompts (none requested). On-device render matches the desktop reference
  `docs/evidence/2/terrain_topdown.png` (same camera/framing, tan Sonoran
  clear color) under the `gl_compatibility` mobile renderer.
- First launch shows Android's one-time immersive-mode hint ("Viewing full
  screen"); dismissed via the "Got it" button (uiautomator bounds
  `[1363,464][1594,590]`). Cold-start relaunch shows the app splash with the
  custom launcher icon, then the terrain scene — all captured in `demo.mp4`.
- Touch input: the MVP scene is a static viewer with no camera/gameplay input
  on any platform — same shared code as desktop, so there is nothing
  touch-specific to exercise yet (orbit/place controls do not exist in the
  shared codebase; adding them is out of scope for this packaging issue).
- Perf: terrain mesh is a single 20x20-cell ArrayMesh; render on the emulator
  was smooth with no ANR. See `docs/evidence/8/`.

## Evidence

- `docs/evidence/8/demo.mp4` — real screen recording of the app running
  (emulator `screenrecord`), plus `still.png`.
- `docs/evidence/8/validator.log` — preset validator output.
- `docs/evidence/8/commands.log` — exact build/install/QA commands run.
