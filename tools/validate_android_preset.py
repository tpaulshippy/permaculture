#!/usr/bin/env python3
"""Validate the Android export preset (issue #8). Packaging only.

Checks:
  - export_presets.cfg parses (no interpolation) and the Android preset is
    complete/consistent (APK format, package id, version, icons resolve to
    real files, zero permissions requested, arm64 + x86_64 ABIs, non-XR).
  - icons/ PNGs exist at the sizes the preset requires (truncation-safe).
  - project.godot, matched on whole uncommented lines, keeps desktop
    Forward Plus and adds only the documented mobile packaging overrides
    (orientation, gl_compatibility, ETC2/ASTC import).
  - No gameplay fork: committed diff vs origin/main plus worktree changes
    stay inside the packaging allowlist (exact files, prefix dirs only),
    and the project.godot key diff vs base touches only documented
    packaging keys. Any git inspection failure is itself a failure.

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
    cp = configparser.ConfigParser(strict=False, interpolation=None)
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

        raw = f.read(8)
        if len(raw) != 8:
            return None
        w, h = struct.unpack(">II", raw)
        return (w, h)


def run_git(*args):
    out = subprocess.run(
        ["git"] + list(args),
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        return None
    return out.stdout


def parse_status_paths(text):
    changed = []
    for line in text.splitlines():
        # Format: XY <path> [-> <orig>]. Untracked shows as "?? <path>".
        path = line[3:].strip().strip('"')
        if " -> " in path:
            path = path.split(" -> ", 1)[1].strip()
        if path:
            changed.append(path)
    return sorted(changed)


def git_committed_vs_base():
    base = run_git("merge-base", "HEAD", "origin/main")
    if base is None:
        return None
    diff = run_git("diff", "--name-only", base.strip(), "HEAD", "--", ".")
    if diff is None:
        return None
    return sorted(p for p in (ln.strip() for ln in diff.splitlines()) if p)


def git_worktree_changed():
    out = run_git("status", "--porcelain", "--untracked-files=all", "--", ".")
    if out is None:
        return None
    return parse_status_paths(out)


def proj_kv(text):
    """Godot cfg key=value pairs, ignoring section headers and ';' comments."""
    kv = {}
    for ln in text.splitlines():
        s = ln.strip()
        if not s or s.startswith(";") or s.startswith("["):
            continue
        if "=" not in s:
            continue
        k, _, v = s.partition("=")
        kv[k.strip()] = v.strip()
    return kv


# project.godot keys this packaging issue is allowed to add/change vs base.
# (Section-relative keys as they literally appear under [display]/[rendering].)
PACKAGING_PROJ_KEYS = {
    "window/handheld/orientation",
    "renderer/rendering_method.mobile",
    "textures/vram_compression/import_etc2_astc",
}


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
    # Line-exact matches: a ';'-commented line must NOT satisfy these checks.
    proj = os.path.join(REPO, "project.godot")
    with open(proj, encoding="utf-8") as f:
        proj_text = f.read()
    proj_lines = set()
    for ln in proj_text.splitlines():
        s = ln.strip()
        if s and not s.startswith(";"):
            proj_lines.add(s)
    hash_comments = [
        ln for ln in proj_text.splitlines() if ln.lstrip().startswith("#")
    ]
    check(not hash_comments,
          "project.godot uses ';' comments (Godot cfg has no '#' comments): %s"
          % hash_comments)
    check('renderer/rendering_method="forward_plus"' in proj_lines,
          "desktop renderer stays forward_plus")
    check('renderer/rendering_method.mobile="gl_compatibility"' in proj_lines,
          "mobile renderer override is gl_compatibility")
    check("textures/vram_compression/import_etc2_astc=true" in proj_lines,
          "ETC2/ASTC import enabled (Android export requirement)")
    check("window/handheld/orientation=4" in proj_lines,
          "handheld orientation is sensor_landscape (4)")

    # No gameplay fork: committed diff vs origin/main AND worktree changes
    # must be packaging-only. Exact file matches; prefixes only for dirs.
    allowed_files = {
        "export_presets.cfg",
        "project.godot",
        ".gitignore",
        "docs/android.md",
        "tools/validate_android_preset.py",
    }
    allowed_dirs = (
        "icons/",
        "docs/evidence/8/",
    )
    committed = git_committed_vs_base()
    worktree = git_worktree_changed()
    if committed is None or worktree is None:
        check(False, "git inspection failed (merge-base/diff/status) — "
                     "cannot prove no gameplay fork")
    else:
        changed = sorted(set(committed) | set(worktree))
        print("committed vs origin/main: %s" % committed)
        print("worktree changes: %s" % worktree)
        bad = [c for c in changed
               if c not in allowed_files
               and not c.startswith(allowed_dirs)]
        check(not bad, "no gameplay fork (non-packaging changes: %s)" % bad)

    # project.godot key diff vs base: only documented packaging keys may be
    # added/changed; nothing else (e.g. main scene, desktop settings).
    base_ref = run_git("merge-base", "HEAD", "origin/main")
    base_text = (run_git("show", "%s:project.godot" % base_ref.strip())
                 if base_ref else None)
    if base_text is None:
        check(False, "could not read base project.godot for key diff — "
                     "cannot prove no gameplay fork")
    else:
        base_kv = proj_kv(base_text)
        cur_kv = proj_kv(proj_text)
        removed = sorted(k for k in base_kv if k not in cur_kv)
        altered = sorted(k for k in cur_kv
                         if k not in base_kv or base_kv[k] != cur_kv[k])
        unexpected = sorted(k for k in altered if k not in PACKAGING_PROJ_KEYS)
        check(not removed, "project.godot removes no keys: %s" % removed)
        check(not unexpected,
              "project.godot changes are packaging-only: %s" % unexpected)

    print("---")
    if FAILURES:
        print("%d FAILURE(S)" % len(FAILURES))
        return 1
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
