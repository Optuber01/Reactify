import sys
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))

from export_swf_shape_assets import parse_fill_styles, parse_shape, svg_for_shape
from gacha_swf_manifest import SwfXmlIndex


ROOT = Path(__file__).resolve().parents[1]


class BitmapFillExportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        xml_path = ROOT / ".cache" / "gacha_clubPC.xml"
        if not xml_path.exists():
            raise unittest.SkipTest("local source SWF XML is unavailable")
        cls.index = SwfXmlIndex.build(xml_path)

    def test_jpeg3_bitmap_fill_preserves_alpha_and_matrix(self):
        shape = parse_shape(self.index, 4160)
        style = shape.fill_styles[2]
        self.assertEqual((style.bitmap_width, style.bitmap_height), (460, 508))
        self.assertFalse(style.bitmap_repeat)
        self.assertTrue(style.bitmap_smoothing)
        expected = (-0.63049315, 0.0, 0.0, 0.63049315, 149.1, -298.0)
        for actual, wanted in zip(style.bitmap_transform, expected):
            self.assertAlmostEqual(actual, wanted)
        svg = svg_for_shape(shape)
        self.assertIn("data:image/png;base64,", svg)
        self.assertIn('clip-path="url(#fill-bitmap-clip-2-0)"', svg)
        self.assertNotIn('fill="#000000"', svg)

    def test_all_bitmap_fill_modes_are_classified(self):
        for fill_type, repeat, smoothing in (
            (64, True, True),
            (65, False, True),
            (66, True, False),
            (67, False, False),
        ):
            xml = ET.fromstring(
                f'<shapes><fillStyles><fillStyles><item fillStyleType="{fill_type}" bitmapId="4159">'
                '<bitmapMatrix hasScale="true" hasRotate="false" scaleX="20" scaleY="20" '
                'translateX="0" translateY="0"/></item></fillStyles></fillStyles></shapes>'
            )
            style = parse_fill_styles(xml, self.index)[1]
            self.assertEqual((style.bitmap_repeat, style.bitmap_smoothing), (repeat, smoothing))

    def test_unknown_fill_mode_fails_explicitly(self):
        xml = ET.fromstring(
            '<shapes><fillStyles><fillStyles><item fillStyleType="99"/></fillStyles></fillStyles></shapes>'
        )
        with self.assertRaisesRegex(ValueError, "unsupported SWF fill style"):
            parse_fill_styles(xml, self.index)


if __name__ == "__main__":
    unittest.main()
