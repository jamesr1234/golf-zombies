import math
import os

import bpy

EXPORT_DIR = "/Users/jamesritchie/golf-zombies/assets/vehicles"
BLEND_PATH = "/Users/jamesritchie/golf-zombies/blender/vehicles/cars.blend"

# Sit camera is 0.96 above the seat; the head beacon tops out near 1.22. Extra
# clearance so a player can board without clipping the header.
HEADROOM = 1.68
ROOF_T = 0.08
WALL = 0.055
GLASS_T = 0.035
SEAT_X = 0.42
WHEEL_AHEAD = 0.38
# Godot SteeringWheel rim radius. Keep body solids out of this sphere.
RIM = 0.30

# Blender Z-up, +Y nose. Every paired part is mirrored on ±X.
CARS = [
    {
        "id": "race_car",
        "title": "RaceCar",
        "kind": "race",
        "at": (-16.0, 0.0, 0.0),
        "paint": (0.58, 0.12, 0.38),
        "half_w": 0.95,
        "half_l": 1.7,
        "wheel_r": 0.30,
        "wheel_x": 0.82,
        "wheel_y": 1.15,
        "seat_y": -0.12,
        "seat_z": 0.52,
        "wheel_z": 0.78,
    },
    {
        "id": "station_wagon",
        "title": "StationWagon",
        "kind": "wagon",
        "at": (-8.0, 0.0, 0.0),
        "paint": (0.32, 0.48, 0.58),
        "half_w": 0.90,
        "half_l": 2.15,
        "wheel_r": 0.34,
        "wheel_x": 0.78,
        "wheel_y": 1.35,
        "seat_y": -0.20,
        "seat_z": 0.88,
        "wheel_z": 1.18,
    },
    {
        "id": "pickup_truck",
        "title": "PickupTruck",
        "kind": "pickup",
        "at": (0.0, 0.0, 0.0),
        "paint": (0.55, 0.36, 0.10),
        "half_w": 1.00,
        "half_l": 2.25,
        "wheel_r": 0.40,
        "wheel_x": 0.86,
        "wheel_y": 1.50,
        "seat_y": 0.55,
        "seat_z": 1.12,
        "wheel_z": 1.42,
    },
    {
        "id": "panel_van",
        "title": "PanelVan",
        "kind": "van",
        "at": (8.0, 0.0, 0.0),
        "paint": (0.28, 0.50, 0.16),
        "half_w": 1.05,
        "half_l": 2.35,
        "wheel_r": 0.36,
        "wheel_x": 0.88,
        "wheel_y": 1.40,
        "seat_y": 0.70,
        "seat_z": 1.08,
        "wheel_z": 1.38,
    },
    {
        "id": "suv",
        "title": "SUV",
        "kind": "suv",
        "at": (16.0, 0.0, 0.0),
        "paint": (0.38, 0.16, 0.55),
        "half_w": 1.00,
        "half_l": 1.95,
        "wheel_r": 0.38,
        "wheel_x": 0.86,
        "wheel_y": 1.25,
        "seat_y": 0.20,
        "seat_z": 1.02,
        "wheel_z": 1.32,
    },
]


def _cabin(spec):
    wheel_y = spec["seat_y"] + WHEEL_AHEAD
    roof = spec["seat_z"] + HEADROOM
    return {
        "wheel_y": wheel_y,
        "visor_y": wheel_y + RIM + 0.08,
        "roof": roof,
        "roof_top": roof + ROOF_T,
        "view_z": spec["seat_z"] + 0.96,
    }


def _collection() -> bpy.types.Collection:
    coll = bpy.data.collections.get("Cars")
    if coll is None:
        coll = bpy.data.collections.new("Cars")
        bpy.context.scene.collection.children.link(coll)
    return coll


def _wipe() -> None:
    for obj in list(bpy.data.objects):
        if obj.name in ("Camera", "Light"):
            continue
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)


