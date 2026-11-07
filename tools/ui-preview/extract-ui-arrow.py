"""Extract the installed UI2 ArrowDown for the isolated preview (no pack loader).
Format verified against current TexturePackDevice JAR bytecode; no game files written.
"""
import io
import struct
import sys
from pathlib import Path
from PIL import Image
source, output = map(Path, sys.argv[1:])
stream = io.BytesIO(source.read_bytes())
def integer():
    return struct.unpack('<i', stream.read(4))[0]
def string():
    size = integer()
    if not 0 <= size <= 4096:
        raise ValueError('Invalid pack string')
    return stream.read(size).decode('utf-8')
if stream.read(4) != b'PZPK' or integer() != 1:
    raise ValueError('Unsupported UI2 pack format')
for _ in range(integer()):
    page, count, alpha = string(), integer(), integer()
    entries = [(string(), struct.unpack('<8i', stream.read(32))) for _ in range(count)]
    png = stream.read(integer())
    for name, (x, y, w, h, ox, oy, fw, fh) in entries:
        if name == 'ArrowDown':
            image = Image.open(io.BytesIO(png))
            canvas = Image.new('RGBA', (fw, fh))
            canvas.paste(image.crop((x, y, x+w, y+h)), (ox, oy))
            output.parent.mkdir(parents=True, exist_ok=True)
            canvas.save(output)
            print(output)
            sys.exit(0)
raise ValueError('ArrowDown not found in installed UI2 pack')
