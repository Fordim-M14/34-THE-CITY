"""
build_passenger.py — Animasyonlu yolcu karakteri (Blender headless → assets/models/passenger.glb)
  blender -b --python tools/build_passenger.py -- --out assets/models

Özgün, düşük poligonlu insan figürü: baş, boyun, gövde, kalça, üst/alt kol, el, üst/alt bacak,
ayak, saç. Armatür + deri ağırlıkları (rijit). Animasyonlar: "idle" (nefes + ağırlık aktarma),
"walk" (bacak/kol salınımı, zıplama). Malzeme yuvaları: Skin, Hair, Shirt, Pants, Shoes —
Godot tarafında her yolcu için rastgele renklendirilir; vücut tipi ölçekle değiştirilir.
Boy: 1.72 m (ayak tabanı z=0).
"""
import bpy, bmesh, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blender_common import *
from mathutils import Vector, Quaternion, Euler

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = "assets/models"
for i, a in enumerate(argv):
    if a == "--out":
        OUT = argv[i + 1]

reset()
scene = bpy.context.scene
scene.render.fps = 24

M = {
    "Skin": mat("Skin", (0.85, 0.66, 0.55, 1), roughness=0.65),
    "Hair": mat("Hair", (0.15, 0.1, 0.07, 1), roughness=0.75),
    "Shirt": mat("Shirt", (0.25, 0.35, 0.6, 1), roughness=0.9),
    "Pants": mat("Pants", (0.15, 0.16, 0.2, 1), roughness=0.9),
    "Shoes": mat("Shoes", (0.08, 0.08, 0.09, 1), roughness=0.6),
    "Eyes": mat("Eyes", (0.05, 0.04, 0.04, 1), roughness=0.2),
    "Jacket": mat("Jacket", (0.2, 0.2, 0.22, 1), roughness=0.85),
    "Bag": mat("Bag", (0.12, 0.12, 0.13, 1), roughness=0.8),
    "Phone": mat("Phone", (0.05, 0.05, 0.05, 1), roughness=0.3, emission=(0.6, 0.7, 0.9, 1), emission_strength=0.8),
}
for m in M.values():
    m.use_backface_culling = True

# ---------------------------------------------------------------------------
# Vücut parçaları: (ad, kemik, malzeme, tür, boyut/konum)

def capsule(bm, r, h, segments=16, rings=5):
    """Z ekseninde kapsül (merkez orijin), yükseklik h (uçlar dahil)."""
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings * 2, radius=r)
    verts = geom["verts"]
    half = max(0.0, h / 2 - r)
    for v in verts:
        if v.co.z > 0:
            v.co.z += half
        else:
            v.co.z -= half
    return verts


def add_part(name, bone, material, kind, size, loc, rot=(0, 0, 0)):
    bm = bmesh.new()
    if kind == "capsule":
        r, h = size
        capsule(bm, r, h)
    elif kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=size[0])
        bmesh.ops.scale(bm, vec=Vector((1.0, size[1], size[2])), verts=bm.verts)
    elif kind == "box":
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], offset=min(size) * 0.25, segments=2, affect="EDGES")
    elif kind == "torso":
        # Gövde: yassılaştırılmış kapsül, üst kısım (omuz) geniş, bel dar
        capsule(bm, size[0], size[2], segments=18, rings=6)
        for v in bm.verts:
            t = (v.co.z + size[2] / 2) / size[2]   # 0 alt .. 1 üst
            w = 0.85 + 0.35 * t
            v.co.x *= w
            v.co.y *= 0.62 * (0.9 + 0.2 * t)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    ob.data.materials.append(M[material])
    ob.location = loc
    ob.rotation_euler = rot
    ob["bone"] = bone
    return ob


# Ölçüler (m)
HIP_Z = 0.92
parts = []
parts.append(add_part("Pelvis", "hips", "Pants", "sphere", (0.19, 0.7, 0.75), (0, 0, HIP_Z - 0.04)))
parts.append(add_part("Torso", "spine", "Shirt", "torso", (0.17, 0.15, 0.52), (0, 0, HIP_Z + 0.24)))
for side, sx in (("L", -1), ("R", 1)):
    parts.append(add_part(f"Shoulder_{side}", f"upper_arm.{side}", "Shirt", "sphere", (0.075, 0.9, 0.9), (sx * 0.23, 0, HIP_Z + 0.44)))
