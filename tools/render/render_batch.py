"""
Renders the HD muscle images for every exercise (front + back) with Blender (bpy).

    pip install bpy
    python render_batch.py <MuscularSystem100.fbx> <SkeletalSystem100.fbx> <repo root> <out dir> [exercise ids...]

Model: Z-Anatomy (CC BY-SA 4.0), based on BodyParts3D (CC BY-SA 2.1 JP).
"""
import bpy, sys, json, math, os
from mathutils import Vector

fbx, skel, repo, outdir = sys.argv[1:5]
only = set(sys.argv[5:])
here = os.path.dirname(os.path.abspath(__file__))
MESHMAP = {k: v for k, v in json.load(open(os.path.join(here, "muscle_meshes.json"))).items() if not k.startswith("_")}
exercises = json.load(open(os.path.join(repo, "IronLog/Resources/Data/exercises.json")))["exercises"]
SAMPLES = int(os.environ.get("SAMPLES", "40"))
RES = (750, 1000)

FRONT_MUSCLES = {"upper_chest", "chest", "front_delts", "side_delts", "biceps", "forearms", "abs", "obliques", "quads", "adductors"}
LEGS = {"quads", "hamstrings", "glutes", "adductors", "calves"}
CORE = {"abs", "obliques", "lower_back"}

# ---------- scene setup (once) ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
HIDE = ("fascia", "bursa", "aponeuro", "sheath", "retinacul", "tendon", "ligament", "septum", "galea", "fat",
        "membrane", "cross section", "iliotibial")
meshes = []
for o in list(bpy.data.objects):
    if o.type != "MESH":
        continue
    if any(h in o.name.lower() for h in HIDE):
        bpy.data.objects.remove(o, do_unlink=True)
    else:
        meshes.append(o)

def zr(o):
    zs = [(o.matrix_world @ Vector(c)).z for c in o.bound_box]
    return min(zs), max(zs)

head = [o for o in meshes if zr(o)[0] > 1.50]
jaw = [o for o in meshes if o not in head and ((zr(o)[0] > 1.40 and zr(o)[1] > 1.50)
       or any(k in o.name.lower() for k in ("platysma", "hyoid", "digastric")))]
hmin = Vector((1e9,) * 3); hmax = Vector((-1e9,) * 3)
for o in head:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        hmin = Vector(map(min, hmin, w)); hmax = Vector(map(max, hmax, w))
for o in head + jaw:
    meshes.remove(o); bpy.data.objects.remove(o, do_unlink=True)
hc = (hmin + hmax) / 2; hs = (hmax - hmin) / 2
bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, location=(0, hc.y + hs.y * 0.05, hc.z - hs.z * 0.02))
dummy = bpy.context.active_object
dummy.scale = (min(hs.x, hs.y * 1.1) * 0.86, hs.y * 0.92, hs.z)
for v in dummy.data.vertices:
    if v.co.z < 0:
        k = 1 + v.co.z * 0.28
        v.co.x *= k
        v.co.y = v.co.y * k - (1 - k) * 0.25
dummy.name = "Mannequin head"
meshes.append(dummy)

before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=skel)
for o in set(bpy.data.objects) - before:
    if o.type == "MESH" and any(k in o.name.lower() for k in ("sternum", "manubrium", "xiphoid", "costal cartilage", "clavicle")):
        meshes.append(o)
    else:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()

def mat(name, color, rough, spec, sss):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in b.inputs: b.inputs["Specular IOR Level"].default_value = spec
    if "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (0.4, 0.2, 0.15)
    return m
CLAY = mat("clay", (0.17, 0.175, 0.185), 0.5, 0.4, 0.05)
RED = mat("red", (0.62, 0.008, 0.02), 0.35, 0.6, 0.12)
DIM = mat("dim", (0.20, 0.035, 0.045), 0.45, 0.4, 0.05)
for o in meshes:
    for p in o.data.polygons: p.use_smooth = True

mins = Vector((1e9,) * 3); maxs = Vector((-1e9,) * 3)
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        mins = Vector(map(min, mins, w)); maxs = Vector(map(max, maxs, w))
center = (mins + maxs) / 2; H = (maxs - mins).z

scene = bpy.context.scene
scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES; scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = RES
scene.render.image_settings.file_format = "JPEG"; scene.render.image_settings.quality = 86
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = -0.9
looks = [i.identifier for i in scene.view_settings.bl_rna.properties["look"].enum_items]
for want in ("AgX - Punchy", "AgX - Medium High Contrast"):
    if want in looks: scene.view_settings.look = want; break
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
# matches the app's card colour (#1C1E22 → linear)
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.0103, 0.0122, 0.0160, 1)

def base(name):
    return name.rsplit(".", 1)[0].lower() if name[-2:] in (".l", ".r") else name.lower()

def matches(name, muscle_ids):
    b = base(name)
    for mid in muscle_ids:
        for p in MESHMAP.get(mid, []):
            if (p.startswith("=") and b == p[1:]) or (not p.startswith("=") and p in b):
                return True
    return False

def setup_camera_and_lights(view, zrange, yaw_deg):
    for o in list(bpy.data.objects):
        if o.type in ("CAMERA", "LIGHT"): bpy.data.objects.remove(o, do_unlink=True)
    d = -1 if view == "front" else 1
    lo, hi = zrange
    target = Vector((center.x, center.y, mins.z + H * (lo + hi) / 2))
    dist = H * (hi - lo) * 2.55
    cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 85
    cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
    yaw = math.radians(yaw_deg)
    cam.location = Vector((target.x + math.sin(yaw) * dist, target.y + d * math.cos(yaw) * dist, target.z + H * 0.02))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    def light(name, loc, energy, color, size):
        ld = bpy.data.lights.new(name, "AREA"); ld.energy = energy; ld.color = color; ld.size = size
        lo_ = bpy.data.objects.new(name, ld); scene.collection.objects.link(lo_); lo_.location = loc
        lo_.rotation_euler = (target - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    light("key", (target.x - H * 0.9, target.y + d * H * 1.4, target.z + H * 0.9), 150 * H * H, (1, 0.97, 0.93), H * 0.8)
    light("fill", (target.x + H * 1.1, target.y + d * H * 1.2, target.z), 45 * H * H, (0.85, 0.9, 1.0), H)
    light("rimL", (target.x - H * 0.8, target.y - d * H * 0.9, target.z + H * 0.4), 260 * H * H, (0.75, 0.82, 1.0), H * 0.4)
    light("rimR", (target.x + H * 0.8, target.y - d * H * 0.9, target.z + H * 0.4), 260 * H * H, (0.75, 0.82, 1.0), H * 0.4)

def region(ex):
    prim = set(ex["primary"])
    if not prim: return (0.0, 1.0)
    if prim <= LEGS: return (0.02, 0.62) if not prim <= {"calves"} else (0.0, 0.42)
    if prim <= CORE: return (0.36, 0.86)
    return (0.46, 0.98)

os.makedirs(outdir, exist_ok=True)
for ex in exercises:
    if only and ex["id"] not in only: continue
    for o in meshes:
        m = RED if matches(o.name, ex["primary"]) else DIM if matches(o.name, ex["secondary"]) else CLAY
        o.data.materials.clear(); o.data.materials.append(m)
    for view in ("front", "back"):
        setup_camera_and_lights(view, region(ex), -18 if view == "front" else 18)
        scene.render.filepath = os.path.join(outdir, f"muscles_{ex['id']}_{view}.jpg")
        bpy.ops.render.render(write_still=True)
        print("WROTE", scene.render.filepath, flush=True)
