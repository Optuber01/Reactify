#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional


TOP_LEVEL_ITEM_RE = re.compile(r"^    <item type=\"([^\"]+)\"")
SPRITE_START_RE = re.compile(
    r'^    <item type="DefineSpriteTag"[^>]*frameCount="(\d+)"[^>]*spriteId="(\d+)"'
)
SHAPE_START_RE = re.compile(
    r'^    <item type="(DefineShapeTag|DefineShape2Tag|DefineShape3Tag|DefineShape4Tag)"[^>]*shapeId="(\d+)"'
)
BITMAP_START_RE = re.compile(r'^    <item type="(DefineBitsJPEG2Tag|DefineBitsJPEG3Tag|DefineBitsJPEG4Tag)"')
LOSSLESS_BITMAP_START_RE = re.compile(
    r'^    <item type="(DefineBitsLosslessTag|DefineBitsLossless2Tag)"[^>]*characterID="(\d+)"'
)
PLACE_RE = re.compile(
    r'^\s*<item type="PlaceObject(?:2|3)Tag"[^>]*characterId="(\d+)"[^>]*depth="(\d+)"[^>]*name="([^"]+)"'
)
PLACE_NONAME_RE = re.compile(
    r'^\s*<item type="PlaceObject(?:2|3)Tag"[^>]*characterId="(\d+)"[^>]*depth="(\d+)"'
)
RATIO_RE = re.compile(r'ratio="(\d+)"')
REMOVE_RE = re.compile(r'^\s*<item type="RemoveObject2Tag"[^>]*depth="(\d+)"')
SHOW_RE = re.compile(r'^\s*<item type="ShowFrameTag"')
XML_ATTR_RE = re.compile(r'([A-Za-z0-9]+)="([^"]*)"')


@dataclass
class TopLevelEntry:
    line_no: int
    byte_offset: int
    item_type: str
    item_id: Optional[int]
    frame_count: Optional[int] = None


class SwfXmlIndex:
    def __init__(self, xml_path: Path, entries: List[TopLevelEntry]):
        self.xml_path = xml_path
        self.entries = entries
        self.sprites: Dict[int, TopLevelEntry] = {
            entry.item_id: entry
            for entry in entries
            if entry.item_type == "DefineSpriteTag" and entry.item_id is not None
        }
        self.shapes: Dict[int, TopLevelEntry] = {
            entry.item_id: entry
            for entry in entries
            if entry.item_type.startswith("DefineShape") and entry.item_id is not None
        }
        self.bitmaps: Dict[int, TopLevelEntry] = {
            entry.item_id: entry
            for entry in entries
            if entry.item_type.startswith(("DefineBitsJPEG", "DefineBitsLossless")) and entry.item_id is not None
        }
        self._entry_pos = {id(entry): idx for idx, entry in enumerate(entries)}

    @classmethod
    def build(cls, xml_path: Path) -> "SwfXmlIndex":
        entries: List[TopLevelEntry] = []
        with xml_path.open("rb") as handle:
            line_no = 0
            while True:
                offset = handle.tell()
                raw = handle.readline()
                if not raw:
                    break
                line_no += 1
                try:
                    line = raw.decode("utf-8")
                except UnicodeDecodeError:
                    line = raw.decode("utf-8", errors="ignore")
                top = TOP_LEVEL_ITEM_RE.match(line)
                if not top:
                    continue
                item_type = top.group(1)
                sprite_match = SPRITE_START_RE.match(line)
                if sprite_match:
                    frame_count = int(sprite_match.group(1))
                    item_id = int(sprite_match.group(2))
                    entries.append(
                        TopLevelEntry(
                            line_no=line_no,
                            byte_offset=offset,
                            item_type=item_type,
                            item_id=item_id,
                            frame_count=frame_count,
                        )
                    )
                    continue
                shape_match = SHAPE_START_RE.match(line)
                if shape_match:
                    entries.append(
                        TopLevelEntry(
                            line_no=line_no,
                            byte_offset=offset,
                            item_type=item_type,
                            item_id=int(shape_match.group(2)),
                        )
                    )
                    continue
                bitmap_match = BITMAP_START_RE.match(line)
                if bitmap_match:
                    entries.append(
                        TopLevelEntry(
                            line_no=line_no,
                            byte_offset=offset,
                            item_type=item_type,
                            item_id=None,
                        )
                    )
                    continue
                lossless_bitmap_match = LOSSLESS_BITMAP_START_RE.match(line)
                if lossless_bitmap_match:
                    entries.append(
                        TopLevelEntry(
                            line_no=line_no,
                            byte_offset=offset,
                            item_type=item_type,
                            item_id=int(lossless_bitmap_match.group(2)),
                        )
                    )
                    continue
                entries.append(
                    TopLevelEntry(
                        line_no=line_no,
                        byte_offset=offset,
                        item_type=item_type,
                        item_id=None,
                    )
                )
        pending_bitmaps: List[TopLevelEntry] = []
        for entry in entries:
            if entry.item_type.startswith("DefineBitsJPEG"):
                pending_bitmaps.append(entry)
                continue
            if entry.item_id is not None and pending_bitmaps:
                first_id = entry.item_id - len(pending_bitmaps)
                for offset, bitmap in enumerate(pending_bitmaps):
                    bitmap.item_id = first_id + offset
                pending_bitmaps.clear()
        if pending_bitmaps:
            raise ValueError("cannot infer trailing SWF bitmap character ids")
        return cls(xml_path, entries)

    def block_bytes(self, entry: TopLevelEntry) -> bytes:
        idx = self._entry_pos[id(entry)]
        end_offset = (
            self.entries[idx + 1].byte_offset if idx + 1 < len(self.entries) else self.xml_path.stat().st_size
        )
        with self.xml_path.open("rb") as handle:
            handle.seek(entry.byte_offset)
            return handle.read(end_offset - entry.byte_offset)


