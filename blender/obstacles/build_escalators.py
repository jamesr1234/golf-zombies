import math
import os

import bpy

CELL = 1.35
EXPORT_DIR = "/Users/jamesritchie/golf-zombies/assets/obstacles"
TITLE = "Large"
SLUG = "large"
AT = (220.0, -202.5, 0.0)
WIDTH_CELLS = 2.0
RISE_CELLS = 5.0
RUN_CELLS = 10.0
RAIL_T = 0.12
DECK_T = 0.12
LANDING = CELL * 1.5
CURB_H = 0.16


def _collection() -> bpy.types.Collection:
    coll = bpy.data.collections.get("Escalator")
    if coll is None:
        coll = bpy.data.collections.new("Escalator")
        bpy.context.scene.collection.children.link(coll)
    return coll


def _wipe() -> None:
    for obj in list(bpy.data.objects):
        if obj.name.startswith("Escalator"):
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.name.startswith("Escalator"):
            bpy.data.meshes.remove(mesh)


def _make_mat(name: str, color: tuple, metallic: float, roughness: float) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (color[0], color[1], color[2], 1.0)
    return mat


def _paint() -> bpy.types.Material:
    return bpy.data.materials.get("ObstacleMustard") or bpy.data.materials[0]


def _cream() -> bpy.types.Material:
    return bpy.data.materials.get("ObstacleCream") or _paint()


def _steel() -> bpy.types.Material:
    return _make_mat("LadderSteel", (0.22, 0.24, 0.28), 0.88, 0.28)


def _button_mat() -> bpy.types.Material:
    return _make_mat("EscalatorButton", (0.15, 0.95, 1.0), 0.2, 0.28)


def _link(obj: bpy.types.Object, parent: bpy.types.Object, coll: bpy.types.Collection, mat) -> None:
    obj.parent = parent
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    coll.objects.link(obj)
    if obj.data is not None and mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)


