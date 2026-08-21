#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import struct
import subprocess
import sys
import tempfile

from ds_store import DSStore


BACKGROUND_SIZE = (720, 440)
LABEL_BACKPLATE_CORES = {
    "Gaugelet": (108, 311, 94, 19),
    "Applications": (516, 311, 98, 19),
}
MINIMUM_LABEL_BACKPLATE_LUMINANCE = 0.68


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def srgb_channel_to_linear(value: int) -> float:
    channel = value / 255.0
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def relative_luminance(red: int, green: int, blue: int) -> float:
    return (
        0.2126 * srgb_channel_to_linear(red)
        + 0.7152 * srgb_channel_to_linear(green)
        + 0.0722 * srgb_channel_to_linear(blue)
    )


def read_bmp(path: pathlib.Path) -> tuple[int, int, int, bytes, int, int, bool]:
    data = path.read_bytes()
    if len(data) < 54 or data[:2] != b"BM":
        fail("sips did not produce a valid BMP for background contrast verification")

    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    dib_size = struct.unpack_from("<I", data, 14)[0]
    width = struct.unpack_from("<i", data, 18)[0]
    signed_height = struct.unpack_from("<i", data, 22)[0]
    planes = struct.unpack_from("<H", data, 26)[0]
    bits_per_pixel = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]

    if dib_size < 40 or width <= 0 or signed_height == 0 or planes != 1:
        fail("sips produced an unsupported BMP header")
    if bits_per_pixel not in (24, 32) or compression != 0:
        fail(
            "sips produced an unsupported BMP pixel format "
            f"({bits_per_pixel}-bit, compression {compression})"
        )

    height = abs(signed_height)
    row_stride = ((width * bits_per_pixel + 31) // 32) * 4
    required_size = pixel_offset + row_stride * height
    if len(data) < required_size:
        fail("sips produced a truncated BMP")

    return (
        width,
        height,
        bits_per_pixel,
        data,
        pixel_offset,
        row_stride,
        signed_height < 0,
    )


def verify_label_backplate_contrast(background: pathlib.Path) -> dict[str, float]:
    with tempfile.TemporaryDirectory(prefix="gaugelet-dmg-layout-") as temporary_dir:
        minimum_luminance: dict[str, float] = {}
        for scale in (1, 2):
            representation_path = pathlib.Path(temporary_dir) / f"background-{scale}x.tiff"
            extraction = subprocess.run(
                [
                    "/usr/bin/tiffutil",
                    "-extract",
                    str(scale - 1),
                    str(background),
                    "-out",
                    str(representation_path),
                ],
                capture_output=True,
                text=True,
            )
            if extraction.returncode != 0:
                fail(
                    f"could not extract DMG background {scale}x representation: "
                    f"{extraction.stderr.strip()}"
                )

            bmp_path = pathlib.Path(temporary_dir) / f"background-{scale}x.bmp"
            conversion = subprocess.run(
                [
                    "/usr/bin/sips",
                    "-s",
                    "format",
                    "bmp",
                    str(representation_path),
                    "--out",
                    str(bmp_path),
                ],
                capture_output=True,
                text=True,
            )
            if conversion.returncode != 0:
                fail(
                    f"could not rasterize DMG background {scale}x representation: "
                    f"{conversion.stderr.strip()}"
                )

            (
                width,
                height,
                bits_per_pixel,
                data,
                pixel_offset,
                row_stride,
                top_down,
            ) = read_bmp(bmp_path)
            expected_size = tuple(dimension * scale for dimension in BACKGROUND_SIZE)
            if (width, height) != expected_size:
                fail(
                    f"rasterized DMG background {scale}x representation is "
                    f"{width}x{height}, expected {expected_size[0]}x{expected_size[1]}"
                )

            bytes_per_pixel = bits_per_pixel // 8
            for label, zone in LABEL_BACKPLATE_CORES.items():
                left, top, zone_width, zone_height = (
                    coordinate * scale for coordinate in zone
                )
                luminance_values = []
                for y in range(top, top + zone_height):
                    stored_y = y if top_down else height - 1 - y
                    for x in range(left, left + zone_width):
                        offset = pixel_offset + stored_y * row_stride + x * bytes_per_pixel
                        blue, green, red = data[offset : offset + 3]
                        luminance_values.append(relative_luminance(red, green, blue))

                darkest_pixel = min(luminance_values)
                result_label = f"{label}@{scale}x"
                minimum_luminance[result_label] = darkest_pixel
                if darkest_pixel < MINIMUM_LABEL_BACKPLATE_LUMINANCE:
                    fail(
                        f"{result_label} label backplate is too dark "
                        f"(minimum relative luminance {darkest_pixel:.3f}, "
                        f"required {MINIMUM_LABEL_BACKPLATE_LUMINANCE:.2f})"
                    )

        return minimum_luminance


if len(sys.argv) != 2:
    fail("usage: verify-dmg-layout.py /path/to/mounted-volume")

mount_root = pathlib.Path(sys.argv[1]).resolve()
ds_store_path = mount_root / ".DS_Store"
background_path = mount_root / ".background.tiff"

if not ds_store_path.is_file():
    fail("mounted DMG is missing .DS_Store")
if not background_path.is_file():
    fail("mounted DMG is missing .background.tiff")

visible_items = sorted(path.name for path in mount_root.iterdir() if not path.name.startswith("."))
if visible_items != ["Applications", "Gaugelet.app"]:
    fail(f"unexpected visible DMG items: {visible_items}")

with DSStore.open(str(ds_store_path), "r") as store:
    app_location = store["Gaugelet.app"]["Iloc"]
    applications_location = store["Applications"]["Iloc"]
    window_settings = store["."]["bwsp"]
    icon_view_settings = store["."]["icvp"]

if app_location != (155, 239):
    fail(f"Gaugelet.app icon is at {app_location}, expected (155, 239)")
if applications_location != (565, 239):
    fail(f"Applications icon is at {applications_location}, expected (565, 239)")

expected_bounds = "{{200, 200}, {720, 440}}"
if window_settings.get("WindowBounds") != expected_bounds:
    fail(
        "Finder window bounds are "
        f"{window_settings.get('WindowBounds')!r}, expected {expected_bounds!r}"
    )

if float(icon_view_settings.get("iconSize", 0)) != 128.0:
    fail(f"Finder icon size is {icon_view_settings.get('iconSize')}, expected 128")
if icon_view_settings.get("labelOnBottom") is not True:
    fail("Finder item labels are not positioned below the icons")
if float(icon_view_settings.get("textSize", 0)) != 14.0:
    fail(f"Finder label text size is {icon_view_settings.get('textSize')}, expected 14")
if icon_view_settings.get("backgroundType") != 2:
    fail("Finder is not configured to use the picture background")
if icon_view_settings.get("arrangeBy") != "none":
    fail(f"Finder arrangeBy is {icon_view_settings.get('arrangeBy')!r}, expected 'none'")

tiff_info = subprocess.run(
    ["/usr/bin/tiffutil", "-info", str(background_path)],
    check=True,
    capture_output=True,
    text=True,
).stdout
if (
    "Image Width: 720 Image Length: 440" not in tiff_info
    or "Image Width: 1440 Image Length: 880" not in tiff_info
    or "Resolution: 72, 72" not in tiff_info
    or "Resolution: 144, 144" not in tiff_info
):
    fail("DMG background does not contain the expected 1x and 2x TIFF representations")

minimum_luminance = verify_label_backplate_contrast(background_path)
contrast_summary = ", ".join(
    f"{label}={value:.3f}" for label, value in minimum_luminance.items()
)
print(f"DMG Finder layout and label contrast verified ({contrast_summary})")