parts.append(add_part("Neck", "neck", "Skin", "capsule", (0.05, 0.14), (0, 0, HIP_Z + 0.52)))
parts.append(add_part("Head", "head", "Skin", "sphere", (0.1, 0.92, 1.18), (0, 0, HIP_Z + 0.68)))
parts.append(add_part("HairCap", "head", "Hair", "sphere", (0.105, 0.95, 1.12), (0, -0.01, HIP_Z + 0.70)))
for side, sx in (("L", -1), ("R", 1)):
    parts.append(add_part(f"UpperArm_{side}", f"upper_arm.{side}", "Shirt", "capsule", (0.05, 0.3), (sx * 0.24, 0, HIP_Z + 0.33)))
    parts.append(add_part(f"Forearm_{side}", f"forearm.{side}", "Skin", "capsule", (0.042, 0.28), (sx * 0.25, 0.0, HIP_Z + 0.04)))
    parts.append(add_part(f"Hand_{side}", f"forearm.{side}", "Skin", "box", (0.04, 0.07, 0.1), (sx * 0.25, 0.0, HIP_Z - 0.14)))
    parts.append(add_part(f"Thigh_{side}", f"thigh.{side}", "Pants", "capsule", (0.08, 0.46), (sx * 0.1, 0, HIP_Z - 0.26)))
    parts.append(add_part(f"Shin_{side}", f"shin.{side}", "Pants", "capsule", (0.06, 0.44), (sx * 0.1, 0, HIP_Z - 0.68)))
    parts.append(add_part(f"Foot_{side}", f"shin.{side}", "Shoes", "box", (0.09, 0.24, 0.07), (sx * 0.1, 0.05, 0.035)))

# Yüz: burun, kulaklar, gözler (karakter hissi)
parts.append(add_part("Nose", "head", "Skin", "sphere", (0.018, 0.9, 1.3), (0, -0.095, HIP_Z + 0.665)))
for side, sx in (("L", -1), ("R", 1)):
    parts.append(add_part(f"Ear_{side}", "head", "Skin", "sphere", (0.02, 0.5, 1.2), (sx * 0.098, -0.01, HIP_Z + 0.67)))
    parts.append(add_part(f"Eye_{side}", "head", "Eyes", "sphere", (0.011, 1.0, 1.0), (sx * 0.035, -0.088, HIP_Z + 0.70)))
# Yaka / kemer (gövdeye detay)
parts.append(add_part("Collar", "spine", "Skin", "sphere", (0.07, 1.0, 0.5), (0, 0, HIP_Z + 0.49)))
parts.append(add_part("Belt", "hips", "Shoes", "box", (0.36, 0.2, 0.035), (0, 0, HIP_Z - 0.0)))

# Saçı kafanın üst yarısıyla sınırla (alt yarıyı kes)
hair = bpy.data.objects["HairCap"]
bm = bmesh.new()
bm.from_mesh(hair.data)
geom = [v for v in bm.verts if v.co.z < -0.02]
bmesh.ops.delete(bm, geom=geom, context="VERTS")
bm.to_mesh(hair.data)
bm.free()

# ---------------------------------------------------------------------------
# Armatür

arm_data = bpy.data.armatures.new("PassengerRig")
arm = bpy.data.objects.new("PassengerRig", arm_data)
scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")

def bone(name, head, tail, parent=None):
    b = arm_data.edit_bones.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    if parent:
        b.parent = arm_data.edit_bones[parent]
    return b

bone("hips", (0, 0, HIP_Z - 0.1), (0, 0, HIP_Z + 0.05))
bone("spine", (0, 0, HIP_Z + 0.05), (0, 0, HIP_Z + 0.45), "hips")
bone("neck", (0, 0, HIP_Z + 0.45), (0, 0, HIP_Z + 0.58), "spine")
bone("head", (0, 0, HIP_Z + 0.58), (0, 0, HIP_Z + 0.82), "neck")
for side, sx in (("L", -1), ("R", 1)):
    bone(f"upper_arm.{side}", (sx * 0.24, 0, HIP_Z + 0.46), (sx * 0.25, 0, HIP_Z + 0.18), "spine")
    bone(f"forearm.{side}", (sx * 0.25, 0, HIP_Z + 0.18), (sx * 0.25, 0, HIP_Z - 0.1), f"upper_arm.{side}")
    bone(f"thigh.{side}", (sx * 0.1, 0, HIP_Z - 0.05), (sx * 0.1, 0, HIP_Z - 0.47), "hips")
    bone(f"shin.{side}", (sx * 0.1, 0, HIP_Z - 0.47), (sx * 0.1, 0, 0.05), f"thigh.{side}")