def _make_mat(
    name: str,
    color: tuple,
    metallic: float,
    roughness: float,
    emit: float = 0.0,
    alpha: float = 1.0,
    transmission: float = 0.0,
):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], alpha)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        for key in ("Transmission Weight", "Transmission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = transmission
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (color[0], color[1], color[2], 1.0)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emit
    if alpha < 0.99:
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
    mat.diffuse_color = (color[0], color[1], color[2], alpha)
    return mat


def _shared() -> dict:
    return {
        "glass": _make_mat("CarGlass", (0.18, 0.28, 0.32), 0.08, 0.06, 0.06, alpha=0.28, transmission=0.85),
        "rubber": _make_mat("CarRubber", (0.04, 0.04, 0.045), 0.02, 0.88),
        "chrome": _make_mat("CarChrome", (0.16, 0.18, 0.20), 0.92, 0.28),
        "dark": _make_mat("CarDark", (0.04, 0.045, 0.05), 0.35, 0.55),
        "light": _make_mat("CarLight", (0.85, 0.72, 0.38), 0.08, 0.32, 1.2),
        "tail": _make_mat("CarTail", (0.55, 0.06, 0.05), 0.08, 0.38, 0.7),
        "glow": _make_mat("CarGlow", (0.35, 0.85, 0.75), 0.2, 0.4, 0.28),
        "hub": _make_mat("CarHub", (0.22, 0.23, 0.25), 0.75, 0.35),
        "leather": _make_mat("CarLeather", (0.10, 0.08, 0.07), 0.04, 0.72),
        "dash": _make_mat("CarDash", (0.07, 0.07, 0.08), 0.12, 0.62),
        "wood": _make_mat("CarWood", (0.28, 0.16, 0.08), 0.08, 0.55),
        "amber": _make_mat("CarAmber", (0.75, 0.42, 0.08), 0.06, 0.40, 0.55),
    }


def _link(obj, parent, coll, mat) -> None:
    obj.parent = parent
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    coll.objects.link(obj)
    if obj.data is not None and mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)


def _box(name, parent, coll, xmin, xmax, ymin, ymax, zmin, zmax, mat):
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


def _cyl(name, parent, coll, radius, depth, at, rot, mat, verts=12):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, location=at, rotation=rot, vertices=verts
    )
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    _link(obj, parent, coll, mat)
    return obj


def _empty(name, parent, coll, at):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=at)
    obj = bpy.context.active_object
    obj.name = name
    obj.empty_display_size = 0.18
    _link(obj, parent, coll, None)
    return obj


def _pair(name, parent, coll, x0, x1, ymin, ymax, zmin, zmax, mat):
    """Mirror a +X slab onto -X. x0/x1 are the right-side extents."""
    lo, hi = (x0, x1) if x1 >= x0 else (x1, x0)
    _box("%sL" % name, parent, coll, -hi, -lo, ymin, ymax, zmin, zmax, mat)
    _box("%sR" % name, parent, coll, lo, hi, ymin, ymax, zmin, zmax, mat)


def _wheels(root, coll, spec, mats) -> None:
    r = spec["wheel_r"]
    for sx, sy, tag in ((-1.0, 1.0, "FL"), (1.0, 1.0, "FR"), (-1.0, -1.0, "RL"), (1.0, -1.0, "RR")):
        at = (sx * spec["wheel_x"], sy * spec["wheel_y"], r)
        _cyl("%s_Tire%s" % (spec["title"], tag), root, coll, r, 0.22, at, (0.0, math.pi * 0.5, 0.0), mats["rubber"])
        _cyl("%s_Hub%s" % (spec["title"], tag), root, coll, r * 0.42, 0.24, at, (0.0, math.pi * 0.5, 0.0), mats["hub"], 8)
        _cyl(
            "%s_Rim%s" % (spec["title"], tag),
            root,
            coll,
            r * 0.78,
            0.06,
            (at[0] + sx * 0.09, at[1], at[2]),
            (0.0, math.pi * 0.5, 0.0),
            mats["chrome"],
            10,
        )
        for i in range(5):
            ang = i * (math.pi * 2.0 / 5.0)
            spoke_at = (at[0] + sx * 0.10, at[1] + math.cos(ang) * r * 0.28, at[2] + math.sin(ang) * r * 0.28)
            _cyl(
                "%s_Spoke%s%s" % (spec["title"], tag, i),
                root,
                coll,
                0.018,
                r * 0.36,
                spoke_at,
                (math.pi * 0.5, 0.0, ang),
                mats["chrome"],
                6,
            )
        _empty("Wheel%s" % tag, root, coll, at)


def _fenders(root, coll, spec, paint) -> None:
    r = spec["wheel_r"]
    for sx, sy, tag in ((-1.0, 1.0, "FL"), (1.0, 1.0, "FR"), (-1.0, -1.0, "RL"), (1.0, -1.0, "RR")):
        x = sx * spec["wheel_x"]
        _box(
            "%s_Arch%s" % (spec["title"], tag),
            root,
            coll,
            x - 0.20,
            x + 0.20,
            sy * spec["wheel_y"] - r * 0.90,
            sy * spec["wheel_y"] + r * 0.90,
            r * 1.12,
            r * 1.12 + 0.12,
            paint,
        )