class SwfResolver:
    def __init__(self, index: SwfXmlIndex):
        self.index = index
        self._sprite_cache: Dict[int, Dict] = {}

    def parse_sprite(self, sprite_id: int) -> Dict:
        if sprite_id in self._sprite_cache:
            return self._sprite_cache[sprite_id]
        entry = self.index.sprites[sprite_id]
        block = self.index.block_bytes(entry).decode("utf-8", errors="ignore").splitlines()
        frames: List[List[Dict]] = []
        current_by_depth: Dict[int, Dict] = {}
        idx = 0
        while idx < len(block):
            line = block[idx]
            place_match = PLACE_RE.match(line)
            if place_match:
                char_id = int(place_match.group(1))
                depth = int(place_match.group(2))
                name = place_match.group(3)
                ratio_match = RATIO_RE.search(line)
                placement = self._parse_place_block(
                    block=block,
                    start_index=idx,
                    character_id=char_id,
                    depth=depth,
                    name=name,
                    ratio=int(ratio_match.group(1)) if ratio_match else None,
                )
                current_by_depth[depth] = self._merge_placement_update(
                    current=current_by_depth.get(depth),
                    update=placement,
                )
                idx = self._skip_to_item_end(block, idx) + 1
                continue
            place_noname = PLACE_NONAME_RE.match(line)
            if place_noname and 'name="' not in line:
                char_id = int(place_noname.group(1))
                depth = int(place_noname.group(2))
                ratio_match = RATIO_RE.search(line)
                placement = self._parse_place_block(
                    block=block,
                    start_index=idx,
                    character_id=char_id,
                    depth=depth,
                    name=None,
                    ratio=int(ratio_match.group(1)) if ratio_match else None,
                )
                current_by_depth[depth] = self._merge_placement_update(
                    current=current_by_depth.get(depth),
                    update=placement,
                )
                idx = self._skip_to_item_end(block, idx) + 1
                continue
            remove_match = REMOVE_RE.match(line)
            if remove_match:
                depth = int(remove_match.group(1))
                current_by_depth.pop(depth, None)
                idx += 1
                continue
            if SHOW_RE.match(line):
                frames.append([current_by_depth[d].copy() for d in sorted(current_by_depth)])
            idx += 1
        data = {
            "sprite_id": sprite_id,
            "frame_count": entry.frame_count,
            "frames": frames,
        }
        self._sprite_cache[sprite_id] = data
        return data

    def _parse_place_block(
        self,
        *,
        block: List[str],
        start_index: int,
        character_id: int,
        depth: int,
        name: Optional[str],
        ratio: Optional[int],
    ) -> Dict:
        placement = {
            "character_id": character_id,
            "depth": depth,
            "name": name,
            "ratio": ratio,
            "matrix": None,
            "color_transform": None,
        }
        if block[start_index].strip().endswith("/>"):
            return placement
        idx = start_index + 1
        while idx < len(block):
            stripped = block[idx].strip()
            if stripped.startswith("<matrix "):
                placement["matrix"] = self._parse_matrix(stripped)
            elif stripped.startswith("<colorTransform "):
                placement["color_transform"] = self._parse_color_transform(stripped)
            elif stripped.startswith("</item>"):
                break
            idx += 1
        return placement

    def _skip_to_item_end(self, block: List[str], start_index: int) -> int:
        if block[start_index].strip().endswith("/>"):
            return start_index
        idx = start_index + 1
        while idx < len(block):
            if block[idx].strip().startswith("</item>"):
                return idx
            idx += 1
        return start_index

    def _merge_placement_update(self, current: Optional[Dict], update: Dict) -> Dict:
        if update["character_id"] != 0 or current is None:
            return update
        merged = current.copy()
        if update["name"] is not None:
            merged["name"] = update["name"]
        if update["ratio"] is not None:
            merged["ratio"] = update["ratio"]
        if update["matrix"] is not None:
            merged["matrix"] = update["matrix"]
        if update["color_transform"] is not None:
            merged["color_transform"] = update["color_transform"]
        return merged

    def _parse_matrix(self, line: str) -> Dict:
        attrs = xml_attrs(line)
        return {
            "has_rotate": attrs.get("hasRotate") == "true",
            "has_scale": attrs.get("hasScale") == "true",
            "scale_x": xml_number(attrs.get("scaleX")),
            "scale_y": xml_number(attrs.get("scaleY")),
            "rotate_skew_0": xml_number(attrs.get("rotateSkew0")),
            "rotate_skew_1": xml_number(attrs.get("rotateSkew1")),
            "translate_x": xml_number(attrs.get("translateX")),
            "translate_y": xml_number(attrs.get("translateY")),
        }

    def _parse_color_transform(self, line: str) -> Dict:
        attrs = xml_attrs(line)
        return {
            "has_add_terms": attrs.get("hasAddTerms") == "true",
            "has_mult_terms": attrs.get("hasMultTerms") == "true",
            "red_mult_term": xml_number(attrs.get("redMultTerm")),
            "green_mult_term": xml_number(attrs.get("greenMultTerm")),
            "blue_mult_term": xml_number(attrs.get("blueMultTerm")),
            "alpha_mult_term": xml_number(attrs.get("alphaMultTerm")),
            "red_add_term": xml_number(attrs.get("redAddTerm")),
            "green_add_term": xml_number(attrs.get("greenAddTerm")),
            "blue_add_term": xml_number(attrs.get("blueAddTerm")),
            "alpha_add_term": xml_number(attrs.get("alphaAddTerm")),
        }

    def resolve_character(self, character_id: int, depth_limit: int = 6) -> Dict:
        if depth_limit < 0:
            return {"type": "max_depth", "id": character_id}
        if character_id in self.index.shapes:
            return {"type": "shape", "id": character_id}
        if character_id not in self.index.sprites:
            return {"type": "unknown", "id": character_id}
        sprite = self.parse_sprite(character_id)
        children = []
        for frame_index, frame in enumerate(sprite["frames"], start=1):
            resolved_frame = []
            for child in frame:
                resolved_frame.append(
                    {
                        **child,
                        "resolved": self.resolve_character(child["character_id"], depth_limit - 1),
                    }
                )
            children.append({"frame": frame_index, "placements": resolved_frame})
        return {
            "type": "sprite",
            "id": character_id,
            "frame_count": sprite["frame_count"],
            "frames": children,
        }

    def leaf_shapes_for_frame(self, character_id: int, nested_frame: int = 1) -> List[int]:
        if character_id in self.index.shapes:
            return [character_id]
        if character_id not in self.index.sprites:
            return []
        sprite = self.parse_sprite(character_id)
        if not sprite["frames"]:
            return []
        frame = sprite["frames"][max(0, min(nested_frame - 1, len(sprite["frames"]) - 1))]
        shapes: List[int] = []
        for child in frame:
            shapes.extend(self.leaf_shapes_for_frame(child["character_id"], 1))
        return sorted(dict.fromkeys(shapes))


