"""
gen_weapons.py — Low-poly stylized weapon mesh generator for MCP Souls Game.

Generates 12 .glb files in assets/models/weapons/. Each weapon has its parts
laid out along the Z axis (handle at Z=0, blade tip at Z=positive), so that
reimporting the .glb in any Y-up scene shows the weapon VERTICAL with the
blade pointing up.

Run from WSL (using Windows Blender.exe):
  "/mnt/c/Program Files/Blender Foundation/Blender 4.0/blender.exe" \
    --background --python tools/gen_weapons.py
"""

import os
import math
import bpy

# -------------------------------------------------------------------- paths
PROJECT_ROOT = r"C:\Users\Rog\Workspace\01_PROYECTOS\mcp-souls-game"
if PROJECT_ROOT.startswith("C:"):
    OUT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "weapons")
else:
    OUT_DIR = PROJECT_ROOT
os.makedirs(OUT_DIR, exist_ok=True)


# -------------------------------------------------------------------- helpers
def clear_scene():
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)


def make_mat(name: str, color: tuple, metallic: float = 0.8, roughness: float = 0.4) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


# Material library
M_METAL = make_mat("Wpn_Metal",  (0.85, 0.85, 0.90, 1.0), 0.9, 0.25)
M_DARK_METAL = make_mat("Wpn_DarkMetal", (0.30, 0.30, 0.35, 1.0), 0.9, 0.30)
M_RUSTY_METAL = make_mat("Wpn_RustyMetal", (0.55, 0.30, 0.20, 1.0), 0.7, 0.50)
M_WOOD = make_mat("Wpn_Wood",  (0.45, 0.28, 0.15, 1.0), 0.0, 0.7)
M_LIGHT_WOOD = make_mat("Wpn_LightWood", (0.65, 0.45, 0.25, 1.0), 0.0, 0.7)
M_DARK_WOOD = make_mat("Wpn_DarkWood", (0.30, 0.18, 0.10, 1.0), 0.0, 0.7)
M_LEATHER = make_mat("Wpn_Leather", (0.35, 0.20, 0.10, 1.0), 0.0, 0.85)
M_DARK_LEATHER = make_mat("Wpn_DarkLeather", (0.20, 0.12, 0.08, 1.0), 0.0, 0.85)
M_GOLD = make_mat("Wpn_Gold",  (0.95, 0.78, 0.30, 1.0), 0.9, 0.20)
M_SILVER = make_mat("Wpn_Silver", (0.95, 0.95, 0.98, 1.0), 0.95, 0.15)
M_BRONZE = make_mat("Wpn_Bronze", (0.75, 0.50, 0.25, 1.0), 0.85, 0.30)
M_CRYSTAL = make_mat("Wpn_Crystal", (0.55, 0.40, 0.90, 1.0), 0.5, 0.10)
M_BONE = make_mat("Wpn_Bone", (0.85, 0.78, 0.60, 1.0), 0.1, 0.6)
M_RED = make_mat("Wpn_Red", (0.80, 0.20, 0.20, 1.0), 0.3, 0.50)


# -------------------------------------------------------------------- primitives
def add_box(name: str, size: tuple, loc=(0, 0, 0), rot=(0, 0, 0), mat=None) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def add_cylinder(name: str, radius: float, depth: float, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, segments: int = 8) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=loc, rotation=rot, vertices=segments)
    obj = bpy.context.active_object
    obj.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def add_cone(name: str, radius: float, depth: float, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, segments: int = 4) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=0.0, depth=depth, location=loc, rotation=rot, vertices=segments)
    obj = bpy.context.active_object
    obj.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def add_sphere(name: str, radius: float, loc=(0, 0, 0), mat=None) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, location=loc, subdivisions=1)
    obj = bpy.context.active_object
    obj.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def add_torus(name: str, major: float, minor: float, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, major_segments: int = 8, minor_segments: int = 4) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=major_segments, minor_segments=minor_segments,
        location=loc, rotation=rot
    )
    obj = bpy.context.active_object
    obj.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def join_objects(objects: list, name: str) -> bpy.types.Object:
    # Convert any CURVE/EMPTY objects to MESH so the join produces a single
    # mesh. Without this, the join fails on objects with curve data.
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
        if o.type == 'CURVE':
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target='MESH')
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