def _mirrors(root, coll, spec, mats, cabin_z, cabin_y) -> None:
    w = spec["half_w"]
    _pair(
        "%s_MirrorArm" % spec["title"],
        root,
        coll,
        w,
        w + 0.08,
        cabin_y - 0.03,
        cabin_y + 0.03,
        cabin_z + 0.03,
        cabin_z + 0.07,
        mats["dark"],
    )
    _pair(
        "%s_Mirror" % spec["title"],
        root,
        coll,
        w + 0.07,
        w + 0.13,
        cabin_y - 0.07,
        cabin_y + 0.09,
        cabin_z,
        cabin_z + 0.11,
        mats["dark"],
    )
    _pair(
        "%s_MirrorGlass" % spec["title"],
        root,
        coll,
        w + 0.125,
        w + 0.145,
        cabin_y - 0.05,
        cabin_y + 0.07,
        cabin_z + 0.02,
        cabin_z + 0.09,
        mats["chrome"],
    )


def _handles(root, coll, spec, mats, y0, y1, z) -> None:
    w = spec["half_w"]
    _pair("%s_Handle" % spec["title"], root, coll, w, w + 0.025, y0, y1, z, z + 0.04, mats["chrome"])


def _grille(root, coll, spec, mats, nose_y, z0, z1) -> None:
    w = spec["half_w"] * 0.58
    _box("%s_Grille" % spec["title"], root, coll, -w, w, nose_y - 0.02, nose_y + 0.05, z0, z1, mats["dark"])
    step = (z1 - z0) / 5.0
    for i in range(4):
        z = z0 + step * (i + 0.55)
        _box(
            "%s_Slat%s" % (spec["title"], i),
            root,
            coll,
            -w + 0.04,
            w - 0.04,
            nose_y + 0.04,
            nose_y + 0.07,
            z,
            z + 0.02,
            mats["chrome"],
        )


def _bumpers(root, coll, spec, mats, nose_y, tail_y, z) -> None:
    w = spec["half_w"]
    _box("%s_BumperF" % spec["title"], root, coll, -w * 0.94, w * 0.94, nose_y - 0.02, nose_y + 0.12, z, z + 0.16, mats["dark"])
    _box("%s_BumperR" % spec["title"], root, coll, -w * 0.94, w * 0.94, tail_y - 0.12, tail_y + 0.02, z, z + 0.16, mats["dark"])
    _box("%s_Plate" % spec["title"], root, coll, -0.18, 0.18, tail_y - 0.14, tail_y - 0.08, z + 0.04, z + 0.13, mats["chrome"])
    _box("%s_PlateF" % spec["title"], root, coll, -0.16, 0.16, nose_y + 0.10, nose_y + 0.14, z + 0.02, z + 0.10, mats["chrome"])


def _exhaust(root, coll, spec, mats, tail_y) -> None:
    for sx, tag in ((-1.0, "L"), (1.0, "R")):
        _cyl(
            "%s_Exhaust%s" % (spec["title"], tag),
            root,
            coll,
            0.045,
            0.18,
            (sx * spec["half_w"] * 0.42, tail_y - 0.08, 0.18),
            (math.pi * 0.5, 0.0, 0.0),
            mats["chrome"],
            8,
        )


def _lights(root, coll, spec, mats, nose_y, tail_y, lamp_z) -> None:
    for sx, tag in ((-0.48, "L"), (0.48, "R")):
        _box(
            "%s_Lamp%s" % (spec["title"], tag),
            root,
            coll,
            sx - 0.20,
            sx + 0.20,
            nose_y + 0.02,
            nose_y + 0.12,
            lamp_z - 0.08,
            lamp_z + 0.08,
            mats["light"],
        )
        _box(
            "%s_Bezel%s" % (spec["title"], tag),
            root,
            coll,
            sx - 0.22,
            sx + 0.22,
            nose_y - 0.02,
            nose_y + 0.04,
            lamp_z - 0.10,
            lamp_z + 0.10,
            mats["dark"],
        )
        _box(
            "%s_Tail%s" % (spec["title"], tag),
            root,
            coll,
            sx - 0.18,
            sx + 0.18,
            tail_y - 0.08,
            tail_y,
            lamp_z - 0.06,
            lamp_z + 0.07,
            mats["tail"],
        )


def _lip(root, coll, spec, glow, y0, y1, z) -> None:
    _box("%s_Lip" % spec["title"], root, coll, -spec["half_w"] - 0.03, spec["half_w"] + 0.03, y0, y1, z, z + 0.03, glow)


def _wipers(root, coll, spec, mats, y, z) -> None:
    for sx, tag in ((-0.28, "L"), (0.28, "R")):
        _box("%s_Wiper%s" % (spec["title"], tag), root, coll, sx - 0.22, sx + 0.22, y, y + 0.02, z, z + 0.015, mats["dark"])


