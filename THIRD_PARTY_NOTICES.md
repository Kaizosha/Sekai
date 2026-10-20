# Third-party notices

## COBE

Sekai 2 adapts the inverse Fibonacci globe shader from COBE and bundles its
land mask. The native implementation changes the projection interface,
coordinate convention, numerical guards, blending, lifecycle, and overlay
rendering. It does not link or run COBE's JavaScript renderer.

Source revision: `7e94076fa8c38707f4c9cd114ff4f7c5c880971e`.

- [COBE source](https://github.com/shuding/cobe/tree/7e94076fa8c38707f4c9cd114ff4f7c5c880971e).
- [Globe shader](https://github.com/shuding/cobe/blob/7e94076fa8c38707f4c9cd114ff4f7c5c880971e/src/globe.frag.glslx).
- [Land mask](https://github.com/shuding/cobe/blob/7e94076fa8c38707f4c9cd114ff4f7c5c880971e/src/texture.png).

The mask is 256 by 128 pixels and 1,108 bytes. Its SHA-256 is
`467619a98670dbb446bc614076d6ba9dc924c9eb395012da10a4a57e15c462da`.

The following license applies to the adapted shader and land mask.

```text
MIT License

Copyright (c) 2021 Shu Ding

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Historical Natural Earth data

Sekai 1.x used Natural Earth 5.1.1 1:10m Admin 0 Map Units data, which is in
the public domain. Sekai 2 does not distribute the 1.x atlas or atlas builder.
Historical provenance remains in the 1.1.0 tag.

- [Natural Earth terms](https://www.naturalearthdata.com/about/terms-of-use/).
