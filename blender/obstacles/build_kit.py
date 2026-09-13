import bpy
from mathutils import Vector

BLEND_PATH = "/Users/jamesritchie/golf-zombies/blender/obstacles/obstacles.blend"
EXPORT_DIR = "/Users/jamesritchie/golf-zombies/assets/obstacles"

CELL = 1.35
C = CELL
SPACING = CELL * 30.0
SIZE_CELLS = {
    "extra_small": 1,
    "small": 3,
    "medium": 5,
    "large": 7,
    "extra_large": 9,
}
SIZE_ORDER = ["extra_small", "small", "medium", "large", "extra_large"]
TYPE_ORDER = ["wall", "ramp", "tunnel", "cube", "pillar", "platform", "steps", "arch"]

COLORS = {
    "ObstacleCoral": (1.00, 0.44, 0.41, 1.0),
    "ObstacleMustard": (1.00, 0.80, 0.36, 1.0),
    "ObstacleSage": (0.59, 0.81, 0.71, 1.0),
    "ObstacleCream": (1.00, 0.93, 0.68, 1.0),
    "ObstacleMint": (0.53, 0.85, 0.69, 1.0),
}

BOX_FACES = (
    (0, 1, 2, 3),
    (4, 7, 6, 5),
    (0, 4, 5, 1),
    (1, 5, 6, 2),
    (2, 6, 7, 3),
    (3, 7, 4, 0),
)

MATS = {
    "wall": "ObstacleCoral",
    "ramp": "ObstacleMustard",
    "tunnel": "ObstacleSage",
    "cube": "ObstacleCream",
    "pillar": "ObstacleMint",
    "platform": "ObstacleCream",
    "steps": "ObstacleMustard",
    "arch": "ObstacleMint",
}


def nuke_kit():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    keep_prefix = ("Ladder", "Escalator")
    for obj in list(bpy.data.objects):
        if obj.name.startswith(keep_prefix):
            continue
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.name.startswith(keep_prefix):
            continue
        bpy.data.meshes.remove(mesh)
    for col in list(bpy.data.collections):
        if col.name in ("Ladder", "Escalator"):
            continue
        if col.name == "Collection" and col == bpy.context.scene.collection:
            continue
        if col.name in ("Obstacles",) or col.name.lower() in TYPE_ORDER:
            bpy.data.collections.remove(col)
    master = bpy.data.collections.get("Obstacles")
    if master is None:
        master = bpy.data.collections.new("Obstacles")
        bpy.context.scene.collection.children.link(master)
    return master


def make_materials():
    mats = {}
    for name, color in COLORS.items():
        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        mat.diffuse_color = color
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = color
            if "Roughness" in bsdf.inputs:
                bsdf.inputs["Roughness"].default_value = 0.55
            if "Metallic" in bsdf.inputs:
                bsdf.inputs["Metallic"].default_value = 0.0
        mats[name] = mat
    return mats


def mesh_object(name, verts, faces, mat, parent, collection):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = parent
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def box(name, x0, x1, y0, y1, z0, z1, mat, parent, collection):
    verts = (
        (x0, y0, z0),
        (x1, y0, z0),
        (x1, y1, z0),
        (x0, y1, z0),
        (x0, y0, z1),
        (x1, y0, z1),
        (x1, y1, z1),
        (x0, y1, z1),
    )
    return mesh_object(name, verts, BOX_FACES, mat, parent, collection)


def make_root(name, collection, location):
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = CELL
    collection.objects.link(empty)
    empty.location = location
    return empty


def build_cube(root, col, mat, n):
    box("Cube", 0.0, n, 0.0, n, 0.0, n, mat, root, col)


def build_wall(root, col, mat, n):
    box("Wall", 0.0, n, 0.0, C, 0.0, n, mat, root, col)


def build_platform(root, col, mat, n):
    box("Platform", 0.0, n, 0.0, n, 0.0, C, mat, root, col)


def build_pillar(root, col, mat, n):
    box("Pillar", 0.0, C, 0.0, C, 0.0, n, mat, root, col)


def build_ramp(root, col, mat, n):
    h = n * 0.5
    verts = (
        (0.0, 0.0, 0.0),
        (n, 0.0, 0.0),
        (n, n, 0.0),
        (0.0, n, 0.0),
        (n, 0.0, h),
        (n, n, h),
    )
    faces = (
        (0, 1, 2, 3),
        (1, 4, 5, 2),
        (0, 3, 5, 4),
        (0, 4, 1),
        (3, 2, 5),
    )
    mesh_object("Ramp", verts, faces, mat, root, col)