FAMILY_CHOOSERS = {
    "avatar": 25945,
    "blush": 15275,
    "front_hair": 23395,
    "rear_hair": 19429,
    "back_hair": 5459,
    "ponytail": 4768,
    "ahoge": 23996,
    "head_shape": 14821,
    "left_eye": 17900,
    "right_eye": 17818,
    "left_eyebrow": 23766,
    "right_eyebrow": 23766,
    "faceshadow": 17911,
    "mouth": 16589,
    "nose": 17881,
    "logo_art": 11423,
    "logo_layout": 11424,
    "shoulder": 7142,
    "upper_sleeve": 7026,
    "lower_sleeve": 8682,
    "glove": 7234,
    "wrist": 7418,
    "thigh_socks": 9607,
    "foot_socks": 9996,
    "thigh_pants": 9731,
    "foot_pants": 10134,
    "body_pants": 10813,
    "shoe": 10703,
    "knee": 10801,
    "body_shirt": 11385,
    "body_jacket": 11717,
    "belt_shirt": 12515,
    "belt_jacket": 12581,
    "belt": 12435,
    "scarf": 13543,
    "other": 14780,
    "accessory": 15264,
    "glasses": 19710,
    "hat": 24691,
    "cape": 5821,
    "wings": 6730,
    "tail": 6403,
    "weapon": 9464,
    "shield": 12841,
    "shadow": 52,
    "special": 4174,
    "chat_bubble_type": 2126,
    "pet": 2021,
    "title": 26023,
    "icon": 26287,
}


