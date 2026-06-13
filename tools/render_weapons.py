"""
render_weapons.py — Render weapon previews in Blender itself.

For each .glb in assets/models/weapons/, imports it into a fresh Blender
scene, frames it with a camera, lights it with 3-point lighting, and renders
a PNG to /tmp/render_<id>.png. This is the visual check that confirms the
weapon actually looks like what we expect (vs the abstract low-poly stubs).

Run:
  "/mnt/c/Program Files/Blender Foundation/Blender 4.0/blender.exe" \
    --background --python tools/render_weapons.py
"""
import os
import sys
import math
import bpy
from mathutils import Vector

PROJECT_ROOT = r"C:\Users\Rog\Workspace\01_PROYECTOS\mcp-souls-game"
if PROJECT_ROOT.startswith("C:"):
    OUT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "weapons")
else:
    OUT_DIR = PROJECT_ROOT
RENDER_DIR = r"C:\Users\Rog\blender_renders" if PROJECT_ROOT.startswith("C:") else "/tmp/blender_renders"
os.makedirs(RENDER_DIR, exist_ok=True)

RENDER_RES = (640, 640)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)
    for block in list(bpy.data.images):
        if block.users == 0:
            bpy.data.images.remove(block)
    for block in list(bpy.data.cameras):
        if block.users == 0:
            bpy.data.cameras.remove(block)
    for block in list(bpy.data.lights):
        if block.users == 0:
            bpy.data.lights.remove(block)


def setup_render_engine():
    """Use EEVEE for fast stylized renders, with filmic tone mapping and good samples."""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.eevee.taa_render_samples = 32
    scene.eevee.use_bloom = False
    scene.eevee.use_gtao = True
    # Color management
    scene.view_settings.view_transform = 'Standard'  # no filmic
    scene.view_settings.look = 'None'
    # Use dark background
    scene.world.use_nodes = True
    wn = scene.world.node_tree.nodes
    bg_node = wn.get("Background")
    if bg_node is None:
        bg_node = wn.new("Background")
    bg_node.inputs["Color"].default_value = (0.08, 0.10, 0.13, 1.0)
    bg_node.inputs["Strength"].default_value = 0.4