bpy.ops.object.mode_set(mode="OBJECT")

# Varyant parçaları (ayrı skinli mesh'ler; Godot adına göre açıp kapatır):
#   HairLong (uzun saç), Backpack (sırt çantası), Handbag (el çantası, sol el), Phone (sağ el), Jacket (ceket)
variants = []
variants.append(add_part("HairLong", "head", "Hair", "sphere", (0.108, 0.98, 1.14), (0, -0.015, HIP_Z + 0.70)))
variants.append(add_part("HairLongBack", "head", "Hair", "box", (0.16, 0.08, 0.26), (0, 0.075, HIP_Z + 0.56)))
variants.append(add_part("Backpack", "spine", "Bag", "box", (0.3, 0.14, 0.4), (0, 0.17, HIP_Z + 0.22)))
variants.append(add_part("BackpackStrapL", "spine", "Bag", "box", (0.04, 0.12, 0.3), (-0.13, 0.03, HIP_Z + 0.35)))
variants.append(add_part("BackpackStrapR", "spine", "Bag", "box", (0.04, 0.12, 0.3), (0.13, 0.03, HIP_Z + 0.35)))
variants.append(add_part("Handbag", "forearm.L", "Bag", "box", (0.08, 0.26, 0.2), (-0.3, 0.0, HIP_Z - 0.22)))
variants.append(add_part("HandbagStrap", "forearm.L", "Bag", "box", (0.02, 0.02, 0.14), (-0.3, 0.0, HIP_Z - 0.06)))
variants.append(add_part("Phone", "forearm.R", "Phone", "box", (0.07, 0.012, 0.14), (0.25, -0.06, HIP_Z - 0.16)))
variants.append(add_part("Jacket", "spine", "Jacket", "torso", (0.185, 0.16, 0.5), (0, 0, HIP_Z + 0.23)))
variants.append(add_part("JacketSleeveL", "upper_arm.L", "Jacket", "capsule", (0.058, 0.3), (-0.24, 0, HIP_Z + 0.33)))
variants.append(add_part("JacketSleeveR", "upper_arm.R", "Jacket", "capsule", (0.058, 0.3), (0.24, 0, HIP_Z + 0.33)))
# Saç (uzun) alt yarısını kes
hl = bpy.data.objects["HairLong"]
bm = bmesh.new()
bm.from_mesh(hl.data)
geom = [v for v in bm.verts if v.co.z < -0.03 and v.co.y < 0.03]
bmesh.ops.delete(bm, geom=geom, context="VERTS")
bm.to_mesh(hl.data)
bm.free()

# Parçaları tek mesh'te birleştir, vertex gruplarıyla rijit ağırlık
for ob in parts + variants:
    vg = ob.vertex_groups.new(name=ob["bone"])
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
bpy.ops.object.select_all(action="DESELECT")
for ob in parts:
    ob.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
body = bpy.context.active_object
body.name = "PassengerBody"
body.parent = arm
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
# UV (basit kutu)
uv_box_project(body, 2.0)
# Varyant grupları: aynı adlı tek nesnelerde birleştir (HairLong+Back, Backpack+straps, Handbag+strap, Jacket+sleeves)
variant_groups = {"HairLong": ["HairLong", "HairLongBack"], "Backpack": ["Backpack", "BackpackStrapL", "BackpackStrapR"],
                  "Handbag": ["Handbag", "HandbagStrap"], "Phone": ["Phone"], "Jacket": ["Jacket", "JacketSleeveL", "JacketSleeveR"]}
variant_objs = []
for gname, names in variant_groups.items():
    objs = [bpy.data.objects[n] for n in names]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    vo = bpy.context.active_object
    vo.name = gname
    vo.parent = arm
    m2 = vo.modifiers.new("Armature", "ARMATURE")
    m2.object = arm
    uv_box_project(vo, 2.0)
    variant_objs.append(vo)