def _interior(root, coll, spec, mats, dash_y1, belt) -> None:
    cab = _cabin(spec)
    for sx, tag in ((-SEAT_X, "Driver"), (SEAT_X, "Passenger")):
        _box(
            "%s_%sSeat" % (spec["title"], tag),
            root,
            coll,
            sx - 0.20,
            sx + 0.20,
            spec["seat_y"] - 0.16,
            spec["seat_y"] + 0.18,
            belt + 0.02,
            spec["seat_z"] + 0.06,
            mats["leather"],
        )
        _box(
            "%s_%sBack" % (spec["title"], tag),
            root,
            coll,
            sx - 0.20,
            sx + 0.20,
            spec["seat_y"] - 0.22,
            spec["seat_y"] - 0.12,
            spec["seat_z"],
            spec["seat_z"] + 0.62,
            mats["leather"],
        )
        _box(
            "%s_%sHeadrest" % (spec["title"], tag),
            root,
            coll,
            sx - 0.12,
            sx + 0.12,
            spec["seat_y"] - 0.20,
            spec["seat_y"] - 0.12,
            spec["seat_z"] + 0.60,
            spec["seat_z"] + 0.78,
            mats["leather"],
        )
    _box(
        "%s_Dash" % spec["title"],
        root,
        coll,
        -spec["half_w"] * 0.72,
        spec["half_w"] * 0.72,
        cab["wheel_y"] + 0.12,
        dash_y1,
        belt + 0.04,
        spec["wheel_z"] - 0.20,
        mats["dash"],
    )
    _box(
        "%s_WheelWell" % spec["title"],
        root,
        coll,
        -SEAT_X - 0.08,
        -SEAT_X + 0.08,
        cab["wheel_y"] + 0.06,
        cab["wheel_y"] + 0.14,
        spec["wheel_z"] - 0.22,
        spec["wheel_z"] - 0.10,
        mats["dark"],
    )


def _greenhouse(root, coll, spec, paint, mats, belt, rear_y, side_glass=True) -> None:
    """Hollow cabin: thin sides, thin roof starting at the windshield, glass only as panes."""
    cab = _cabin(spec)
    w = spec["half_w"]
    visor = cab["visor_y"]
    roof = cab["roof"]
    # Roof stops at the seat so it never sits over the wheel. A thin header
    # bridges the A-pillars above the windshield.
    _box("%s_Roof" % spec["title"], root, coll, -w * 0.88, w * 0.88, rear_y, spec["seat_y"] + 0.08, roof, cab["roof_top"], paint)
    _box(
        "%s_Header" % spec["title"],
        root,
        coll,
        -w * 0.86,
        w * 0.86,
        visor - 0.05,
        visor + 0.03,
        roof - 0.03,
        roof + 0.03,
        mats["dark"],
    )
    _pair("%s_HeaderRail" % spec["title"], root, coll, w * 0.80, w * 0.88, spec["seat_y"] + 0.08, visor, roof - 0.02, roof + 0.03, paint)
    _box(
        "%s_GlassF" % spec["title"],
        root,
        coll,
        -w * 0.70,
        w * 0.70,
        visor,
        visor + GLASS_T,
        belt + 0.10,
        roof - 0.02,
        mats["glass"],
    )
    _wipers(root, coll, spec, mats, visor + GLASS_T, belt + 0.12)
    _pair("%s_Sill" % spec["title"], root, coll, w - WALL, w, rear_y, visor, belt, belt + 0.12, paint)
    _pair("%s_Rail" % spec["title"], root, coll, w * 0.86, w * 0.90, rear_y + 0.04, visor - 0.04, roof - 0.06, roof, paint)
    for y0, y1, tag in ((visor - 0.08, visor, "A"), ((rear_y + visor) * 0.5 - 0.05, (rear_y + visor) * 0.5 + 0.05, "B"), (rear_y, rear_y + 0.08, "C")):
        _pair("%s_Pillar%s" % (spec["title"], tag), root, coll, w * 0.84, w * 0.90, y0, y1, belt, roof, mats["dark"])
    if side_glass:
        _pair(
            "%s_GlassSide" % spec["title"],
            root,
            coll,
            w - 0.02,
            w + 0.01,
            rear_y + 0.12,
            visor - 0.10,
            belt + 0.14,
            roof - 0.08,
            mats["glass"],
        )
        _pair(
            "%s_WindowChrome" % spec["title"],
            root,
            coll,
            w + 0.005,
            w + 0.02,
            rear_y + 0.10,
            visor - 0.08,
            belt + 0.12,
            belt + 0.16,
            mats["chrome"],
        )
    _box(
        "%s_GlassR" % spec["title"],
        root,
        coll,
        -w * 0.64,
        w * 0.64,
        rear_y,
        rear_y + GLASS_T,
        belt + 0.12,
        roof - 0.06,
        mats["glass"],
    )
    _interior(root, coll, spec, mats, visor - 0.02, belt)
    _mirrors(root, coll, spec, mats, belt + 0.42, visor - 0.10)