def setup_camera_and_lights(model_dim: float, view: str = "front"):
    """Frame the model with a 3-point lighting setup. model_dim is a rough
    'radius' of the weapon — camera distance and light placement scale with it.
    view: 'front' (3/4 from upper-right, default), 'side' (perpendicular to Z,
    looking from +X — best for weapons with curve in the YZ plane like scimitar),
    'top' (perpendicular to X, looking from +Y — best for bow curve in XZ)."""
    # Camera
    cam_data = bpy.data.cameras.new("StudioCam")
    cam_data.lens = 70  # longer lens for less perspective distortion
    cam_data.sensor_width = 36
    cam_data.clip_end = 100.0
    cam_obj = bpy.data.objects.new("StudioCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    # Frame the weapon so it fills ~70% of the frame.
    dist = max(model_dim * 1.6, 1.0)
    if view == "side":
        # Looking from +X (lateral profile of the weapon)
        cam_obj.location = Vector((dist, 0, model_dim * 0.5))
    elif view == "top":
        # Looking from +Y (top profile, good for bows with XZ curve)
        cam_obj.location = Vector((0, dist, model_dim * 0.5))
    else:
        # 3/4 view from upper-right-front
        cam_obj.location = Vector((model_dim * 0.5, -model_dim * 0.4, dist))
    # Look at the model center
    target = Vector((0, 0, model_dim * 0.5))
    direction = (target - cam_obj.location).normalized()
    rot_quat = direction.to_track_quat('-Z', 'Y')
    cam_obj.rotation_euler = rot_quat.to_euler()

    # Key light — main light from upper-front-right
    key_data = bpy.data.lights.new("Key", 'AREA')
    key_data.energy = 60  # EEVEE-friendly intensity (much lower than Cycles)
    key_data.size = model_dim * 0.6
    key_data.color = (1.0, 0.96, 0.92)
    key_obj = bpy.data.objects.new("Key", key_data)
    bpy.context.collection.objects.link(key_obj)
    key_obj.location = Vector((model_dim * 1.2, -model_dim * 1.0, model_dim * 1.5))
    key_obj.rotation_euler = (math.radians(45), 0, math.radians(-30))

    # Fill light — soft from opposite side
    fill_data = bpy.data.lights.new("Fill", 'AREA')
    fill_data.energy = 25
    fill_data.size = model_dim * 0.9
    fill_data.color = (0.85, 0.92, 1.0)
    fill_obj = bpy.data.objects.new("Fill", fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = Vector((-model_dim * 1.2, model_dim * 0.8, model_dim * 0.6))
    fill_obj.rotation_euler = (math.radians(45), 0, math.radians(150))

    # Rim light — from behind to separate from background
    rim_data = bpy.data.lights.new("Rim", 'AREA')
    rim_data.energy = 35
    rim_data.size = model_dim * 0.5
    rim_data.color = (1.0, 0.95, 0.85)
    rim_obj = bpy.data.objects.new("Rim", rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = Vector((0, model_dim * 1.2, model_dim * 0.5))
    rim_obj.rotation_euler = (math.radians(-30), 0, 0)

    return cam_obj, key_obj


def render_weapon(glb_path: str, out_path: str, model_dim: float = 0.5, view: str = "front"):
    clear_scene()
    setup_render_engine()

    # Import the .glb
    bpy.ops.import_scene.gltf(filepath=glb_path)
    imported = list(bpy.context.selected_objects)
    if not imported:
        print(f"  [FAIL] no objects imported from {glb_path}")
        return False
    # Join all into one object (for cleaner framing)
    bpy.ops.object.select_all(action='DESELECT')
    for o in imported:
        o.select_set(True)
    bpy.context.view_layer.objects.active = imported[0]
    bpy.ops.object.join()
    model = bpy.context.active_object
    model.name = "Weapon"
    # The .glb was exported with export_yup=True (Blender Z-up scene → .glb
    # Y-up). When Blender RE-IMPORTS that .glb, it shows the model with
    # Y as the "up" axis and the handle along Y (horizontal). The blade,
    # originally along +Y in the source Z-up scene, now points along +Z
    # in the .glb (vertical, up). So the model is ALREADY in a "blade up"
    # orientation after import — we just need to center it on the pommel.
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    # Compute bounding-box to frame the camera
    bbox = [model.matrix_world @ Vector(c) for c in model.bound_box]
    bb_min = Vector((min(c.x for c in bbox), min(c.y for c in bbox), min(c.z for c in bbox)))
    bb_max = Vector((max(c.x for c in bbox), max(c.y for c in bbox), max(c.z for c in bbox)))
    extent = max(bb_max.x - bb_min.x, bb_max.y - bb_min.y, bb_max.z - bb_min.z)
    model_dim_actual = max(extent, 0.1)
    # Center the model: shift so the model is centered in the frame.
    # The pommel will end up at the bottom, the blade tip at the top.
    center_x = (bb_min.x + bb_max.x) / 2.0
    center_y = (bb_min.y + bb_max.y) / 2.0
    z_offset = -bb_min.z
    model.location = (-center_x, -center_y, z_offset)

    setup_camera_and_lights(model_dim_actual, view)

    # Render
    scene = bpy.context.scene
    scene.render.resolution_x = RENDER_RES[0]
    scene.render.resolution_y = RENDER_RES[1]
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    return True


def main():
    weapons = [
        ("short_sword",     "front"),
        ("long_sword",      "front"),
        ("great_sword",     "front"),
        ("dagger",          "front"),
        ("scimitar",        "side"),  # curve in YZ plane → side view
        ("war_axe",         "side"),  # head on +Y → side view shows silhouette
        ("mace",            "front"),
        ("spear",           "front"),
        ("great_scythe",    "side"),  # curve in YZ plane → side view
        ("long_bow",        "top"),   # curve in XZ plane → top view
        ("arcane_staff",    "front"),
        ("cursed_blade",    "front"),
    ]
    print(f"[render_weapons] Output: {RENDER_DIR}")
    for wid, view in weapons:
        glb_path = os.path.join(OUT_DIR, f"wpn_{wid}.glb")
        out_path = os.path.join(RENDER_DIR, f"render_{wid}.png")
        if not os.path.exists(glb_path):
            print(f"  [SKIP] {wid}: no .glb at {glb_path}")
            continue
        ok = render_weapon(glb_path, out_path, view=view)
        if ok:
            sz = os.path.getsize(out_path)
            print(f"  ✓ {wid} ({view}): {sz:,} bytes -> {out_path}")


if __name__ == "__main__":
    main()