# -------------------------------------------------------------------- weapon builders
# CONVENTION: +Z is the up axis (handle direction). Pommel at Z=0, blade tip
# at Z=positive. All parts are stacked ALONG Z, so the weapon stands vertical
# (handle down, blade up) in any Y-up scene that reimports the .glb.
# The +Y axis is the "forward" of the blade (no rotation needed in normal
# usage; the blade's "back" face is -Y, the "front" face is +Y).


def build_short_sword() -> bpy.types.Object:
    """1h straight sword. Total height ~0.9m, blade 0.55m. Recognizable."""
    parts = []
    # Pommel — visible round knob at the bottom
    parts.append(add_sphere("Pommel", 0.045, loc=(0, 0, 0.045), mat=M_GOLD))
    # Handle — narrow wood grip
    parts.append(add_cylinder("Handle", 0.025, 0.18, loc=(0, 0, 0.16), mat=M_DARK_WOOD))
    # Guard — wide cross-piece, distinctive horizontal bar
    parts.append(add_box("Guard", (0.22, 0.05, 0.05), loc=(0, 0, 0.28), mat=M_DARK_METAL))
    # Blade — TALL and clearly along Z (same axis as handle)
    parts.append(add_box("BladeBase", (0.05, 0.015, 0.55), loc=(0, 0, 0.58), mat=M_METAL))
    # Tip — cone along Z (the cone's default axis is Z, so no rotation)
    parts.append(add_cone("BladeTip", 0.030, 0.10, loc=(0, 0, 0.91), mat=M_METAL, segments=4))
    return join_objects(parts, "Weapon_ShortSword")


def build_long_sword() -> bpy.types.Object:
    """1h sword slightly longer and slimmer than short_sword. ~1.0m total."""
    parts = []
    parts.append(add_sphere("Pommel", 0.05, loc=(0, 0, 0.05), mat=M_SILVER))
    parts.append(add_cylinder("Handle", 0.025, 0.20, loc=(0, 0, 0.18), mat=M_LEATHER))
    # Slightly curved guard (slim quillons)
    parts.append(add_box("GuardL", (0.02, 0.04, 0.04), loc=(-0.10, 0, 0.30), mat=M_DARK_METAL))
    parts.append(add_box("GuardR", (0.02, 0.04, 0.04), loc=( 0.10, 0, 0.30), mat=M_DARK_METAL))
    parts.append(add_box("GuardC", (0.22, 0.05, 0.04), loc=(0, 0, 0.30), mat=M_DARK_METAL))
    # Longer blade
    parts.append(add_box("BladeBase", (0.04, 0.012, 0.70), loc=(0, 0, 0.67), mat=M_METAL))
    # Fuller (groove line) — visible darker stripe
    parts.append(add_box("Fuller", (0.018, 0.003, 0.55), loc=(0, 0, 0.68), mat=M_DARK_METAL))
    # Tip
    parts.append(add_cone("BladeTip", 0.025, 0.12, loc=(0, 0, 1.08), mat=M_METAL, segments=4))
    return join_objects(parts, "Weapon_LongSword")


def build_great_sword() -> bpy.types.Object:
    """2h greatsword. Long handle, big guard, very long blade. ~1.5m total."""
    parts = []
    parts.append(add_sphere("Pommel", 0.07, loc=(0, 0, 0.07), mat=M_DARK_METAL))
    # Long 2h handle
    parts.append(add_cylinder("Handle", 0.030, 0.40, loc=(0, 0, 0.27), mat=M_LEATHER))
    # Wide cross-guard
    parts.append(add_box("Guard", (0.36, 0.05, 0.05), loc=(0, 0, 0.50), mat=M_DARK_METAL))
    # Decorative guard tips (chapes on the ends of the quillons)
    parts.append(add_box("GuardTipL", (0.05, 0.05, 0.06), loc=(-0.18, 0, 0.50), mat=M_GOLD))
    parts.append(add_box("GuardTipR", (0.05, 0.05, 0.06), loc=( 0.18, 0, 0.50), mat=M_GOLD))
    # Long blade
    parts.append(add_box("BladeBase", (0.06, 0.018, 1.10), loc=(0, 0, 1.10), mat=M_METAL))
    # Tip
    parts.append(add_cone("BladeTip", 0.04, 0.16, loc=(0, 0, 1.72), mat=M_METAL, segments=4))
    return join_objects(parts, "Weapon_GreatSword")


