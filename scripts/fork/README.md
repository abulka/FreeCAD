# Fork-local build helpers

These are fork-only maintenance scripts (not part of upstream FreeCAD). They
exist because the pixi env plays two roles on a dev machine:

1. **dependency env** for building/running FreeCAD from the build tree
   (`pixi run build-release`, then run `build/release/bin/FreeCAD`)
2. **bundle payload** when assembling a distributable `.app`, which requires
   FreeCAD to be *installed into* the env (`pixi run install-release`)

Role 2 leaves FreeCAD's own modules inside the env. If they stay there, the
build-tree binaries load a poisoned mix (some modules from the env, some from
the build tree) and PartDesign breaks with
`GeoFeatureGroupExtension can only be applied to GeoFeatures`.

## Commands

### Daily development (no install, no cleanup - nothing to remember)

```bash
pixi run build-release          # incremental build
open build/release/bin/FreeCAD  # or just double-click it
pixi run test-release           # test suite
```

### Assemble a local macOS bundle (rare - the monthly CI builds do this for you)

```bash
scripts/fork/build_local_bundle.sh            # -> dist/*.app + .zip, env cleaned automatically
```

If it is interrupted: `scripts/fork/clean_install.sh` restores the env manually.

### Monthly pipeline (automatic, no local action needed)

- 1st of month 00:00 UTC: `sketchfix_sync.yml` merges upstream main into fork main
- 1st of month 03:00 UTC: `build_release.yml` builds all platforms and publishes
  a `weekly-YYYY.MM.DD` prerelease on the fork

## History

- The `GeoFeatureGroupExtension` bug fixed here is upstream issue #22381
  (Symmetric constraint + already-constrained directions = rank-deficient
  system; fixed by weakening the constraint, mirroring the arc special case).
- The pixi-env pollution bug was self-inflicted by local `install-release`
  runs; `clean_install.sh` is the antidote.
