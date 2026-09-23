"""Package downloaded CC0 GLBs as glTF with shared, byte-identical textures.

Usage: python scripts/prepare_nature_assets.py INPUT_DIRECTORY OUTPUT_DIRECTORY
No geometry or texture pixels are changed. Source hashes live in manifest.json.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys

source, output = map(Path, sys.argv[1:3])
output.mkdir(parents=True, exist_ok=True)
(output / 'textures').mkdir(exist_ok=True)
for path in sorted(source.glob('*.glb')):
    data = path.read_bytes()
    json_size = struct.unpack_from('<I', data, 12)[0]
    document = json.loads(data[20:20+json_size])
    binary = data[28+json_size:]
    image_views = set()
    for image in document.get('images', []):
        view_id = image.pop('bufferView')
        view = document['bufferViews'][view_id]
        offset = view.get('byteOffset', 0)
        content = binary[offset:offset+view['byteLength']]
        suffix = '.png' if image.pop('mimeType') == 'image/png' else '.jpg'
        filename = hashlib.sha256(content).hexdigest()[:16] + suffix
        (output / 'textures' / filename).write_bytes(content)
        image['uri'] = 'textures/' + filename
        image_views.add(view_id)
    packed = bytearray()
    views, remap = [], {}
    for index, original in enumerate(document['bufferViews']):
        if index in image_views:
            continue
        packed.extend(b'\0' * (-len(packed) % 4))
        view = dict(original)
        offset = original.get('byteOffset', 0)
        view['byteOffset'] = len(packed)
        packed.extend(binary[offset:offset+original['byteLength']])
        remap[index] = len(views)
        views.append(view)
    for accessor in document['accessors']:
        assert 'sparse' not in accessor
        if 'bufferView' in accessor:
            accessor['bufferView'] = remap[accessor['bufferView']]
    document['bufferViews'] = views
    document['buffers'] = [{'uri':path.stem+'.bin', 'byteLength':len(packed)}]
    (output / (path.stem+'.bin')).write_bytes(packed)
    (output / (path.stem+'.gltf')).write_text(json.dumps(document,separators=(',',':')),encoding='utf-8')
    print(path.stem, len(packed), 'geometry bytes')
