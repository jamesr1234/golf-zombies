import math
import os

import bpy

CELL = 1.35
SIZES = [
    ("ExtraSmall", "extra_small", 1, (-0.675, -202.5, 0.0)),
    ("Small", "small", 2, (39.825, -202.5, 0.0)),
    ("Medium", "medium", 3, (80.325, -202.5, 0.0)),
    ("Large", "large", 5, (120.825, -202.5, 0.0)),
    ("ExtraLarge", "extra_large", 7, (161.325, -202.5, 0.0)),
]
EXPORT_DIR = "/Users/jamesritchie/golf-zombies/assets/obstacles"
RUNG = 0.45
INSET = 0.10
CHAN_W = 0.10
CHAN_D = 0.15
WEB = 0.028
FLANGE = 0.024


def _collection() -> bpy.types.Collection:
    coll = bpy.data.collections.get("Ladder")
    if coll is None:
        coll = bpy.data.collections.new("Ladder")
        bpy.context.scene.collection.children.link(coll)
    return coll


def _wipe() -> None:
    for obj in list(bpy.data.objects):
        if obj.name.startswith("Ladder"):
            bpy.data.objects.remove(obj, do_unlink=True)


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


def _fly_paint() -> bpy.types.Material:
    return bpy.data.materials.get("ObstacleCream") or _paint()


def _steel() -> bpy.types.Material:
    return _make_mat("LadderSteel", (0.22, 0.24, 0.28), 0.88, 0.28)


def _rubber() -> bpy.types.Material:
    return _make_mat("LadderShoe", (0.05, 0.05, 0.06), 0.04, 0.8)


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


def _channel(
    name: str,
    parent: bpy.types.Object,
    coll: bpy.types.Collection,
    x0: float,
    y0: float,
    z0: float,
    z1: float,
    open_right: bool,
    collide: bool,
    mat,
) -> None:
    x1 = x0 + CHAN_W
    y1 = y0 + CHAN_D
    if open_right:
        web_a, web_b = x0, x0 + WEB
    else:
        web_a, web_b = x1 - WEB, x1
    suffix = "-convcol" if collide else ""
    _box(name + "_Web" + suffix, parent, coll, web_a, web_b, y0, y1, z0, z1, mat)
    _box(name + "_Front", parent, coll, x0, x1, y0, y0 + FLANGE, z0, z1, mat)
    _box(name + "_Back", parent, coll, x0, x1, y1 - FLANGE, y1, z0, z1, mat)
    cap_t = 0.03
    _box(name + "_CapB", parent, coll, x0, x1, y0, y1, z0, z0 + cap_t, mat)
    _box(name + "_CapT", parent, coll, x0, x1, y0, y1, z1 - cap_t, z1, mat)


def _d_rung(
    name: str,
    parent: bpy.types.Object,
    coll: bpy.types.Collection,
    x0: float,
    x1: float,
    y: float,
    z: float,
    paint,
    steel,
) -> None:
    span = abs(x1 - x0)
    mid = (x0 + x1) * 0.5
    _cyl(name, parent, coll, 0.032, span, (mid, y, z), (0.0, math.pi * 0.5, 0.0), paint)
    tread = 0.014
    _box(name + "_Tread", parent, coll, x0, x1, y - 0.028, y + 0.028, z, z + tread, paint)
    for side, x in (("L", x0), ("R", x1)):
        _cyl(
            name + "_Sleeve" + side,
            parent,
            coll,
            0.04,
            0.03,
            (x, y, z),
            (0.0, math.pi * 0.5, 0.0),
            steel,
            10,
        )


def _rung_zs(z0: float, z1: float) -> list:
    span = max(0.2, z1 - z0)
    n = max(2, round(span / RUNG))
    return [z0 + span * (float(i) / float(n - 1)) for i in range(n)]


def _lock(
    name: str,
    parent: bpy.types.Object,
    coll: bpy.types.Collection,
    x: float,
    y: float,
    z: float,
    outward: float,
    steel,
) -> None:
    _box(name + "_Body", parent, coll, x, x + outward * 0.05, y - 0.03, y + 0.03, z, z + 0.07, steel)
    _box(
        name + "_Hook",
        parent,
        coll,
        x + outward * 0.02,
        x + outward * 0.05,
        y - 0.018,
        y + 0.018,
        z - 0.08,
        z + 0.01,
        steel,
    )
    _cyl(
        name + "_Pin",
        parent,
        coll,
        0.012,
        0.06,
        (x + outward * 0.025, y, z + 0.035),
        (math.pi * 0.5, 0.0, 0.0),
        steel,
        8,
    )