# ---------------------------------------------------------------------------
# Animasyonlar

def set_pose(frame, rots):
    """rots: {kemik: (rx, ry, rz) derece}"""
    for name, (rx, ry, rz) in rots.items():
        pb = arm.pose.bones[name]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ")
        pb.keyframe_insert("rotation_euler", frame=frame)


def set_loc(frame, name, loc):
    pb = arm.pose.bones[name]
    pb.location = Vector(loc)
    pb.keyframe_insert("location", frame=frame)


def make_action(name, length, poses, hip_bob=0.0):
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for frame, rots in poses:
        set_pose(frame, rots)
        if hip_bob > 0.0:
            # Kalça: iki adımda iki kez zıplama
            t = frame / length
            set_loc(frame, "hips", (0, 0, -abs(math.sin(t * math.pi * 2)) * hip_bob))
    # Döngü için son kare = ilk kare
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
        mod = fc.modifiers.new("CYCLES")
    act.frame_range = (0, length)
    act.use_frame_range = True
    return act


# Yürüme döngüsü (24 kare = 1 s, iki adım)
A = 32   # bacak salınımı
B = 25   # kol salınımı
walk = make_action("walk", 24, [
    (0,  {"thigh.L": (-A, 0, 0), "thigh.R": (A, 0, 0), "shin.L": (0, 0, 0), "shin.R": (35, 0, 0),
          "upper_arm.L": (B, 0, 0), "upper_arm.R": (-B, 0, 0), "forearm.L": (-20, 0, 0), "forearm.R": (-35, 0, 0),
          "spine": (3, 0, 2), "head": (-2, 0, 0)}),
    (6,  {"thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0), "shin.L": (5, 0, 0), "shin.R": (50, 0, 0),
          "upper_arm.L": (0, 0, 0), "upper_arm.R": (0, 0, 0), "forearm.L": (-25, 0, 0), "forearm.R": (-25, 0, 0),
          "spine": (3, 0, 0), "head": (-2, 0, 0)}),
    (12, {"thigh.L": (A, 0, 0), "thigh.R": (-A, 0, 0), "shin.L": (35, 0, 0), "shin.R": (0, 0, 0),
          "upper_arm.L": (-B, 0, 0), "upper_arm.R": (B, 0, 0), "forearm.L": (-35, 0, 0), "forearm.R": (-20, 0, 0),
          "spine": (3, 0, -2), "head": (-2, 0, 0)}),
    (18, {"thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0), "shin.L": (50, 0, 0), "shin.R": (5, 0, 0),
          "upper_arm.L": (0, 0, 0), "upper_arm.R": (0, 0, 0), "forearm.L": (-25, 0, 0), "forearm.R": (-25, 0, 0),
          "spine": (3, 0, 0), "head": (-2, 0, 0)}),
    (24, {"thigh.L": (-A, 0, 0), "thigh.R": (A, 0, 0), "shin.L": (0, 0, 0), "shin.R": (35, 0, 0),
          "upper_arm.L": (B, 0, 0), "upper_arm.R": (-B, 0, 0), "forearm.L": (-20, 0, 0), "forearm.R": (-35, 0, 0),
          "spine": (3, 0, 2), "head": (-2, 0, 0)}),
], hip_bob=0.035)

