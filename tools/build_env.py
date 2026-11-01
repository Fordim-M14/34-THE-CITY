"""
build_env.py — Çevre propları (Blender headless → assets/models/props/*.glb)
  blender -b --python tools/build_env.py -- --out assets/models/props

Her prop ayrı GLB, kökü bir Empty; +Y ileri (Godot'ta -Z), +Z yukarı, ray üstü z=0.
"""
import bpy, bmesh, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blender_common import *

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = "assets/models/props"
for i, a in enumerate(argv):
    if a == "--out":
        OUT = argv[i + 1]

SEG = 10.0


def materials():
    M = {}
    M["lining"] = mat("Env_Lining", (0.78, 0.78, 0.8, 1), roughness=0.95, tex="concrete_lining", tex_scale=0.5, normal_strength=1.2)
    M["concrete"] = mat("Env_Concrete", (0.75, 0.74, 0.72, 1), roughness=0.95, tex="concrete_rough", tex_scale=0.5, normal_strength=1.0)
    M["metal"] = mat("Env_Metal", (0.7, 0.71, 0.73, 1), metallic=1.0, roughness=0.35, tex="metal_brushed", tex_scale=2.0, normal_strength=0.3)
    M["metal_dark"] = mat("Env_MetalDark", (0.2, 0.21, 0.23, 1), metallic=0.8, roughness=0.5)
    M["galv"] = mat("Env_Galvanized", (0.55, 0.57, 0.6, 1), metallic=0.9, roughness=0.55, tex="metal_brushed", tex_scale=3.0, normal_strength=0.2)
    M["paint_red"] = mat("Env_PaintRed", (0.7, 0.08, 0.06, 1), metallic=0.2, roughness=0.45)
    M["paint_green"] = mat("Env_PaintGreen", (0.1, 0.45, 0.2, 1), metallic=0.1, roughness=0.5)
    M["paint_grey"] = mat("Env_PaintGrey", (0.45, 0.46, 0.48, 1), metallic=0.3, roughness=0.5)
    M["rubber"] = mat("Env_Rubber", (0.05, 0.05, 0.055, 1), roughness=0.95)
    M["plastic_white"] = mat("Env_PlasticWhite", (0.9, 0.9, 0.9, 1), roughness=0.4)
    M["glass"] = mat("Env_Glass", (0.6, 0.72, 0.8, 1), roughness=0.03, alpha=0.2)
    M["light"] = mat("Env_Light", (1, 1, 1, 1), roughness=0.3, emission=(0.95, 0.97, 1.0, 1), emission_strength=3.5)
    M["light_warm"] = mat("Env_LightWarm", (1, 1, 1, 1), roughness=0.3, emission=(1.0, 0.85, 0.6, 1), emission_strength=3.0)
    M["screen"] = mat("Env_Screen", (0.03, 0.04, 0.06, 1), roughness=0.2)
    M["wood"] = mat("Env_Wood", (0.55, 0.38, 0.22, 1), roughness=0.6)
    M["yellow"] = mat("Env_Yellow", (0.95, 0.75, 0.12, 1), roughness=0.6)
    M["sign_green"] = mat("Env_SignGreen", (0.05, 0.4, 0.15, 1), roughness=0.5, emission=(0.1, 0.9, 0.3, 1), emission_strength=0.8)
    M["cable"] = mat("Env_Cable", (0.1, 0.1, 0.12, 1), roughness=0.8)
    M["pipe_red"] = mat("Env_PipeRed", (0.6, 0.1, 0.08, 1), metallic=0.4, roughness=0.5)
    for m in M.values():
        m.use_backface_culling = True
    return M


