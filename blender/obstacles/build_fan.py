import bpy
from math import cos, pi, sin
from mathutils import Vector

BLEND_PATH = "/Users/jamesritchie/golf-zombies/blender/obstacles/fan.blend"
EXPORT_PATH = "/Users/jamesritchie/golf-zombies/assets/course/fan.glb"
CELL = 1.35
SPAN = CELL * 5.0
BASE_H = 0.32
COWL_R = 2.55
COWL_INNER = 2.28
COWL_H = 0.92
BLADE_COUNT = 5
BOX_FACES = (
    (0, 1, 2, 3),
    (4, 7, 6, 5),
    (0, 4, 5, 1),
    (1, 5, 6, 2),
    (2, 6, 7, 3),
    (3, 7, 4, 0),
)
COLORS = {
    "FanShell": ((0.07, 0.09, 0.10, 1.0), 0.35, 0.42, (0.07, 0.09, 0.10, 1.0), 0.0),
    "FanFrame": ((0.09, 0.26, 0.28, 1.0), 0.45, 0.32, (0.09, 0.26, 0.28, 1.0), 0.2),
    "FanCyan": ((0.15, 0.95, 1.0, 1.0), 0.05, 0.22, (0.15, 0.95, 1.0, 1.0), 6.0),
    "FanIce": ((0.80, 0.97, 1.0, 1.0), 0.02, 0.16, (0.80, 0.97, 1.0, 1.0), 5.0),
    "FanOrange": ((1.00, 0.42, 0.06, 1.0), 0.05, 0.18, (1.00, 0.42, 0.06, 1.0), 8.0),
}


def _wipe():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        if mat.name.startswith("Fan"):
            bpy.data.materials.remove(mat)


