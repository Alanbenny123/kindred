"""Generate the simple Kindred app icon without external image packages."""

import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID = ROOT / "mobile/android/app/src/main/res"


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def render(size: int) -> bytes:
    background = (238, 119, 117)
    foreground = (255, 250, 246)
    rows = []
    for py in range(size):
        row = bytearray([0])
        for px in range(size):
            coverage = 0
            for oy in (0.25, 0.75):
                for ox in (0.25, 0.75):
                    x = ((px + ox) / size - 0.5) / 0.30
                    y = (0.52 - (py + oy) / size) / 0.30
                    term = x * x + y * y - 1
                    if term * term * term - x * x * y * y * y <= 0:
                        coverage += 1
            row.extend(round(background[i] * (1 - coverage / 4) + foreground[i] * coverage / 4) for i in range(3))
        rows.append(row)
    raw = b"".join(rows)
    return (b"\x89PNG\r\n\x1a\n" +
            png_chunk(b"IHDR", struct.pack(">2I5B", size, size, 8, 2, 0, 0, 0)) +
            png_chunk(b"IDAT", zlib.compress(raw, 9)) +
            png_chunk(b"IEND", b""))


def main() -> None:
    sizes = {}
    for item in json.loads((IOS / "Contents.json").read_text())["images"]:
        size = round(float(item["size"].split("x")[0]) * int(item["scale"][0]))
        sizes[IOS / item["filename"]] = size
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        sizes[ANDROID / f"mipmap-{density}" / "ic_launcher.png"] = size
    cache = {}
    for file, size in sizes.items():
        if size not in cache:
            cache[size] = render(size)
        file.write_bytes(cache[size])
    print(f"Generated {len(sizes)} icon files.")


if __name__ == "__main__":
    main()