def tunnel_segment(M):
    """10 m tünel segmenti: kemerli kaplama (iç yüz), halka derzleri, sol yürüyüş yolu + korkuluk,
    sağ kablo tavaları ve yangın borusu, tavan lamba yuvaları."""
    root = empty("TunnelSeg", (0, 0, 0))
    # Profil (iç yüz) — 11 nokta kemer
    prof = [(-2.95, -0.7), (2.95, -0.7), (2.95, 2.4), (2.75, 3.4), (2.2, 4.2), (1.3, 4.75), (0.0, 4.95),
            (-1.3, 4.75), (-2.2, 4.2), (-2.75, 3.4), (-2.95, 2.4), (-2.95, 0.85), (-2.25, 0.85), (-2.25, -0.7)]
    bm = bmesh.new()
    rings = []
    n_r = 7   # 1.5 m'lik halka derzleri için loop'lar
    ys = [0.0]
    for k in range(1, n_r):
        y = SEG * k / (n_r - 1)
        ys += [y - 0.02, y + 0.02] if k < n_r - 1 else [y]
    # Derz: iç kısım 2 cm içeri (büyütme)
    for i, y in enumerate(ys):
        groove = (i % 2 == 1) and i != len(ys) - 1
        scale = 1.012 if groove else 1.0
        verts = [bm.verts.new((x * scale, y, (z - 2.0) * scale + 2.0)) for (x, z) in prof]
        rings.append(verts)
    n = len(prof)
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # İç yüz: normaller içe (merkeze) baksın
    for f in bm.faces:
        c = f.calc_center_median()
        to_center = Vector((0, c.y, 2.0)) - c
        if f.normal.dot(to_center) < 0:
            f.normal_flip()
    lining = obj_from_bmesh("Lining", bm, M["lining"], smooth=False, parent=root)
    uv_box_project(lining, 0.5)
    # Yürüyüş yolu kaplaması ve korkuluk (sol)
    box("WalkTop", (0.7, SEG, 0.04), (-2.6, SEG / 2, 0.87), M["concrete"], root)
    for y in (1.0, 4.0, 7.0, 10.0):
        cylinder(f"RailPost_{y}", 0.02, 1.0, (-2.3, y, 1.37), M["galv"], root, segments=10)
    cylinder("RailTop", 0.018, SEG, (-2.3, SEG / 2, 1.87), M["galv"], root, rot=(math.radians(90), 0, 0), segments=10)
    cylinder("RailMid", 0.014, SEG, (-2.3, SEG / 2, 1.4), M["galv"], root, rot=(math.radians(90), 0, 0), segments=8)
    # Kablo tavaları (sağ) ve kablolar
    for z in (1.5, 1.95, 2.4):
        box(f"Tray_{z}", (0.3, SEG, 0.06), (2.75, SEG / 2, z), M["galv"], root)
        box(f"TrayLip_{z}", (0.02, SEG, 0.1), (2.61, SEG / 2, z + 0.05), M["galv"], root)
        for k in range(3):
            cylinder(f"Cable_{z}_{k}", 0.018, SEG, (2.66 + k * 0.07, SEG / 2, z + 0.05), M["cable"], root, rot=(math.radians(90), 0, 0), segments=8)
    for y in (2.5, 7.5):
        box(f"TrayBracket_{y}", (0.36, 0.05, 1.1), (2.77, y, 1.95), M["galv"], root)
    # Yangın borusu (sağ, alçak) ve askı
    cylinder("FirePipe", 0.06, SEG, (2.7, SEG / 2, 0.55), M["pipe_red"], root, rot=(math.radians(90), 0, 0), segments=12)
    for y in (1.5, 5.0, 8.5):
        box(f"PipeHanger_{y}", (0.2, 0.05, 0.1), (2.82, y, 0.6), M["galv"], root)
    # Tünel lambası (sağ üst, 5 m'de bir) — Godot ışıkları ayrıca ekler
    for y in (2.5, 7.5):
        box(f"LampBody_{y}", (0.18, 1.25, 0.1), (2.3, y, 3.65), M["galv"], root)
        box(f"LampLens_{y}", (0.14, 1.15, 0.03), (2.28, y, 3.60), M["light_warm"], root)
    # Tavan kablo kanalı
    box("CeilDuct", (0.35, SEG, 0.12), (0.9, SEG / 2, 4.75), M["galv"], root)
    # Drenaj kanalı (orta)
    box("Drain", (0.4, SEG, 0.05), (0.0, SEG / 2, -0.68), M["concrete"], root)
    return root


def emergency_door(M):
    """Tünel duvarına niş + acil çıkış kapısı + yeşil tabela (sağ duvara monte)."""
    root = empty("EmergencyDoor", (0, 0, 0))
    box("Niche", (0.5, 1.6, 2.4), (3.1, 0, 0.6), M["concrete"], root)
    box("DoorLeaf", (0.06, 1.0, 2.05), (2.9, 0, 0.4), M["paint_green"], root, bevel=0.01)
    box("DoorFrame", (0.08, 1.14, 2.15), (2.92, 0, 0.42), M["metal_dark"], root)
    cylinder("Handle", 0.015, 0.25, (2.85, 0.35, 0.4), M["metal"], root, rot=(math.radians(90), 0, 0), segments=8)
    box("Sign", (0.03, 0.6, 0.25), (2.85, 0, 1.75), M["sign_green"], root)
    box("Lamp", (0.1, 0.3, 0.08), (2.85, 0, 2.0), M["light"], root)
    return root