def _mat(name):
    base, metal, rough, emit, strength = COLORS[name]
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = base
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = base
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metal
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = rough
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emit
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def _mesh(name, verts, faces, parent, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def _empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.4
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def _box(name, sx, sy, sz, cx, cy, cz, parent, mat):
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    verts = (
        (cx - hx, cy - hy, cz - hz),
        (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz),
        (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz),
        (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz),
        (cx - hx, cy + hy, cz + hz),
    )
    return _mesh(name, verts, BOX_FACES, parent, mat)


def _cylinder(name, radius, z0, z1, parent, mat, segs=24, inner=0.0):
    verts = []
    faces = []
    rings = [radius] if inner <= 0.0 else [radius, inner]
    for r in rings:
        for z in (z0, z1):
            for i in range(segs):
                a = 2.0 * pi * i / segs
                verts.append((cos(a) * r, sin(a) * r, z))
    if inner <= 0.0:
        for i in range(segs):
            n = (i + 1) % segs
            faces.append((i, n, segs + n, segs + i))
        faces.append(tuple(range(segs - 1, -1, -1)))
        faces.append(tuple(range(segs, segs * 2)))
    else:
        # outer wall, inner wall, top ring, bottom ring
        for i in range(segs):
            n = (i + 1) % segs
            faces.append((i, n, segs + n, segs + i))
            io = segs * 2
            faces.append((io + n, io + i, io + segs + i, io + segs + n))
            faces.append((segs + i, segs + n, io + segs + n, io + segs + i))
            faces.append((io + i, io + n, n, i))
    return _mesh(name, verts, faces, parent, mat)


def _cone(name, r0, r1, z0, z1, parent, mat, segs=20):
    verts = [(0.0, 0.0, z0), (0.0, 0.0, z1)]
    for i in range(segs):
        a = 2.0 * pi * i / segs
        verts.append((cos(a) * r0, sin(a) * r0, z0))
    for i in range(segs):
        a = 2.0 * pi * i / segs
        verts.append((cos(a) * r1, sin(a) * r1, z1))
    faces = []
    for i in range(segs):
        n = (i + 1) % segs
        faces.append((0, 2 + n, 2 + i))
        faces.append((1, 2 + segs + i, 2 + segs + n))
        faces.append((2 + i, 2 + n, 2 + segs + n, 2 + segs + i))
    return _mesh(name, verts, faces, parent, mat)


def _blade(index, parent, mat):
    angle = 2.0 * pi * index / float(BLADE_COUNT)
    length = 2.05
    tip_w = 0.14
    root_w = 0.38
    thick = 0.05
    verts = (
        (0.42, -root_w * 0.5, -thick),
        (0.42, root_w * 0.5, -thick),
        (0.42, root_w * 0.5, thick),
        (0.42, -root_w * 0.5, thick),
        (0.42 + length, -tip_w * 0.5, -thick * 0.4),
        (0.42 + length, tip_w * 0.5, -thick * 0.4),
        (0.42 + length, tip_w * 0.5, thick * 0.4),
        (0.42 + length, -tip_w * 0.5, thick * 0.4),
    )
    twisted = []
    for x, y, z in verts:
        t = (x - 0.42) / length
        twist = 0.45 * t
        cy = y * cos(twist) - z * sin(twist)
        cz = y * sin(twist) + z * cos(twist)
        twisted.append((x, cy, cz))
    obj = _mesh("Blade%d" % (index + 1), twisted, BOX_FACES, parent, mat)
    obj.rotation_euler = (0.0, 0.0, angle)
    return obj


def build():
    _wipe()
    units = bpy.context.scene.unit_settings
    units.system = "METRIC"
    units.scale_length = 1.0
    units.length_unit = "METERS"
    shell = _mat("FanShell")
    frame = _mat("FanFrame")
    cyan = _mat("FanCyan")
    ice = _mat("FanIce")
    orange = _mat("FanOrange")
    root = _empty("Fan", (0.0, 0.0, 0.0))
    _box("Base-convcol", SPAN, SPAN, BASE_H, 0.0, 0.0, BASE_H * 0.5, root, shell)
    inset = SPAN * 0.5 - 0.38
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        _box("Foot%d" % (i + 1), 0.55, 0.55, 0.16, sx * inset, sy * inset, 0.08, root, frame)
        _cylinder("Bolt%d" % (i + 1), 0.08, 0.16, 0.26, root, ice, segs=10)
        bpy.data.objects["Bolt%d" % (i + 1)].location = (sx * inset, sy * inset, 0.0)
    _box("Hazard1", SPAN * 0.92, 0.18, 0.05, 0.0, -(SPAN * 0.5 - 0.16), BASE_H + 0.02, root, orange)
    _box("Hazard2", SPAN * 0.92, 0.18, 0.05, 0.0, SPAN * 0.5 - 0.16, BASE_H + 0.02, root, orange)
    _cylinder("Cowling", COWL_R, BASE_H, BASE_H + COWL_H, root, frame, segs=36, inner=COWL_INNER)
    _cylinder(
        "Lip",
        COWL_R + 0.08,
        BASE_H + COWL_H,
        BASE_H + COWL_H + 0.1,
        root,
        cyan,
        segs=36,
        inner=COWL_INNER - 0.04,
    )
    _cylinder("Well", COWL_INNER + 0.06, BASE_H, BASE_H + 0.08, root, cyan, segs=28, inner=COWL_INNER - 0.1)
    for i in range(4):
        angle = 2.0 * pi * i / 4.0 + pi * 0.25
        strut = _box("Strut%d" % (i + 1), COWL_INNER * 1.85, 0.1, 0.07, 0.0, 0.0, BASE_H + 0.12, root, ice)
        strut.rotation_euler = (0.0, 0.0, angle)
    hub_z = BASE_H + 0.42
    rotor = _empty("Rotor", (0.0, 0.0, hub_z), root)
    _cylinder("Hub", 0.42, -0.14, 0.14, rotor, cyan, segs=18)
    _cone("Nose", 0.32, 0.04, 0.12, 0.40, rotor, ice)
    for i in range(BLADE_COUNT):
        _blade(i, rotor, shell)
    return root


def export_root(root):
    view = bpy.context.view_layer
    for obj in bpy.data.objects:
        obj.select_set(False)
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    view.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=EXPORT_PATH,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_cameras=False,
        export_extras=False,
        export_yup=True,
        export_animations=False,
    )


def measure(root):
    corners = []
    for child in root.children_recursive:
        if child.type != "MESH":
            continue
        for vert in child.bound_box:
            corners.append(child.matrix_world @ Vector(vert))
    xs = [p.x for p in corners]
    ys = [p.y for p in corners]
    zs = [p.z for p in corners]
    return {
        "size": [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)],
        "min": [round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
        "objects": sorted(o.name for o in bpy.data.objects),
    }


# Leave mill_remote on disk; this file is saved as fan.blend after the wipe.
root = build()
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
export_root(root)
result = {"blend": BLEND_PATH, "glb": EXPORT_PATH, **measure(root)}