def _empties(root, coll, spec) -> None:
    cab = _cabin(spec)
    _empty("DriverSeat", root, coll, (-SEAT_X, spec["seat_y"], spec["seat_z"]))
    _empty("PassengerSeat", root, coll, (SEAT_X, spec["seat_y"], spec["seat_z"]))
    _empty("SteeringWheel", root, coll, (-SEAT_X, cab["wheel_y"], spec["wheel_z"]))
    _empty("DriverView", root, coll, (-SEAT_X, spec["seat_y"] - 0.42, cab["view_z"]))


def _build_race(root, coll, spec, paint, mats) -> None:
    w, l = spec["half_w"], spec["half_l"]
    cab = _cabin(spec)
    visor = cab["visor_y"]
    _box("%s_Nose" % spec["title"], root, coll, -w * 0.70, w * 0.70, 0.55, l, 0.26, 0.54, paint)
    _box("%s_Deck" % spec["title"], root, coll, -w, w, -l, 0.70, 0.20, 0.50, paint)
    _pair("%s_Pod" % spec["title"], root, coll, w * 0.62, w + 0.04, -0.55, 0.85, 0.22, 0.48, paint)
    _pair("%s_Skirt" % spec["title"], root, coll, w, w + 0.05, -0.70, 0.55, 0.18, 0.30, mats["dark"])
    _box("%s_Splitter" % spec["title"], root, coll, -w * 0.78, w * 0.78, l - 0.04, l + 0.14, 0.18, 0.24, mats["dark"])
    _box("%s_Diffuser" % spec["title"], root, coll, -w * 0.70, w * 0.70, -l - 0.08, -l + 0.16, 0.16, 0.22, mats["dark"])
    for i, y in enumerate((l - 0.35, l - 0.55)):
        _box("%s_HoodVent%s" % (spec["title"], i), root, coll, -0.16, 0.16, y, y + 0.10, 0.52, 0.58, mats["dark"])
    _box("%s_Visor" % spec["title"], root, coll, -w * 0.48, w * 0.48, visor, visor + 0.05, 0.62, 1.05, mats["glass"])
    _box("%s_VisorCap" % spec["title"], root, coll, -w * 0.50, w * 0.50, visor - 0.02, visor + 0.06, 1.03, 1.08, mats["dark"])
    _box("%s_CockpitSill" % spec["title"], root, coll, -w * 0.52, w * 0.52, -0.48, visor, 0.48, 0.56, mats["dark"])
    _pair("%s_CockpitWall" % spec["title"], root, coll, w * 0.46, w * 0.54, -0.48, visor, 0.50, 0.78, paint)
    hoop_y0 = spec["seat_y"] - 0.55
    hoop_y1 = spec["seat_y"] - 0.45
    hoop_z = spec["seat_z"] + 1.42
    _pair("%s_HoopPost" % spec["title"], root, coll, 0.38, 0.46, hoop_y0, hoop_y1, 0.54, hoop_z, mats["dark"])
    _box("%s_HoopBar" % spec["title"], root, coll, -0.46, 0.46, hoop_y0, hoop_y1, hoop_z - 0.06, hoop_z, mats["dark"])
    _box("%s_Wing" % spec["title"], root, coll, -w * 0.96, w * 0.96, -l - 0.16, -l + 0.02, 0.92, 1.00, paint)
    _pair("%s_Endplate" % spec["title"], root, coll, w * 0.92, w * 1.00, -l - 0.18, -l + 0.04, 0.70, 1.04, mats["dark"])
    _pair("%s_WingStay" % spec["title"], root, coll, 0.22, 0.28, -l + 0.02, -l + 0.10, 0.48, 0.94, mats["chrome"])
    _box("%s_Stripe" % spec["title"], root, coll, -0.10, 0.10, -l + 0.20, l - 0.10, 0.50, 0.56, mats["dark"])
    for sx, tag in ((-0.62, "L"), (0.62, "R")):
        _cyl("%s_Roundel%s" % (spec["title"], tag), root, coll, 0.12, 0.02, (sx, 0.10, 0.51), (0.0, 0.0, 0.0), mats["glow"], 12)
    _interior(root, coll, spec, mats, visor - 0.04, 0.50)
    _fenders(root, coll, spec, paint)
    _grille(root, coll, spec, mats, l, 0.30, 0.48)
    _bumpers(root, coll, spec, mats, l, -l, 0.18)
    _mirrors(root, coll, spec, mats, 0.72, visor - 0.06)
    _exhaust(root, coll, spec, mats, -l)
    _lip(root, coll, spec, mats["glow"], -l, l, 0.49)
    _lights(root, coll, spec, mats, l, -l, 0.44)