idle = make_action("idle", 72, [
    (0,  {"spine": (0, 0, 0), "head": (0, 0, 0), "upper_arm.L": (3, 0, 4), "upper_arm.R": (3, 0, -4), "forearm.L": (-8, 0, 0), "forearm.R": (-8, 0, 0), "thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0), "shin.L": (0, 0, 0), "shin.R": (0, 0, 0)}),
    (24, {"spine": (1.5, 0, 1.5), "head": (-3, 12, 0), "upper_arm.L": (4, 0, 5), "upper_arm.R": (2, 0, -4), "forearm.L": (-10, 0, 0), "forearm.R": (-6, 0, 0), "thigh.L": (0, 0, 1), "thigh.R": (0, 0, -1), "shin.L": (0, 0, 0), "shin.R": (0, 0, 0)}),
    (48, {"spine": (0.5, 0, -1.5), "head": (2, -10, 0), "upper_arm.L": (2, 0, 4), "upper_arm.R": (4, 0, -5), "forearm.L": (-6, 0, 0), "forearm.R": (-10, 0, 0), "thigh.L": (0, 0, -1), "thigh.R": (0, 0, 1), "shin.L": (0, 0, 0), "shin.R": (0, 0, 0)}),
    (72, {"spine": (0, 0, 0), "head": (0, 0, 0), "upper_arm.L": (3, 0, 4), "upper_arm.R": (3, 0, -4), "forearm.L": (-8, 0, 0), "forearm.R": (-8, 0, 0), "thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0), "shin.L": (0, 0, 0), "shin.R": (0, 0, 0)}),
])

# Oturma (72 kare, hafif nefes/baş hareketi) — koltukta: uyluk -85°, diz +85°
SIT = {"thigh.L": (-85, 0, 4), "thigh.R": (-85, 0, -4), "shin.L": (88, 0, 0), "shin.R": (88, 0, 0),
       "upper_arm.L": (10, 0, 6), "upper_arm.R": (10, 0, -6), "forearm.L": (-30, 0, 0), "forearm.R": (-30, 0, 0)}
sit = make_action("sit", 72, [
    (0,  dict(SIT, spine=(4, 0, 0), head=(0, 0, 0))),
    (24, dict(SIT, spine=(5, 0, 1), head=(-4, 14, 0))),
    (48, dict(SIT, spine=(3.5, 0, -1), head=(3, -12, 0))),
    (72, dict(SIT, spine=(4, 0, 0), head=(0, 0, 0))),
])
SITP = dict(SIT, **{"upper_arm.R": (25, 0, -10), "forearm.R": (-95, 0, 15), "upper_arm.L": (12, 0, 8), "forearm.L": (-60, 0, 0)})
sit_phone = make_action("sit_phone", 72, [
    (0,  dict(SITP, spine=(8, 0, 0), head=(26, 0, 0))),
    (36, dict(SITP, spine=(9, 0, 1), head=(28, 4, 0))),
    (72, dict(SITP, spine=(8, 0, 0), head=(26, 0, 0))),
])
STP = {"thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0), "shin.L": (0, 0, 0), "shin.R": (0, 0, 0),
       "upper_arm.L": (4, 0, 5), "forearm.L": (-15, 0, 0), "upper_arm.R": (22, 0, -8), "forearm.R": (-105, 0, 12)}
stand_phone = make_action("stand_phone", 72, [
    (0,  dict(STP, spine=(4, 0, 0), head=(24, 0, 0))),
    (36, dict(STP, spine=(5, 0, 1.5), head=(26, 3, 0))),
    (72, dict(STP, spine=(4, 0, 0), head=(24, 0, 0))),
])
# Direğe tutunarak ayakta (sağ kol yukarı)
HOLD = {"thigh.L": (0, 0, 0), "thigh.R": (0, 0, 0), "shin.L": (0, 0, 0), "shin.R": (0, 0, 0),
        "upper_arm.L": (3, 0, 4), "forearm.L": (-8, 0, 0), "upper_arm.R": (-150, 0, -20), "forearm.R": (-20, 0, 0)}
stand_hold = make_action("stand_hold", 72, [
    (0,  dict(HOLD, spine=(0, 0, 0), head=(0, 0, 0))),
    (36, dict(HOLD, spine=(1, 0, 1.5), head=(-3, 10, 0))),
    (72, dict(HOLD, spine=(0, 0, 0), head=(0, 0, 0))),
])

# NLA'ya it (tüm action'lar dışa aktarılsın)
arm.animation_data.action = None
for act in (idle, walk, sit, sit_phone, stand_phone, stand_hold):
    track = arm.animation_data.nla_tracks.new()
    track.name = act.name
    strip = track.strips.new(act.name, 0, act)
    strip.name = act.name

bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
body.select_set(True)
for vo in variant_objs:
    vo.select_set(True)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "passenger.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                          export_yup=True, export_materials="EXPORT", export_animations=True, export_skins=True,
                          export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=2,
                          export_lights=False, export_cameras=False)
print("[GLB]", path, os.path.getsize(path) // 1024, "KB")
