"""Render the app's geometric camera/lock mark into Xcode's icon sizes.

Optional development tool: python -m pip install Pillow; python scripts/generate_icon.py
No image dependency is needed for the iOS build itself.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
icon_root = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
image = Image.new("RGB", (1024, 1024), (225, 227, 232))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((274, 254, 566, 400), radius=42, fill=(58, 61, 68))
draw.rounded_rectangle((158, 342, 866, 758), radius=92, fill=(58, 61, 68))
draw.ellipse((324, 358, 700, 734), fill=(17, 20, 28))
draw.ellipse((373, 407, 651, 685), fill=(80, 89, 112))
draw.ellipse((407, 441, 617, 651), fill=(23, 28, 43))
draw.ellipse((437, 463, 492, 518), fill=(143, 165, 204))
draw.rounded_rectangle((740, 263, 892, 418), radius=36, fill=(255, 204, 0))
draw.arc((779, 291, 853, 374), 180, 360, fill=(40, 40, 40), width=16)
draw.rounded_rectangle((771, 328, 861, 391), radius=12, fill=(40, 40, 40))
draw.ellipse((809, 349, 823, 363), fill=(255, 204, 0))

with (icon_root / "Contents.json").open(encoding="utf-8") as handle:
    icons = json.load(handle)["images"]
for icon in icons:
    points = float(icon["size"].split("x")[0])
    pixels = round(points * float(icon["scale"].removesuffix("x")))
    image.resize((pixels, pixels), Image.Resampling.LANCZOS).save(icon_root / icon["filename"])
print(f"Rendered {len(icons)} app icon sizes.")