def _build_wagon(root, coll, spec, paint, mats) -> None:
    w, l = spec["half_w"], spec["half_l"]
    cab = _cabin(spec)
    belt = 0.78
    rear = -l + 0.16
    _box("%s_Hull" % spec["title"], root, coll, -w, w, -l, l, 0.26, belt, paint)
    _box("%s_Hood" % spec["title"], root, coll, -w * 0.92, w * 0.92, cab["visor_y"], l - 0.06, belt - 0.04, belt + 0.10, paint)
    _greenhouse(root, coll, spec, paint, mats, belt, rear)
    _box("%s_Drip" % spec["title"], root, coll, -w * 0.92, w * 0.92, rear, cab["visor_y"], cab["roof_top"], cab["roof_top"] + 0.03, mats["chrome"])
    _pair("%s_RoofRail" % spec["title"], root, coll, 0.28, 0.34, rear + 0.20, cab["visor_y"] - 0.20, cab["roof_top"], cab["roof_top"] + 0.05, mats["chrome"])
    for i, y in enumerate((-0.55, 0.05, 0.55)):
        _box("%s_Crossbar%s" % (spec["title"], i), root, coll, -0.34, 0.34, y, y + 0.04, cab["roof_top"] + 0.03, cab["roof_top"] + 0.07, mats["chrome"])
    _pair("%s_Wood" % spec["title"], root, coll, w - 0.03, w + 0.02, -l + 0.30, cab["visor_y"] - 0.12, 0.42, 0.70, mats["wood"])
    _box("%s_BeltChrome" % spec["title"], root, coll, -w - 0.01, w + 0.01, -l + 0.10, l - 0.10, belt - 0.02, belt + 0.02, mats["chrome"])
    _fenders(root, coll, spec, paint)
    _handles(root, coll, spec, mats, 0.10, 0.28, belt + 0.16)
    _handles(root, coll, spec, mats, -0.55, -0.38, belt + 0.16)
    _grille(root, coll, spec, mats, l, 0.40, 0.64)
    _bumpers(root, coll, spec, mats, l, -l, 0.22)
    _exhaust(root, coll, spec, mats, -l)
    _lip(root, coll, spec, mats["glow"], -l, l, belt - 0.04)
    _lights(root, coll, spec, mats, l, -l, 0.54)


def _build_pickup(root, coll, spec, paint, mats) -> None:
    w, l = spec["half_w"], spec["half_l"]
    cab = _cabin(spec)
    belt = 0.90
    cab_rear = 0.16
    _box("%s_Hull" % spec["title"], root, coll, -w, w, -l, l, 0.34, belt, paint)
    _box("%s_Hood" % spec["title"], root, coll, -w * 0.90, w * 0.90, cab["visor_y"], l - 0.10, belt - 0.02, belt + 0.14, paint)
    _greenhouse(root, coll, spec, paint, mats, belt, cab_rear)
    _box("%s_BedFloor" % spec["title"], root, coll, -w * 0.84, w * 0.84, -l + 0.12, cab_rear - 0.04, belt, belt + 0.06, mats["dark"])
    _pair("%s_BedRail" % spec["title"], root, coll, w * 0.84, w * 0.92, -l + 0.12, cab_rear - 0.04, belt, belt + 0.42, paint)
    _box("%s_Tailgate" % spec["title"], root, coll, -w * 0.86, w * 0.86, -l, -l + 0.08, belt, belt + 0.40, paint)
    _box("%s_TailHandle" % spec["title"], root, coll, -0.16, 0.16, -l - 0.02, -l + 0.02, belt + 0.16, belt + 0.22, mats["chrome"])
    for i, y in enumerate((-1.55, -1.10, -0.65, -0.20)):
        _box("%s_Slat%s" % (spec["title"], i), root, coll, -w * 0.78, w * 0.78, y, y + 0.05, belt + 0.05, belt + 0.08, mats["dark"])
    _box("%s_Crate" % spec["title"], root, coll, -0.28, 0.28, -0.55, -0.05, belt + 0.06, belt + 0.36, mats["dark"])
    _pair("%s_Step" % spec["title"], root, coll, w * 0.70, w + 0.08, 0.22, 0.95, 0.36, 0.42, mats["chrome"])
    _pair("%s_Mud" % spec["title"], root, coll, spec["wheel_x"] - 0.10, spec["wheel_x"] + 0.10, -spec["wheel_y"] - 0.42, -spec["wheel_y"] - 0.28, 0.18, 0.46, mats["dark"])
    roof_front = spec["seat_y"] + 0.02
    for i, x in enumerate((-0.28, 0.0, 0.28)):
        _box(
            "%s_CabLamp%s" % (spec["title"], i),
            root,
            coll,
            x - 0.06,
            x + 0.06,
            roof_front - 0.10,
            roof_front,
            cab["roof_top"],
            cab["roof_top"] + 0.05,
            mats["amber"],
        )
    _box("%s_Hitch" % spec["title"], root, coll, -0.08, 0.08, -l - 0.10, -l, 0.28, 0.38, mats["chrome"])
    _fenders(root, coll, spec, paint)
    _handles(root, coll, spec, mats, 0.40, 0.58, belt + 0.22)
    _grille(root, coll, spec, mats, l, 0.46, 0.80)
    _bumpers(root, coll, spec, mats, l, -l, 0.28)
    _exhaust(root, coll, spec, mats, -l)
    _lip(root, coll, spec, mats["glow"], -l, l, belt - 0.04)
    _lights(root, coll, spec, mats, l, -l, 0.66)


