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
        action = rebake(rig, next(o for o in imported if o.type == "ARMATURE"), clip)
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


def rebake(rig, source, clip):
    """The clip on the model's own skeleton, frame by frame.

    Each animation file rests its skeleton in the clip's first frame, not in the
    model's bind pose, and Blender keys bones relative to their rest; played on
    the model as it is, every joint turns from the wrong rest. Each bone is
    posed where the clip puts it in armature space and keyed against the
    model's rest instead.
    """
    scene = bpy.context.scene
    if max(abs(a - b) for row, other in zip(source.matrix_world, rig.matrix_world) for a, b in zip(row, other)) > 1e-5:
        raise SystemExit(f"{clip} imports its skeleton elsewhere than the model's")
    taken = source.animation_data.action
    start, end = (int(round(f)) for f in taken.frame_range)
    frames = {}
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        frames[frame] = {b.name: b.matrix.copy() for b in source.pose.bones}
    bpy.data.actions.remove(taken)
    rig.animation_data.action = bpy.data.actions.new(clip)
    rig.animation_data.action.use_fake_user = True
    for frame, poses in frames.items():
        for bone in rig.pose.bones:
            rest = bone.bone.matrix_local
            if bone.parent:
                rest = bone.parent.bone.matrix_local.inverted() @ rest
                basis = rest.inverted() @ poses[bone.parent.name].inverted() @ poses[bone.name]
            else:
                basis = rest.inverted() @ poses[bone.name]
            location, rotation, scale = basis.decompose()
            bone.rotation_mode = "QUATERNION"
            bone.location, bone.rotation_quaternion, bone.scale = location, rotation, scale
            for path in ("location", "rotation_quaternion", "scale"):
                bone.keyframe_insert(path, frame=frame)
    # Evaluated on the model, every bone must land where the clip put it.
    worst = 0.0
    for frame in (start, (start + end) // 2, end):
        scene.frame_set(frame)
        for bone in rig.pose.bones:
            wanted = frames[frame][bone.name]
            worst = max(worst, (bone.matrix.translation - wanted.translation).length / 100,
                        max(abs(a - b) for row, other in zip(bone.matrix.to_3x3(), wanted.to_3x3()) for a, b in zip(row, other)))
    if worst > 1e-3:
        raise SystemExit(f"{clip} rebakes {worst:.4f} off its source")
    action = rig.animation_data.action
    rig.animation_data.action = None
    return action


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