def build_steps(root, col, mat, n):
    treads = max(1, int(round(n / C)))
    for i in range(treads):
        box("Step%d" % i, i * C, (i + 1) * C, 0.0, n, 0.0, (i + 1) * C, mat, root, col)


def build_tunnel(root, col, mat, n):
    thick = C
    outer = n + thick * 2.0
    box("Floor", 0.0, n, 0.0, outer, 0.0, thick, mat, root, col)
    box("Ceiling", 0.0, n, 0.0, outer, thick + n, thick + n + thick, mat, root, col)
    box("WallL", 0.0, n, 0.0, thick, thick, thick + n, mat, root, col)
    box("WallR", 0.0, n, outer - thick, outer, thick, thick + n, mat, root, col)


def build_arch(root, col, mat, n):
    thick = C
    height = n
    width = n + thick * 2.0
    box("PostL", 0.0, thick, 0.0, thick, 0.0, height, mat, root, col)
    box("PostR", width - thick, width, 0.0, thick, 0.0, height, mat, root, col)
    box("Lintel", 0.0, width, 0.0, thick, height, height + thick, mat, root, col)


BUILDERS = {
    "cube": build_cube,
    "wall": build_wall,
    "platform": build_platform,
    "pillar": build_pillar,
    "ramp": build_ramp,
    "steps": build_steps,
    "tunnel": build_tunnel,
    "arch": build_arch,
}


def display_name(kind, size):
    return "".join(part.title() for part in ("%s_%s" % (kind, size)).split("_"))


def filename_for(root_name):
    out = []
    for ch in root_name:
        if ch.isupper() and out:
            out.append("_")
        out.append(ch.lower())
    return "".join(out) + ".glb"


def attach_collision(root):
    for child in root.children_recursive:
        if child.type != "MESH":
            continue
        part = child.name.split(".")[0]
        new_name = "%s_%s-convcol" % (root.name, part)
        child.name = new_name
        child.data.name = new_name


def export_root(root):
    old = root.matrix_world.copy()
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    path = "%s/%s" % (EXPORT_DIR, filename_for(root.name))
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_cameras=False,
        export_extras=False,
        export_yup=True,
        export_animations=False,
    )
    root.matrix_world = old
    bpy.context.view_layer.update()
    return filename_for(root.name)


def set_grid():
    units = bpy.context.scene.unit_settings
    units.system = "METRIC"
    units.scale_length = 1.0
    units.length_unit = "METERS"
    ts = bpy.context.scene.tool_settings
    ts.use_snap = True
    if hasattr(ts, "snap_elements_base"):
        ts.snap_elements_base = {"INCREMENT"}
    if hasattr(ts, "use_snap_grid_absolute"):
        ts.use_snap_grid_absolute = True
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type != "VIEW_3D":
                continue
            space = area.spaces.active
            space.overlay.grid_scale = CELL
            if hasattr(space.overlay, "grid_subdivisions"):
                space.overlay.grid_subdivisions = 1


def measure(root):
    corners = []
    for child in root.children_recursive:
        if child.type != "MESH":
            continue
        for v in child.bound_box:
            corners.append(child.matrix_world @ Vector(v))
    if not corners:
        return [0.0, 0.0, 0.0]
    xs = [p.x for p in corners]
    ys = [p.y for p in corners]
    zs = [p.z for p in corners]
    return [round(max(xs) - min(xs), 4), round(max(ys) - min(ys), 4), round(max(zs) - min(zs), 4)]


def run():
    master = nuke_kit()
    mats = make_materials()
    type_cols = {}
    for kind in TYPE_ORDER:
        col = bpy.data.collections.get(kind.title())
        if col is None:
            col = bpy.data.collections.new(kind.title())
            master.children.link(col)
        type_cols[kind] = col
    roots = []
    for kind in TYPE_ORDER:
        for size in SIZE_ORDER:
            n = SIZE_CELLS[size] * C
            loc = (SIZE_ORDER.index(size) * SPACING, -TYPE_ORDER.index(kind) * SPACING, 0.0)
            root = make_root(display_name(kind, size), type_cols[kind], loc)
            BUILDERS[kind](root, type_cols[kind], mats[MATS[kind]], n)
            attach_collision(root)
            roots.append(root)
    bpy.context.view_layer.update()
    exported = [export_root(root) for root in roots]
    set_grid()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bounds = []
    off = []
    for root in roots:
        size = measure(root)
        for dim in size:
            steps = round(dim / CELL)
            if abs(dim - steps * CELL) > 0.02 and abs(dim - steps * CELL * 0.5) > 0.02:
                off.append((root.name, dim))
        bounds.append({"name": root.name, "cells": [round(d / CELL, 2) for d in size]})
    return {"exported": exported, "count": len(exported), "off_grid": off, "bounds": bounds}


result = run()