def build_dagger() -> bpy.types.Object:
    """1h dagger. Very short handle, small but wide blade. Easy to recognize."""
    parts = []
    # Round pommel (visible knob)
    parts.append(add_sphere("Pommel", 0.040, loc=(0, 0, 0.040), mat=M_DARK_METAL))
    # Short handle
    parts.append(add_cylinder("Handle", 0.022, 0.12, loc=(0, 0, 0.10), mat=M_DARK_LEATHER))
    # Cross-guard (proportionally wide for a dagger)
    parts.append(add_box("Guard", (0.16, 0.04, 0.03), loc=(0, 0, 0.18), mat=M_DARK_METAL))
    # Wide triangular blade — clearly larger than a tiny sliver
    parts.append(add_box("BladeBase", (0.05, 0.015, 0.22), loc=(0, 0, 0.31), mat=M_METAL))
    # Pointed tip
    parts.append(add_cone("BladeTip", 0.030, 0.10, loc=(0, 0, 0.47), mat=M_METAL, segments=4))
    return join_objects(parts, "Weapon_Dagger")


def add_curved_blade_2d(name: str, silhouette_2d: list, thickness: float, mat,
                         origin: tuple = (0, 0, 0), rot: tuple = (0, 0, 0)) -> bpy.types.Object:
    """Create a flat curved blade by defining a 2D silhouette polygon (in the
    YZ plane) and extruding it in X for thickness.

    `silhouette_2d` is a list of (y, z) tuples in order around the outline.
    First and last points should connect (curve is closed). The result is a
    smooth, flat blade with polycount proportional to the resolution.

    Returns the created object (a Curve converted to Mesh via join).
    """
    curve_data = bpy.data.curves.new(name, type='CURVE')
    curve_data.dimensions = '2D'
    curve_data.fill_mode = 'BOTH'  # fill the 2D outline
    spline = curve_data.splines.new('BEZIER')
    spline.bezier_points.add(len(silhouette_2d) - 1)
    for i, (y, z) in enumerate(silhouette_2d):
        bp = spline.bezier_points[i]
        bp.co = (0, y, z)
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
    spline.use_cyclic_u = True
    curve_data.extrude = thickness  # in X
    curve_data.materials.append(mat)
    curve_data.resolution_u = 16  # smoothness of the curves
    curve_data.bevel_depth = 0.0  # no bevel, just the silhouette
    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(obj)
    obj.location = origin
    obj.rotation_euler = rot
    return obj


def add_curved_tube(name: str, points_3d: list, radius: float, mat,
                    origin: tuple = (0, 0, 0), rot: tuple = (0, 0, 0)) -> bpy.types.Object:
    """Create a tapered tube along a 3D path (Bezier curve with bevel).
    `points_3d` is a list of (x, y, z) control points. The tube radius can
    vary by tweaking bevel_depth, but it's roughly constant here.
    """
    curve_data = bpy.data.curves.new(name, type='CURVE')
    curve_data.dimensions = '3D'
    spline = curve_data.splines.new('BEZIER')
    spline.bezier_points.add(len(points_3d) - 1)
    for i, p in enumerate(points_3d):
        bp = spline.bezier_points[i]
        bp.co = p
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
    curve_data.bevel_depth = radius
    curve_data.bevel_resolution = 3
    curve_data.fill_mode = 'FULL'
    curve_data.extrude = 0.0
    curve_data.materials.append(mat)
    curve_data.resolution_u = 24
    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(obj)
    obj.location = origin
    obj.rotation_euler = rot
    return obj


def build_scimitar() -> bpy.types.Object:
    """1h curved sword (alfanje). Curved blade from a 2D silhouette extruded in X."""
    parts = []
    parts.append(add_sphere("Pommel", 0.05, loc=(0, 0, 0.05), mat=M_GOLD))
    parts.append(add_cylinder("Handle", 0.024, 0.20, loc=(0, 0, 0.18), mat=M_DARK_WOOD))
    parts.append(add_box("Guard", (0.18, 0.04, 0.04), loc=(0, 0, 0.30), mat=M_GOLD))
    # Blade silhouette: a curved comma shape in the YZ plane.
    # The "spine" (back of the blade) curves gently; the "edge" (cutting side)
    # curves more aggressively forward. 14 control points give a smooth curve.
    silhouette = [
        # Spine: starts at the guard, goes up and slightly forward
        (0.00, 0.34),
        (0.02, 0.42),
        (0.05, 0.50),
        (0.10, 0.60),
        (0.18, 0.70),
        (0.28, 0.80),
        (0.42, 0.92),
        (0.55, 1.02),
        # Tip
        (0.62, 1.12),
        # Edge: curves back to base, sweeping forward then back
        (0.55, 1.05),
        (0.45, 0.95),
        (0.35, 0.82),
        (0.25, 0.70),
        (0.15, 0.58),
        (0.08, 0.48),
        (0.03, 0.40),
        (0.00, 0.34),  # back to start (closed)
    ]
    parts.append(add_curved_blade_2d("ScimitarBlade", silhouette, 0.025, M_METAL))
    return join_objects(parts, "Weapon_Scimitar")


