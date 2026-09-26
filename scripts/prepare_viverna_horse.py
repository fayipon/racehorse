# Builds the race horse from the licensed Viverna "Horses (Stallions)" pack (Fab).
# The pack's zips stay in vendor/viverna and the web-sized model and textures this
# writes to godot/assets/viverna; neither is committed, as the licence forbids
# redistributing the asset itself. Only the exported game carries it.
#
#   blender -b --factory-startup --python scripts/prepare_viverna_horse.py
import os
import shutil
import tempfile
import zipfile

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PACK = os.path.join(ROOT, "vendor", "viverna")
OUT = os.path.join(ROOT, "godot", "assets", "viverna")
# The pack's clips under the names the race adapter plays.
CLIPS = {"Idle_1": "Idle", "Idle_2": "Idle_2", "Idle_4": "Idle_Headlow", "Eat": "Eating", "Walk": "Walk", "Gallop": "Gallop"}
# LOD1 races on desktops, LOD2 on phones; LOD3 only casts the shadows.
LODS = {"Stallion_LOD1": "Body", "Stallion_LOD2": "BodyLow", "Stallion_LOD3": "BodyShadow"}
# The coats the stable is dressed from; the rest of the field is tinted from these.
COATS = ["Black", "Creame", "Gray", "GrayRose", "White"]
SIZE = 1024


def unpack(work):
    wanted = ["FBX/Stallion.fbx"] + [f"Animations/Stallion_{clip}.fbx" for clip in CLIPS]
    wanted += [f"Tex/TX_Horse.{coat}_Albedo.png" for coat in COATS]
    wanted += ["Tex/TX_Horse_Normals.png", "Tex/TX_Horse_MADS.tga", "Tex/TX_HorseHair_Albedo.tga", "Tex/TX_HorseHair_Normals.png"]
    found = {}
    for name in os.listdir(PACK):
        if not name.endswith(".zip"):
            continue
        with zipfile.ZipFile(os.path.join(PACK, name)) as pack:
            for entry in pack.namelist():
                for want in wanted:
                    if entry.replace("\\", "/").endswith(want) and want not in found:
                        found[want] = pack.extract(entry, work)
    missing = [w for w in wanted if w not in found]
    if missing:
        raise SystemExit(f"Missing from {PACK}: {missing}")
    return found


def build_model(files):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.fbx(filepath=files["FBX/Stallion.fbx"])
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    rig.name = "Stallion"
    for ob in list(bpy.data.objects):
        if ob.type == "MESH":
            if ob.name in LODS:
                ob.name = ob.data.name = LODS[ob.name]
            else:
                bpy.data.objects.remove(ob, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    rig.animation_data_create()
    for source, clip in CLIPS.items():
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=files[f"Animations/Stallion_{source}.fbx"])
        imported = [o for o in bpy.data.objects if o not in before]
        action = next(o for o in imported if o.type == "ARMATURE").animation_data.action
        action.name = clip
        action.use_fake_user = True
        for ob in imported:
            bpy.data.objects.remove(ob, do_unlink=True)
        track = rig.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, int(action.frame_range[0]), action)
        if hasattr(strip, "action_slot") and action.slots:
            strip.action_slot = action.slots[0]
        track.mute = True
    rig.animation_data.action = None
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for ob in rig.children:
        ob.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, "stallion.glb"),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_skins=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_yup=True,
    )


def load(path, data=False):
    image = bpy.data.images.load(path)
    if data:
        image.colorspace_settings.name = "Non-Color"
    image.scale(SIZE, SIZE)
    return np.array(image.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)


def save(pixels, name, alpha=False):
    image = bpy.data.images.new(name, SIZE, SIZE, alpha=alpha)
    image.colorspace_settings.name = "Non-Color"
    image.pixels = pixels.ravel()
    image.filepath_raw = os.path.join(OUT, "textures", name + ".png")
    image.file_format = "PNG"
    image.save()


# Godot imports them as lossy WebP with mipmaps, as the course's plant textures.
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=1
compress/lossy_quality={quality}
compress/normal_map={normal}
mipmaps/generate=true
detect_3d/compress_to=0
"""


def build_textures(files):
    os.makedirs(os.path.join(OUT, "textures"), exist_ok=True)
    maps = {}
    for coat in COATS:
        maps[f"coat_{coat.lower()}"] = (load(files[f"Tex/TX_Horse.{coat}_Albedo.png"]), False, False)
    maps["body_normal"] = (load(files["Tex/TX_Horse_Normals.png"], True), False, True)
    # MADS packs metallic, ambient occlusion, a detail mask and gloss; Godot
    # reads occlusion, roughness and metallic from red, green and blue.
    mads = load(files["Tex/TX_Horse_MADS.tga"], True)
    orm = np.stack([mads[..., 1], 1.0 - mads[..., 3], mads[..., 0], np.ones_like(mads[..., 0])], axis=-1)
    maps["body_orm"] = (orm, False, False)
    maps["hair_albedo"] = (load(files["Tex/TX_HorseHair_Albedo.tga"]), True, False)
    maps["hair_normal"] = (load(files["Tex/TX_HorseHair_Normals.png"], True), False, True)
    for name, (pixels, alpha, normal) in maps.items():
        save(pixels, name, alpha)
        with open(os.path.join(OUT, "textures", name + ".png.import"), "w", encoding="utf-8") as f:
            f.write(IMPORT.format(quality=.9 if normal else .85, normal=1 if normal else 0))


def main():
    work = tempfile.mkdtemp()
    try:
        files = unpack(work)
        if os.path.isdir(OUT):
            shutil.rmtree(OUT)
        build_model(files)
        build_textures(files)
        print("Viverna horse written to", OUT)
    finally:
        shutil.rmtree(work, ignore_errors=True)


main()
