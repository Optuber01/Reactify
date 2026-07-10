#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import csv
import html
import io
import math
import zlib
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path
from typing import Deque, Dict, Iterable, List, Optional, Sequence, Tuple
from xml.etree import ElementTree as ET

from gacha_swf_manifest import SwfXmlIndex


ROOT = Path(__file__).resolve().parents[1]
XML_PATH = ROOT / ".cache" / "gacha_clubPC.xml"
UNRESOLVED_PATH = ROOT / "docs" / "data" / "asset-resolution" / "unresolved_leaf_ids.csv"
EXPORT_LOG_PATH = ROOT / "docs" / "data" / "asset-resolution" / "exported_swf_leaf_assets.csv"


FAMILY_OUTPUT_DIRS = {
    "left_eye": ROOT / ".assetmap" / "Textures" / "Gacha character parts" / "Head" / "Face" / "Mouth",
    "right_eye": ROOT / ".assetmap" / "Textures" / "Gacha character parts" / "Head" / "Face" / "Mouth",
    "left_eyebrow": ROOT / ".assetmap" / "Textures" / "Gacha character parts" / "Head" / "Hair" / "Front Hair",
    "right_eyebrow": ROOT / ".assetmap" / "Textures" / "Gacha character parts" / "Head" / "Hair" / "Front Hair",
    "front_hair": ROOT / ".assetmap" / "Textures" / "Gacha character parts" / "Head" / "Hair" / "Front Hair",
    "rear_hair": ROOT / ".assetmap" / "Textures" / "Gacha character parts" / "Head" / "Eyes" / "Eyes",
    "back_hair": ROOT / ".assetmap" / "Textures" / "Gacha character parts" / "Head" / "Hair" / "Back Hair",
    "ponytail": ROOT / ".assetmap" / "Textures" / "Gacha character parts" / "Head" / "Hair" / "Ponytail",
}


@dataclass(frozen=True)
class Point:
    x: int
    y: int


@dataclass(frozen=True)
class Edge:
    start: Point
    end: Point
    control: Optional[Point] = None

    def reversed(self) -> "Edge":
        return Edge(start=self.end, end=self.start, control=self.control)


@dataclass(frozen=True)
class GradientStop:
    ratio: int
    color: str
    opacity: str


@dataclass(frozen=True)
class FillStyle:
    color: str
    opacity: str
    gradient_kind: Optional[str] = None
    gradient_transform: Optional[Tuple[float, float, float, float, float, float]] = None
    gradient_stops: Tuple[GradientStop, ...] = ()
    bitmap_data_uri: Optional[str] = None
    bitmap_width: Optional[int] = None
    bitmap_height: Optional[int] = None
    bitmap_transform: Optional[Tuple[float, float, float, float, float, float]] = None
    bitmap_repeat: bool = False
    bitmap_smoothing: bool = False


@dataclass(frozen=True)
class LineStyle:
    width: int
    color: str
    opacity: str