def build_war_axe() -> bpy.types.Object:
    """1h axe. Wooden handle + axe head from a 2D silhouette + a small spike."""
    parts = []
    # Long handle
    parts.append(add_cylinder("Handle", 0.030, 0.95, loc=(0, 0, 0.52), mat=M_DARK_WOOD))
    # Pommel cap at bottom
    parts.append(add_sphere("Pommel", 0.04, loc=(0, 0, 0.05), mat=M_DARK_METAL))
    # Wrap/grip on handle
    parts.append(add_cylinder("Grip", 0.034, 0.20, loc=(0, 0, 0.40), mat=M_LEATHER))
    # Axe head: 2D silhouette of a fan/wedge shape (like a half-moon).
    # Drawn in the YZ plane: top is the back of the axe (near the handle),
    # the curve bulges to +Y (the cutting edge).
    silhouette = [
        # Inner edge (against the handle), Z=0.65 to Z=1.05
        (0.00, 0.65),  # bottom-inner
        (0.00, 1.05),  # top-inner
        # Top of the axe head
        (0.08, 1.10),
        (0.18, 1.10),
        # Curved cutting edge (bulges to +Y)
        (0.28, 1.00),
        (0.36, 0.90),
        (0.40, 0.80),
        (0.36, 0.70),
        (0.28, 0.65),
        (0.18, 0.62),
        (0.08, 0.62),
        (0.00, 0.65),  # back to start (closed)
    ]
    parts.append(add_curved_blade_2d("AxeHead", silhouette, 0.10, M_METAL))
    # Back spike (counterbalance) on the -Y side
    parts.append(add_cone("AxeSpike", 0.030, 0.14, loc=(0, -0.16, 0.90), rot=(0, 0, math.pi/2), mat=M_DARK_METAL, segments=4))
    return join_objects(parts, "Weapon_WarAxe")


def build_mace() -> bpy.types.Object:
    """1h mace. Heavy spiked head on a wooden handle."""
    parts = []
    # Handle
    parts.append(add_cylinder("Handle", 0.024, 0.85, loc=(0, 0, 0.47), mat=M_DARK_WOOD))
    # Pommel cap
    parts.append(add_sphere("Pommel", 0.035, loc=(0, 0, 0.05), mat=M_DARK_METAL))
    # Grip
    parts.append(add_cylinder("Grip", 0.028, 0.18, loc=(0, 0, 0.45), mat=M_LEATHER))
    # Mace head: icosphere (visible mass) at top of handle
    parts.append(add_sphere("MaceHead", 0.11, loc=(0, 0, 0.95), mat=M_DARK_METAL))
    # 6 spikes around the head (visible in profile from any side)
    parts.append(add_cone("SpikeUp",   0.030, 0.14, loc=(0, 0,    1.10), mat=M_METAL, segments=4))
    parts.append(add_cone("SpikeFwd",  0.030, 0.14, loc=(0, 0.11, 0.95), rot=(math.pi/2, 0, 0), mat=M_METAL, segments=4))
    parts.append(add_cone("SpikeBack", 0.030, 0.14, loc=(0, -0.11,0.95), rot=(math.pi/2, 0, 0), mat=M_METAL, segments=4))
    parts.append(add_cone("SpikeUR",   0.030, 0.10, loc=(0.08, 0.08, 1.05), rot=(-0.6, 0.6, 0), mat=M_METAL, segments=4))
    parts.append(add_cone("SpikeUL",   0.030, 0.10, loc=(-0.08, 0.08, 1.05), rot=(-0.6, -0.6, 0), mat=M_METAL, segments=4))
    return join_objects(parts, "Weapon_Mace")