def chooser_manifest(resolver: SwfResolver, chooser_id: int) -> Dict:
    chooser = resolver.parse_sprite(chooser_id)
    frames_out = []
    for frame_index, frame in enumerate(chooser["frames"], start=1):
        placements = []
        for placement in frame:
            child_id = placement["character_id"]
            resolved = resolver.resolve_character(child_id)
            placements.append(
                {
                    **placement,
                    "leaf_shapes_first_frame": resolver.leaf_shapes_for_frame(child_id, 1),
                    "resolved": resolved,
                }
            )
        frames_out.append({"frame": frame_index, "placements": placements})
    return {
        "chooser_sprite_id": chooser_id,
        "frame_count": chooser["frame_count"],
        "frames": frames_out,
    }


def manifest_to_csv(manifest: Dict) -> str:
    lines = [
        "frame,depth,name,direct_character_id,direct_type,nested_frame,leaf_shapes",
    ]
    for frame in manifest["frames"]:
        frame_no = frame["frame"]
        for placement in frame["placements"]:
            resolved = placement["resolved"]
            if resolved["type"] == "sprite":
                for nested in resolved["frames"]:
                    leafs = []
                    for nested_place in nested["placements"]:
                        leafs.extend(collect_leaf_shapes(nested_place["resolved"]))
                    leafs = sorted(dict.fromkeys(leafs))
                    lines.append(
                        ",".join(
                            [
                                str(frame_no),
                                str(placement["depth"]),
                                csv_cell(placement["name"] or ""),
                                str(placement["character_id"]),
                                resolved["type"],
                                str(nested["frame"]),
                                csv_cell(" ".join(str(x) for x in leafs)),
                            ]
                        )
                    )
            else:
                lines.append(
                    ",".join(
                        [
                            str(frame_no),
                            str(placement["depth"]),
                            csv_cell(placement["name"] or ""),
                            str(placement["character_id"]),
                            resolved["type"],
                            "1",
                            csv_cell(" ".join(str(x) for x in collect_leaf_shapes(resolved))),
                        ]
                    )
                )
    return "\n".join(lines) + "\n"


def sprite_frames_csv(index: SwfXmlIndex, sprite: Dict) -> str:
    lines = [
        "frame,depth,name,character_id,character_type,character_frame_count,translate_x,translate_y,scale_x,scale_y,rotate_skew_0,rotate_skew_1,has_scale,has_rotate,red_mult_term,green_mult_term,blue_mult_term,alpha_mult_term",
    ]
    for frame_no, frame in enumerate(sprite["frames"], start=1):
        for placement in frame:
            character_id = placement["character_id"]
            if character_id in index.sprites:
                character_type = "sprite"
                character_frame_count = index.sprites[character_id].frame_count
            elif character_id in index.shapes:
                character_type = "shape"
                character_frame_count = ""
            elif character_id == 0:
                character_type = "empty"
                character_frame_count = ""
            else:
                character_type = "unknown"
                character_frame_count = ""
            matrix = placement.get("matrix") or {}
            color_transform = placement.get("color_transform") or {}
            lines.append(
                ",".join(
                    [
                        str(frame_no),
                        str(placement["depth"]),
                        csv_cell(placement["name"] or ""),
                        str(character_id),
                        character_type,
                        str(character_frame_count),
                        csv_cell("" if matrix.get("translate_x") is None else str(matrix["translate_x"])),
                        csv_cell("" if matrix.get("translate_y") is None else str(matrix["translate_y"])),
                        csv_cell("" if matrix.get("scale_x") is None else str(matrix["scale_x"])),
                        csv_cell("" if matrix.get("scale_y") is None else str(matrix["scale_y"])),
                        csv_cell("" if matrix.get("rotate_skew_0") is None else str(matrix["rotate_skew_0"])),
                        csv_cell("" if matrix.get("rotate_skew_1") is None else str(matrix["rotate_skew_1"])),
                        csv_cell("" if matrix.get("has_scale") is None else str(matrix["has_scale"])),
                        csv_cell("" if matrix.get("has_rotate") is None else str(matrix["has_rotate"])),
                        csv_cell("" if color_transform.get("red_mult_term") is None else str(color_transform["red_mult_term"])),
                        csv_cell("" if color_transform.get("green_mult_term") is None else str(color_transform["green_mult_term"])),
                        csv_cell("" if color_transform.get("blue_mult_term") is None else str(color_transform["blue_mult_term"])),
                        csv_cell("" if color_transform.get("alpha_mult_term") is None else str(color_transform["alpha_mult_term"])),
                    ]
                )
            )
    return "\n".join(lines) + "\n"


