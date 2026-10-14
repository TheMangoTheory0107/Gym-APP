"""
Exports the interactive 3D body used in the app (IronLog/Resources/Models/MuscleBody.usdz).

    python export_3d.py <MuscularSystem100.fbx> <SkeletalSystem100.fbx> <out.usdz> [decimate_ratio]

Each muscle group from muscles.json becomes ONE mesh named "m_<muscle id>" (e.g. m_chest, m_lats);
everything else is merged into "m_body". The app recolours those meshes per exercise.
Model: Z-Anatomy (CC BY-SA 4.0), based on BodyParts3D (CC BY-SA 2.1 JP).
"""
import bpy, sys, json, os
from mathutils import Vector

fbx, skel, out = sys.argv[1:4]
ratio = float(sys.argv[4]) if len(sys.argv) > 4 else 0.1
here = os.path.dirname(os.path.abspath(__file__))
MESHMAP = {k: v for k, v in json.load(open(os.path.join(here, "muscle_meshes.json"))).items() if not k.startswith("_")}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
HIDE = ("fascia", "bursa", "aponeuro", "sheath", "retinacul", "tendon", "ligament", "septum", "galea", "fat",
        "membrane", "cross section", "iliotibial")
meshes = []
for o in list(bpy.data.objects):
    if o.type != "MESH":
        if o.type != "EMPTY": bpy.data.objects.remove(o, do_unlink=True)
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
bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, location=(0, hc.y + hs.y * 0.05, hc.z - hs.z * 0.02))
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

def base(name):
    return name.rsplit(".", 1)[0].lower() if name[-2:] in (".l", ".r") else name.lower()

def group_of(name):
    b = base(name)
    for mid, pats in MESHMAP.items():
        for p in pats:
            if (p.startswith("=") and b == p[1:]) or (not p.startswith("=") and p in b):
                return mid
    return "body"

# Decimate every mesh, apply, then join per group.
groups = {}
for o in meshes:
    if len(o.data.polygons) > 60:
        mod = o.modifiers.new("dec", "DECIMATE")
        mod.ratio = ratio
    groups.setdefault(group_of(o.name), []).append(o)

depsgraph = bpy.context.evaluated_depsgraph_get()
final = []
for gid, objs in groups.items():
    # Bake each object (modifiers + world transform) into one new mesh.
    import bmesh
    bm = bmesh.new()
    for o in objs:
        ev = o.evaluated_get(depsgraph)
        me = ev.to_mesh()
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        ev.to_mesh_clear()
    mesh = bpy.data.meshes.new(f"m_{gid}")
    bm.to_mesh(mesh); bm.free()
    for p in mesh.polygons: p.use_smooth = True
    mat = bpy.data.materials.new(f"mat_{gid}")
    mesh.materials.append(mat)
    ob = bpy.data.objects.new(f"m_{gid}", mesh)
    bpy.context.scene.collection.objects.link(ob)
    final.append(ob)

for o in list(bpy.data.objects):
    if o not in final: bpy.data.objects.remove(o, do_unlink=True)

tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in final)
print("GROUPS", sorted(o.name for o in final))
print("TRIS", tris)

bpy.ops.wm.usd_export(filepath=out, export_materials=True, export_uvmaps=False, export_normals=True,
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                      export_global_up_selection="Y", triangulate_meshes=True, export_animation=False)
print("WROTE", out, os.path.getsize(out))