def build_spear() -> bpy.types.Object:
    """2h spear. Long wooden shaft + spear head with a leaf shape."""
    parts = []
    # Very long shaft
    parts.append(add_cylinder("Shaft", 0.022, 1.8, loc=(0, 0, 0.95), mat=M_DARK_WOOD))
    # Pommel cap (bottom)
    parts.append(add_sphere("Pommel", 0.035, loc=(0, 0, 0.05), mat=M_DARK_METAL))
    # Grip
    parts.append(add_cylinder("Grip", 0.026, 0.25, loc=(0, 0, 0.30), mat=M_LEATHER))
    # Collar (where head meets shaft)
    parts.append(add_torus("Collar", 0.040, 0.014, loc=(0, 0, 1.78), rot=(0, 0, 0), mat=M_BRONZE))
    # Spear head — leaf shape: 2 boxes crossed
    parts.append(add_box("SpearA", (0.06, 0.03, 0.36), loc=(0, 0, 2.02), mat=M_METAL))
    parts.append(add_box("SpearB", (0.03, 0.06, 0.36), loc=(0, 0, 2.02), mat=M_METAL))
    # Tip
    parts.append(add_cone("SpearTip", 0.040, 0.12, loc=(0, 0, 2.26), mat=M_METAL, segments=4))
    return join_objects(parts, "Weapon_Spear")


def build_great_scythe() -> bpy.types.Object:
    """2h scythe. Long wooden shaft + broad curved blade (2D silhouette)."""
    parts = []
    # Shaft
    parts.append(add_cylinder("Shaft", 0.028, 1.6, loc=(0, 0, 0.85), mat=M_DARK_WOOD))
    # Pommel cap
    parts.append(add_sphere("Pommel", 0.045, loc=(0, 0, 0.05), mat=M_DARK_METAL))
    # Grip
    parts.append(add_cylinder("Grip", 0.033, 0.22, loc=(0, 0, 0.40), mat=M_LEATHER))
    # Curved blade silhouette: a long, broad scythe blade. The top of the
    # blade attaches to the shaft (Z~1.5), then it curves forward and down
    # in a sweeping arc.
    silhouette = [
        # Inner edge (near the shaft, slightly forward)
        (0.00, 1.50),
        (0.00, 1.85),
        # Top-outer (apex of the curve)
        (0.20, 1.95),
        (0.40, 1.90),
        (0.55, 1.78),
        (0.65, 1.62),
        # Tip (forward end of blade)
        (0.70, 1.50),
        (0.65, 1.45),
        # Bottom-outer (curving back toward the shaft)
        (0.50, 1.45),
        (0.35, 1.50),
        (0.20, 1.55),
        (0.10, 1.55),
        (0.00, 1.50),  # back to start (closed)
    ]
    parts.append(add_curved_blade_2d("ScytheBlade", silhouette, 0.04, M_BRONZE))
    return join_objects(parts, "Weapon_GreatScythe")


def build_long_bow() -> bpy.types.Object:
    """2h bow. Curved stave (3D Bezier tube) + taut string."""
    parts = []
    # Curved stave using a 3D Bezier curve with bevel depth (gives a tube).
    # The control points define a U-shape: bottom at (0, 0, 0.15), middle
    # (belly) at (-0.32, 0, 0.90), top at (0, 0, 1.65).
    stave_points = [
        (0, 0, 0.15),
        (-0.10, 0, 0.40),
        (-0.32, 0, 0.90),
        (-0.10, 0, 1.40),
        (0, 0, 1.65),
    ]
    parts.append(add_curved_tube("BowStave", stave_points, 0.022, M_LIGHT_WOOD))
    # String — straight cylinder on the +X side, taut from end to end
    parts.append(add_cylinder("String", 0.006, 1.55, loc=(0.04, 0, 0.90), mat=M_DARK_METAL))
    # Grip (leather wrap in the center, on the -X belly side)
    parts.append(add_cylinder("Grip", 0.040, 0.20, loc=(-0.18, 0, 0.90), mat=M_LEATHER))
    return join_objects(parts, "Weapon_LongBow")


