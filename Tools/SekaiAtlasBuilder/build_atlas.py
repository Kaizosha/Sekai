#!/usr/bin/env python3
"""Build Sekai's deterministic runtime atlas from pinned Natural Earth vectors."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

import mapbox_earcut
import numpy as np
import shapefile
import shapely
from shapely.geometry import MultiPolygon, Point, Polygon, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree
from shapely.validation import make_valid


MAGIC = b"SEKAIAT\0"
VERSION = 1
HEADER_SIZE = 128
HEADER = struct.Struct("<8s8I8Q")
POINT = struct.Struct("<HHBBHHHI")
MESH_RECORD = struct.Struct("<HBBIIII")
VERTEX = struct.Struct("<HH")
LINE_SEGMENT = struct.Struct("<HBBHHHH")
LOD_TOLERANCES = (0.22, 0.055, 0.0)
LANGUAGE_FIELDS = (
    "AR", "BN", "DE", "EN", "ES", "FA", "FR", "EL", "HE", "HI", "HU",
    "ID", "IT", "JA", "KO", "NL", "PL", "PT", "RU", "SV", "TR", "UK",
    "UR", "VI", "ZH", "ZHT",
)
WORLDVIEW_FIELDS = (
    "ISO", "US", "FR", "RU", "ES", "CN", "TW", "IN", "NP", "PK", "DE",
    "GB", "BR", "IL", "PS", "SA", "EG", "MA", "PT", "AR", "JP", "KO",
    "VN", "TR", "ID", "PL", "GR", "IT", "NL", "SE", "BD", "UA",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("sources.json"))
    parser.add_argument("--cache", type=Path, default=Path(".build/atlas-cache"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--particles", type=int)
    return parser.parse_args()


def aligned(value: int, alignment: int = 16) -> int:
    return (value + alignment - 1) // alignment * alignment


def download(source: dict[str, str], cache: Path) -> Path:
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / Path(source["url"]).name
    if not archive.exists():
        print(f"Downloading {source['url']}")
        urllib.request.urlretrieve(source["url"], archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != source["sha256"]:
        raise RuntimeError(f"Checksum mismatch for {archive}: {digest}")
    destination = cache / archive.stem
    marker = destination / ".extracted"
    if not marker.exists():
        destination.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as source_zip:
            source_zip.extractall(destination)
        marker.touch()
    return destination


def polygons(geometry) -> list[Polygon]:
    if geometry.is_empty:
        return []
    if isinstance(geometry, Polygon):
        return [geometry]
    if isinstance(geometry, MultiPolygon):
        return list(geometry.geoms)
    return [item for item in geometry.geoms if isinstance(item, Polygon)]


def clean_geometry(raw):
    geometry = shape(raw.__geo_interface__)
    if not geometry.is_valid:
        geometry = make_valid(geometry)
    return geometry


def stable_entities(records: list[dict], key: str, name: str) -> tuple[list[dict], dict[str, int]]:
    names: dict[str, str] = {}
    for record in records:
        identifier = str(record.get(key) or "UNK")
        names.setdefault(identifier, str(record.get(name) or identifier))
    entities = [{"id": identifier, "name": names[identifier]} for identifier in sorted(names)]
    return entities, {item["id"]: index for index, item in enumerate(entities)}


def quantize_latitude(value: float) -> int:
    return round((min(max(value, -90.0), 90.0) + 90.0) / 180.0 * 65535.0)


def normalize_longitude(value: float) -> float:
    return (value + 180.0) % 360.0 - 180.0


def quantize_longitude(value: float) -> int:
    return round((normalize_longitude(value) + 180.0) / 360.0 * 65535.0)


def unwrap_ring(coordinates, reference: float | None = None) -> np.ndarray:
    values = np.asarray(coordinates, dtype=np.float64)[:, :2].copy()
    if len(values) > 1 and np.array_equal(values[0], values[-1]):
        values = values[:-1]
    if not len(values):
        return values
    if reference is None:
        reference = float(values[0, 0])
    previous = reference
    for index in range(len(values)):
        longitude = float(values[index, 0])
        while longitude - previous > 180.0:
            longitude -= 360.0
        while longitude - previous < -180.0:
            longitude += 360.0
        values[index, 0] = longitude
        previous = longitude
    return values


def append_polygon_mesh(poly: Polygon, vertices: list[tuple[int, int]], indices: list[int]) -> None:
    exterior = unwrap_ring(poly.exterior.coords)
    if len(exterior) < 3:
        return
    rings = [exterior]
    reference = float(exterior[0, 0])
    rings.extend(unwrap_ring(interior.coords, reference) for interior in poly.interiors)
    rings = [ring for ring in rings if len(ring) >= 3]
    flat = np.concatenate(rings)
    ends = np.cumsum([len(ring) for ring in rings], dtype=np.uint32)
    local_indices = mapbox_earcut.triangulate_float64(flat, ends)
    base = len(vertices)
    vertices.extend(
        (quantize_latitude(float(latitude)), quantize_longitude(float(longitude)))
        for longitude, latitude in flat
    )
    indices.extend(base + int(index) for index in local_indices)


def build_geometry(features: list[dict], geometries: list) -> tuple[bytes, bytes, bytes, bytes, list[dict]]:
    mesh_records = bytearray()
    mesh_vertices: list[tuple[int, int]] = []
    mesh_indices: list[int] = []
    line_segments = bytearray()
    geometry_stats: list[dict] = []

    for feature_index, geometry in enumerate(geometries):
        feature_line_start = len(line_segments) // LINE_SEGMENT.size
        feature_stats = {"meshVertices": 0, "triangles": 0, "lineSegments": 0}
        for lod, tolerance in enumerate(LOD_TOLERANCES):
            simplified = geometry if tolerance == 0 else geometry.simplify(tolerance, preserve_topology=True)
            vertex_start = len(mesh_vertices)
            index_start = len(mesh_indices)
            for poly in polygons(simplified):
                append_polygon_mesh(poly, mesh_vertices, mesh_indices)
                for ring_index, ring in enumerate((poly.exterior, *poly.interiors)):
                    coordinates = list(ring.coords)
                    for start, end in zip(coordinates, coordinates[1:]):
                        line_segments.extend(LINE_SEGMENT.pack(
                            feature_index,
                            lod,
                            1 if ring_index > 0 else 0,
                            quantize_latitude(start[1]),
                            quantize_longitude(start[0]),
                            quantize_latitude(end[1]),
                            quantize_longitude(end[0]),
                        ))
            vertex_count = len(mesh_vertices) - vertex_start
            index_count = len(mesh_indices) - index_start
            mesh_records.extend(MESH_RECORD.pack(
                feature_index, lod, 0, vertex_start, vertex_count, index_start, index_count
            ))
            if lod == len(LOD_TOLERANCES) - 1:
                feature_stats = {
                    "meshVertices": vertex_count,
                    "triangles": index_count // 3,
                    "lineSegments": len(line_segments) // LINE_SEGMENT.size - feature_line_start,
                }
        geometry_stats.append(feature_stats)

    vertex_bytes = bytearray()
    for latitude, longitude in mesh_vertices:
        vertex_bytes.extend(VERTEX.pack(latitude, longitude))
    index_bytes = np.asarray(mesh_indices, dtype="<u4").tobytes()
    return bytes(mesh_records), bytes(vertex_bytes), index_bytes, bytes(line_segments), geometry_stats


def candidate_coordinates(start: int, count: int, total: int) -> tuple[np.ndarray, np.ndarray]:
    indices = np.arange(start, start + count, dtype=np.uint64)
    latitude_hash = hash64(indices, np.uint64(0x243F6A8885A308D3))
    longitude_hash = hash64(indices, np.uint64(0x13198A2E03707344))
    unit = 1.0 / float(2**64)
    z = 1.0 - 2.0 * ((latitude_hash.astype(np.float64) + 0.5) * unit)
    latitudes = np.degrees(np.arcsin(z))
    longitudes = (longitude_hash.astype(np.float64) + 0.5) * unit * 360.0 - 180.0
    return latitudes, longitudes


def hash64(values: np.ndarray, salt: np.uint64) -> np.ndarray:
    with np.errstate(over="ignore"):
        mixed = values + salt + np.uint64(0x9E3779B97F4A7C15)
        mixed = (mixed ^ (mixed >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        mixed = (mixed ^ (mixed >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        return mixed ^ (mixed >> np.uint64(31))


def assign_features(points, tree: STRtree, geometries: list) -> np.ndarray:
    assignments = np.full(len(points), -1, dtype=np.int32)
    pairs = tree.query(points)
    if pairs.size:
        point_indexes = pairs[0]
        feature_indexes = pairs[1]
        for feature_index in np.unique(feature_indexes):
            candidates = point_indexes[feature_indexes == feature_index]
            unassigned = candidates[assignments[candidates] < 0]
            if not len(unassigned):
                continue
            selected = shapely.contains_xy(
                geometries[int(feature_index)],
                shapely.get_x(points[unassigned]),
                shapely.get_y(points[unassigned]),
            )
            assignments[unassigned[selected]] = int(feature_index)
    missing = np.flatnonzero(assignments < 0)
    for point_index in missing:
        point = points[point_index]
        candidates = tree.query(point)
        for feature_index in candidates:
            if geometries[int(feature_index)].covers(point):
                assignments[point_index] = int(feature_index)
                break
    return assignments


def representative_points(geometries: list) -> list[tuple[float, float, int]]:
    output = []
    for feature_index, geometry in enumerate(geometries):
        point = geometry.representative_point()
        output.append((point.y, point.x, feature_index))
    return output


def build_particles(
    count: int,
    features: list[dict],
    geometries: list,
    continent_indexes: dict[str, int],
    sovereign_indexes: dict[str, int],
    admin_indexes: dict[str, int],
) -> bytes:
    shapely.prepare(geometries)
    tree = STRtree(geometries)
    records: list[tuple[float, float, int, int, int]] = [
        (latitude, longitude, feature_index, 1, feature_index)
        for latitude, longitude, feature_index in representative_points(geometries)
    ]
    candidate_total = math.ceil((count - len(records)) / 0.255)
    chunk_size = 200_000
    for start in range(0, candidate_total, chunk_size):
        amount = min(chunk_size, candidate_total - start)
        latitudes, longitudes = candidate_coordinates(start, amount, candidate_total)
        point_array = shapely.points(longitudes, latitudes)
        assignments = assign_features(point_array, tree, geometries)
        accepted = np.flatnonzero(assignments >= 0)
        for point_index in accepted:
            records.append((
                float(latitudes[point_index]),
                float(longitudes[point_index]),
                int(assignments[point_index]),
                0,
                len(features) + int(hash64(
                    np.asarray([start + int(point_index)], dtype=np.uint64),
                    np.uint64(0xA4093822299F31D0),
                )[0]),
            ))
        print(f"Particles: {len(records):,}/{count:,}")
    if len(records) < count:
        raise RuntimeError(f"Generated only {len(records)} of {count} particles")

    representatives = records[:len(features)]
    candidates = sorted(records[len(features):], key=lambda record: record[4])
    records = representatives + candidates[:count - len(representatives)]
    regional_ranks: defaultdict[int, int] = defaultdict(int)
    output = bytearray(count * POINT.size)
    for global_rank, (latitude, longitude, feature_index, flags, _) in enumerate(records):
        feature = features[feature_index]
        regional_rank = regional_ranks[feature_index]
        regional_ranks[feature_index] += 1
        POINT.pack_into(
            output,
            global_rank * POINT.size,
            quantize_latitude(latitude),
            quantize_longitude(longitude),
            continent_indexes[feature["continent"]],
            flags,
            feature_index,
            sovereign_indexes[feature["sovereignID"]],
            admin_indexes[feature["countryID"]],
            regional_rank,
        )
    for feature_index, feature in enumerate(features):
        feature["particleCount"] = regional_ranks[feature_index]
    return bytes(output)


def write_atlas(
    destination: Path,
    metadata: dict,
    point_bytes: bytes,
    mesh_records: bytes,
    mesh_vertices: bytes,
    mesh_indices: bytes,
    line_segments: bytes,
    source_hash: int,
) -> None:
    metadata_bytes = json.dumps(metadata, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    metadata_offset = HEADER_SIZE
    points_offset = aligned(metadata_offset + len(metadata_bytes))
    mesh_records_offset = aligned(points_offset + len(point_bytes))
    mesh_vertices_offset = aligned(mesh_records_offset + len(mesh_records))
    mesh_indices_offset = aligned(mesh_vertices_offset + len(mesh_vertices))
    line_segments_offset = aligned(mesh_indices_offset + len(mesh_indices))
    file_length = line_segments_offset + len(line_segments)
    header = HEADER.pack(
        MAGIC,
        VERSION,
        HEADER_SIZE,
        len(point_bytes) // POINT.size,
        len(metadata["mapUnits"]),
        len(mesh_records) // MESH_RECORD.size,
        len(mesh_vertices) // VERTEX.size,
        len(mesh_indices) // 4,
        len(line_segments) // LINE_SEGMENT.size,
        len(metadata_bytes),
        points_offset,
        mesh_records_offset,
        mesh_vertices_offset,
        mesh_indices_offset,
        line_segments_offset,
        file_length,
        source_hash,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as output:
        output.write(header)
        output.write(bytes(HEADER_SIZE - len(header)))
        output.write(metadata_bytes)
        output.write(bytes(points_offset - output.tell()))
        output.write(point_bytes)
        output.write(bytes(mesh_records_offset - output.tell()))
        output.write(mesh_records)
        output.write(bytes(mesh_vertices_offset - output.tell()))
        output.write(mesh_vertices)
        output.write(bytes(mesh_indices_offset - output.tell()))
        output.write(mesh_indices)
        output.write(bytes(line_segments_offset - output.tell()))
        output.write(line_segments)
    print(f"Wrote {destination} ({destination.stat().st_size / 1_048_576:.1f} MiB)")


def main() -> None:
    arguments = parse_args()
    manifest = json.loads(arguments.manifest.read_text())
    source = manifest["sources"]["mapUnits"]
    extracted = download(source, arguments.cache)
    shapefile_path = next(extracted.glob("*.shp")).with_suffix("")
    reader = shapefile.Reader(str(shapefile_path), encoding="utf-8")
    records = [record.as_dict() for record in reader.iterRecords()]
    geometries = [clean_geometry(raw) for raw in reader.iterShapes()]

    continents = sorted({str(record["CONTINENT"]) for record in records})
    continent_indexes = {name: index for index, name in enumerate(continents)}
    sovereigns, sovereign_indexes = stable_entities(records, "SOV_A3", "SOVEREIGNT")
    countries, admin_indexes = stable_entities(records, "ADM0_A3", "ADMIN")
    features = []
    for index, (record, geometry) in enumerate(zip(records, geometries)):
        minimum_x, minimum_y, maximum_x, maximum_y = geometry.bounds
        names = {
            language.lower(): record.get(f"NAME_{language}")
            for language in LANGUAGE_FIELDS
            if record.get(f"NAME_{language}")
        }
        worldview = {
            key.lower(): record.get(f"FCLASS_{key}")
            for key in WORLDVIEW_FIELDS
            if record.get(f"FCLASS_{key}")
        }
        features.append({
            "index": index,
            "id": str(record["GU_A3"]),
            "naturalEarthID": int(record["NE_ID"]),
            "name": str(record["NAME"]),
            "longName": str(record.get("NAME_LONG") or record["NAME"]),
            "type": str(record["TYPE"]),
            "continent": str(record["CONTINENT"]),
            "region": str(record["REGION_UN"]),
            "subregion": str(record["SUBREGION"]),
            "sovereignID": str(record["SOV_A3"]),
            "countryID": str(record["ADM0_A3"]),
            "isoA2": str(record.get("ISO_A2") or ""),
            "isoA3": str(record.get("ISO_A3") or ""),
            "label": [float(record["LABEL_Y"]), float(record["LABEL_X"])],
            "bounds": [minimum_y, minimum_x, maximum_y, maximum_x],
            "minimumZoom": float(record.get("MIN_ZOOM") or 0),
            "names": names,
            "worldview": worldview,
        })

    mesh_records, mesh_vertices, mesh_indices, line_segments, stats = build_geometry(
        features, geometries
    )
    for feature, geometry_stats in zip(features, stats):
        feature["geometry"] = geometry_stats
    particle_count = arguments.particles or int(manifest["particleCount"])
    point_bytes = build_particles(
        particle_count,
        features,
        geometries,
        continent_indexes,
        sovereign_indexes,
        admin_indexes,
    )
    metadata = {
        "formatVersion": VERSION,
        "source": "Natural Earth 1:10m Admin 0 Map Units",
        "sourceVersion": manifest["naturalEarthVersion"],
        "sourceSHA256": source["sha256"],
        "particleCount": particle_count,
        "lodTolerancesDegrees": list(LOD_TOLERANCES),
        "continents": continents,
        "sovereigns": sovereigns,
        "countries": countries,
        "worldviews": [key.lower() for key in WORLDVIEW_FIELDS],
        "mapUnits": features,
    }
    source_hash = int(source["sha256"][:16], 16)
    write_atlas(
        arguments.output,
        metadata,
        point_bytes,
        mesh_records,
        mesh_vertices,
        mesh_indices,
        line_segments,
        source_hash,
    )


if __name__ == "__main__":
    main()