@dataclass
class ShapeSvg:
    shape_id: int
    xmin: int
    ymin: int
    xmax: int
    ymax: int
    fill_paths: Dict[int, List[List[Edge]]]
    line_paths: Dict[int, List[List[Edge]]]
    fill_styles: Dict[int, FillStyle]
    line_styles: Dict[int, LineStyle]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export missing SWF DefineShape leaf ids as SVG assets without flattening wrappers."
    )
    parser.add_argument("--xml", default=str(XML_PATH))
    parser.add_argument("--unresolved", default=str(UNRESOLVED_PATH))
    parser.add_argument("--log", default=str(EXPORT_LOG_PATH))
    parser.add_argument(
        "--families",
        default="",
        help="Comma-separated family filter. Default exports every unresolved non-excluded family.",
    )
    parser.add_argument(
        "--ids",
        default="",
        help="Comma-separated explicit leaf ids to export. When set, unresolved CSV is only used for family routing.",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def unresolved_targets(path: Path, families: set[str], explicit_ids: set[int]) -> Dict[Tuple[str, int], Dict[str, str]]:
    targets: Dict[Tuple[str, int], Dict[str, str]] = {}
    with path.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            if row["next_action"] == "exclude_from_renderer":
                continue
            family = row["family"]
            if families and family not in families:
                continue
            leaf_id = int(row["leaf_id"])
            if explicit_ids and leaf_id not in explicit_ids:
                continue
            if family not in FAMILY_OUTPUT_DIRS:
                continue
            key = (family, leaf_id)
            current = targets.get(key)
            if current is None:
                targets[key] = {
                    "family": family,
                    "leaf_id": str(leaf_id),
                    "first_chooser_frame": row["chooser_frame"],
                    "name_paths": row["name_path"],
                    "reasons": row["reason"],
                    "row_count": "1",
                }
            else:
                current["row_count"] = str(int(current["row_count"]) + 1)
                if row["name_path"] not in current["name_paths"].split(";"):
                    current["name_paths"] += ";" + row["name_path"]
                if row["reason"] not in current["reasons"].split(";"):
                    current["reasons"] += ";" + row["reason"]
    return targets


def parse_shape(index: SwfXmlIndex, shape_id: int) -> ShapeSvg:
    if shape_id not in index.shapes:
        raise KeyError(f"{shape_id} is not a DefineShape tag in {index.xml_path}")
    root = ET.fromstring(index.block_bytes(index.shapes[shape_id]).decode("utf-8", errors="ignore"))
    bounds = root.find("shapeBounds")
    if bounds is None:
        bounds = root.find("edgeBounds")
    if bounds is None:
        raise ValueError(f"shape {shape_id} has no bounds")
    xmin = int(bounds.attrib["Xmin"])
    ymin = int(bounds.attrib["Ymin"])
    xmax = int(bounds.attrib["Xmax"])
    ymax = int(bounds.attrib["Ymax"])

    shape_with_style = root.find("shapes")
    if shape_with_style is None:
        raise ValueError(f"shape {shape_id} has no shapes block")

    fill_styles = parse_fill_styles(shape_with_style, index)
    line_styles = parse_line_styles(shape_with_style)
    fill_edges: Dict[int, List[Edge]] = defaultdict(list)
    line_edges: Dict[int, List[Edge]] = defaultdict(list)

    cursor = Point(0, 0)
    fill0 = 0
    fill1 = 0
    line = 0
    records = shape_with_style.find("shapeRecords")
    if records is None:
        raise ValueError(f"shape {shape_id} has no shape records")

    for record in records:
        record_type = record.attrib.get("type")
        if record_type == "StyleChangeRecord":
            if record.attrib.get("stateMoveTo") == "true":
                cursor = Point(int(record.attrib.get("moveDeltaX", "0")), int(record.attrib.get("moveDeltaY", "0")))
            if record.attrib.get("stateFillStyle0") == "true":
                fill0 = int(record.attrib.get("fillStyle0", "0"))
            if record.attrib.get("stateFillStyle1") == "true":
                fill1 = int(record.attrib.get("fillStyle1", "0"))
            if record.attrib.get("stateLineStyle") == "true":
                line = int(record.attrib.get("lineStyle", "0"))
            continue
        if record_type == "StraightEdgeRecord":
            dx, dy = straight_delta(record)
            edge = Edge(start=cursor, end=Point(cursor.x + dx, cursor.y + dy))
            cursor = edge.end
        elif record_type == "CurvedEdgeRecord":
            control = Point(
                cursor.x + int(record.attrib.get("controlDeltaX", "0")),
                cursor.y + int(record.attrib.get("controlDeltaY", "0")),
            )
            edge = Edge(
                start=cursor,
                control=control,
                end=Point(
                    control.x + int(record.attrib.get("anchorDeltaX", "0")),
                    control.y + int(record.attrib.get("anchorDeltaY", "0")),
                ),
            )
            cursor = edge.end
        elif record_type == "EndShapeRecord":
            break
        else:
            continue

        if fill1:
            fill_edges[fill1].append(edge)
        if fill0:
            fill_edges[fill0].append(edge.reversed())
        if line:
            line_edges[line].append(edge)

    return ShapeSvg(
        shape_id=shape_id,
        xmin=xmin,
        ymin=ymin,
        xmax=xmax,
        ymax=ymax,
        fill_paths={style: stitch_edges(edges) for style, edges in fill_edges.items()},
        line_paths={style: stitch_edges(edges, close_paths=False) for style, edges in line_edges.items()},
        fill_styles=fill_styles,
        line_styles=line_styles,
    )


def parse_fill_styles(shape_with_style: ET.Element, swf_index: Optional[SwfXmlIndex] = None) -> Dict[int, FillStyle]:
    styles: Dict[int, FillStyle] = {}
    fill_styles = shape_with_style.find("./fillStyles/fillStyles")
    if fill_styles is None:
        return styles
    for style_index, item in enumerate(fill_styles, start=1):
        fill_type = item.attrib.get("fillStyleType")
        if fill_type == "0":
            styles[style_index] = color_style(item.find("color"))
            continue
        if fill_type in {"16", "18", "19"}:
            styles[style_index] = gradient_style(item, fill_type)
            continue
        if fill_type in {"64", "65", "66", "67"}:
            if swf_index is None:
                raise ValueError("bitmap fill requires a SWF bitmap index")
            styles[style_index] = bitmap_style(item, fill_type, swf_index)
            continue
        raise ValueError(f"unsupported SWF fill style {fill_type!r}")
    return styles


def bitmap_style(item: ET.Element, fill_type: str, index: SwfXmlIndex) -> FillStyle:
    bitmap_id = int(item.attrib["bitmapId"])
    if bitmap_id == 65535:
        return FillStyle(color="none", opacity="0")
    matrix = item.find("bitmapMatrix")
    if matrix is None:
        raise ValueError(f"bitmap fill {bitmap_id} has no matrix")
    data_uri, width, height = decode_bitmap(index, bitmap_id)
    a, b, c, d, tx, ty = matrix_tuple(matrix)
    return FillStyle(
        color="",
        opacity="1",
        bitmap_data_uri=data_uri,
        bitmap_width=width,
        bitmap_height=height,
        bitmap_transform=(a / 20, b / 20, c / 20, d / 20, tx, ty),
        bitmap_repeat=fill_type in {"64", "66"},
        bitmap_smoothing=fill_type in {"64", "65"},
    )


def decode_bitmap(index: SwfXmlIndex, bitmap_id: int) -> Tuple[str, int, int]:
    entry = index.bitmaps.get(bitmap_id)
    if entry is None:
        raise ValueError(f"bitmap fill references missing bitmap {bitmap_id}")
    root = ET.fromstring(index.block_bytes(entry).decode("utf-8", errors="ignore"))
    try:
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError("bitmap fill export requires Pillow") from exc
    image_hex = root.attrib.get("imageData")
    if image_hex:
        with Image.open(io.BytesIO(bytes.fromhex(image_hex))) as source:
            image = source.convert("RGBA")
        alpha_hex = root.attrib.get("bitmapAlphaData")
        if alpha_hex:
            alpha = zlib.decompress(bytes.fromhex(alpha_hex))
            expected = image.width * image.height
            if len(alpha) != expected:
                raise ValueError(f"bitmap {bitmap_id} alpha length {len(alpha)} != {expected}")
            image.putalpha(Image.frombytes("L", image.size, alpha))
    elif entry.item_type.startswith("DefineBitsLossless"):
        image = decode_lossless_bitmap(root, bitmap_id, Image)
    else:
        raise ValueError(f"bitmap {bitmap_id} has no supported image payload")
    output = io.BytesIO()
    image.save(output, format="PNG")
    encoded = base64.b64encode(output.getvalue()).decode("ascii")
    return f"data:image/png;base64,{encoded}", image.width, image.height


def decode_lossless_bitmap(root: ET.Element, bitmap_id: int, image_module) -> object:
    if root.attrib.get("bitmapFormat") != "5":
        raise ValueError(f"bitmap {bitmap_id} uses unsupported lossless format {root.attrib.get('bitmapFormat')}")
    width = int(root.attrib["bitmapWidth"])
    height = int(root.attrib["bitmapHeight"])
    payload_hex = root.attrib.get("zlibBitmapData") or root.attrib.get("bitmapData")
    if not payload_hex:
        raise ValueError(f"bitmap {bitmap_id} has no lossless payload")
    raw = zlib.decompress(bytes.fromhex(payload_hex))
    if len(raw) != width * height * 4:
        raise ValueError(f"bitmap {bitmap_id} payload length {len(raw)} != {width * height * 4}")
    rgba = bytearray(len(raw))
    has_alpha = root.attrib.get("type") == "DefineBitsLossless2Tag"
    for offset in range(0, len(raw), 4):
        alpha = raw[offset] if has_alpha else 255
        red, green, blue = raw[offset + 1 : offset + 4]
        if has_alpha and 0 < alpha < 255:
            red = min(255, round(red * 255 / alpha))
            green = min(255, round(green * 255 / alpha))
            blue = min(255, round(blue * 255 / alpha))
        rgba[offset : offset + 4] = bytes((red, green, blue, alpha))
    return image_module.frombytes("RGBA", (width, height), bytes(rgba))


def parse_line_styles(shape_with_style: ET.Element) -> Dict[int, LineStyle]:
    styles: Dict[int, LineStyle] = {}
    containers = [
        shape_with_style.find("./lineStyles/lineStyles"),
        shape_with_style.find("./lineStyles/lineStyles2"),
    ]
    for container in containers:
        if container is None or not list(container):
            continue
        for index, item in enumerate(container, start=1):
            color = item.find("color")
            style = color_style(color)
            styles[index] = LineStyle(
                width=int(item.attrib.get("width", "20")),
                color=style.color,
                opacity=style.opacity,
            )
        break
    return styles


def color_style(color: Optional[ET.Element]) -> FillStyle:
    if color is None:
        return FillStyle(color="#000000", opacity="1")
    red = int(color.attrib.get("red", "0"))
    green = int(color.attrib.get("green", "0"))
    blue = int(color.attrib.get("blue", "0"))
    alpha = int(color.attrib.get("alpha", "255"))
    return FillStyle(color=f"#{red:02x}{green:02x}{blue:02x}", opacity=format_float(alpha / 255))


def gradient_style(item: ET.Element, fill_type: str) -> FillStyle:
    gradient_matrix = item.find("gradientMatrix")
    if gradient_matrix is None:
        return FillStyle(color="#000000", opacity="1")
    gradient = item.find("gradient") or item.find("focalGradient")
    if gradient is None:
        return FillStyle(color="#000000", opacity="1")
    records = gradient.find("gradientRecords")
    if records is None:
        return FillStyle(color="#000000", opacity="1")
    stops: List[GradientStop] = []
    for record in records:
        stop_style = color_style(record.find("color"))
        stops.append(
            GradientStop(
                ratio=int(record.attrib.get("ratio", "0")),
                color=stop_style.color,
                opacity=stop_style.opacity,
            )
        )
    if not stops:
        return FillStyle(color="#000000", opacity="1")
    return FillStyle(
        color=stops[0].color,
        opacity=stops[0].opacity,
        gradient_kind="linear" if fill_type == "16" else "radial",
        gradient_transform=matrix_tuple(gradient_matrix),
        gradient_stops=tuple(stops),
    )


def matrix_tuple(matrix: ET.Element) -> Tuple[float, float, float, float, float, float]:
    has_scale = matrix.attrib.get("hasScale") == "true"
    has_rotate = matrix.attrib.get("hasRotate") == "true"
    scale_x = float(matrix.attrib.get("scaleX", "1" if not has_scale else "0"))
    scale_y = float(matrix.attrib.get("scaleY", "1" if not has_scale else "0"))
    rotate_skew_0 = float(matrix.attrib.get("rotateSkew0", "0" if has_rotate else "0"))
    rotate_skew_1 = float(matrix.attrib.get("rotateSkew1", "0" if has_rotate else "0"))
    translate_x = int(matrix.attrib.get("translateX", "0")) / 20
    translate_y = int(matrix.attrib.get("translateY", "0")) / 20
    return (scale_x, rotate_skew_1, rotate_skew_0, scale_y, translate_x, translate_y)


def straight_delta(record: ET.Element) -> Tuple[int, int]:
    if record.attrib.get("generalLineFlag") == "true":
        return int(record.attrib.get("deltaX", "0")), int(record.attrib.get("deltaY", "0"))
    if record.attrib.get("vertLineFlag") == "true":
        return 0, int(record.attrib.get("deltaY", "0"))
    return int(record.attrib.get("deltaX", "0")), 0


def stitch_edges(edges: Sequence[Edge], close_paths: bool = True) -> List[List[Edge]]:
    by_start: Dict[Point, Deque[Edge]] = defaultdict(deque)
    for edge in edges:
        by_start[edge.start].append(edge)

    paths: List[List[Edge]] = []
    remaining = len(edges)
    while remaining:
        start = next(point for point, queue in by_start.items() if queue)
        first = by_start[start].popleft()
        remaining -= 1
        path = [first]
        current = first.end
        while current != path[0].start:
            queue = by_start.get(current)
            if not queue:
                break
            path.append(queue.popleft())
            remaining -= 1
            current = path[-1].end
        if close_paths and path[-1].end != path[0].start:
            # Keep the real edges visible; do not synthesize guessed closing geometry.
            paths.append(path)
        else:
            paths.append(path)
    return paths


def svg_for_shape(shape: ShapeSvg) -> str:
    canvas_min_x = min(0, shape.xmin)
    canvas_min_y = min(0, shape.ymin)
    canvas_max_x = max(0, shape.xmax)
    canvas_max_y = max(0, shape.ymax)
    width = max(1, canvas_max_x - canvas_min_x)
    height = max(1, canvas_max_y - canvas_min_y)
    width_px = format_float(width / 20)
    height_px = format_float(height / 20)
    translate_x = -canvas_min_x / 20
    translate_y = -canvas_min_y / 20
    lines = [
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        (
            f'<svg xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'height="{height_px}px" width="{width_px}px" '
            f'viewBox="0 0 {width_px} {height_px}" '
            f'xmlns="http://www.w3.org/2000/svg">'
        ),
    ]
    gradient_lines: List[str] = []
    for style_index in sorted(shape.fill_paths):
        style = shape.fill_styles.get(style_index, FillStyle(color="#000000", opacity="1"))
        if style.gradient_kind is None:
            continue
        gradient_lines.extend(svg_gradient_lines(style, f"fill-gradient-{style_index}"))
    for style_index in sorted(shape.fill_paths):
        style = shape.fill_styles[style_index]
        if style.bitmap_data_uri is not None and style.bitmap_repeat:
            gradient_lines.extend(svg_bitmap_lines(style, f"fill-bitmap-{style_index}"))
    if gradient_lines:
        lines.append("  <defs>")
        lines.extend(gradient_lines)
        lines.append("  </defs>")
    lines.append(
        f'  <g transform="matrix(1.0, 0.0, 0.0, 1.0, {format_float(translate_x)}, {format_float(translate_y)})">'
    )
    for style_index in sorted(shape.fill_paths):
        style = shape.fill_styles.get(style_index, FillStyle(color="#000000", opacity="1"))
        for path_number, path in enumerate(shape.fill_paths[style_index]):
            d = path_data(path, close=True)
            if style.bitmap_data_uri is not None and not style.bitmap_repeat:
                if style.bitmap_transform is None or style.bitmap_width is None or style.bitmap_height is None:
                    raise ValueError("clipped bitmap fill is incomplete")
                a, b, c, d_matrix, tx, ty = style.bitmap_transform
                transform = f"matrix({format_float(a)}, {format_float(b)}, {format_float(c)}, {format_float(d_matrix)}, {format_float(tx)}, {format_float(ty)})"
                clip_id = f"fill-bitmap-clip-{style_index}-{path_number}"
                lines.append(f'    <defs><clipPath id="{clip_id}" clipPathUnits="userSpaceOnUse"><path d="{html.escape(d)}" fill-rule="evenodd"/></clipPath></defs>')
                lines.append(f'    <g clip-path="url(#{clip_id})"><image width="{style.bitmap_width}" height="{style.bitmap_height}" href="{style.bitmap_data_uri}" transform="{transform}" image-rendering="{"auto" if style.bitmap_smoothing else "pixelated"}"/></g>')
                continue
            attrs = svg_fill_attrs(style, f"fill-gradient-{style_index}")
            lines.append(
                f'    <path d="{html.escape(d)}" {attrs} fill-rule="evenodd" stroke="none"/>'
            )
    for style_index in sorted(shape.line_paths):
        style = shape.line_styles.get(style_index, LineStyle(width=20, color="#000000", opacity="1"))
        for path in shape.line_paths[style_index]:
            d = path_data(path, close=False)
            attrs = (
                f'fill="none" stroke="{style.color}" stroke-linecap="round" '
                f'stroke-linejoin="round" stroke-width="{format_float(style.width / 20)}"'
            )
            if style.opacity != "1":
                attrs += f' stroke-opacity="{style.opacity}"'
            lines.append(f'    <path d="{html.escape(d)}" {attrs}/>')
    lines.append("  </g>")
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def svg_fill_attrs(style: FillStyle, gradient_id: str) -> str:
    if style.bitmap_data_uri is not None:
        return f'fill="url(#{gradient_id.replace("gradient", "bitmap")})"'
    if style.gradient_kind is not None:
        return f'fill="url(#{gradient_id})"'
    attrs = f'fill="{style.color}"'
    if style.opacity != "1":
        attrs += f' fill-opacity="{style.opacity}"'
    return attrs


def svg_bitmap_lines(style: FillStyle, pattern_id: str) -> List[str]:
    if style.bitmap_data_uri is None or style.bitmap_transform is None:
        return []
    if style.bitmap_width is None or style.bitmap_height is None:
        raise ValueError("bitmap fill has no dimensions")
    a, b, c, d, tx, ty = style.bitmap_transform
    transform = f"matrix({format_float(a)}, {format_float(b)}, {format_float(c)}, {format_float(d)}, {format_float(tx)}, {format_float(ty)})"
    rendering = "auto" if style.bitmap_smoothing else "pixelated"
    return [
        f'    <pattern id="{pattern_id}" patternUnits="userSpaceOnUse" width="{style.bitmap_width}" height="{style.bitmap_height}" patternTransform="{transform}">',
        f'      <image width="{style.bitmap_width}" height="{style.bitmap_height}" href="{style.bitmap_data_uri}" image-rendering="{rendering}"/>',
        "    </pattern>",
    ]


def svg_gradient_lines(style: FillStyle, gradient_id: str) -> List[str]:
    if style.gradient_kind is None or style.gradient_transform is None:
        return []
    a, b, c, d, tx, ty = style.gradient_transform
    transform = (
        f'matrix({format_float(a)}, {format_float(b)}, {format_float(c)}, '
        f'{format_float(d)}, {format_float(tx)}, {format_float(ty)})'
    )
    coords = (
        'x1="-819.2" y1="0" x2="819.2" y2="0"'
        if style.gradient_kind == "linear"
        else 'cx="0" cy="0" r="819.2" fx="0" fy="0"'
    )
    lines = [
        (
            f'    <{style.gradient_kind}Gradient id="{gradient_id}" '
            f'gradientUnits="userSpaceOnUse" {coords} gradientTransform="{transform}">'
        )
    ]
    for stop in style.gradient_stops:
        attrs = (
            f'      <stop offset="{format_float(stop.ratio / 255)}" '
            f'stop-color="{stop.color}"'
        )
        if stop.opacity != "1":
            attrs += f' stop-opacity="{stop.opacity}"'
        attrs += '/>'
        lines.append(attrs)
    lines.append(f'    </{style.gradient_kind}Gradient>')
    return lines


def path_data(path: Sequence[Edge], close: bool) -> str:
    if not path:
        return ""
    chunks = [f"M{coord(path[0].start.x)} {coord(path[0].start.y)}"]
    for edge in path:
        if edge.control is None:
            chunks.append(f"L{coord(edge.end.x)} {coord(edge.end.y)}")
        else:
            chunks.append(
                f"Q{coord(edge.control.x)} {coord(edge.control.y)} {coord(edge.end.x)} {coord(edge.end.y)}"
            )
    if close and path[-1].end == path[0].start:
        chunks.append("Z")
    return " ".join(chunks)


def coord(value: int) -> str:
    return format_float(value / 20)


def format_float(value: float) -> str:
    if abs(value) < 1e-12:
        value = 0.0
    if math.isclose(value, round(value), abs_tol=1e-9):
        return str(int(round(value)))
    return f"{value:.6f}".rstrip("0").rstrip(".")


def write_csv(path: Path, rows: Sequence[Dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "family",
        "leaf_id",
        "status",
        "asset_path",
        "first_chooser_frame",
        "row_count",
        "name_paths",
        "reasons",
        "source_file",
        "notes",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def relative(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def main() -> int:
    args = parse_args()
    families = {part.strip() for part in args.families.split(",") if part.strip()}
    explicit_ids = {int(part.strip()) for part in args.ids.split(",") if part.strip()}
    targets = unresolved_targets(Path(args.unresolved), families, explicit_ids)
    index = SwfXmlIndex.build(Path(args.xml))
    rows: List[Dict[str, str]] = []

    for family, leaf_id in sorted(targets, key=lambda item: (item[0], item[1])):
        target = targets[(family, leaf_id)]
        out_dir = FAMILY_OUTPUT_DIRS[family]
        out_path = out_dir / f"{leaf_id}.svg"
        if leaf_id not in index.shapes:
            rows.append(
                {
                    **target,
                    "status": "not_a_define_shape",
                    "asset_path": relative(out_path),
                    "source_file": relative(Path(args.xml)),
                    "notes": "leaf id was unresolved but is not present as a shape tag",
                }
            )
            continue
        try:
            shape = parse_shape(index, leaf_id)
            svg = svg_for_shape(shape)
        except Exception as exc:  # noqa: BLE001 - this is a batch evidence exporter.
            rows.append(
                {
                    **target,
                    "status": "export_failed",
                    "asset_path": relative(out_path),
                    "source_file": relative(Path(args.xml)),
                    "notes": f"{type(exc).__name__}: {exc}",
                }
            )
            continue
        if not args.dry_run:
            out_dir.mkdir(parents=True, exist_ok=True)
            out_path.write_text(svg, encoding="utf-8")
        rows.append(
            {
                **target,
                "status": "dry_run" if args.dry_run else "exported_svg",
                "asset_path": relative(out_path),
                "source_file": relative(Path(args.xml)),
                "notes": "SVG generated from DefineShape records; wrapper graph and transforms remain in resolution CSVs",
            }
        )

    if not args.dry_run:
        write_csv(Path(args.log), rows)
    exported = sum(1 for row in rows if row["status"] in {"exported_svg", "dry_run"})
    failed = len(rows) - exported
    print(f"targets={len(rows)} exported={exported} failed={failed}")
    by_family: Dict[str, int] = defaultdict(int)
    for row in rows:
        if row["status"] in {"exported_svg", "dry_run"}:
            by_family[row["family"]] += 1
    for family in sorted(by_family):
        print(f"{family},{by_family[family]}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