def vent_fan(M):
    """Havalandırma nişi: büyük fan + ızgara (sağ duvar)."""
    root = empty("VentFan", (0, 0, 0))
    box("Niche", (0.8, 2.2, 2.2), (3.2, 0, 2.3), M["concrete"], root)
    cylinder("Ring", 0.95, 0.15, (2.85, 0, 2.3), M["galv"], root, rot=(0, math.radians(90), 0), segments=32)
    cylinder("Hub", 0.18, 0.2, (2.8, 0, 2.3), M["metal_dark"], root, rot=(0, math.radians(90), 0), segments=16)
    for k in range(6):
        b = box(f"Blade_{k}", (0.03, 0.22, 0.7), (2.8, 0, 2.3), M["metal"], root)
        b.rotation_euler = (math.radians(k * 60), 0, 0)
        b.location = (2.8, math.sin(math.radians(k * 60)) * 0.45, 2.3 + math.cos(math.radians(k * 60)) * 0.45)
        b.rotation_euler = (math.radians(-k * 60), math.radians(25), 0)
    for k in range(7):
        box(f"Grill_{k}", (0.02, 1.9, 0.03), (2.78, 0, 1.4 + k * 0.3), M["galv"], root)
    return root


def bench(M):
    root = empty("Bench", (0, 0, 0))
    for k in range(5):
        box(f"Slat_{k}", (0.07, 1.8, 0.025), (-0.17 + k * 0.085, 0, 0.45), M["wood"], root, bevel=0.005)
    for k in range(4):
        box(f"BackSlat_{k}", (0.025, 1.8, 0.07), (0.24, 0, 0.62 + k * 0.085), M["wood"], root, bevel=0.005)
    for y in (-0.75, 0.75):
        box(f"Leg_{y}", (0.5, 0.06, 0.05), (0.0, y, 0.42), M["metal_dark"], root)
        box(f"LegV_{y}", (0.06, 0.06, 0.42), (-0.15, y, 0.21), M["metal_dark"], root)
        box(f"LegV2_{y}", (0.06, 0.06, 0.42), (0.15, y, 0.21), M["metal_dark"], root)
        b = box(f"BackSup_{y}", (0.05, 0.06, 0.5), (0.26, y, 0.72), M["metal_dark"], root)
        b.rotation_euler = (0, math.radians(-8), 0)
    return root


def trash_bin(M):
    root = empty("TrashBin", (0, 0, 0))
    cylinder("Body", 0.22, 0.85, (0, 0, 0.425), M["galv"], root, segments=24)
    cylinder("Lid", 0.24, 0.06, (0, 0, 0.88), M["metal_dark"], root, segments=24)
    box("Slot", (0.3, 0.12, 0.12), (0, 0, 0.75), M["rubber"], root)
    return root


def pis_screen(M):
    """Tavandan asılı çift yüzlü yolcu bilgi ekranı (Godot ekranı Label3D/Viewport ile doldurur)."""
    root = empty("PIS", (0, 0, 0))
    box("Housing", (1.1, 0.12, 0.42), (0, 0, 0), M["metal_dark"], root, bevel=0.01)
    plane("PIS_Screen_A", 1.0, 0.34, (0, -0.065, 0), M["screen"], root, rot=(math.radians(90), 0, 0))
    plane("PIS_Screen_B", 1.0, 0.34, (0, 0.065, 0), M["screen"], root, rot=(math.radians(90), 0, math.radians(180)))
    for x in (-0.4, 0.4):
        box(f"Hanger_{x}", (0.04, 0.04, 0.5), (x, 0, 0.45), M["metal_dark"], root)
    return root


