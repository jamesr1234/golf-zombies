"""Smooth cart helix with a ski-jump lip. Run inside Blender via blender-mcp."""

import math
import os

import bpy
import bmesh
from mathutils import Vector

EXPORT_DIR = "/Users/jamesritchie/golf-zombies/assets/course"
EXPORT = os.path.join(EXPORT_DIR, "spiral_track.glb")
BLEND = "/Users/jamesritchie/golf-zombies/blender/obstacles/spiral_track.blend"
SIZES = (
    ("spiral_track.glb", 12.0),
    ("spiral_track_extra_large.glb", 22.0),
    ("spiral_track_gigantic.glb", 36.0),
)

RADIUS = 28.0
WIDTH = 12.0
TURNS = 9
RISE = 10.0
DECK = 0.85
LIFT = 0.16
RAIL_H = 1.6
RAIL_T = 0.45
APPROACH = 22.0
CORE_R = 3.8
PILLAR_R = 0.7
PILLAR_IN = 0.42
LAUNCH_ARC = 24.0
LAUNCH_DEG = 26.0
LAUNCH_RAIL_CUT = 2.2
HELIX_STEPS = 128
LAUNCH_STEPS = 64
APPROACH_STEPS = 16
PILLARS_PER_TURN = 8


def helix_height() -> float:
    return float(TURNS) * RISE


def helix_grade() -> float:
    return math.atan(RISE / (math.tau * RADIUS))


def kappa() -> float:
    return (math.radians(LAUNCH_DEG) - helix_grade()) / LAUNCH_ARC


def launch_rise() -> float:
    return (math.cos(helix_grade()) - math.cos(math.radians(LAUNCH_DEG))) / kappa()


def helix_point(t: float) -> Vector:
    a = t * math.tau * float(TURNS)
    return Vector((math.sin(a) * RADIUS, math.cos(a) * RADIUS, LIFT + t * helix_height()))


def helix_tangent(t: float) -> Vector:
    a = t * math.tau * float(TURNS)
    da = math.tau * float(TURNS)
    return Vector((math.cos(a) * RADIUS * da, -math.sin(a) * RADIUS * da, helix_height()))


def launch_point(s: float) -> Vector:
    pitch = helix_grade() + kappa() * s
    end = helix_point(1.0)
    tang = helix_tangent(1.0)
    flat = Vector((tang.x, tang.y, 0.0)).normalized()
    horiz = (math.sin(pitch) - math.sin(helix_grade())) / kappa()
    vert = (math.cos(helix_grade()) - math.cos(pitch)) / kappa()
    return end + flat * horiz + Vector((0.0, 0.0, vert))


def launch_tangent(s: float) -> Vector:
    pitch = helix_grade() + kappa() * s
    tang = helix_tangent(1.0)
    flat = Vector((tang.x, tang.y, 0.0)).normalized()
    return (flat * math.cos(pitch) + Vector((0.0, 0.0, math.sin(pitch)))).normalized()


def _frame(tangent: Vector) -> tuple:
    heading = Vector(tangent)
    if heading.length_squared < 1e-10:
        heading = Vector((1.0, 0.0, 0.0))
    heading.normalize()
    right = heading.cross(Vector((0.0, 0.0, 1.0)))
    if right.length_squared < 1e-8:
        right = heading.cross(Vector((0.0, 1.0, 0.0)))
    right.normalize()
    up = right.cross(heading).normalized()
    return right, up


def _path() -> list:
    samples = []
    start = helix_point(0.0)
    origin = Vector((start.x - APPROACH, start.y, start.z))
    inbound = Vector((1.0, 0.0, 0.0))
    for i in range(APPROACH_STEPS):
        t = i / float(APPROACH_STEPS)
        samples.append((origin.lerp(start, t), inbound))
    for i in range(HELIX_STEPS * TURNS + 1):
        t = i / float(HELIX_STEPS * TURNS)
        samples.append((helix_point(t), helix_tangent(t).normalized()))
    for i in range(1, LAUNCH_STEPS + 1):
        s = LAUNCH_ARC * (i / float(LAUNCH_STEPS))
        samples.append((launch_point(s), launch_tangent(s)))
    return samples


def _mat(name, color, metallic, roughness, emit=0.0):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emit
    mat.diffuse_color = (*color, 1.0)
    return mat


def _object(name, mesh, mat):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if mat is not None:
        mesh.materials.append(mat)
    return obj


def _smooth(obj):
    mesh = obj.data
    for poly in mesh.polygons:
        poly.use_smooth = True
    if hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = math.radians(60.0)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if hasattr(bpy.ops.object, "shade_auto_smooth"):
        bpy.ops.object.shade_auto_smooth(angle=math.radians(60.0))
    else:
        bpy.ops.object.shade_smooth()


def _sweep(name, samples, profile, mat):
    bm = bmesh.new()
    rings = []
    for point, tangent in samples:
        right, up = _frame(tangent)
        ring = []
        for px, py in profile:
            ring.append(bm.verts.new(point + right * px + up * py))
        rings.append(ring)
    n = len(profile)
    for i in range(1, len(rings)):
        a = rings[i - 1]
        b = rings[i]
        for k in range(n):
            nxt = (k + 1) % n
            bm.faces.new((a[k], a[nxt], b[nxt], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = _object(name, mesh, mat)
    _smooth(obj)
    return obj


def _cylinder(name, radius, height, at, mat, verts=20):
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=verts,
        radius1=radius,
        radius2=radius,
        depth=height,
    )
    bmesh.ops.translate(bm, verts=bm.verts, vec=at)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = _object(name, mesh, mat)
    _smooth(obj)
    return obj


def _box(name, size, at, tangent, mat):
    right, up = _frame(tangent)
    heading = tangent.normalized()
    hx, hy, hz = size.x * 0.5, size.y * 0.5, size.z * 0.5
    corners = [
        at + right * ox + up * oy + heading * oz
        for ox in (-hx, hx)
        for oy in (-hy, hy)
        for oz in (-hz, hz)
    ]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(
        [tuple(p) for p in corners],
        [],
        [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4), (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6)],
    )
    mesh.update()
    return _object(name, mesh, mat)


