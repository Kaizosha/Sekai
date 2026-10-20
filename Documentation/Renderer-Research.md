# Native renderer research

Sekai 2 adapts the analytical globe in [COBE 2.0.1](https://github.com/shuding/cobe/tree/7e94076fa8c38707f4c9cd114ff4f7c5c880971e).
The inspected source revision is `7e94076fa8c38707f4c9cd114ff4f7c5c880971e`.
The translated shader and bundled land mask retain Shu Ding's complete MIT
notice in `Sources/SekaiKit/Resources/COBE-LICENSE.txt` and
[Third-party notices](../THIRD_PARTY_NOTICES.md).

## Analysis evidence

[REA](https://github.com/morluto/rea/tree/ccc7da309d7db385d5c6d73b0a3a8e093be33504)
was inspected at `ccc7da309d7db385d5c6d73b0a3a8e093be33504`.
The official `rea-agents` npm package 6.7.0 was installed in a task-local
folder with lifecycle scripts disabled. No global agent or MCP configuration
was changed. Its static JavaScript analysis exited successfully with zero
parse failures across 19 source files. A focused four-file analysis also
completed with zero parse failures. Its evidence identifier was
`ev_a028192f87937cf0f4f0f41270f0e9323d584437ba4cc918b7fd0bcfba980ff8`.
The full JSON remains a local development artifact rather than a runtime
resource or a large checked-in generated file.

The successful command used these CLI arguments, with paths pointing to the
local source clone and official task-local installation:

```sh
node node_modules/rea-agents/scripts/rea.mjs \
  analyze-javascript-application ../cobe --json
```

The focused invocation added:

```sh
--source-path src/index.js --source-path src/webgl.js \
--source-path src/anchor.js --source-path scripts/build.js
```

REA's JavaScript AST relationships establish static source structure. They do
not execute WebGL or parse GLSL, prove a relationship runs, or measure frame
pacing. The shader equations were read directly from the pinned source and
then exercised in native Metal pixel tests. REA is development tooling and is
not linked into Sekai or Together.

## Rendering decisions

COBE 2 uses two fullscreen triangles for its globe, an inverse Fibonacci
lattice lookup with four candidates per covered fragment, and a tiny binary
land mask. Density is a uniform rather than an uploaded point array. Markers
and decorative quadratic Bézier arcs add optional instanced passes. Its caller
owns the update loop.

Sekai uses one oversized fullscreen triangle and a native `MTKView` cadence
owner. All passes share one quaternion camera and accumulated monotonic
rotation. Markers are instanced disks; arcs are intentionally raised great-circle
ribbons rather than copies of COBE's Bézier geometry. There is no WebView,
JavaScript runtime, generic GIS scene graph, geographic lookup index, or atlas.

The native shader uses defined ascending smoothstep edges, clamped sphere
square roots, bounded sample indices, safe pole and rim expressions, and
premultiplied linear output to an sRGB target. Its supported Fibonacci density
range is 512 through 32,768 samples. The palette, camera, density and opacity
are uniforms. Overlay geometry buffers change only when overlay values change.

The 256 by 128 land mask is the 1,108-byte COBE mask. Its SHA-256 is
`467619a98670dbb446bc614076d6ba9dc924c9eb395012da10a4a57e15c462da`.
Together's prior mask was byte-identical. The package now owns the one copy.
It is illustrative geography, not a navigation or legal boundary dataset.

## Verification boundary

Package tests render through the compiled production Metal library. They check
Light and Dark pixels, transparent corners, known inland and Pacific mask
orientation, front/back overlay occlusion, buffer reuse, explicit failures, and
finite float-format output at density limits, the poles and the sphere rim.
A native attached-host test establishes actual completed GPU work before
checking suspension and renderer release. Together separately verifies the
native globe-plus-language-picker flow on its supported device matrix.

A different cost model and smaller resources do not prove a native speedup.
Physical-device presented intervals, GPU duration, main-thread work and thermal
behavior remain separate measurements. Submitted draw counts are not reported
as displayed frames per second.