def build_arcane_staff() -> bpy.types.Object:
    """2h staff. Long wooden shaft + crystal orb at the top. Tall (1.7m)."""
    parts = []
    parts.append(add_cylinder("Shaft", 0.032, 1.6, loc=(0, 0, 0.85), mat=M_DARK_WOOD))
    parts.append(add_sphere("Pommel", 0.05, loc=(0, 0, 0.05), mat=M_DARK_METAL))
    # Lower grip
    parts.append(add_cylinder("Grip1", 0.035, 0.22, loc=(0, 0, 0.25), mat=M_LEATHER))
    # Upper grip
    parts.append(add_cylinder("Grip2", 0.035, 0.22, loc=(0, 0, 1.30), mat=M_LEATHER))
    # Gold collar under the orb
    parts.append(add_torus("Collar", 0.065, 0.018, loc=(0, 0, 1.58), rot=(0, 0, 0), mat=M_GOLD))
    # Crystal orb (icosphere for low-poly)
    parts.append(add_sphere("Orb", 0.13, loc=(0, 0, 1.75), mat=M_CRYSTAL))
    return join_objects(parts, "Weapon_ArcaneStaff")


def build_cursed_blade() -> bpy.types.Object:
    """Special 'cursed' 1h sword: dark with reddish rust + menacing details."""
    parts = []
    # Dark pommel (pointed, suggests menace)
    parts.append(add_cone("Pommel", 0.05, 0.10, loc=(0, 0, 0.05), rot=(math.pi, 0, 0), mat=M_DARK_METAL, segments=4))
    # Handle wrapped in red leather
    parts.append(add_cylinder("Handle", 0.024, 0.20, loc=(0, 0, 0.20), mat=M_RED))
    # Guard with menacing 'wings'
    parts.append(add_box("GuardC", (0.22, 0.05, 0.04), loc=(0, 0, 0.32), mat=M_DARK_METAL))
    parts.append(add_cone("WingL", 0.025, 0.10, loc=(-0.13, 0, 0.34), rot=(0, 0, math.pi/2), mat=M_DARK_METAL, segments=4))
    parts.append(add_cone("WingR", 0.025, 0.10, loc=( 0.13, 0, 0.34), rot=(0, 0, -math.pi/2), mat=M_DARK_METAL, segments=4))
    # Blade — RUSTY_METAL for the cursed look
    parts.append(add_box("BladeBase", (0.055, 0.015, 0.55), loc=(0, 0, 0.65), mat=M_RUSTY_METAL))
    # Fuller (groove line) — visible darker stripe
    parts.append(add_box("Fuller", (0.014, 0.004, 0.42), loc=(0, 0, 0.66), mat=M_DARK_METAL))
    # Tip
    parts.append(add_cone("BladeTip", 0.030, 0.10, loc=(0, 0, 0.97), mat=M_RUSTY_METAL, segments=4))
    return join_objects(parts, "Weapon_CursedBlade")


# -------------------------------------------------------------------- export
def export_glb(obj: bpy.types.Object, filename: str) -> str:
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    out_path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,  # convert Z-up to Y-up
        export_materials='EXPORT',
        export_normals=True,
        export_animations=False,
    )
    # Count geometry: handle both MESH and CURVE-typed data
    if obj.type == 'MESH':
        n_verts = len(obj.data.vertices)
        n_faces = sum(len(p.vertices) for p in obj.data.polygons) // 3
    else:
        n_verts = 0
        n_faces = 0
    return out_path, n_verts, n_faces


# -------------------------------------------------------------------- main
WEAPON_BUILDERS = {
    "wpn_short_sword.glb": build_short_sword,
    "wpn_long_sword.glb": build_long_sword,
    "wpn_great_sword.glb": build_great_sword,
    "wpn_dagger.glb": build_dagger,
    "wpn_scimitar.glb": build_scimitar,
    "wpn_war_axe.glb": build_war_axe,
    "wpn_mace.glb": build_mace,
    "wpn_spear.glb": build_spear,
    "wpn_great_scythe.glb": build_great_scythe,
    "wpn_long_bow.glb": build_long_bow,
    "wpn_arcane_staff.glb": build_arcane_staff,
    "wpn_cursed_blade.glb": build_cursed_blade,
}


def main():
    print(f"[gen_weapons] Output dir: {OUT_DIR}")
    print(f"[gen_weapons] Weapons to build: {len(WEAPON_BUILDERS)}")
    for filename, builder in WEAPON_BUILDERS.items():
        clear_scene()
        obj = builder()
        path, n_verts, n_faces = export_glb(obj, filename)
        size = os.path.getsize(path)
        print(f"  ✓ {filename}: {size:,} bytes, ~{n_verts} verts, ~{n_faces} tris")
    print(f"\n[gen_weapons] Done. {len(WEAPON_BUILDERS)} weapons exported to {OUT_DIR}")


if __name__ == "__main__":
    main()
