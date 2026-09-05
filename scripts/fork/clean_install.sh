#!/bin/bash
# Removes the files that `pixi run install-release` copied into the pixi env.
#
# WHY THIS EXISTS: the pixi env must contain dependencies ONLY (Qt, OCCT, ...).
# FreeCAD's own modules must live in the build tree (build/release/Mod, lib).
# If install-release has run, FreeCAD's modules exist in BOTH places, and the
# build-tree binaries then load some modules from env/lib and others from the
# build tree - the same C++ module gets mapped twice, which corrupts FreeCAD's
# type registration. Symptom: "GeoFeatureGroupExtension can only be applied to
# GeoFeatures" when creating PartDesign bodies or sketches.
#
# It is surgical: it removes exactly the files listed in
# build/release/install_manifest.txt (written by cmake --install), so pixi's
# own packages are never touched.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$REPO/build/release/install_manifest.txt"

if [ ! -f "$MANIFEST" ]; then
    echo "No install manifest at $MANIFEST - nothing to clean."
    exit 0
fi

count=$(wc -l < "$MANIFEST" | tr -d ' ')
echo "Removing $count files that install-release copied into the pixi env..."

while IFS= read -r f; do
    if [ -f "$f" ] || [ -L "$f" ]; then
        rm -f "$f"
    fi
done < "$MANIFEST"

# prune empty directories among the top-level dirs the install touched
top_dirs=$(sed "s|/.pixi/envs/default/||" "$MANIFEST" | cut -d/ -f1 | sort -u)
for d in $top_dirs; do
    target="$REPO/.pixi/envs/default/$d"
    [ -d "$target" ] || continue
    for _ in 1 2 3 4 5 6; do
        find "$target" -depth -type d -empty -delete 2>/dev/null || true
    done
    # remove stray __pycache__ left from running the installed python modules
    find "$target" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
done

echo "Pixi env restored to dependency-only state."