def cctv(M):
    root = empty("CCTV", (0, 0, 0))
    box("Mount", (0.08, 0.08, 0.2), (0, 0, -0.1), M["metal_dark"], root)
    box("Body", (0.1, 0.3, 0.1), (0, 0.1, -0.2), M["plastic_white"], root, bevel=0.01)
    cylinder("Lens", 0.03, 0.08, (0, 0.27, -0.2), M["rubber"], root, rot=(math.radians(90), 0, 0), segments=12)
    box("Led", (0.02, 0.02, 0.02), (0.03, 0.26, -0.17), M["paint_red"], root)
    return root


def ceiling_light(M):
    """Gömme tavan armatürü 1.2 m."""
    root = empty("CeilingLight", (0, 0, 0))
    box("Frame", (0.3, 1.25, 0.06), (0, 0, 0), M["plastic_white"], root)
    box("Diffuser", (0.24, 1.18, 0.02), (0, 0, -0.025), M["light"], root)
    return root


def column(M):
    root = empty("Column", (0, 0, 0))
    cylinder("Shaft", 0.3, 4.3, (0, 0, 2.15), M["metal"], root, segments=28)
    cylinder("Base", 0.38, 0.12, (0, 0, 0.06), M["metal_dark"], root, segments=28)
    cylinder("Cap", 0.4, 0.15, (0, 0, 4.37), M["metal_dark"], root, segments=28)
    return root


def escalator(M):
    """Yürüyen merdiven: 30°, yükseklik 4.5 m, iki balustrade (cam), basamaklar, taraklar."""
    root = empty("Escalator", (0, 0, 0))
    h = 4.5
    run = h / math.tan(math.radians(30))
    L = math.hypot(run, h)
    cx, cz = run / 2, h / 2
    rot = (math.radians(-30), 0, 0)
    body = box("Truss", (1.5, L + 1.2, 0.5), (0, cx, cz - 0.4), M["metal_dark"], root)
    body.rotation_euler = rot
    for sx in (-0.75, 0.75):
        g = box(f"Balustrade_{sx}", (0.03, L, 1.0), (sx, cx, cz + 0.55), M["glass"], root)
        g.rotation_euler = rot
        hr = cylinder(f"Handrail_{sx}", 0.04, L + 0.6, (sx, cx, cz + 1.08), M["rubber"], root, rot=(math.radians(60), 0, 0), segments=12)
        sk = box(f"Skirt_{sx}", (0.05, L, 0.25), (sx * 0.97, cx, cz + 0.1), M["metal"], root)
        sk.rotation_euler = rot
    steps = int(L / 0.4)
    for i in range(steps):
        t = (i + 0.5) / steps
        s = box(f"Step_{i}", (1.3, 0.4, 0.22), (0, run * t, h * t + 0.08), M["galv"], root)
        box(f"StepEdge_{i}", (1.3, 0.4, 0.01), (0, run * t, h * t + 0.19), M["yellow"], root)
    box("CombTop", (1.5, 1.2, 0.12), (0, run + 0.6, h + 0.06), M["metal"], root)
    box("CombBot", (1.5, 1.2, 0.12), (0, -0.6, 0.06), M["metal"], root)
    for sx in (-0.9, 0.9):
        box(f"EndPost_{sx}", (0.12, 0.12, 1.1), (sx, -1.0, 0.55), M["metal"], root)
        box(f"EndPostT_{sx}", (0.12, 0.12, 1.1), (sx, run + 1.0, h + 0.55), M["metal"], root)
    return root


def elevator(M):
    root = empty("Elevator", (0, 0, 0))
    hgt = 4.3
    for sx in (-1.0, 1.0):
        box(f"Frame_{sx}", (0.1, 2.0, hgt), (sx, 0, hgt / 2), M["metal_dark"], root)
    box("FrameBack", (2.1, 0.1, hgt), (0, 1.0, hgt / 2), M["metal_dark"], root)
    box("Roof", (2.2, 2.2, 0.12), (0, 0, hgt), M["metal_dark"], root)
    box("GlassL", (0.03, 1.9, hgt - 0.3), (-0.95, 0, hgt / 2), M["glass"], root)
    box("GlassR", (0.03, 1.9, hgt - 0.3), (0.95, 0, hgt / 2), M["glass"], root)
    box("GlassBack", (1.9, 0.03, hgt - 0.3), (0, 0.95, hgt / 2), M["glass"], root)
    # Kapılar (ön)
    for sx in (-0.45, 0.45):
        box(f"Door_{sx}", (0.85, 0.05, 2.1), (sx, -0.95, 1.05), M["metal"], root)
        box(f"DoorGlass_{sx}", (0.4, 0.06, 1.0), (sx, -0.95, 1.4), M["glass"], root)
    box("Header", (2.0, 0.12, 0.3), (0, -0.95, 2.3), M["metal_dark"], root)
    box("Indicator", (0.4, 0.02, 0.15), (0, -1.02, 2.3), M["light"], root)
    box("CallPanel", (0.15, 0.03, 0.3), (1.1, -0.95, 1.2), M["metal"], root)
    return root


