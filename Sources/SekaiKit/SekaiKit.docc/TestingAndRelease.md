# Testing and release

The package's tests cover finite value normalization, camera conventions,
rotation continuity, lifecycle transitions, typed failures, resource loading,
and actual Metal output. An unavailable GPU is a verification limitation,
not evidence that a render test passed.

Before publishing a release:

1. Run `swift test` from the intended source revision with a separate scratch
   build path.
2. Verify that the bundled compiled Metal library loads and produces nonempty
   pixels, transparent corners, land, and correct overlay occlusion.
3. Verify a settled suspended host performs no autonomous render work and that
   dismantling releases the previous renderer.
4. Build each platform declared in `Package.swift`.
5. Exercise the native example on a physical iPhone and iPad.
6. Check Light and Dark appearances, Reduce Motion, motion interruption, camera
   input, resizing, and background transitions.
7. Measure frame pacing and resource retention in a Release build.
8. Build DocC and check links and example symbols.
9. Tag only the exact source revision that passed the recorded checks.

Keep results distinct. A simulator image, a passing value test, and physical
GPU timing establish different facts. Do not report the first two as proof of
physical-device frame pacing.

Use a clean scratch path outside synced source folders to avoid signing
failures caused by local Finder metadata. Preserve failed results and record
the source revision, toolchain, device, OS, and command used for each run.
