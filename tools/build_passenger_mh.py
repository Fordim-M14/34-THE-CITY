"""
build_passenger_mh.py — MakeHuman (CC0) taban mesh + hedefler + iskeletten gerçekçi yolcu karakterleri.
  blender -b --python tools/build_passenger_mh.py -- --mh /path/to/makehuman/makehuman/data --out assets/models

Kaynak: makehumancommunity/makehuman deposu `makehuman/data` (base.obj, targets/macrodetails, rigs/default.*,
eyes/low-poly) — tüm bu varlıklar **CC0 1.0** (LICENSE.ASSETS.md). Kod tarafı AGPL'dir ama burada
MakeHuman programı kullanılmaz; yalnızca CC0 veri dosyaları bu betikle okunur.

Üretilen her GLB: gövde (deri), Shirt/Pants/Shoes (helper-tights ve ayak yüzeylerinden), Jacket,
HairCap/HairLong (helper-hair), gözler (beyaz + iris), çanta/telefon aksesuarları; MakeHuman
iskeleti (163 kemik, CC0 ağırlıklar); animasyonlar: idle, walk, sit, sit_phone, stand_phone, stand_hold.
Dekimasyon ile ~6–8k üçgen/karakter.

Varyantlar: cinsiyet × yaş × etnik köken × kilo (makro hedef karışımı) → passenger_<ad>.glb
"""
import bpy, bmesh, sys, os, math, json, random
from mathutils import Vector, Euler, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blender_common import mat, reset, uv_box_project

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
MH = "/tmp/mh/makehuman/data"
OUT = "assets/models"
DECIMATE = 0.18
for i, a in enumerate(argv):
    if a == "--mh":
        MH = argv[i + 1]
    if a == "--out":
        OUT = argv[i + 1]
    if a == "--decimate":
        DECIMATE = float(argv[i + 1])

S = 0.1   # MakeHuman desimetre → metre

# ---------------------------------------------------------------------------
# OBJ okuma (gruplu)

def read_obj(path):
    verts, uvs, groups = [], [], {}
    g = "default"
    for line in open(path, encoding="utf-8", errors="ignore"):
        if line.startswith("v "):
            verts.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("vt "):
            p = line.split()
            uvs.append((float(p[1]), float(p[2])))
        elif line.startswith("g "):
            g = line.split()[1]
        elif line.startswith("f "):
            face = []
            for t in line.split()[1:]:
                parts = t.split("/")
                vi = int(parts[0]) - 1
                ti = int(parts[1]) - 1 if len(parts) > 1 and parts[1] else -1
                face.append((vi, ti))
            groups.setdefault(g, []).append(face)
    return verts, uvs, groups


def read_target(path):
    out = []
    for line in open(path, encoding="utf-8", errors="ignore"):
        if line.startswith("#") or not line.strip():
            continue
        p = line.split()
        out.append((int(p[0]), float(p[1]), float(p[2]), float(p[3])))
    return out


def apply_targets(verts, targets):
    v = [list(x) for x in verts]
    for path, w in targets:
        if w == 0.0 or not os.path.exists(path):
            continue
        for (i, dx, dy, dz) in read_target(path):
            v[i][0] += dx * w
            v[i][1] += dy * w
            v[i][2] += dz * w
    return v


def to_blender(p):
    """MakeHuman (x sağ, y yukarı, z öne) → Blender (x, -z, y), metre; ayak tabanı z=0'a taşınır (sonra)."""
    return Vector((p[0] * S, -p[2] * S, p[1] * S))


# ---------------------------------------------------------------------------

