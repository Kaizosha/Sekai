#!/usr/bin/env python3
"""Build the offline territory mask from the checksum-pinned Natural Earth archive."""
import argparse
import hashlib
import itertools
import math
from pathlib import Path
import struct
import zipfile

SOURCE_SHA256 = "45bebe2aaf8bf42b9daf4428594925bcb11eabd32fe9dc6e0acf681438053eb5"
WIDTH, HEIGHT = 1024, 512


def records(data):
    count, header, length = struct.unpack_from("<IHH", data, 4)
    fields = []
    for position in range(32, header - 1, 32):
        field = data[position:position + 32]
        fields.append((field[:11].split(b"\0")[0].decode("ascii"), field[16]))
    for index in range(count):
        row = data[header + index * length:header + (index + 1) * length]
        position, values = 1, {}
        for name, size in fields:
            values[name] = row[position:position + size].decode("utf-8").strip(" \0")
            position += size
        yield values


def polygons(data):
    position = 100
    while position < len(data):
        _, words = struct.unpack_from(">II", data, position)
        shape = data[position + 8:position + 8 + words * 2]
        position += 8 + words * 2
        kind = struct.unpack_from("<I", shape)[0]
        if kind == 0:
            yield []
            continue
        if kind != 5:
            raise ValueError(f"Expected Polygon shapefile, found shape {kind}")
        parts, points = struct.unpack_from("<II", shape, 36)
        starts = list(struct.unpack_from(f"<{parts}I", shape, 44)) + [points]
        coordinates = list(struct.iter_unpack("<dd", shape[44 + parts * 4:44 + parts * 4 + points * 16]))
        rings = []
        for start, end in zip(starts, starts[1:]):
            ring = []
            for longitude, latitude in coordinates[start:end]:
                if ring:
                    longitude += 360 * round((ring[-1][0] - longitude) / 360)
                ring.append((longitude, latitude))
            rings.append(ring)
        yield rings


def region_id(code):
    if len(code) != 2 or not all("A" <= letter <= "Z" for letter in code):
        return 0
    return (ord(code[0]) - 65) * 26 + ord(code[1]) - 65 + 1


def rasterize(raster, rings, identifier):
    if not rings:
        return
    minimum = min(y for ring in rings for _, y in ring)
    maximum = max(y for ring in rings for _, y in ring)
    first = max(0, math.ceil((90 - maximum) * HEIGHT / 180 - 0.5))
    last = min(HEIGHT - 1, math.floor((90 - minimum) * HEIGHT / 180 - 0.5))
    for row in range(first, last + 1):
        latitude = 90 - (row + 0.5) * 180 / HEIGHT
        crossings = []
        for ring in rings:
            for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
                if (y1 > latitude) == (y2 > latitude):
                    continue
                longitude = x1 + (latitude - y1) * (x2 - x1) / (y2 - y1)
                crossings.append(longitude)
        crossings.sort()
        for left, right in zip(crossings[::2], crossings[1::2]):
            for shift in [-360, 0, 360]:
                start = max(0, math.ceil((left + shift + 180) * WIDTH / 360 - 0.5))
                end = min(WIDTH - 1, math.floor((right + shift + 180) * WIDTH / 360 - 0.5))
                if end >= start:
                    raster[row * WIDTH + start:row * WIDTH + end + 1] = [identifier] * (end - start + 1)


def build(source):
    content = source.read_bytes()
    if hashlib.sha256(content).hexdigest() != SOURCE_SHA256:
        raise ValueError("Natural Earth archive checksum does not match the pinned 5.1.1 source")
    with zipfile.ZipFile(source) as archive:
        attributes = records(archive.read("ne_10m_admin_0_map_units.dbf"))
        shapes = polygons(archive.read("ne_10m_admin_0_map_units.shp"))
        raster = [0] * (WIDTH * HEIGHT)
        identifiers = set()
        for fields, rings in itertools.zip_longest(attributes, shapes):
            if fields is None or rings is None:
                raise ValueError("Shapefile and attribute counts differ")
            identifier = region_id(fields["ISO_A2_EH"])
            if identifier:
                identifiers.add(identifier)
                rasterize(raster, rings, identifier)
    output = bytearray(b"SKRG\x02\x00" + struct.pack("<HHH", WIDTH, HEIGHT, len(identifiers)))
    output += struct.pack(f"<{len(identifiers)}H", *sorted(identifiers))
    position = 0
    while position < len(raster):
        value, count = raster[position], 1
        while position + count < len(raster) and raster[position + count] == value and count < 65535:
            count += 1
        output += struct.pack("<HH", value, count)
        position += count
    return bytes(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = build(args.source)
    args.output.write_bytes(result)
    print(f"{len(result)} bytes, SHA-256 {hashlib.sha256(result).hexdigest()}")


if __name__ == "__main__":
    main()