def collect_leaf_shapes(resolved: Dict) -> List[int]:
    kind = resolved["type"]
    if kind == "shape":
        return [resolved["id"]]
    if kind != "sprite":
        return []
    shapes: List[int] = []
    for frame in resolved["frames"]:
        for placement in frame["placements"]:
            shapes.extend(collect_leaf_shapes(placement["resolved"]))
        break
    return sorted(dict.fromkeys(shapes))


def flatten_leaf_paths(manifest: Dict, skip_unknown: bool = True) -> List[Dict]:
    rows: List[Dict] = []
    chooser_id = manifest["chooser_sprite_id"]

    def walk_resolved(
        *,
        chooser_frame: int,
        placement: Dict,
        resolved: Dict,
        name_path: List[str],
        character_path: List[int],
        depth_path: List[int],
        sprite_path: List[int],
        frame_path: List[int],
    ) -> None:
        kind = resolved["type"]
        if kind == "shape":
            rows.append(
                {
                    "chooser_frame": chooser_frame,
                    "name_path": name_path,
                    "character_path": character_path,
                    "depth_path": depth_path,
                    "sprite_path": sprite_path,
                    "frame_path": frame_path,
                    "leaf_kind": kind,
                    "leaf_id": resolved["id"],
                }
            )
            return
        if kind == "unknown":
            if not skip_unknown:
                rows.append(
                    {
                        "chooser_frame": chooser_frame,
                        "name_path": name_path,
                        "character_path": character_path,
                        "depth_path": depth_path,
                        "sprite_path": sprite_path,
                        "frame_path": frame_path,
                        "leaf_kind": kind,
                        "leaf_id": resolved["id"],
                    }
                )
            return
        if kind != "sprite":
            rows.append(
                {
                    "chooser_frame": chooser_frame,
                    "name_path": name_path,
                    "character_path": character_path,
                    "depth_path": depth_path,
                    "sprite_path": sprite_path,
                    "frame_path": frame_path,
                    "leaf_kind": kind,
                    "leaf_id": resolved["id"],
                }
            )
            return
        next_sprite_path = sprite_path + [resolved["id"]]
        for frame in resolved["frames"]:
            next_frame_path = frame_path + [frame["frame"]]
            for child in frame["placements"]:
                walk_resolved(
                    chooser_frame=chooser_frame,
                    placement=child,
                    resolved=child["resolved"],
                    name_path=name_path + [child["name"] or "<anon>"],
                    character_path=character_path + [child["character_id"]],
                    depth_path=depth_path + [child["depth"]],
                    sprite_path=next_sprite_path,
                    frame_path=next_frame_path,
                )

    for chooser_frame in manifest["frames"]:
        frame_no = chooser_frame["frame"]
        for placement in chooser_frame["placements"]:
            walk_resolved(
                chooser_frame=frame_no,
                placement=placement,
                resolved=placement["resolved"],
                name_path=[placement["name"] or "<anon>"],
                character_path=[placement["character_id"]],
                depth_path=[placement["depth"]],
                sprite_path=[chooser_id],
                frame_path=[],
            )
    return rows