def build_mesh_object(name, verts_bl, uvs, faces, material, vmap_out):
    """faces: [(vi, ti), ...] listesi; vmap_out: orijinal vi → yerel indeks sözlüğü (ağırlıklar için)."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    local = {}
    for face in faces:
        bverts = []
        for (vi, ti) in face:
            if vi not in local:
                local[vi] = bm.verts.new(verts_bl[vi])
            bverts.append(local[vi])
        try:
            f = bm.faces.new(bverts)
        except ValueError:
            continue
        for loop, (vi, ti) in zip(f.loops, face):
            loop[uv_layer].uv = uvs[ti] if ti >= 0 else (0.0, 0.0)
        f.smooth = True
    bm.verts.index_update()
    for vi, bv in local.items():
        vmap_out[vi] = bv.index
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(material)
    return ob


def add_weights(ob, vmap, weights, bone_filter=None):
    for bone, lst in weights.items():
        if bone_filter and bone not in bone_filter:
            continue
        vg = None
        for (vi, w) in lst:
            if vi in vmap:
                if vg is None:
                    vg = ob.vertex_groups.new(name=bone)
                vg.add([vmap[vi]], w, "REPLACE")


def displace(ob, amount):
    mod = ob.modifiers.new("Offset", "DISPLACE")
    mod.strength = amount
    mod.mid_level = 0.0
    mod.direction = "NORMAL"


def decimate(ob, ratio):
    mod = ob.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = ratio
    mod.use_collapse_triangulate = True


def apply_mods(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


# ---------------------------------------------------------------------------
# Karakter üretimi

def build_character(tag, targets, hair_long, seed):
    reset()
    scene = bpy.context.scene
    scene.render.fps = 24
    rnd = random.Random(seed)
    M = {
        "Skin": mat("Skin", (0.85, 0.66, 0.55, 1), roughness=0.55),
        "Hair": mat("Hair", (0.15, 0.1, 0.07, 1), roughness=0.8),
        "Shirt": mat("Shirt", (0.25, 0.35, 0.6, 1), roughness=0.9, tex="seat_fabric", tex_scale=6.0, normal_strength=0.4),
        "Pants": mat("Pants", (0.15, 0.16, 0.2, 1), roughness=0.85, tex="seat_fabric", tex_scale=6.0, normal_strength=0.4),
        "Shoes": mat("Shoes", (0.08, 0.08, 0.09, 1), roughness=0.5),
        "Eyes": mat("Eyes", (0.9, 0.9, 0.9, 1), roughness=0.15),
        "Iris": mat("Iris", (0.08, 0.06, 0.05, 1), roughness=0.2),
        "Lips": mat("Lips", (0.6, 0.3, 0.3, 1), roughness=0.5),
        "Jacket": mat("Jacket", (0.2, 0.2, 0.22, 1), roughness=0.85, tex="seat_fabric", tex_scale=5.0, normal_strength=0.5),
        "Bag": mat("Bag", (0.12, 0.12, 0.13, 1), roughness=0.8),
        "Phone": mat("Phone", (0.05, 0.05, 0.05, 1), roughness=0.3, emission=(0.6, 0.7, 0.9, 1), emission_strength=0.8),
    }
    for m in M.values():
        m.use_backface_culling = True
    verts, uvs, groups = read_obj(os.path.join(MH, "3dobjs", "base.obj"))
    verts = apply_targets(verts, targets)
    vbl = [to_blender(p) for p in verts]
    zmin = min(v.z for v in vbl)
    for v in vbl:
        v.z -= zmin   # ayak tabanı z=0
    # Eklem konumları (morf sonrası)
    skel = json.load(open(os.path.join(MH, "rigs", "default.mhskel")))
    weights = json.load(open(os.path.join(MH, "rigs", "default_weights.mhw")))["weights"]
    joints = {}
    for jname, idxs in skel["joints"].items():
        acc = Vector((0, 0, 0))
        for i in idxs:
            acc += vbl[i]
        joints[jname] = acc / max(1, len(idxs))

    # Yüzey grupları
    body_faces = groups["body"]
    tights = groups["helper-tights"]
    # Saç: helper-hair uzun saç yardımcısıdır (yüzü kapatır); kısa saç için kafatası derisi yüzeyleri
    # kullanılır: göz hizasının üstü + kafanın arka yarısı (ense çizgisine kadar)
    eye_z = joints["eye.L____head"].z
    head_c = joints["head____head"]
    hair_faces, brow_faces, lip_faces = [], [], []
    mouth_z = eye_z - 0.072
    for f in body_faces:
        zs = [vbl[vi].z for (vi, _) in f]
        ys = [vbl[vi].y for (vi, _) in f]
        xs = [vbl[vi].x for (vi, _) in f]
        zc = sum(zs) / len(zs)
        yc = sum(ys) / len(ys)
        xc = sum(xs) / len(xs)
        if zc < head_c.z - 0.06 and zc > eye_z - 0.16:
            # yüz/baş dışı değil; baş bölgesi aşağıda ense: zc > boyun
            pass
        # Saç derisi: alın çizgisi üstü (öne gidildikçe yükselen eşik) ve başın arka yarısı
        front = -(yc - head_c.y)            # öne doğru pozitif
        limit = eye_z + 0.05 + max(0.0, front - 0.04) * 1.2
        if zc > limit and zc < head_c.z + 0.2:
            hair_faces.append(f)
        elif yc > head_c.y + 0.015 and zc > eye_z - 0.05 and zc <= limit:
            hair_faces.append(f)        # başın arkası (enseye kadar)
        # Kaşlar: göz hizasının hemen üstü, ön yüz, göz merkezlerinin çevresi
        if eye_z + 0.022 < zc < eye_z + 0.033 and front > 0.06 and 0.014 < abs(xc) < 0.047:
            brow_faces.append(f)
        # Dudaklar: ağız çizgisi, ön orta
        if mouth_z - 0.006 < zc < mouth_z + 0.006 and front > 0.07 and abs(xc) < 0.022:
            lip_faces.append(f)
    hair_long_faces = [f for f in groups["helper-hair"] if min(vbl[vi].z for (vi, _) in f) > eye_z - 0.12 and sum(vbl[vi].y for (vi, _) in f) / len(f) > head_c.y - 0.04]
    # Vücut: ayak bölgesi ayakkabı olur (z < bilek). Bilek yüksekliği: foot.L kemik başı
    ankle_z = joints["foot.L____head"].z + 0.02
    shoe_faces = [f for f in body_faces if max(vbl[vi].z for (vi, _) in f) < ankle_z + 0.06]
    # Giysi: tights helper → gömlek/pantolon (bel: pelvis eklemi)
    waist_z = joints["spine04____head"].z - 0.02
    shirt_faces, pants_faces = [], []
    for f in tights:
        zc = sum(vbl[vi].z for (vi, _) in f) / len(f)
        (shirt_faces if zc >= waist_z else pants_faces).append(f)

    objs = {}
    vmaps = {}
    for name, faces, matkey, disp, dec in (
        ("PassengerBody", body_faces, "Skin", 0.0, DECIMATE),
        ("Shirt", shirt_faces, "Shirt", 0.012, 0.5),
        ("Pants", pants_faces, "Pants", 0.010, 0.5),
        ("Shoes", shoe_faces, "Shoes", 0.006, 0.6),
        ("Jacket", shirt_faces, "Jacket", 0.026, 1.0),
        ("HairCap", hair_faces, "Hair", 0.012, 1.0),
        ("HairLong", hair_long_faces, "Hair", 0.008, 1.0),
        ("Eyebrows", brow_faces, "Hair", 0.002, 1.0),
        ("Lips", lip_faces, "Lips", 0.0015, 1.0),
    ):
        vm = {}
        ob = build_mesh_object(name, vbl, uvs, faces, M[matkey], vm)
        if disp > 0:
            displace(ob, disp)
        if dec < 1.0:
            decimate(ob, dec)
        objs[name] = ob
        vmaps[name] = vm
    # Gözler: beyaz küre + iris (göz eklemleri)
    eye_objs = []
    for side in ("l", "r"):
        c = joints[f"eye.{side.upper()}____head"] if f"eye.{side.upper()}____head" in joints else None
        if c is None:
            continue
        for nm, r, off, mk in (("EyeBall", 0.0125, Vector((0, 0, 0)), "Eyes"), ("Iris", 0.0055, Vector((0, -0.0105, 0)), "Iris")):
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=r)
            for v in bm.verts:
                v.co += c + off
            me = bpy.data.meshes.new(f"{nm}_{side}")
            bm.to_mesh(me)
            bm.free()
            eo = bpy.data.objects.new(f"{nm}_{side}", me)
            scene.collection.objects.link(eo)
            eo.data.materials.append(M[mk])
            for p in eo.data.polygons:
                p.use_smooth = True
            eye_objs.append(eo)
    # Aksesuarlar: sırt çantası (spine02), el çantası (lowerarm01.L), telefon (lowerarm01.R)
    def acc_box(name, size, center, matkey, bone):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], offset=min(size) * 0.2, segments=2, affect="EDGES")
        for v in bm.verts:
            v.co += center
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        scene.collection.objects.link(ob)
        ob.data.materials.append(M[matkey])
        ob["bone"] = bone
        return ob
    sp = joints["spine02____head"]
    wl = joints["wrist.L____head"]
    wr = joints["wrist.R____head"]
    acc = []
    acc.append(acc_box("Backpack", (0.3, 0.14, 0.4), Vector((0, sp.y + 0.16, sp.z + 0.02)), "Bag", "spine02"))
    acc.append(acc_box("Handbag", (0.08, 0.26, 0.2), Vector((wl.x - 0.03, wl.y, wl.z - 0.16)), "Bag", "lowerarm01.L"))
    acc.append(acc_box("Phone", (0.07, 0.012, 0.14), Vector((wr.x, wr.y - 0.05, wr.z - 0.03)), "Phone", "lowerarm01.R"))

    # Modifikatörleri uygula (dekimasyon/ofset) — ağırlıklar vertex gruplarıyla korunur: önce gruplar
    all_mesh = list(objs.values()) + eye_objs + acc
    for name, ob in objs.items():
        add_weights(ob, vmaps[name], weights)
    for ob in eye_objs:
        vg = ob.vertex_groups.new(name="head")
        vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    for ob in acc:
        vg = ob.vertex_groups.new(name=ob["bone"])
        vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    for ob in all_mesh:
        if ob.modifiers:
            apply_mods(ob)

    # Armatür
    arm_data = bpy.data.armatures.new("PassengerRig")
    arm = bpy.data.objects.new("PassengerRig", arm_data)
    scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    bones = skel["bones"]
    order = []
    def visit(b):
        order.append(b)
        for c, d in bones.items():
            if d["parent"] == b:
                visit(c)
    for b, d in bones.items():
        if d["parent"] is None:
            visit(b)
    for b in order:
        d = bones[b]
        eb = arm_data.edit_bones.new(b)
        h = joints[d["head"]]
        t = joints[d["tail"]]
        if (t - h).length < 0.005:
            t = h + Vector((0, 0, 0.01))
        eb.head = h
        eb.tail = t
        eb.align_roll(Vector((0, -1, 0)))   # Z ekseni öne: X ekseni sağa → X etrafında dönüş = öne/arkaya bükülme
        if d["parent"]:
            eb.parent = arm_data.edit_bones[d["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    for ob in all_mesh:
        ob.parent = arm
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    # Bükülme işareti: upperleg01.L'i X etrafında -60° döndür; alt bacak öne (y azalır) gitmeli
    pb = arm.pose.bones["upperleg01.L"]
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = Euler((math.radians(-60), 0, 0), "XYZ")
    bpy.context.view_layer.update()
    tail_world = arm.matrix_world @ pb.tail
    rest_tail = arm.matrix_world @ arm.data.bones["upperleg01.L"].tail_local
    sign = 1.0 if tail_world.y < rest_tail.y - 0.05 else -1.0
    pb.rotation_euler = Euler((0, 0, 0), "XYZ")
    bpy.context.view_layer.update()
    print("[MH] bükülme işareti", sign)

    # Animasyonlar (eski rig adlarından MH adlarına eşleme; açı işareti otomatik)
    MAP = {"hips": "root", "spine": "spine03", "neck": "neck01", "head": "head",
           "upper_arm.L": "upperarm01.L", "upper_arm.R": "upperarm01.R", "forearm.L": "lowerarm01.L", "forearm.R": "lowerarm01.R",
           "thigh.L": "upperleg01.L", "thigh.R": "upperleg01.R", "shin.L": "lowerleg01.L", "shin.R": "lowerleg01.R"}

    def set_pose(frame, rots):
        for name, (rx, ry, rz) in rots.items():
            pb = arm.pose.bones[MAP[name]]
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler((math.radians(rx) * sign, math.radians(ry), math.radians(rz)), "XYZ")
            pb.keyframe_insert("rotation_euler", frame=frame)

    def set_loc(frame, name, loc):
        pb = arm.pose.bones[MAP[name]]
        pb.location = Vector(loc)
        pb.keyframe_insert("location", frame=frame)

    def make_action(name, length, poses, hip_bob=0.0):
        act = bpy.data.actions.new(name)
        arm.animation_data_create()
        arm.animation_data.action = act
        for frame, rots in poses:
            set_pose(frame, rots)
            if hip_bob > 0.0:
                t = frame / length
                set_loc(frame, "hips", (0, 0, -abs(math.sin(t * math.pi * 2)) * hip_bob))
        for fc in act.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
            fc.modifiers.new("CYCLES")
        act.frame_range = (0, length)
        act.use_frame_range = True
        return act

    A, B = 30, 22
    ZERO = {k: (0, 0, 0) for k in MAP if k != "hips"}
    def P(**kw):
        d = dict(ZERO)
        for k, v in kw.items():
            d[k.replace("_L", ".L").replace("_R", ".R")] = v
        return d
    walk = make_action("walk", 24, [
        (0, P(thigh_L=(-A, 0, 0), thigh_R=(A, 0, 0), shin_L=(0, 0, 0), shin_R=(35, 0, 0), upper_arm_L=(B, 0, 0), upper_arm_R=(-B, 0, 0), forearm_L=(-20, 0, 0), forearm_R=(-35, 0, 0), spine=(3, 0, 2), head=(-2, 0, 0))),
        (6, P(shin_L=(5, 0, 0), shin_R=(50, 0, 0), forearm_L=(-25, 0, 0), forearm_R=(-25, 0, 0), spine=(3, 0, 0), head=(-2, 0, 0))),
        (12, P(thigh_L=(A, 0, 0), thigh_R=(-A, 0, 0), shin_L=(35, 0, 0), upper_arm_L=(-B, 0, 0), upper_arm_R=(B, 0, 0), forearm_L=(-35, 0, 0), forearm_R=(-20, 0, 0), spine=(3, 0, -2), head=(-2, 0, 0))),
        (18, P(shin_L=(50, 0, 0), shin_R=(5, 0, 0), forearm_L=(-25, 0, 0), forearm_R=(-25, 0, 0), spine=(3, 0, 0), head=(-2, 0, 0))),
        (24, P(thigh_L=(-A, 0, 0), thigh_R=(A, 0, 0), shin_L=(0, 0, 0), shin_R=(35, 0, 0), upper_arm_L=(B, 0, 0), upper_arm_R=(-B, 0, 0), forearm_L=(-20, 0, 0), forearm_R=(-35, 0, 0), spine=(3, 0, 2), head=(-2, 0, 0))),
    ], hip_bob=0.03)
    idle = make_action("idle", 72, [
        (0, P(upper_arm_L=(3, 0, 4), upper_arm_R=(3, 0, -4), forearm_L=(-8, 0, 0), forearm_R=(-8, 0, 0))),
        (24, P(spine=(1.5, 0, 1.5), head=(-3, 12, 0), upper_arm_L=(4, 0, 5), upper_arm_R=(2, 0, -4), forearm_L=(-10, 0, 0), forearm_R=(-6, 0, 0))),
        (48, P(spine=(0.5, 0, -1.5), head=(2, -10, 0), upper_arm_L=(2, 0, 4), upper_arm_R=(4, 0, -5), forearm_L=(-6, 0, 0), forearm_R=(-10, 0, 0))),
        (72, P(upper_arm_L=(3, 0, 4), upper_arm_R=(3, 0, -4), forearm_L=(-8, 0, 0), forearm_R=(-8, 0, 0))),
    ])
    SIT = dict(thigh_L=(-85, 0, 4), thigh_R=(-85, 0, -4), shin_L=(88, 0, 0), shin_R=(88, 0, 0), upper_arm_L=(10, 0, 6), upper_arm_R=(10, 0, -6), forearm_L=(-30, 0, 0), forearm_R=(-30, 0, 0))
    sit = make_action("sit", 72, [
        (0, P(spine=(4, 0, 0), **SIT)), (24, P(spine=(5, 0, 1), head=(-4, 14, 0), **SIT)),
        (48, P(spine=(3.5, 0, -1), head=(3, -12, 0), **SIT)), (72, P(spine=(4, 0, 0), **SIT)),
    ])
    SITP = dict(SIT, upper_arm_R=(25, 0, -10), forearm_R=(-95, 0, 15), upper_arm_L=(12, 0, 8), forearm_L=(-60, 0, 0))
    sit_phone = make_action("sit_phone", 72, [
        (0, P(spine=(8, 0, 0), head=(26, 0, 0), **SITP)), (36, P(spine=(9, 0, 1), head=(28, 4, 0), **SITP)), (72, P(spine=(8, 0, 0), head=(26, 0, 0), **SITP)),
    ])
    STP = dict(upper_arm_L=(4, 0, 5), forearm_L=(-15, 0, 0), upper_arm_R=(22, 0, -8), forearm_R=(-105, 0, 12))
    stand_phone = make_action("stand_phone", 72, [
        (0, P(spine=(4, 0, 0), head=(24, 0, 0), **STP)), (36, P(spine=(5, 0, 1.5), head=(26, 3, 0), **STP)), (72, P(spine=(4, 0, 0), head=(24, 0, 0), **STP)),
    ])
    HOLD = dict(upper_arm_L=(3, 0, 4), forearm_L=(-8, 0, 0), upper_arm_R=(-150, 0, -20), forearm_R=(-20, 0, 0))
    stand_hold = make_action("stand_hold", 72, [
        (0, P(**HOLD)), (36, P(spine=(1, 0, 1.5), head=(-3, 10, 0), **HOLD)), (72, P(**HOLD)),
    ])
    arm.animation_data.action = None
    for act in (idle, walk, sit, sit_phone, stand_phone, stand_hold):
        track = arm.animation_data.nla_tracks.new()
        track.name = act.name
        strip = track.strips.new(act.name, 0, act)
        strip.name = act.name
    # Dışa aktar
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for ob in all_mesh:
        ob.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"passenger_{tag}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_materials="EXPORT", export_animations=True, export_skins=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=2,
                              export_lights=False, export_cameras=False)
    tris = sum(len(ob.data.polygons) for ob in all_mesh)
    print("[GLB]", path, os.path.getsize(path) // 1024, "KB", "yüzey:", tris)


def T(*parts):
    return os.path.join(MH, "targets", "macrodetails", *parts)


VARIANTS = [
    # tag, hedef listesi [(dosya, ağırlık)], uzun saç
    ("m_young", [(T("caucasian-male-young.target"), 0.6), (T("asian-male-young.target"), 0.25), (T("african-male-young.target"), 0.15),
                 (T("universal-male-young-averagemuscle-averageweight.target"), 1.0)], False),
    ("m_old", [(T("caucasian-male-old.target"), 0.7), (T("african-male-old.target"), 0.3),
               (T("universal-male-old-averagemuscle-maxweight.target"), 0.6), (T("universal-male-old-averagemuscle-averageweight.target"), 0.4)], False),
    ("m_heavy", [(T("caucasian-male-young.target"), 0.5), (T("asian-male-young.target"), 0.5),
                 (T("universal-male-young-averagemuscle-maxweight.target"), 1.0)], False),
    ("f_young", [(T("caucasian-female-young.target"), 0.55), (T("asian-female-young.target"), 0.3), (T("african-female-young.target"), 0.15),
                 (T("universal-female-young-averagemuscle-averageweight.target"), 1.0)], True),
    ("f_old", [(T("caucasian-female-old.target"), 0.8), (T("asian-female-old.target"), 0.2),
               (T("universal-female-old-averagemuscle-averageweight.target"), 1.0)], True),
    ("f_slim", [(T("caucasian-female-young.target"), 0.4), (T("african-female-young.target"), 0.6),
                (T("universal-female-young-averagemuscle-minweight.target"), 0.7), (T("universal-female-young-averagemuscle-averageweight.target"), 0.3)], True),
]

only = [a for a in argv if a in [v[0] for v in VARIANTS]]
for tag, targets, hair_long in VARIANTS:
    if only and tag not in only:
        continue
    build_character(tag, targets, hair_long, hash(tag) & 0xFFFF)
print("[MH] done")