def _box(
    name: str,
    parent: bpy.types.Object,
    coll: bpy.types.Collection,
    xmin: float,
    xmax: float,
    ymin: float,
    ymax: float,
    zmin: float,
    zmax: float,
    mat,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    obj = bpy.context.active_object
    obj.name = name
    lo_x, hi_x = (xmin, xmax) if xmax >= xmin else (xmax, xmin)
    lo_y, hi_y = (ymin, ymax) if ymax >= ymin else (ymax, ymin)
    lo_z, hi_z = (zmin, zmax) if zmax >= zmin else (zmax, zmin)
    obj.dimensions = (hi_x - lo_x, hi_y - lo_y, hi_z - lo_z)
    obj.location = ((lo_x + hi_x) * 0.5, (lo_y + hi_y) * 0.5, (lo_z + hi_z) * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    _link(obj, parent, coll, mat)
    return obj


def _cyl(
    name: str,
    parent: bpy.types.Object,
    coll: bpy.types.Collection,
    radius: float,
    depth: float,
    at: tuple,
    rot: tuple,
    mat,
    verts: int = 12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, location=at, rotation=rot, vertices=verts
    )
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    _link(obj, parent, coll, mat)
    return obj


def _wedge(
    name: str,
    parent: bpy.types.Object,
    coll: bpy.types.Collection,
    width: float,
    run: float,
    rise: float,
    mat,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    verts = [
        (0.0, 0.0, 0.0),
        (width, 0.0, 0.0),
        (0.0, 0.0, DECK_T),
        (width, 0.0, DECK_T),
        (0.0, run, 0.0),
        (width, run, 0.0),
        (0.0, run, rise),
        (width, run, rise),
    ]
    faces = [
        (0, 1, 3, 2),
        (4, 6, 7, 5),
        (0, 4, 5, 1),
        (2, 3, 7, 6),
        (0, 2, 6, 4),
        (1, 5, 7, 3),
    ]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    _link(obj, parent, coll, mat)
    return obj


def _empty(name: str, parent: bpy.types.Object, coll: bpy.types.Collection, at: tuple) -> bpy.types.Object:
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=at)
    obj = bpy.context.active_object
    obj.name = name
    obj.empty_display_size = 0.25
    _link(obj, parent, coll, None)
    return obj


def _build_one(coll: bpy.types.Collection) -> bpy.types.Object:
    width = CELL * WIDTH_CELLS
    rise = CELL * RISE_CELLS
    run = CELL * RUN_CELLS
    paint = _paint()
    cream = _cream()
    steel = _steel()
    glow = _button_mat()
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=AT)
    root = bpy.context.active_object
    root.name = "Escalator%s" % TITLE
    root.empty_display_size = 0.4
    for old in list(root.users_collection):
        old.objects.unlink(root)
    coll.objects.link(root)
    walk0 = RAIL_T
    walk1 = width - RAIL_T
    _wedge("Escalator%s_Slope-convcol" % TITLE, root, coll, width, run, rise, paint)
    _box(
        "Escalator%s_Bottom-convcol" % TITLE,
        root,
        coll,
        0.0,
        width,
        0.0,
        LANDING,
        0.0,
        DECK_T,
        cream,
    )
    _box(
        "Escalator%s_Top-convcol" % TITLE,
        root,
        coll,
        0.0,
        width,
        run - LANDING,
        run,
        rise - DECK_T,
        rise - 0.02,
        cream,
    )
    for side, x0, x1 in (("L", 0.0, RAIL_T), ("R", width - RAIL_T, width)):
        _box(
            "Escalator%s_Rail%s-convcol" % (TITLE, side),
            root,
            coll,
            x0,
            x1,
            0.0,
            run,
            0.0,
            rise,
            paint,
        )
        _box(
            "Escalator%s_Curb%s" % (TITLE, side),
            root,
            coll,
            x0,
            x1,
            0.0,
            run,
            0.0,
            CURB_H,
            steel,
        )
    angle = math.atan2(rise, run)
    hyp = math.hypot(run, rise)
    rail_len = hyp - 1.4
    rail_rot = (math.pi * 0.5 + angle, 0.0, 0.0)
    for side, x in (("L", walk0 + 0.04), ("R", walk1 - 0.04)):
        _cyl(
            "Escalator%s_Hand%s" % (TITLE, side),
            root,
            coll,
            0.028,
            rail_len,
            (x, run * 0.5, rise * 0.5 + 0.1),
            rail_rot,
            steel,
            10,
        )
        for i, t in enumerate((0.12, 0.5, 0.84)):
            _cyl(
                "Escalator%s_Post%s%d" % (TITLE, side, i),
                root,
                coll,
                0.022,
                0.72,
                (x, run * t, rise * t + 0.36),
                (0.0, 0.0, 0.0),
                steel,
                8,
            )
    _box(
        "Escalator%s_CombB" % TITLE,
        root,
        coll,
        walk0,
        walk1,
        0.02,
        0.16,
        DECK_T,
        DECK_T + 0.03,
        steel,
    )
    _box(
        "Escalator%s_CombT" % TITLE,
        root,
        coll,
        walk0,
        walk1,
        run - 0.16,
        run - 0.02,
        rise - 0.05,
        rise - 0.02,
        steel,
    )
    bx = width * 0.5
    by = run - LANDING * 0.45
    bz = rise - 0.28
    _cyl(
        "Escalator%s_ButtonStem" % TITLE,
        root,
        coll,
        0.08,
        0.14,
        (bx, by, bz + 0.07),
        (0.0, 0.0, 0.0),
        steel,
        12,
    )
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, location=(bx, by, bz + 0.16), segments=16, ring_count=8)
    cap = bpy.context.active_object
    cap.name = "Escalator%s_Button" % TITLE
    cap.scale = (1.0, 1.0, 0.42)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    _link(cap, root, coll, glow)
    _empty("Escalator%s_ButtonMark" % TITLE, root, coll, (bx, by, bz + 0.22))
    _empty("Escalator%s_Slope" % TITLE, root, coll, (width * 0.5, run * 0.5, rise * 0.5))
    _empty("Escalator%s_Top" % TITLE, root, coll, (width * 0.5, run - LANDING * 0.5, rise))
    return root


def _export(root: bpy.types.Object) -> str:
    held = tuple(root.location)
    root.location = (0.0, 0.0, 0.0)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    path = os.path.join(EXPORT_DIR, "escalator_%s.glb" % SLUG)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_skins=False,
        export_animations=False,
    )
    root.location = held
    return path


def run() -> dict:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    _wipe()
    root = _build_one(_collection())
    path = _export(root)
    bpy.ops.wm.save_mainfile()
    return {"exported": path, "width": CELL * WIDTH_CELLS, "rise": CELL * RISE_CELLS, "run": CELL * RUN_CELLS}


result = run()