def _build_van(root, coll, spec, paint, mats) -> None:
    w, l = spec["half_w"], spec["half_l"]
    cab = _cabin(spec)
    belt = 0.72
    rear = -l + 0.08
    _box("%s_Hull" % spec["title"], root, coll, -w, w, -l, l, 0.30, belt, paint)
    _box("%s_Hood" % spec["title"], root, coll, -w * 0.90, w * 0.90, cab["visor_y"], l - 0.08, belt - 0.02, belt + 0.16, paint)
    _greenhouse(root, coll, spec, paint, mats, belt, rear, side_glass=False)
    _pair("%s_CargoWall" % spec["title"], root, coll, w - WALL, w, rear, cab["visor_y"] - 0.08, belt, cab["roof"], paint)
    _pair("%s_Door" % spec["title"], root, coll, w + 0.01, w + 0.04, -0.35, 0.85, belt + 0.04, cab["roof"] - 0.10, mats["dark"])
    _pair("%s_DoorTrack" % spec["title"], root, coll, w + 0.02, w + 0.05, -0.45, 0.95, belt + 0.22, belt + 0.28, mats["chrome"])
    _pair("%s_DoorGlass" % spec["title"], root, coll, w + 0.035, w + 0.05, 0.50, 0.82, belt + 0.46, cab["roof"] - 0.28, mats["glass"])
    _pair("%s_DoorHandle" % spec["title"], root, coll, w + 0.04, w + 0.06, 0.62, 0.78, belt + 0.32, belt + 0.38, mats["chrome"])
    for i, y in enumerate((-1.7, -1.05, -0.40, 0.20)):
        _box("%s_Rib%s" % (spec["title"], i), root, coll, -w * 0.86, w * 0.86, y, y + 0.08, cab["roof_top"], cab["roof_top"] + 0.06, mats["dark"])
    _pair("%s_Barn" % spec["title"], root, coll, 0.02, w * 0.88, -l - 0.02, -l + 0.04, belt + 0.06, cab["roof"] - 0.08, mats["dark"])
    _pair("%s_BarnWin" % spec["title"], root, coll, 0.16, w * 0.62, -l - 0.03, -l + 0.01, belt + 0.55, cab["roof"] - 0.28, mats["glass"])
    _pair("%s_Board" % spec["title"], root, coll, w * 0.62, w + 0.10, -0.20, 1.10, 0.32, 0.38, mats["chrome"])
    _box("%s_Badge" % spec["title"], root, coll, -0.18, 0.18, l - 0.02, l + 0.03, 1.42, 1.56, mats["chrome"])
    _fenders(root, coll, spec, paint)
    _handles(root, coll, spec, mats, 0.70, 0.88, belt + 0.28)
    _grille(root, coll, spec, mats, l, 0.40, 0.68)
    _bumpers(root, coll, spec, mats, l, -l, 0.24)
    _exhaust(root, coll, spec, mats, -l)
    _lip(root, coll, spec, mats["glow"], -l, l, cab["roof"] - 0.02)
    _lights(root, coll, spec, mats, l, -l, 0.58)


