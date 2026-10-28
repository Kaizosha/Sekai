# Offline territory mask

`RegionMask.rle` is generated from Natural Earth 5.1.1 1:10m Admin 0 Map Units.
The source data is public domain. Its boundaries are a cartographic reference,
not a statement about sovereignty or the coverage of a language.

Download the pinned archive from
<https://naturalearth.s3.amazonaws.com/10m_cultural/ne_10m_admin_0_map_units.zip>.
Its SHA-256 is
`45bebe2aaf8bf42b9daf4428594925bcb11eabd32fe9dc6e0acf681438053eb5`.
The builder rejects a different archive and requires only Python 3.9 or newer.

```sh
python3 Tools/RegionMask/build.py /path/to/ne_10m_admin_0_map_units.zip \
  Sources/SekaiKit/Resources/RegionMask.rle
```

The output is 43,792 bytes, with SHA-256
`3ef133eba5609d3c7c5ee05e09decdb36719c29a2e35a932f238f9bbcff0a47a`.
The generator uses even-odd scanlines at texel centers, preserves polygon holes,
and unwraps rings across the antimeridian. `ISO_A2_EH` supplies the territory code.
Features without an alpha-2 code do not invent a replacement.

The mask has 1,024 columns and 512 north-to-south rows. Each value is an unsigned
16-bit integer. Zero means ocean or an unassigned territory. An alpha-2 code
maps to `(firstLetter - A) * 26 + (secondLetter - A) + 1`.
The binary header is `SKRG`, version bytes `2, 0`, little-endian width, height,
and registry count. A sorted list of that many nonzero unique territory IDs
follows. The registry includes tiny source territories absent from the raster.
The remaining little-endian pairs contain a registered territory value or zero,
and a positive run length. Decoding must produce exactly width times height values.

The renderer creates one integer Metal texture from this immutable mask. It
reads one texel without interpolation at the existing Fibonacci dot coordinate.
Selection changes update a small color palette. They do not rasterize polygons
or upload another map texture. Tiny territories may contain no globe dot at a
chosen density. An explicit fallback coordinate can draw a small anchor in that
case. It never expands a territory into a circular geographic area.

Tests cover known country interiors, neighboring territories, ocean, Alaska,
antimeridian land, malformed resources, small-territory fallback and real Metal
pixels. A map with this resolution is suitable for a decorative globe, not GIS
measurement or exact border inspection.
