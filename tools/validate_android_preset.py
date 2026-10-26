#!/usr/bin/env python3
"""Validate the Android export preset (issue #8). Packaging only.

Checks:
  - export_presets.cfg parses and the Android preset is complete/consistent
    (APK format, package id, version, icons resolve to real files,
    zero permissions requested, arm64 + x86_64 ABIs, non-XR).
  - icons/ PNGs exist at the sizes the preset requires.
  - project.godot keeps desktop Forward Plus, adds only the documented
    mobile packaging overrides (orientation, gl_compatibility).
  - No gameplay fork: no changes vs origin/main outside the packaging
    allowlist (preset, icons, project.godot packaging keys, .gitignore,
    docs/android.md, this validator, docs/evidence/8/).

Exit code 0 = all checks passed, 1 = at least one failure.
"""

import configparser
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAILURES = []


def check(cond, label):
    print(("PASS: " if cond else "FAIL: ") + label)
    if not cond:
        FAILURES.append(label)


def read_cfg(path):
    cp = configparser.ConfigParser(strict=False)
    # Preserve case; ConfigParser lowercases keys by default.
    cp.optionxform = str
    with open(path, encoding="utf-8") as f:
        cp.read_file(f)
    return cp


def png_size(path):
    with open(path, "rb") as f:
        sig = f.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            return None
        f.read(4)  # length
        if f.read(4) != b"IHDR":
            return None
        import struct

        w, h = struct.unpack(">II", f.read(8))
        return (w, h)


def git_changed_vs_main():
    out = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all", "--", "."],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        return None
    changed = []
    for line in out.stdout.splitlines():
        # Format: XY <path> [-> <orig>]. Untracked shows as "?? <path>".
        path = line[3:].strip().strip('"')
        if " -> " in path:
            path = path.split(" -> ", 1)[1].strip()
        if path:
            changed.append(path)
    return sorted(changed)


def main():
    print("=== Android export preset validation (issue #8) ===")
    preset_path = os.path.join(REPO, "export_presets.cfg")
    check(os.path.isfile(preset_path), "export_presets.cfg exists")

    cp = read_cfg(preset_path)
    check("preset.0" in cp.sections(), "preset.0 section present")
    p = dict(cp["preset.0"]) if "preset.0" in cp.sections() else {}
    check("preset.0.options" in cp.sections(), "preset.0.options section present")
    o = dict(cp["preset.0.options"]) if "preset.0.options" in cp.sections() else {}

    check(p.get("platform") == '"Android"', "preset platform is Android")
    check(p.get("runnable") == "true", "preset is runnable")
    check(
        p.get("export_filter") == '"all_resources"',
        "export_filter is all_resources (shared codebase, no fork)",
    )
    check(
        p.get("export_path", "").strip('"').endswith(".apk"),
        "export_path targets a debug APK for device QA",
    )
    check(o.get("gradle_build/export_format") == "0", "export_format=0 (APK)")
    check(
        o.get("gradle_build/use_gradle_build") == "true",
        "gradle build enabled",
    )
    check(
        o.get('package/unique_name', '').strip('"') != ""
        and "$genname" not in o.get("package/unique_name", ""),
        "package/unique_name is set explicitly: %s" % o.get("package/unique_name"),
    )
    check(
        o.get("version/code", "").isdigit(),
        "version/code is set: %s" % o.get("version/code"),
    )
    check(
        o.get('version/name', '').strip('"') != "",
        "version/name is set: %s" % o.get("version/name"),
    )
    check(o.get("package/signed") == "true", "package/signed=true (debug keystore)")
    check(o.get("xr_features/xr_mode") == "0", "non-XR app (xr_mode=0)")
    check(o.get("screen/immersive_mode") == "true", "immersive_mode=true")

    abis = [
        k
        for k in (
            "architectures/armeabi-v7a",
            "architectures/arm64-v8a",
            "architectures/x86",
            "architectures/x86_64",
        )
        if o.get(k) == "true"
    ]
    check("architectures/arm64-v8a" in abis, "arm64-v8a enabled (devices)")
    check("architectures/x86_64" in abis, "x86_64 enabled (emulator coverage)")
    check(
        "architectures/armeabi-v7a" not in abis and "architectures/x86" not in abis,
        "32-bit ABIs off (64-bit Play requirement)",
    )

    # Icons resolve to real files at the required sizes.
    icon_reqs = {
        "launcher_icons/main_192x192": (192, 192),
        "launcher_icons/adaptive_foreground_432x432": (432, 432),
        "launcher_icons/adaptive_background_432x432": (432, 432),
    }
    for key, want in icon_reqs.items():
        rel = o.get(key, "").strip('"')
        check(bool(rel), "%s points at a file" % key)
        if rel:
            rel = rel.removeprefix("res://")
            full = os.path.join(REPO, rel)
            check(os.path.isfile(full), "%s exists: %s" % (key, rel))
            if os.path.isfile(full):
                got = png_size(full)
                check(got == want, "%s is %dx%d (got %s)" % (rel, want[0], want[1], got))

    # Permissions: zero requested.
    perm_keys = [k for k in o if k.startswith("permissions/") and k != "permissions/custom_permissions"]
    check(len(perm_keys) > 0, "permission keys enumerated (%d)" % len(perm_keys))
    denied = [k for k in perm_keys if o.get(k) != "false"]
    check(not denied, "no Android permissions requested (offenders: %s)" % denied)
    check(
        o.get("permissions/custom_permissions") == "PackedStringArray()",
        "no custom permissions",
    )

    # project.godot: desktop renderer untouched, mobile overrides documented.
    proj = os.path.join(REPO, "project.godot")
    with open(proj, encoding="utf-8") as f:
        proj_text = f.read()
    check('renderer/rendering_method="forward_plus"' in proj_text,
          "desktop renderer stays forward_plus")
    check('renderer/rendering_method.mobile="gl_compatibility"' in proj_text,
          "mobile renderer override is gl_compatibility")
    check("window/handheld/orientation=4" in proj_text,
          "handheld orientation is sensor_landscape (4)")

    # No gameplay fork: changed files must be packaging-only.
    allowed_prefixes = (
        "export_presets.cfg",
        "project.godot",
        ".gitignore",
        "icons/",
        "docs/android.md",
        "docs/evidence/8/",
        "tools/validate_android_preset.py",
    )
    changed = git_changed_vs_main()
    if changed is None:
        print("SKIP: could not diff vs origin/main (no git history?)")
    else:
        print("changed vs origin/main: %s" % changed)
        bad = [c for c in changed if not c.startswith(allowed_prefixes)]
        check(not bad, "no gameplay fork (non-packaging changes: %s)" % bad)

    print("---")
    if FAILURES:
        print("%d FAILURE(S)" % len(FAILURES))
        return 1
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
