from pathlib import Path
from PIL import Image, ImageDraw

image = Image.new("RGBA",(256,256),(0,0,0,0))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((4,4,252,252),48,fill="#14373b")
draw.rounded_rectangle((39,54,217,177),23,fill="#62e1b9")
draw.polygon(((67,157),(116,157),(67,205)),fill="#62e1b9")
draw.rounded_rectangle((65,86,190,101),6,fill="#153639")
draw.rounded_rectangle((65,119,151,134),6,fill="#153639")
image.save(Path(__file__).resolve().parents[1]/"desktop/GameLingo.ico", sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])

