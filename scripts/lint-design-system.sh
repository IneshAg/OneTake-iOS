#!/usr/bin/env python3
import sys
import os
import re
import argparse

RULES = [
    ("radius", r"cornerRadius:\s*[0-9]", "Avoid cornerRadius literals; use OTRadius tokens"),
    ("font-size", r"\.font\(\.system\(size:", "Avoid .font(.system(size:)); use Font.ot* tokens"),
    ("frame-literal", r"\.frame\([^)]*(minHeight|height|minWidth|width):\s*[0-9]{2,}", "Avoid fixed frame height/width literals; use OTControlSize or intrinsic content size"),
    ("padding-literal", r"\.padding\((\.[a-zA-Z]+,\s*)?[0-9]", "Avoid padding literals; use OTSpace tokens"),
    ("raw-color", r"Color\(UIColor\(|Color\(red:|Color\.(white|black)\.opacity", "Avoid raw Color literals; use OT color tokens"),
    ("system-button-style", r"\.buttonStyle\(\.(bordered|borderedProminent|glass|glassProminent)\)", "Avoid system button styles; use .ot() button styles"),
    ("manual-surface", r"background\(OT\.(fillField|surfaceCard|surfaceRaised),\s*in:", "Avoid hand-rolled card backgrounds; use .otCard() or OTCallout"),
    ("hidden-navbar", r"\.toolbar\(\.hidden,\s*for:\s*\.navigationBar\)", "Avoid hiding navigation bar manually; use OTScreen"),
    ("on-dark-flag", r"onDark:", "Avoid onDark parameters; use .otSurface(.camera) environment"),
]

def main():
    parser = argparse.ArgumentParser(description="Design system linter for OneTake")
    parser.add_argument("--xcode", action="store_true", help="Emit Xcode format warnings")
    parser.add_argument("--strict", action="store_true", help="Fail if any violation is found")
    parser.add_argument("--path", type=str, default=None, help="Limit scanning to a specific directory")
    args = parser.parse_args()

    # Determine script root
    script_dir = os.path.dirname(os.path.realpath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, ".."))
    baseline_file = os.path.join(script_dir, "design-lint-baseline.txt")

    if args.path:
        target_dirs = [os.path.abspath(args.path)]
    else:
        target_dirs = [os.path.join(repo_root, "OneTake"), os.path.join(repo_root, "OneTakeWidgets")]

    # Collect Swift files
    files = []
    for d in target_dirs:
        if os.path.isfile(d):
            if d.endswith(".swift"):
                files.append(d)
            continue
        for root, dirs, fnames in os.walk(d):
            # Exclude Packages/
            parts = os.path.relpath(root, repo_root).split(os.sep)
            if "Packages" in parts:
                continue
            for f in fnames:
                if f.endswith(".swift"):
                    files.append(os.path.join(root, f))

    compiled_rules = [(rid, re.compile(pat), desc) for (rid, pat, desc) in RULES]
    counts = {rid: 0 for rid, _, _ in RULES}
    violations = []

    for fpath in sorted(files):
        try:
            with open(fpath, "r", encoding="utf-8", errors="ignore") as fp:
                for line_idx, line in enumerate(fp, 1):
                    if "ot-lint:allow" in line:
                        continue
                    for rid, cregex, desc in compiled_rules:
                        if cregex.search(line):
                            counts[rid] += 1
                            violations.append((fpath, line_idx, rid, desc))
        except Exception as e:
            pass

    # Read baseline if present
    baseline = {}
    if os.path.exists(baseline_file):
        try:
            with open(baseline_file, "r", encoding="utf-8") as bf:
                for line in bf:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        parts = line.split()
                        if len(parts) >= 2:
                            baseline[parts[0]] = int(parts[1])
        except Exception:
            baseline = {}

    failed = False

    if args.xcode:
        for fpath, lnum, rid, desc in violations:
            print(f"{fpath}:{lnum}: warning: [{rid}] {desc}")

    if not args.xcode:
        for rid, _, _ in RULES:
            print(f"{rid} {counts[rid]}")

    if args.strict:
        for rid, _, _ in RULES:
            if counts[rid] > 0:
                sys.stderr.write(f"Strict lint failure: {rid} has {counts[rid]} violations\n")
                failed = True
    elif baseline and not args.path:
        for rid, _, _ in RULES:
            base_count = baseline.get(rid, 0)
            if counts[rid] > base_count:
                sys.stderr.write(f"Baseline exceeded: {rid} count {counts[rid]} > baseline {base_count}\n")
                failed = True

    if failed:
        sys.exit(1)
    sys.exit(0)

if __name__ == "__main__":
    main()
