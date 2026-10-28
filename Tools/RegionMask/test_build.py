import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("region_mask_builder", Path(__file__).with_name("build.py"))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class RegionMaskBuilderTests(unittest.TestCase):
    def value(self, raster, latitude, longitude):
        x = int(((longitude + 180) % 360) * builder.WIDTH / 360)
        y = int((90 - latitude) * builder.HEIGHT / 180)
        return raster[y * builder.WIDTH + x]

    def test_polygon_holes_leave_ocean(self):
        raster = [0] * (builder.WIDTH * builder.HEIGHT)
        rings = [
            [(-10, -10), (-10, 10), (10, 10), (10, -10), (-10, -10)],
            [(-5, -5), (5, -5), (5, 5), (-5, 5), (-5, -5)],
        ]
        builder.rasterize(raster, rings, 1)
        self.assertEqual(self.value(raster, 8, 0), 1)
        self.assertEqual(self.value(raster, 0, 0), 0)
        self.assertEqual(self.value(raster, 0, 12), 0)

    def test_unwrapped_ring_colors_both_antimeridian_edges(self):
        raster = [0] * (builder.WIDTH * builder.HEIGHT)
        builder.rasterize(raster, [[(179, -5), (179, 5), (181, 5), (181, -5), (179, -5)]], 2)
        self.assertEqual(self.value(raster, 0, 179.7), 2)
        self.assertEqual(self.value(raster, 0, -179.7), 2)
        self.assertEqual(self.value(raster, 0, 0), 0)

    def test_invalid_codes_are_not_encoded(self):
        self.assertEqual(builder.region_id("JP"), (ord("J") - 65) * 26 + ord("P") - 65 + 1)
        for code in ["-99", "419", "jp", "J", "日本"]:
            self.assertEqual(builder.region_id(code), 0)

    def test_wrong_source_fails_before_parsing(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.zip"
            source.write_bytes(b"different source")
            with self.assertRaisesRegex(ValueError, "checksum"):
                builder.build(source)


if __name__ == "__main__":
    unittest.main()