def fire_cabinet(M):
    root = empty("FireCabinet", (0, 0, 0))
    box("Body", (0.25, 0.7, 0.9), (0, 0, 0.45), M["paint_red"], root, bevel=0.01)
    box("Glass", (0.02, 0.5, 0.6), (-0.13, 0, 0.5), M["glass"], root)
    box("Label", (0.01, 0.4, 0.08), (-0.135, 0, 0.85), M["plastic_white"], root)
    return root


def sign_frame(M):
    """Tavandan asılı yön tabelası (Godot Label3D ekler)."""
    root = empty("SignFrame", (0, 0, 0))
    box("Board", (2.4, 0.06, 0.5), (0, 0, 0), M["metal_dark"], root, bevel=0.01)
    plane("Sign_A", 2.3, 0.42, (0, -0.035, 0), M["screen"], root, rot=(math.radians(90), 0, 0))
    plane("Sign_B", 2.3, 0.42, (0, 0.035, 0), M["screen"], root, rot=(math.radians(90), 0, math.radians(180)))
    for x in (-1.0, 1.0):
        box(f"Hanger_{x}", (0.03, 0.03, 0.6), (x, 0, 0.55), M["metal_dark"], root)
    return root


def vending(M):
    root = empty("Vending", (0, 0, 0))
    box("Body", (0.9, 0.8, 1.9), (0, 0, 0.95), M["paint_grey"], root, bevel=0.01)
    box("Glass", (0.6, 0.03, 1.2), (-0.1, -0.41, 1.15), M["glass"], root)
    box("Inner", (0.58, 0.3, 1.18), (-0.1, -0.25, 1.15), M["light"], root)
    box("Panel", (0.2, 0.03, 0.6), (0.33, -0.41, 1.3), M["metal_dark"], root)
    box("Slot", (0.5, 0.03, 0.25), (-0.1, -0.41, 0.35), M["rubber"], root)
    return root


def signal_head(M):
    """Sinyal direği gövdesi (lambalar Godot'ta emissive malzeme ile değiştirilir)."""
    root = empty("SignalHead", (0, 0, 0))
    cylinder("Post", 0.05, 2.4, (0, 0, 1.2), M["galv"], root, segments=12)
    box("Head", (0.36, 0.22, 1.15), (0, 0, 2.95), M["metal_dark"], root, bevel=0.02)
    for i, name in enumerate(("Lamp_green", "Lamp_yellow", "Lamp_red")):
        z = 2.55 + i * 0.35
        cylinder(f"Hood_{name}", 0.13, 0.16, (0, 0.14, z + 0.04), M["metal_dark"], root, rot=(math.radians(90), 0, 0), segments=16)
        cylinder(name, 0.1, 0.03, (0, 0.12, z), M["rubber"], root, rot=(math.radians(90), 0, 0), segments=16)
    box("IdPlate", (0.22, 0.02, 0.1), (0, 0.12, 2.2), M["plastic_white"], root)
    return root


PROPS = {
    "tunnel_segment": tunnel_segment, "emergency_door": emergency_door, "vent_fan": vent_fan,
    "bench": bench, "trash_bin": trash_bin, "pis_screen": pis_screen, "cctv": cctv, "ceiling_light": ceiling_light,
    "column": column, "escalator": escalator, "elevator": elevator, "fire_cabinet": fire_cabinet,
    "sign_frame": sign_frame, "vending": vending, "signal_head": signal_head,
}


def main():
    reset()
    M = materials()
    for name, fn in PROPS.items():
        root = fn(M)
        objs = [root] + list(root.children_recursive)
        for ob in objs:
            if ob.type == "MESH" and ob.data.materials and not ob.data.uv_layers:
                uv_box_project(ob, 1.0)
        export_glb(os.path.join(OUT, name + ".glb"), objs)
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)


main()