def _build_suv(root, coll, spec, paint, mats) -> None:
    w, l = spec["half_w"], spec["half_l"]
    cab = _cabin(spec)
    belt = 0.88
    rear = -l + 0.32
    _box("%s_Hull" % spec["title"], root, coll, -w, w, -l, l, 0.32, belt, paint)
    _box("%s_Cladding" % spec["title"], root, coll, -w - 0.04, w + 0.04, -l + 0.08, l - 0.08, 0.32, 0.52, mats["dark"])
    _box("%s_Hood" % spec["title"], root, coll, -w * 0.90, w * 0.90, cab["visor_y"], l - 0.16, belt - 0.02, belt + 0.12, paint)
    _greenhouse(root, coll, spec, paint, mats, belt, rear)
    _pair("%s_RoofRail" % spec["title"], root, coll, 0.34, 0.40, rear + 0.16, cab["visor_y"] - 0.16, cab["roof_top"], cab["roof_top"] + 0.06, mats["chrome"])
    _box("%s_RoofBox" % spec["title"], root, coll, -0.28, 0.28, -0.35, 0.45, cab["roof_top"] + 0.02, cab["roof_top"] + 0.28, mats["dark"])
    _pair("%s_Step" % spec["title"], root, coll, w * 0.72, w + 0.10, -0.55, 0.70, 0.34, 0.40, mats["chrome"])
    _box("%s_SkidF" % spec["title"], root, coll, -w * 0.72, w * 0.72, l - 0.06, l + 0.08, 0.26, 0.34, mats["chrome"])
    _box("%s_SkidR" % spec["title"], root, coll, -w * 0.72, w * 0.72, -l - 0.08, -l + 0.04, 0.26, 0.34, mats["chrome"])
    _cyl("%s_Spare" % spec["title"], root, coll, 0.32, 0.10, (0.0, -l - 0.08, belt + 0.28), (math.pi * 0.5, 0.0, 0.0), mats["rubber"], 14)
    _cyl("%s_SpareHub" % spec["title"], root, coll, 0.12, 0.12, (0.0, -l - 0.10, belt + 0.28), (math.pi * 0.5, 0.0, 0.0), mats["hub"], 8)
    for sx, tag in ((-0.38, "L"), (0.38, "R")):
        _box("%s_Fog%s" % (spec["title"], tag), root, coll, sx - 0.10, sx + 0.10, l + 0.04, l + 0.08, 0.38, 0.48, mats["light"])
    _cyl("%s_Antenna" % spec["title"], root, coll, 0.012, 0.36, (0.0, rear + 0.10, cab["roof_top"] + 0.18), (0.0, 0.0, 0.0), mats["chrome"], 6)
    _fenders(root, coll, spec, paint)
    _handles(root, coll, spec, mats, 0.18, 0.36, belt + 0.20)
    _handles(root, coll, spec, mats, -0.42, -0.24, belt + 0.20)
    _grille(root, coll, spec, mats, l, 0.44, 0.74)
    _bumpers(root, coll, spec, mats, l, -l, 0.26)
    _exhaust(root, coll, spec, mats, -l)
    _lip(root, coll, spec, mats["glow"], -l, l, belt - 0.02)
    _lights(root, coll, spec, mats, l, -l, 0.64)


def _build_one(spec, coll, mats):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=spec["at"])
    root = bpy.context.active_object
    root.name = spec["title"]
    root.empty_display_size = 0.4
    for old in list(root.users_collection):
        old.objects.unlink(root)
    coll.objects.link(root)
    paint = _make_mat("CarPaint_%s" % spec["title"], spec["paint"], 0.22, 0.52, 0.0)
    builders = {
        "race": _build_race,
        "wagon": _build_wagon,
        "pickup": _build_pickup,
        "van": _build_van,
        "suv": _build_suv,
    }
    builders[spec["kind"]](root, coll, spec, paint, mats)
    _wheels(root, coll, spec, mats)
    _empties(root, coll, spec)
    return root


_MARKERS = (
    "DriverSeat",
    "PassengerSeat",
    "SteeringWheel",
    "DriverView",
    "WheelFL",
    "WheelFR",
    "WheelRL",
    "WheelRR",
)


def _export(root, slug: str) -> str:
    held = tuple(root.location)
    root.location = (0.0, 0.0, 0.0)
    for child in root.children:
        base = child.name.split(".")[0]
        if base in _MARKERS:
            child.name = base
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    os.makedirs(EXPORT_DIR, exist_ok=True)
    path = os.path.join(EXPORT_DIR, "%s.glb" % slug)
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
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    _wipe()
    coll = _collection()
    mats = _shared()
    paths = []
    clearances = []
    for spec in CARS:
        root = _build_one(spec, coll, mats)
        cab = _cabin(spec)
        clearances.append(
            {
                "id": spec["id"],
                "roof": cab["roof"],
                "wheel_z": spec["wheel_z"],
                "headroom": cab["roof"] - spec["seat_z"],
                "wheel_below_roof": cab["roof"] - (spec["wheel_z"] + RIM),
            }
        )
        paths.append(_export(root, spec["id"]))
    bpy.ops.wm.save_mainfile()
    return {"exported": paths, "count": len(paths), "blend": BLEND_PATH, "clearances": clearances}


result = run()
