# Atlas

The bundled atlas is generated from pinned Natural Earth 1:10m Admin 0 Map
Units. Its little-endian binary format begins with a 128-byte versioned header,
followed by JSON metadata, 16-byte particle records, vector mesh records,
quantized vertices, triangle indices, and line segments. Sections are aligned
for mapped reads.

Particles quantize latitude and longitude to UInt16 and store map-unit,
sovereign, country, continent, global rank, and regional rank keys. The master
set is generated once with an equal-area Fibonacci sequence. Every density and
filter is a deterministic selection from that hierarchy.

Use `SekaiAtlas.bundled` for metadata, search, feature lookup, counts, and
particle access. Avoid repeatedly requesting public particle arrays in frame
loops; the view caches prepared GPU buffers.

Natural Earth political classifications are data, not legal claims. Choose an
appropriate `SekaiWorldview` in applications that expose disputed boundaries.
Multipart and overseas geometry is retained.