def _wipe():
    for obj in list(bpy.data.objects):
        if obj.name.startswith("Spiral"):
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.name.startswith("Spiral"):
            bpy.data.meshes.remove(mesh)


def _build():
    samples = _path()
    deck = _mat("SpiralDeck", (0.07, 0.08, 0.10), 0.22, 0.58)
    rail = _mat("SpiralRail", (0.15, 0.95, 1.0), 0.35, 0.28, 0.8)
    cream = _mat("SpiralCore", (0.18, 0.20, 0.24), 0.18, 0.62)
    amber = _mat("SpiralMark", (1.0, 0.7, 0.1), 0.2, 0.32, 1.6)
    half = WIDTH * 0.5
    deck_prof = [(-half, 0.0), (half, 0.0), (half, DECK), (-half, DECK)]
    rail_l = [
        (-half - RAIL_T, 0.0),
        (-half, 0.0),
        (-half, DECK + RAIL_H),
        (-half - RAIL_T, DECK + RAIL_H),
    ]
    rail_r = [
        (half, 0.0),
        (half + RAIL_T, 0.0),
        (half + RAIL_T, DECK + RAIL_H),
        (half, DECK + RAIL_H),
    ]
    travelled = 0.0
    for i in range(1, len(samples)):
        travelled += (samples[i][0] - samples[i - 1][0]).length
    keep = travelled - LAUNCH_RAIL_CUT
    acc = 0.0
    rail_samples = [samples[0]]
    cut_at = None
    for i in range(1, len(samples)):
        acc += (samples[i][0] - samples[i - 1][0]).length
        if acc > keep:
            cut_at = i
            break
        rail_samples.append(samples[i])
    objs = [
        _sweep("SpiralDeck", samples, deck_prof, deck),
        _sweep("SpiralRailL", rail_samples, rail_l, rail),
        _sweep("SpiralRailR", rail_samples, rail_r, rail),
    ]
    total = helix_height() + launch_rise() + DECK + 1.4
    objs.append(_cylinder("SpiralCore", CORE_R, total, Vector((0.0, 0.0, total * 0.5)), cream, 24))
    for turn in range(TURNS):
        for spoke in range(PILLARS_PER_TURN):
            t = (float(turn) + float(spoke) / float(PILLARS_PER_TURN)) / float(TURNS)
            at = helix_point(t)
            inward = Vector((-at.x, -at.y, 0.0)).normalized()
            foot = at + inward * (WIDTH * PILLAR_IN)
            top = at.z
            bot = 0.0 if turn == 0 else helix_point(t - 1.0 / float(TURNS)).z
            h = max(1.2, top - bot - DECK * 0.2)
            objs.append(
                _cylinder(
                    "SpiralPillar_%d_%d" % (turn, spoke),
                    PILLAR_R,
                    h,
                    Vector((foot.x, foot.y, bot + h * 0.5)),
                    cream,
                    12,
                )
            )
    lip = samples[-1]
    objs.append(
        _box(
            "SpiralLip",
            Vector((WIDTH * 1.04, 0.12, 0.38)),
            lip[0] + Vector((0.0, 0.0, DECK + 0.08)),
            lip[1],
            amber,
        )
    )
    for i in range(3):
        s = LAUNCH_ARC * (0.28 + 0.27 * i)
        at = launch_point(s)
        tang = launch_tangent(s)
        _right, up = _frame(tang)
        objs.append(
            _box(
                "SpiralChevron_%d" % i,
                Vector((0.9, 0.05, 0.9)),
                at + up * (DECK + 0.05),
                tang,
                amber,
            )
        )
    start = helix_point(0.0)
    objs.append(
        _box(
            "SpiralStart",
            Vector((WIDTH * 0.92, 0.06, 0.7)),
            start + Vector((0.0, 0.0, DECK + 0.04)),
            Vector((1.0, 0.0, 0.0)),
            _mat("SpiralStart", (0.92, 0.96, 1.0), 0.15, 0.35, 0.9),
        )
    )
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(os.path.dirname(EXPORT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=EXPORT,
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
    return {
        "exported": EXPORT,
        "objects": [obj.name for obj in objs],
        "count": len(objs),
        "height": helix_height() + launch_rise(),
        "grade_deg": math.degrees(helix_grade()),
        "launch_deg": LAUNCH_DEG,
        "launch_rise": launch_rise(),
        "samples": len(samples),
        "rail_cut": cut_at,
        "verts": sum(len(obj.data.vertices) for obj in objs if obj.type == "MESH"),
    }


def run(slug: str = "spiral_track.glb", width: float = 12.0):
    global EXPORT, WIDTH
    EXPORT = os.path.join(EXPORT_DIR, slug)
    WIDTH = width
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    _wipe()
    scene = bpy.data.scenes.new("SpiralTrack")
    previous = bpy.context.window.scene
    bpy.context.window.scene = scene
    built = _build()
    bpy.context.window.scene = previous
    bpy.data.scenes.remove(scene)
    _wipe()
    built["width"] = width
    built["restored"] = bpy.data.filepath
    return built


def run_sizes(wanted=None):
    exported = []
    for slug, width in SIZES:
        if wanted and slug not in wanted:
            continue
        exported.append(run(slug, width))
    return {"sizes": exported}


result = run_sizes(("spiral_track_extra_large.glb", "spiral_track_gigantic.glb"))