def layer_paths_to_csv(rows: List[Dict]) -> str:
    lines = [
        "chooser_frame,name_path,character_path,depth_path,sprite_path,frame_path,leaf_kind,leaf_id",
    ]
    for row in rows:
        lines.append(
            ",".join(
                [
                    str(row["chooser_frame"]),
                    csv_cell("/".join(row["name_path"])),
                    csv_cell("/".join(str(x) for x in row["character_path"])),
                    csv_cell("/".join(str(x) for x in row["depth_path"])),
                    csv_cell("/".join(str(x) for x in row["sprite_path"])),
                    csv_cell("/".join(str(x) for x in row["frame_path"])),
                    row["leaf_kind"],
                    str(row["leaf_id"]),
                ]
            )
        )
    return "\n".join(lines) + "\n"


def csv_cell(value: str) -> str:
    if any(ch in value for ch in [",", "\"", "\n"]):
        return '"' + value.replace('"', '""') + '"'
    return value


def xml_attrs(line: str) -> Dict[str, str]:
    return dict(XML_ATTR_RE.findall(line))


def xml_number(value: Optional[str]) -> Optional[int | float | str]:
    if value is None or value == "":
        return None
    try:
        if any(ch in value for ch in [".", "e", "E"]):
            return float(value)
        return int(value)
    except ValueError:
        return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    manifest_parser = sub.add_parser("manifest")
    manifest_parser.add_argument("--xml", required=True)
    manifest_parser.add_argument("--family", choices=sorted(FAMILY_CHOOSERS))
    manifest_parser.add_argument("--sprite-id", type=int)
    manifest_parser.add_argument("--format", choices=["json", "csv"], default="json")
    manifest_parser.add_argument("--out")

    layers_parser = sub.add_parser("layers")
    layers_parser.add_argument("--xml", required=True)
    layers_parser.add_argument("--family", choices=sorted(FAMILY_CHOOSERS))
    layers_parser.add_argument("--sprite-id", type=int)
    layers_parser.add_argument("--format", choices=["json", "csv"], default="csv")
    layers_parser.add_argument("--out")
    layers_parser.add_argument("--include-unknown", action="store_true")

    frames_parser = sub.add_parser("frames")
    frames_parser.add_argument("--xml", required=True)
    frames_parser.add_argument("--family", choices=sorted(FAMILY_CHOOSERS))
    frames_parser.add_argument("--sprite-id", type=int)
    frames_parser.add_argument("--format", choices=["json", "csv"], default="csv")
    frames_parser.add_argument("--out")

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "manifest":
        if args.family is None and args.sprite_id is None:
            raise SystemExit("pass --family or --sprite-id")
        chooser_id = args.sprite_id or FAMILY_CHOOSERS[args.family]
        xml_path = Path(args.xml)
        index = SwfXmlIndex.build(xml_path)
        resolver = SwfResolver(index)
        manifest = chooser_manifest(resolver, chooser_id)
        payload = manifest_to_csv(manifest) if args.format == "csv" else json.dumps(manifest, indent=2)
        if args.out:
            Path(args.out).write_text(payload, encoding="utf-8")
        else:
            print(payload)
        return 0
    if args.command == "layers":
        if args.family is None and args.sprite_id is None:
            raise SystemExit("pass --family or --sprite-id")
        chooser_id = args.sprite_id or FAMILY_CHOOSERS[args.family]
        xml_path = Path(args.xml)
        index = SwfXmlIndex.build(xml_path)
        resolver = SwfResolver(index)
        manifest = chooser_manifest(resolver, chooser_id)
        rows = flatten_leaf_paths(manifest, skip_unknown=not args.include_unknown)
        payload = layer_paths_to_csv(rows) if args.format == "csv" else json.dumps(rows, indent=2)
        if args.out:
            Path(args.out).write_text(payload, encoding="utf-8")
        else:
            print(payload)
        return 0
    if args.command == "frames":
        if args.family is None and args.sprite_id is None:
            raise SystemExit("pass --family or --sprite-id")
        sprite_id = args.sprite_id or FAMILY_CHOOSERS[args.family]
        xml_path = Path(args.xml)
        index = SwfXmlIndex.build(xml_path)
        resolver = SwfResolver(index)
        sprite = resolver.parse_sprite(sprite_id)
        payload = sprite_frames_csv(index, sprite) if args.format == "csv" else json.dumps(sprite, indent=2)
        if args.out:
            Path(args.out).write_text(payload, encoding="utf-8")
        else:
            print(payload)
        return 0
    raise SystemExit(1)


if __name__ == "__main__":
    raise SystemExit(main())
