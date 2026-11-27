"""Batch processor for AI-generated actor standees.

Takes raw solid-white-background PNGs from assets/actors/raw/,
removes the outer white background cleanly with flood-fill + soft alpha matting,
trims transparent margins, normalizes height while preserving aspect ratio,
and outputs ready-to-use transparent PNGs into assets/actors/.

Usage:
    python tools/process_sprites.py
"""

from pathlib import Path
import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "assets" / "actors" / "raw"
OUT_DIR = ROOT / "assets" / "actors"
PORTRAIT_DIR = OUT_DIR / "portraits"
TARGET_HEIGHT = 256
PORTRAIT_SIZE = 128


def remove_white_background(img_rgba: np.ndarray) -> np.ndarray:
    """Flood-fill outer near-white background and feather edge pixels cleanly."""
    h, w = img_rgba.shape[:2]
    rgb = img_rgba[:, :, :3].astype(np.float32)

    # Distance from pure white (255, 255, 255)
    diff = 255.0 - rgb
    dist = np.sqrt(np.mean(diff * diff, axis=2))  # 0 = pure white

    # Mark candidate background pixels (very bright and low saturation)
    max_c = np.max(rgb, axis=2)
    min_c = np.min(rgb, axis=2)
    sat = max_c - min_c
    bg_candidate = ((dist < 30.0) & (sat < 28.0)).astype(np.uint8)

    # Connected components: only remove regions touching the image border
    num_labels, labels = cv2.connectedComponents(bg_candidate, connectivity=4)
    border_labels = set()
    border_labels.update(np.unique(labels[0, :]).tolist())
    border_labels.update(np.unique(labels[h - 1, :]).tolist())
    border_labels.update(np.unique(labels[:, 0]).tolist())
    border_labels.update(np.unique(labels[:, w - 1]).tolist())
    border_labels.discard(0)

    is_bg = np.isin(labels, list(border_labels))

    # Also remove tiny enclosed pure-white holes (e.g. between arm and cloak)
    # that are very close to pure white
    inner_white = (dist < 14.0) & (sat < 14.0) & (~is_bg)
    is_bg = is_bg | inner_white

    alpha = np.where(is_bg, 0.0, 255.0).astype(np.float32)

    # Soften 1-2px halo around foreground border to kill white fringing
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    fg_mask = (~is_bg).astype(np.uint8)
    eroded = cv2.erode(fg_mask, kernel, iterations=1)
    border_ring = (fg_mask == 1) & (eroded == 0)

    # On the 1px border ring, fade alpha based on how white the pixel is
    ring_alpha = np.clip((dist - 12.0) / 38.0, 0.0, 1.0) * 255.0
    alpha = np.where(border_ring, np.minimum(alpha, ring_alpha), alpha)

    # De-contaminate white halo on semi-transparent border pixels
    out = img_rgba.copy()
    semi = border_ring & (alpha > 0) & (alpha < 250)
    if np.any(semi):
        a_norm = np.clip(alpha[semi] / 255.0, 0.15, 1.0)[:, None]
        recovered = (rgb[semi] - 255.0 * (1.0 - a_norm)) / a_norm
        out[semi, :3] = np.clip(recovered, 0, 255).astype(np.uint8)

    out[:, :, 3] = np.clip(alpha, 0, 255).astype(np.uint8)
    return out


def trim_and_resize(img_rgba: np.ndarray, target_height: int = TARGET_HEIGHT) -> Image.Image:
    alpha = img_rgba[:, :, 3]
    ys, xs = np.where(alpha > 20)
    if len(xs) == 0 or len(ys) == 0:
        return Image.fromarray(img_rgba, mode="RGBA")

    pad = 6
    y0 = max(0, int(ys.min()) - pad)
    y1 = min(img_rgba.shape[0], int(ys.max()) + pad + 1)
    x0 = max(0, int(xs.min()) - pad)
    x1 = min(img_rgba.shape[1], int(xs.max()) + pad + 1)

    cropped = Image.fromarray(img_rgba[y0:y1, x0:x1], mode="RGBA")
    cw, ch = cropped.size
    scale = target_height / float(ch)
    new_w = max(1, int(round(cw * scale)))
    return cropped.resize((new_w, target_height), Image.Resampling.LANCZOS)


def make_portrait(full_rgba: Image.Image, size: int = PORTRAIT_SIZE) -> Image.Image:
    """Crop upper torso/head from a transparent standee into a clean square portrait."""
    w, h = full_rgba.size
    crop_h = int(round(h * 0.52))
    crop_size = max(crop_h, int(round(w * 0.78)))
    crop_size = min(crop_size, max(w, h))
    cx = w // 2
    x0 = max(0, cx - crop_size // 2)
    y0 = 0
    x1 = min(w, x0 + crop_size)
    y1 = min(h, y0 + crop_size)
    sub = full_rgba.crop((x0, y0, x1, y1))

    # Place centered on a square canvas with dark slate twilight backdrop
    side = max(sub.width, sub.height)
    canvas = Image.new("RGBA", (side, side), (26, 30, 38, 255))
    ox = (side - sub.width) // 2
    oy = max(0, (side - sub.height) // 2)
    canvas.alpha_composite(sub, (ox, oy))
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def process_all(raw_dir: Path = RAW_DIR, out_dir: Path = OUT_DIR) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    portrait_dir = out_dir / "portraits"
    portrait_dir.mkdir(parents=True, exist_ok=True)
    if not raw_dir.exists():
        print(f"No raw directory found: {raw_dir}")
        return
    files = sorted(raw_dir.glob("*.png"))
    if not files:
        print(f"No PNG files found in {raw_dir}")
        return
    for src in files:
        im = Image.open(src).convert("RGBA")
        arr = np.array(im)
        cleaned = remove_white_background(arr)
        final_img = trim_and_resize(cleaned, TARGET_HEIGHT)
        dst = out_dir / src.name
        final_img.save(dst, "PNG", optimize=True)
        print(f"[OK] {src.name} -> {dst} ({final_img.size[0]}x{final_img.size[1]})")
        if not src.stem.endswith("_back"):
            portrait = make_portrait(final_img, PORTRAIT_SIZE)
            p_dst = portrait_dir / src.name
            portrait.save(p_dst, "PNG", optimize=True)
            print(f"  [PORTRAIT] -> {p_dst} ({portrait.size[0]}x{portrait.size[1]})")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=RAW_DIR)
    parser.add_argument("--output", type=Path, default=OUT_DIR)
    args = parser.parse_args()
    process_all(args.input, args.output)
