# Testing And Release

Unit tests validate atlas integrity, hierarchy filtering, deterministic density,
multipart countries, antimeridian bounds, quaternion normalization, Codable
state, and layer order.

Before release:

1. Rebuild the atlas from pinned sources and verify its SHA-256 provenance.
2. Run `swift test` from a clean clone.
3. Build each declared destination with Xcode.
4. Run the Demo on physical iPhone and iPad hardware.
5. Exercise all renderer layers, filters, density intents, camera projections,
   appearance modes, and performance policies.
6. Inspect memory, frame pacing, thermal behavior, and static GPU activity.
7. Build DocC and verify every symbol link.
8. Tag only the exact commit that passed the matrix.

Generated build folders can inherit Finder metadata from synced workspaces.
Use a clean scratch path for release verification so resource signing reflects
repository content rather than local extended attributes.
