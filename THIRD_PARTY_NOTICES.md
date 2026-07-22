# Third-Party Notices

## Natural Earth

SekaiKit's built-in particles, hierarchy, labels, and boundary geometry are
derived from Natural Earth 5.1.1 1:10m Admin 0 Map Units data. The exact source
archive and SHA-256 checksum are pinned in
`Tools/SekaiAtlasBuilder/sources.json`.

Natural Earth vector and raster map data is in the public domain. Attribution
is not required, but the project recommends the optional credit:

> Made with Natural Earth.

Source and terms:

- https://www.naturalearthdata.com/downloads/10m-cultural-vectors/
- https://www.naturalearthdata.com/about/terms-of-use/

The bundled data is intended for visualization. It is not intended for
navigation, surveying, legal boundary determination, or precision GIS work.

## Cobe

Cobe's open-source API and examples were used as a feature-research reference.
SekaiKit does not bundle, link, or execute Cobe or its web renderer; it provides
an independent SwiftUI and Metal implementation using Apple platform APIs.

Cobe is distributed under the MIT License:

- https://github.com/shuding/cobe
- https://github.com/shuding/cobe/blob/main/LICENSE
- https://cobe.vercel.app/