def _build_one(title: str, cells: int, at: tuple, coll: bpy.types.Collection) -> bpy.types.Object:
    width = CELL
    depth = CELL
    height = CELL * float(cells)
    paint = _paint()
    fly_paint = _fly_paint()
    steel = _steel()
    rubber = _rubber()
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=at)
    root = bpy.context.active_object
    root.name = "Ladder%s" % title
    root.empty_display_size = 0.4
    for old in list(root.users_collection):
        old.objects.unlink(root)
    coll.objects.link(root)
    _box("Ladder%s_Foot-convcol" % title, root, coll, 0.0, width, 0.0, depth, 0.0, 0.06, paint)
    _box(
        "Ladder%s_Top-convcol" % title,
        root,
        coll,
        0.0,
        width,
        0.0,
        depth,
        height - 0.06,
        height,
        paint,
    )
    base_z0 = 0.06
    base_z1 = height * 0.62
    fly_z0 = height * 0.32
    fly_z1 = height - 0.06
    base_y = 0.04
    fly_y = 0.26
    fly_inset = INSET + 0.04
    _channel(
        "Ladder%s_BaseL" % title, root, coll, INSET, base_y, base_z0, base_z1, True, True, paint
    )
    _channel(
        "Ladder%s_BaseR" % title,
        root,
        coll,
        width - INSET - CHAN_W,
        base_y,
        base_z0,
        base_z1,
        False,
        True,
        paint,
    )
    _channel(
        "Ladder%s_FlyL" % title, root, coll, fly_inset, fly_y, fly_z0, fly_z1, True, True, fly_paint
    )
    _channel(
        "Ladder%s_FlyR" % title,
        root,
        coll,
        width - fly_inset - CHAN_W,
        fly_y,
        fly_z0,
        fly_z1,
        False,
        True,
        fly_paint,
    )
    base_x0 = INSET + CHAN_W + 0.01
    base_x1 = width - INSET - CHAN_W - 0.01
    fly_x0 = fly_inset + CHAN_W + 0.01
    fly_x1 = width - fly_inset - CHAN_W - 0.01
    base_rung_y = base_y + CHAN_D * 0.5
    fly_rung_y = fly_y + CHAN_D * 0.5
    for i, z in enumerate(_rung_zs(base_z0 + 0.18, base_z1 - 0.1)):
        _d_rung("Ladder%s_BaseRung%d" % (title, i), root, coll, base_x0, base_x1, base_rung_y, z, paint, steel)
    for i, z in enumerate(_rung_zs(fly_z0 + 0.14, fly_z1 - 0.1)):
        _d_rung("Ladder%s_FlyRung%d" % (title, i), root, coll, fly_x0, fly_x1, fly_rung_y, z, fly_paint, steel)
    lock_z = fly_z0 + 0.1
    _lock("Ladder%s_LockL" % title, root, coll, INSET, base_y + CHAN_D * 0.5, lock_z, -1.0, steel)
    _lock(
        "Ladder%s_LockR" % title,
        root,
        coll,
        width - INSET,
        base_y + CHAN_D * 0.5,
        lock_z,
        1.0,
        steel,
    )
    for side, x0, x1 in (
        ("L", INSET - 0.015, INSET + CHAN_W + 0.02),
        ("R", width - INSET - CHAN_W - 0.02, width - INSET + 0.015),
    ):
        _box(
            "Ladder%s_Guide%s" % (title, side),
            root,
            coll,
            x0,
            x1,
            base_y + CHAN_D - 0.01,
            fly_y + CHAN_D + 0.02,
            lock_z - 0.04,
            lock_z + 0.1,
            steel,
        )
    pulley_z = base_z1 - 0.05
    pulley_y = base_y + CHAN_D + 0.02
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.045,
        minor_radius=0.01,
        location=(width * 0.5, pulley_y, pulley_z),
        rotation=(math.pi * 0.5, 0.0, 0.0),
        major_segments=16,
        minor_segments=8,
    )
    pulley = bpy.context.active_object
    pulley.name = "Ladder%s_Pulley" % title
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    _link(pulley, root, coll, steel)
    _cyl(
        "Ladder%s_PulleyAxle" % title,
        root,
        coll,
        0.01,
        0.08,
        (width * 0.5, pulley_y, pulley_z),
        (math.pi * 0.5, 0.0, 0.0),
        steel,
        8,
    )
    rope_x = width - INSET - CHAN_W * 0.5
    _cyl(
        "Ladder%s_Rope" % title,
        root,
        coll,
        0.008,
        pulley_z - 0.22,
        (rope_x, pulley_y, (pulley_z + 0.22) * 0.5),
        (0.0, 0.0, 0.0),
        steel,
        8,
    )
    _box(
        "Ladder%s_Cleat" % title,
        root,
        coll,
        rope_x - 0.03,
        rope_x + 0.03,
        pulley_y - 0.02,
        pulley_y + 0.02,
        0.2,
        0.28,
        steel,
    )
    for side, x0 in (("L", INSET), ("R", width - INSET - CHAN_W)):
        _box(
            "Ladder%s_Shoe%s" % (title, side),
            root,
            coll,
            x0 - 0.02,
            x0 + CHAN_W + 0.02,
            0.0,
            base_y + CHAN_D + 0.04,
            0.0,
            0.07,
            rubber,
        )
    return root


def _export(root: bpy.types.Object, slug: str) -> str:
    held = tuple(root.location)
    root.location = (0.0, 0.0, 0.0)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    path = os.path.join(EXPORT_DIR, "ladder_%s.glb" % slug)
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
    coll = _collection()
    paths = []
    for title, slug, cells, at in SIZES:
        root = _build_one(title, cells, at, coll)
        paths.append(_export(root, slug))
    bpy.ops.wm.save_mainfile()
    return {"exported": paths, "count": len(paths)}


result = run()
