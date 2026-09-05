#!/bin/bash
# Builds a self-contained macOS .app bundle of the current checkout (the
# official conda-bundle recipe, incl. the rpath self-containment fix) and
# restores the pixi env to a clean dev state afterwards.
#
# Usage:   scripts/fork/build_local_bundle.sh [output-dir]
# Result:  <output-dir>/FreeCAD_sketchfix-local-<...>.app + .zip
#
# NOTE: run `scripts/fork/clean_install.sh` if this script is interrupted -
# the env must not keep FreeCAD's own modules (see clean_install.sh header).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${1:-$REPO/dist}"
command -v pixi > /dev/null || export PATH="$HOME/.pixi/bin:$PATH"

cd "$REPO"
echo "==> 1/8 Building (incremental)"
pixi run build-release

echo "==> 2/8 Installing into the pixi env (needed as bundle payload)"
pixi run install-release

ENV_DIR="$REPO/.pixi/envs/default"
WORK="$(mktemp -d)"
trap 'echo "workdir: $WORK"' EXIT
APP="$WORK/FreeCAD.app"
mkdir -p "$APP/Contents/Resources"

echo "==> 3/8 Copying env into bundle Resources"
rsync -a \
    --exclude include --exclude "*.a" --exclude "*.pyc" --exclude "__pycache__" \
    "$ENV_DIR/" "$APP/Contents/Resources/"

echo "==> 4/8 Trimming bin, resources, plugins"
cd "$APP/Contents/Resources"
mv bin bin_tmp && mkdir bin
for e in FreeCAD FreeCADCmd ccx python pip gmsh dot unflatten; do
    cp "bin_tmp/$e" bin/ 2>/dev/null || true
done
rm -rf bin_tmp
sed -i '' '1s|.*|#!/usr/bin/env python|' bin/pip
cp "$REPO/package/rattler-build/osx/resources/"* .
if [ -d PlugIns ]; then mv PlugIns ../; fi
find . -path "*/__pycache__/*" -delete 2>/dev/null || true
find . -name "*.pyc" -type f -delete 2>/dev/null || true

echo "==> 5/8 Fixing library paths (official script)"
python3 "$REPO/package/rattler-build/scripts/fix_macos_lib_paths.py" lib -r > /dev/null

echo "==> 6/8 Building launcher"
cd "$WORK"
cmake -B build-launcher "$REPO/package/rattler-build/osx/launcher" > /dev/null
cmake --build build-launcher 2>&1 | tail -1
mkdir -p "$APP/Contents/MacOS"
cp build-launcher/FreeCAD "$APP/Contents/MacOS/FreeCAD"

version=$(python3 -c "
import json
v = json.load(open('$REPO/version.json'))
print(f\"{v['version_major']}.{v['version_minor']}.{v['version_patch']}\")")
sed -e "s/FREECAD_BUNDLE_VERSION/${version}d0/" \
    -e "s/APPLICATION_MENU_NAME/FreeCAD/" \
    "$REPO/package/rattler-build/osx/Info.plist.template" > "$APP/Contents/Info.plist"
pixi list -e default > "$APP/Contents/packages.txt" 2>/dev/null || true

echo "==> 7/8 Smoke tests + rpath self-containment + signing"
cd "$APP/Contents/Resources"
./bin/freecadcmd --safe-mode --version | head -1
./bin/freecadcmd --safe-mode --console \
    "import pivy; from pivy import coin; print('pivy OK')" | tail -1
python3 "$REPO/scripts/fork/fix_bundle_rpaths.py" "$APP/Contents/Resources"
codesign --force --sign - "$APP" 2>&1 | tail -1 || true

echo "==> 8/8 Zipping + cleaning the pixi env"
mkdir -p "$OUT_DIR"
name="FreeCAD_sketchfix-local-$(git -C "$REPO" rev-parse --short HEAD)-$(date +%Y%m%d)"
cd "$WORK"
zip -rqy "$OUT_DIR/$name.zip" FreeCAD.app -x "*.DS_Store"
shasum -a 256 "$OUT_DIR/$name.zip" > "$OUT_DIR/$name.zip-SHA256.txt"
"$REPO/scripts/fork/clean_install.sh"
cp -R FreeCAD.app "$OUT_DIR/"

echo ""
echo "DONE:"
echo "  app : $OUT_DIR/$name.app"
echo "  zip : $OUT_DIR/$name.zip"
echo "The pixi env has been cleaned - build/release/bin/FreeCAD works as before."
