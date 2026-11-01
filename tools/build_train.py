"""
build_train.py — ARS T-400 "Boğaz" metro aracı (Blender headless → GLB).
  blender -b --python tools/build_train.py -- --out assets/models

Koordinatlar (Blender): +X sağ, +Y ileri (burun), +Z yukarı. glTF dışa aktarımda
Godot'ta ileri = -Z olur. Ray üstü z=0, araç tabanı z=1.1, çatı z=3.55.

Godot'un bulduğu adlar: Cam_Eye, Ctl_lever, Ctl_reverser, Btn_*, Lamp_*, Speedo_Needle,
MMI_Screen, Door_L_<i>_a/b, Door_R_<i>_a/b, Headlight_L/R, Taillight_L/R, CabinLight,
Dest_Front, Dest_Side_L/R, InteriorLight_*
"""
import bpy, bmesh, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blender_common import *
import build_cabin
import build_saloon

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = "assets/models"
for i, a in enumerate(argv):
    if a == "--out":
        OUT = argv[i + 1]

L = 21.5
HW = 1.425
FLOOR = 1.1
ROOF = 3.55
SKIRT = 0.78
CAB_Y = 8.0            # kabin bölme duvarı (ön araçta)
BODY_COLOR = (0.08, 0.52, 0.50, 1)   # ARS turkuaz
DARK = (0.08, 0.085, 0.09, 1)


def materials():
    M = {}
    M["paint"] = mat("T400_Paint", BODY_COLOR, metallic=0.35, roughness=0.3, tex="paint_metal", tex_scale=2.0, normal_strength=0.5)
    M["paint_dark"] = mat("T400_PaintDark", (0.10, 0.11, 0.12, 1), metallic=0.5, roughness=0.35, tex="paint_metal", tex_scale=2.0, normal_strength=0.4)
    M["accent"] = mat("T400_Accent", (0.95, 0.72, 0.12, 1), metallic=0.2, roughness=0.4)
    M["glass"] = mat("T400_Glass", (0.35, 0.45, 0.5, 1), metallic=0.0, roughness=0.03, alpha=0.32)
    M["glass_cab"] = mat("T400_GlassCab", (0.6, 0.72, 0.8, 1), metallic=0.0, roughness=0.02, alpha=0.12)
    M["metal"] = mat("T400_Metal", (0.75, 0.76, 0.78, 1), metallic=1.0, roughness=0.3, tex="metal_brushed", tex_scale=3.0, normal_strength=0.3)
    M["metal_dark"] = mat("T400_MetalDark", (0.25, 0.26, 0.28, 1), metallic=0.9, roughness=0.5)
    M["rubber"] = mat("T400_Rubber", (0.06, 0.06, 0.065, 1), metallic=0.0, roughness=0.9)
    M["interior"] = mat("T400_Interior", (0.86, 0.87, 0.88, 1), metallic=0.0, roughness=0.55)
    M["interior_dark"] = mat("T400_InteriorDark", (0.22, 0.23, 0.25, 1), metallic=0.1, roughness=0.6)
    M["floor"] = mat("T400_Floor", (0.5, 0.5, 0.52, 1), roughness=0.8, tex="rubber_floor", tex_scale=1.5, normal_strength=0.8)
    M["seat"] = mat("T400_Seat", (0.12, 0.25, 0.48, 1), roughness=0.95, tex="seat_fabric", tex_scale=2.0, normal_strength=0.6)
    M["seat_cab"] = mat("T400_SeatCab", (0.12, 0.13, 0.15, 1), roughness=0.85, tex="seat_fabric", tex_scale=2.0, normal_strength=0.5)
    M["desk"] = mat("T400_Desk", (0.14, 0.15, 0.17, 1), metallic=0.05, roughness=0.5)
    M["desk_light"] = mat("T400_DeskLight", (0.55, 0.56, 0.58, 1), metallic=0.1, roughness=0.5)
    M["ceiling"] = mat("T400_Ceiling", (0.9, 0.9, 0.9, 1), roughness=0.5, metallic=0.4, tex="ceiling_perforated", tex_scale=2.0, normal_strength=0.4)
    M["light"] = mat("T400_Light", (1.0, 1.0, 1.0, 1), roughness=0.3, emission=(0.95, 0.97, 1.0, 1), emission_strength=3.0)
    M["headlight"] = mat("T400_Headlight", (1.0, 1.0, 1.0, 1), roughness=0.1, emission=(1.0, 0.97, 0.85, 1), emission_strength=6.0)
    M["taillight"] = mat("T400_Taillight", (0.7, 0.05, 0.05, 1), roughness=0.2, emission=(1.0, 0.1, 0.08, 1), emission_strength=2.5)
    M["dest"] = mat("T400_Dest", (0.02, 0.02, 0.02, 1), roughness=0.3, emission=(1.0, 0.55, 0.1, 1), emission_strength=1.5)
    M["screen"] = mat("MMI_Screen", (0.02, 0.05, 0.07, 1), roughness=0.2)
    M["dial"] = mat("T400_Dial", (0.92, 0.93, 0.95, 1), roughness=0.4, emission=(0.9, 0.92, 0.95, 1), emission_strength=0.25)
    M["needle"] = mat("T400_Needle", (0.9, 0.12, 0.08, 1), roughness=0.4, emission=(1.0, 0.15, 0.1, 1), emission_strength=0.8)
    for key, col in (("green", (0.1, 0.8, 0.3)), ("red", (0.85, 0.1, 0.1)), ("blue", (0.15, 0.4, 0.9)), ("yellow", (0.95, 0.75, 0.1)), ("grey", (0.6, 0.6, 0.62))):
        M["btn_" + key] = mat("T400_Btn_" + key, col + (1,), roughness=0.35, emission=col + (1,), emission_strength=0.3)
    M["lamp_off"] = mat("T400_LampOff", (0.2, 0.2, 0.2, 1), roughness=0.4)
    M["panel"] = mat("T400_Panel", (0.12, 0.14, 0.17, 1), metallic=0.1, roughness=0.45)
    M["flag_red"] = mat("T400_FlagRed", (0.85, 0.05, 0.08, 1), roughness=0.8)
    M["flag_white"] = mat("T400_FlagWhite", (0.95, 0.95, 0.95, 1), roughness=0.8)
    M["tea"] = mat("T400_Tea", (0.55, 0.2, 0.04, 1), roughness=0.1, alpha=0.85)
    M["tea_glass"] = mat("T400_TeaGlass", (0.8, 0.85, 0.9, 1), roughness=0.05, alpha=0.3)
    M["paper"] = mat("T400_Paper", (0.95, 0.95, 0.92, 1), roughness=0.9)
    M["wood"] = mat("T400_Wood", (0.45, 0.3, 0.18, 1), roughness=0.6)
    M["brass"] = mat("T400_Brass", (0.8, 0.65, 0.3, 1), metallic=1.0, roughness=0.35)
    M["plastic_dark"] = mat("T400_PlasticDark", (0.11, 0.115, 0.125, 1), metallic=0.0, roughness=0.55, tex="plastic_grain", tex_scale=4.0, normal_strength=0.5)
    M["plastic_grey"] = mat("T400_PlasticGrey", (0.58, 0.59, 0.6, 1), metallic=0.0, roughness=0.6, tex="plastic_grain", tex_scale=4.0, normal_strength=0.5)
    M["plastic_white"] = mat("T400_PlasticWhite", (0.85, 0.85, 0.84, 1), metallic=0.0, roughness=0.5)
    M["leather"] = mat("T400_Leather", (0.09, 0.09, 0.1, 1), metallic=0.0, roughness=0.6, tex="leather", tex_scale=3.0, normal_strength=0.8)
    M["metal_painted"] = mat("T400_MetalPainted", (0.42, 0.43, 0.45, 1), metallic=0.3, roughness=0.5, tex="metal_worn", tex_scale=3.0, normal_strength=0.4)
    M["rubber_ribbed"] = mat("T400_RubberRibbed", (0.12, 0.12, 0.125, 1), metallic=0.0, roughness=0.9, tex="rubber_ribbed", tex_scale=3.0, normal_strength=1.0)
    M["floor_dark"] = mat("T400_FloorDark", (0.3, 0.3, 0.32, 1), roughness=0.8, tex="rubber_floor", tex_scale=1.5, normal_strength=0.8)
    M["glass_dark"] = mat("T400_GlassDark", (0.05, 0.05, 0.06, 1), metallic=0.0, roughness=0.05, alpha=0.6)
    M["visor"] = mat("T400_Visor", (0.2, 0.2, 0.22, 1), metallic=0.0, roughness=0.9)
    M["wall_panel"] = mat("T400_WallPanel", (0.8, 0.81, 0.82, 1), metallic=0.0, roughness=0.5, tex="panel_lines", tex_scale=1.0, normal_strength=0.5)
    for m in M.values():
        m.use_backface_culling = True
    return M


def profile_points(scale_x=1.0, top_drop=0.0, bottom_raise=0.0):
    """Araç kesiti (sağ yarı, alttan üste), sonra aynalanır. (x, z) listesi, saat yönünün tersi."""
    pts_r = [
        (HW - 0.10, SKIRT + bottom_raise),
        (HW - 0.02, FLOOR - 0.15),
        (HW, FLOOR + 0.35),
        (HW, FLOOR + 1.25),
        (HW - 0.03, FLOOR + 1.75),
        (HW - 0.10, ROOF - 0.70),
        (HW - 0.22, ROOF - 0.42),
        (HW - 0.42, ROOF - 0.20),
        (HW - 0.72, ROOF - 0.06),
        (HW - 1.05, ROOF - 0.0),
    ]
    pts_r = [(x * scale_x, z - top_drop * max(0.0, (z - FLOOR) / (ROOF - FLOOR)) ** 1.5) for (x, z) in pts_r]
    top = (0.0, ROOF - top_drop)
    pts = pts_r + [top] + [(-x, z) for (x, z) in reversed(pts_r)]
    return pts


def make_shell(name, front_nose, rear_nose, M):
    bm = bmesh.new()
    loops = []

    def add_loop(y, scale_x=1.0, top_drop=0.0, bottom_raise=0.0, rake=0.0, sign=1):
        verts = []
        for (x, z) in profile_points(scale_x, top_drop, bottom_raise):
            t = max(0.0, (z - SKIRT) / (ROOF - SKIRT))
            verts.append(bm.verts.new((x, y - sign * rake * (t ** 1.3), z)))
        loops.append(verts)
        return verts

    y0 = -L / 2
    y1 = L / 2
    NOSE = [(0.0, 0.78, 0.50, 0.22, 0.55), (0.3, 0.87, 0.30, 0.14, 0.42), (0.85, 0.94, 0.12, 0.06, 0.22),
            (1.6, 0.985, 0.02, 0.0, 0.06), (2.6, 1.0, 0.0, 0.0, 0.0)]
    if rear_nose:
        for (d, sx, drop, raise_, rake) in NOSE:
            add_loop(y0 + d, sx, drop, raise_, rake, -1)
    else:
        add_loop(y0)
    if front_nose:
        for (d, sx, drop, raise_, rake) in reversed(NOSE):
            add_loop(y1 - d, sx, drop, raise_, rake, 1)
    else:
        add_loop(y1)
    # Halkaları köprüle
    n = len(loops[0])
    for a, b in zip(loops[:-1], loops[1:]):
        for i in range(n):
            v1, v2 = a[i], a[(i + 1) % n]
            v3, v4 = b[(i + 1) % n], b[i]
            bm.faces.new((v1, v2, v3, v4))
    # Uçları kapat
    bm.faces.new(list(reversed(loops[0])))
    bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bmesh(name, bm, M["paint"], smooth=True)
    ob.data.materials.append(M["interior"])
    # Pencere bandı için ikinci malzeme değil; koyu bant ayrı nesne. Yumuşatma: otomatik smooth
    ob.data.use_auto_smooth = True
    ob.data.auto_smooth_angle = math.radians(50)
    return ob


def window_cutters(front_cab, rear_cab, door_ys):
    """Pencere ve kapı kesici kutuları (liste)."""
    cutters = []
    # Kapılar
    for side in (-1, 1):
        for i, y in enumerate(door_ys):
            c = box(f"cut_door_{side}_{i}", (0.6, 1.32, 1.98), (side * HW, y, FLOOR + 0.99))
            cutters.append(c)
    # Pencereler: kapı aralarında
    ys = sorted(door_ys)
    spans = []
    start = -L / 2 + 0.6 if not rear_cab else -L / 2 + 2.6
    end = L / 2 - 0.6 if not front_cab else L / 2 - 2.6
    prev = start
    for y in ys:
        spans.append((prev, y - 0.75))
        prev = y + 0.75
    spans.append((prev, end))
    for side in (-1, 1):
        for (a, b) in spans:
            w = b - a - 0.5
            if w < 0.6:
                continue
            # geniş aralıklarda iki pencere
            if w > 2.6:
                w2 = (w - 0.25) / 2
                for k in (0, 1):
                    cy = a + 0.25 + w2 / 2 + k * (w2 + 0.25)
                    cutters.append(box(f"cut_win_{side}_{cy:.1f}", (0.6, w2, 0.95), (side * HW, cy, FLOOR + 1.65)))
            else:
                cutters.append(box(f"cut_win_{side}_{(a + b) / 2:.1f}", (0.6, w, 0.95), (side * HW, (a + b) / 2, FLOOR + 1.65)))
    # Kabin yan camları
    if front_cab:
        for side in (-1, 1):
            cutters.append(box(f"cut_cabwin_{side}", (0.6, 1.1, 0.85), (side * HW, L / 2 - 1.75, FLOOR + 1.65)))
        # Ön cam
        cutters.append(box("cut_windshield", (2.05, 1.6, 1.25), (0, L / 2 - 0.3, FLOOR + 0.95 + 0.625)))
        cutters[-1].rotation_euler = (math.radians(-12), 0, 0)
    if rear_cab:
        for side in (-1, 1):
            cutters.append(box(f"cut_rcabwin_{side}", (0.6, 1.1, 0.85), (side * HW, -L / 2 + 1.75, FLOOR + 1.65)))
        cutters.append(box("cut_rwindshield", (2.05, 1.6, 1.25), (0, -L / 2 + 0.3, FLOOR + 0.95 + 0.625)))
        cutters[-1].rotation_euler = (math.radians(12), 0, 0)
    # Vagonlar arası geçiş açıklıkları (kabinsiz uçlar)
    if not rear_cab:
        cutters.append(box("cut_gang_rear", (1.3, 0.8, 2.05), (0, -L / 2, FLOOR + 1.025)))
    if not front_cab:
        cutters.append(box("cut_gang_front", (1.3, 0.8, 2.05), (0, L / 2, FLOOR + 1.025)))
    return cutters


def glass_panels(front_cab, rear_cab, door_ys, M, parent):
    """Pencere camları (kesilen açıklıkların hemen içinde, hafif içeride)."""
    ys = sorted(door_ys)
    spans = []
    start = -L / 2 + 0.6 if not rear_cab else -L / 2 + 2.6
    end = L / 2 - 0.6 if not front_cab else L / 2 - 2.6
    prev = start
    for y in ys:
        spans.append((prev, y - 0.75))
        prev = y + 0.75
    spans.append((prev, end))
    k = 0
    for side in (-1, 1):
        for (a, b) in spans:
            w = b - a - 0.5
            if w < 0.6:
                continue
            if w > 2.6:
                w2 = (w - 0.25) / 2
                for j in (0, 1):
                    cy = a + 0.25 + w2 / 2 + j * (w2 + 0.25)
                    box(f"Glass_{k}", (0.02, w2 + 0.04, 0.99), (side * (HW - 0.04), cy, FLOOR + 1.65), M["glass"], parent)
                    k += 1
            else:
                box(f"Glass_{k}", (0.02, w + 0.04, 0.99), (side * (HW - 0.04), (a + b) / 2, FLOOR + 1.65), M["glass"], parent)
                k += 1
    if front_cab:
        for side in (-1, 1):
            box(f"GlassCab_{side}", (0.02, 1.14, 0.89), (side * (HW - 0.05), L / 2 - 1.75, FLOOR + 1.65), M["glass_cab"], parent)
        ws = box("Windshield", (2.1, 0.02, 1.32), (0, L / 2 - 0.36, FLOOR + 0.95 + 0.625), M["glass_cab"], parent)
        ws.rotation_euler = (math.radians(-12), 0, 0)
    if rear_cab:
        for side in (-1, 1):
            box(f"GlassRCab_{side}", (0.02, 1.14, 0.89), (side * (HW - 0.05), -L / 2 + 1.75, FLOOR + 1.65), M["glass"], parent)
        ws = box("RWindshield", (2.1, 0.02, 1.32), (0, -L / 2 + 0.36, FLOOR + 0.95 + 0.625), M["glass"], parent)
        ws.rotation_euler = (math.radians(12), 0, 0)


def doors(door_ys, M, parent):
    for side, tag in ((-1, "L"), (1, "R")):
        for i, y in enumerate(door_ys):
            for leaf, k in (("a", -1), ("b", 1)):
                d = box(f"Door_{tag}_{i}_{leaf}", (0.05, 0.64, 1.95), (side * (HW + 0.025), y + k * 0.33, FLOOR + 0.975), M["paint"], parent, bevel=0.01)
                # Kapı camı
                box(f"DoorGlass_{tag}_{i}_{leaf}", (0.06, 0.42, 0.78), (0, 0, 0.45), M["glass"], d)
                # Sarı kenar bandı, kauçuk kapanma contası, cam çerçevesi, tekme plakası
                box(f"DoorEdge_{tag}_{i}_{leaf}", (0.052, 0.03, 1.9), (0, -k * 0.305, 0), M["accent"], d)
                box(f"DoorSeal_{tag}_{i}_{leaf}", (0.06, 0.012, 1.9), (0, -k * 0.325, 0), M["rubber"], d)
                for dy in (-0.225, 0.225):
                    box(f"DoorWinFrameV_{tag}_{i}_{leaf}_{dy}", (0.058, 0.03, 0.84), (0, dy, 0.45), M["plastic_dark"], d)
                for dz in (-0.405, 0.405):
                    box(f"DoorWinFrameH_{tag}_{i}_{leaf}_{dz}", (0.058, 0.48, 0.03), (0, 0, 0.45 + dz), M["plastic_dark"], d)
                box(f"DoorKick_{tag}_{i}_{leaf}", (0.056, 0.6, 0.16), (0, 0, -0.85), M["metal"], d)
            # Kapı üstü uyarı lambası
            box(f"DoorLamp_{tag}_{i}", (0.03, 0.18, 0.05), (side * (HW + 0.02), y, FLOOR + 2.03), M["taillight"], parent)
            # Kapı kılavuz rayı (üst)
            box(f"DoorRail_{tag}_{i}", (0.04, 2.7, 0.04), (side * (HW + 0.03), y, FLOOR + 2.0), M["metal_dark"], parent)


def roof_and_underframe(idx, M, parent):
    # Klima üniteleri
    for y in (-6.5, 6.5):
        ac = box(f"AC_{y}", (1.7, 2.4, 0.38), (0, y, ROOF + 0.17), M["metal"], parent, bevel=0.04)
        for k in range(6):
            box(f"ACfin_{y}_{k}", (1.5, 0.03, 0.2), (0, y - 1.0 + k * 0.4, ROOF + 0.32), M["metal_dark"], parent)
    # Çatı kanalı
    box("RoofDuct", (0.5, L - 3.0, 0.14), (0.6, 0, ROOF + 0.07), M["metal_dark"], parent, bevel=0.02)
    # Pantograf (çift sayılı araçlarda)
    if idx % 2 == 0:
        base = box("PantoBase", (1.6, 1.2, 0.12), (0, 1.5, ROOF + 0.06), M["metal_dark"], parent)
        for sx in (-0.6, 0.6):
            cylinder("PantoIns_%d" % sx, 0.07, 0.25, (sx, 1.5 - 0.4, ROOF + 0.18), M["interior"], parent, rot=(0, 0, 0))
        arm1 = cylinder("PantoArm1", 0.035, 1.6, (0, 1.2, ROOF + 0.75), M["metal"], parent, rot=(math.radians(-62), 0, 0))
        arm2 = cylinder("PantoArm2", 0.03, 1.5, (0, 0.2, ROOF + 1.2), M["metal"], parent, rot=(math.radians(55), 0, 0))
        box("PantoHead", (1.3, 0.06, 0.04), (0, -0.35, ROOF + 1.55), M["metal_dark"], parent)
        box("PantoHead2", (1.3, 0.06, 0.04), (0, -0.05, ROOF + 1.55), M["metal_dark"], parent)
    # Alt şase
    box("Underframe", (HW * 2 - 0.5, L - 1.0, 0.45), (0, 0, FLOOR - 0.35), M["metal_dark"], parent)
    for y in (-3.0, 0.5, 3.5):
        box(f"UFbox_{y}", (1.6, 1.4, 0.5), (0, y, FLOOR - 0.5), M["rubber"], parent, bevel=0.02)
    # Bojiler
    for y in (-7.0, 7.0):
        bog = box(f"Bogie_{y}", (2.2, 2.9, 0.3), (0, y, 0.75), M["metal_dark"], parent, bevel=0.03)
        for sx in (-1.0, 1.0):
            box(f"BogieSide_{y}_{sx}", (0.18, 2.6, 0.45), (sx, y, 0.7), M["metal_dark"], parent, bevel=0.02)
        for wy in (-1.1, 1.1):
            cylinder(f"Axle_{y}_{wy}", 0.08, 1.7, (0, y + wy, 0.42), M["metal"], parent, rot=(0, math.radians(90), 0))
            for sx in (-0.72, 0.72):
                cylinder(f"Wheel_{y}_{wy}_{sx}", 0.42, 0.12, (sx, y + wy, 0.42), M["metal"], parent, rot=(0, math.radians(90), 0), segments=28, bevel=0.02)
                cylinder(f"Disc_{y}_{wy}_{sx}", 0.3, 0.04, (sx * 1.15, y + wy, 0.42), M["metal_dark"], parent, rot=(0, math.radians(90), 0), segments=20)
            box(f"Motor_{y}_{wy}", (0.9, 0.5, 0.45), (0, y + wy * 0.45, 0.62), M["rubber"], parent, bevel=0.02)
        for sx in (-0.95, 0.95):
            for wy in (-1.1, 1.1):
                box(f"Spring_{y}_{wy}_{sx}", (0.22, 0.22, 0.3), (sx, y + wy, 0.95), M["rubber"], parent)
    # Yan etek (koyu bant)
    for side in (-1, 1):
        box(f"Skirt_{side}", (0.03, L - 1.2, 0.3), (side * (HW - 0.08), 0, SKIRT + 0.1), M["paint_dark"], parent)
        box(f"Stripe_{side}", (0.012, L - 0.8, 0.10), (side * (HW + 0.004), 0, FLOOR + 0.45), M["accent"], parent)
        # Hedef göstergesi (yan)
        box(f"DestSideBox_{side}", (0.03, 1.3, 0.22), (side * (HW - 0.02), 0, ROOF - 0.22), M["desk"], parent)
        plane(f"Dest_Side_{'L' if side < 0 else 'R'}", 1.2, 0.16, (side * (HW + 0.0), 0, ROOF - 0.22), M["dest"], parent, rot=(math.radians(90), 0, math.radians(90 if side > 0 else -90)))


def nose_details(front, M, parent):
    s = 1 if front else -1
    yt = s * L / 2
    # Farlar: gövde + lens
    for sx in (-0.82, 0.82):
        tag = "L" if sx < 0 else "R"
        cylinder(f"HeadHousing_{tag}_{s}", 0.2, 0.08, (sx, yt - s * 0.08, FLOOR + 0.62), M["metal_dark"], parent, rot=(math.radians(90), 0, 0))
        cylinder(f"HeadLens_{tag}_{s}", 0.16, 0.04, (sx, yt - s * 0.03, FLOOR + 0.62), M["headlight"] if front else M["taillight"], parent, rot=(math.radians(90), 0, 0))
        cylinder(f"TailLens_{tag}_{s}", 0.07, 0.04, (sx, yt - s * 0.03, FLOOR + 0.3), M["taillight"] if front else M["headlight"], parent, rot=(math.radians(90), 0, 0))
        if front:
            empty(f"Headlight_{tag}", (sx, yt + 0.05, FLOOR + 0.62), parent, rot=(math.radians(-90), 0, 0) if False else (0, 0, 0))
            empty(f"Taillight_{tag}", (sx, yt + 0.05, FLOOR + 0.3), parent)
    # Üst far
    cylinder(f"TopLens_{s}", 0.11, 0.04, (0, yt - s * 0.55, ROOF - 0.62), M["headlight"], parent, rot=(math.radians(90), 0, 0))
    # Hedef göstergesi (ön)
    box(f"DestBox_{s}", (1.3, 0.05, 0.26), (0, yt - s * 0.62, ROOF - 0.33), M["desk"], parent)
    plane(f"Dest_Front" if front else "Dest_Rear", 1.2, 0.18, (0, yt - s * 0.585, ROOF - 0.33), M["dest"], parent, rot=(math.radians(90 - 10 * s), 0, 0) if False else (math.radians(90), 0, 0 if front else math.radians(180)))
    # Kaplin + tampon
    box(f"Coupler_{s}", (0.3, 0.9, 0.25), (0, yt + s * 0.25, 0.85), M["metal_dark"], parent)
    box(f"CouplerHead_{s}", (0.45, 0.2, 0.35), (0, yt + s * 0.72, 0.85), M["metal_dark"], parent, bevel=0.03)
    box(f"Bumper_{s}", (1.9, 0.12, 0.12), (0, yt + s * 0.1, 0.95), M["accent"], parent, bevel=0.02)
    # Silecek
    w = box(f"Wiper_{s}", (0.03, 0.02, 0.85), (-0.35, yt - s * 0.30, FLOOR + 1.6), M["rubber"], parent)
    w.rotation_euler = (math.radians(-12 * s), math.radians(20), 0)
    # Kabin kapısı (dış, yanda) çerçevesi
    for side in (-1, 1):
        box(f"CabDoorFrame_{s}_{side}", (0.02, 0.7, 1.9), (side * (HW + 0.005), yt - s * 2.55, FLOOR + 1.0), M["paint_dark"], parent)


def interior(front_cab, rear_cab, door_ys, M, parent):
    """Yolcu salonu v4 — bkz. tools/build_saloon.py."""
    build_saloon.build_interior(front_cab, rear_cab, door_ys, M, parent, L, HW, FLOOR, ROOF, CAB_Y)
    if front_cab:
        build_cabin.bulkhead_front(M, parent, HW, FLOOR, ROOF, CAB_Y)
    if rear_cab:
        _bulkhead(-CAB_Y, -1, M, parent)


def _bulkhead(y, s, M, parent):
    inner = HW - 0.06
    w = box(f"Bulkhead_{s}", (inner * 2, 0.06, ROOF - FLOOR - 0.3), (0, y, FLOOR + (ROOF - FLOOR - 0.3) / 2), M["interior"], parent)
    # Kapı (bölme kapısı) ve camı
    box(f"CabDoor_{s}", (0.72, 0.05, 1.95), (0.75, y, FLOOR + 0.975), M["interior_dark"], parent)
    box(f"CabDoorGlass_{s}", (0.4, 0.06, 0.7), (0.75, y, FLOOR + 1.6), M["glass"], parent)
    box(f"BulkWin_{s}", (0.9, 0.08, 0.6), (-0.6, y, FLOOR + 1.7), M["glass"], parent)


def cabin(M, parent):
    """Makinist kabini v4 — bkz. tools/build_cabin.py (ergonomi korunur: göz z=FLOOR+1.25)."""
    build_cabin.build(M, parent, L, HW, FLOOR, ROOF, CAB_Y)


def build_car(name, front_cab, rear_cab, idx, M):
    root = empty(name, (0, 0, 0))
    door_ys = [-7.0, -0.5, 6.0] if front_cab else ([-6.0, 0.5, 7.0] if rear_cab else [-7.2, 0.0, 7.2])
    shell = make_shell(name + "_Shell", front_cab, rear_cab, M)
    shell.parent = root
    # Önce ince cidar (solidify), sonra pencere/kapı delikleri (boolean) — aksi halde boolean
    # dolu hacme cep açar ve açıklık oluşmaz.
    sol = shell.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.05
    sol.offset = -1.0
    sol.material_offset = 1
    sol.use_rim = True
    cutters = window_cutters(front_cab, rear_cab, door_ys)
    for c in cutters:
        boolean_cut(shell, c)
    apply_all(shell)
    uv_box_project(shell, 0.5)
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    glass_panels(front_cab, rear_cab, door_ys, M, root)
    doors(door_ys, M, root)
    roof_and_underframe(idx, M, root)
    if front_cab:
        nose_details(True, M, root)
    if rear_cab:
        nose_details(False, M, root)
    interior(front_cab, rear_cab, door_ys, M, root)
    if front_cab:
        cabin(M, root)
    # Alt nesnelere UV (dokulu olanlar)
    for ob in root.children_recursive:
        if ob.type == "MESH" and ob.data.materials and not ob.data.uv_layers:
            uv_box_project(ob, 1.0)
    join_static(root)
    return root


KEEP_PREFIXES = ("Door_", "DoorLamp", "Headlight", "Taillight", "HeadLens", "TailLens", "TopLens", "Dest", "PIS_",
                 "RouteMap_", "AdPanel_", "InteriorLight", "CabLightStrip", "CabinLight", "Cam_Eye", "Ctl_", "Btn_",
                 "Lamp_", "Speedo_", "MMI_Screen", "SpeedDigital", "CCTV_", "Sw_", "Knob_", "Radio_Display", "CabDoorPivot",
                 "ARSPlate", "Timetable", "Fan_Hub", "Glass", "Windshield", "RWindshield", "Wiper", "Pedal_", "CabSeat_",
                 "Extinguisher", "FlagCloth", "TeaLiquid", "TeaGlass", "SpeedoGlass", "CCTVDome_", "SeatDivGlass", "HammerGlass",
                 "CabWinSealIn", "BulkWin_", "Bulkhead_1", "EndWall", "GangPlate", "DoorSeal")


NOCOL_PREFIXES = ("Strap", "StrapRing", "TriArm", "TriArmUp", "TriHub", "HandrailPost", "Handrail_", "CeilLight", "AirVent", "Speaker_",
                  "PISBox", "RouteMapFrame", "AdFrame", "CCTVDomeBase", "DoorRailBox", "DoorRoller", "EmergRelease", "DoorSign",
                  "CableDuct", "CeilVent", "VentSlat", "CabSpeaker", "SpeakerRing", "CabLightFrame", "FanBody", "FanGuard", "FanMount", "FanGuardSpoke")


def join_static(root):
    """Hareket etmeyen, Godot'un adıyla aramadığı kutuları malzeme başına tek mesh'e birleştirir
    (çizim çağrısı sayısını ~1500'den ~20'ye indirir). Tavan/asılı ince parçalar (tutamak halkaları,
    üç kollu direk kolları, armatürler…) StaticNC_ adıyla ayrı birleştirilir: çarpışma üretilmez,
    böylece yürüyen oyuncu baş hizasındaki ince nesnelere takılmaz."""
    groups = {}
    for ob in list(root.children_recursive):
        if ob.type != "MESH" or ob.parent is not root:
            continue
        if ob.name.endswith("_Shell"):
            continue
        if any(ob.name.startswith(p) for p in KEEP_PREFIXES):
            continue
        if any(ch.type == "MESH" for ch in ob.children):
            continue
        if len(ob.data.materials) != 1 or ob.data.materials[0] is None:
            continue
        m = ob.data.materials[0]
        if m.blend_method == "BLEND":
            continue
        nocol = any(ob.name.startswith(p) for p in NOCOL_PREFIXES)
        groups.setdefault(("NC_" if nocol else "") + m.name, []).append(ob)
    for mname, obs in groups.items():
        if len(obs) < 2:
            # Tek nesne: yine de Static_ adıyla işaretle (Godot çarpışma üretimi bu öneke bakar;
            # v0.4'te orta vagonlarda "Floor" tek kaldığı için zemin çarpışması üretilmiyordu).
            prefix = ("StaticNC_" + mname[3:].replace("T400_", "")) if mname.startswith("NC_") else ("Static_" + mname.replace("T400_", ""))
            obs[0].name = prefix + "_" + obs[0].name
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        joined.name = ("StaticNC_" + mname[3:].replace("T400_", "")) if mname.startswith("NC_") else ("Static_" + mname.replace("T400_", ""))
        joined.data.name = joined.name
        bpy.ops.object.select_all(action="DESELECT")
        print("[JOIN]", joined.name, len(obs))


def main():
    reset()
    M = materials()
    front = build_car("T400_Front", True, False, 0, M)
    objs = [front] + list(front.children_recursive)
    export_glb(os.path.join(OUT, "t400_front.glb"), objs)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    mid = build_car("T400_Mid", False, False, 1, M)
    objs = [mid] + list(mid.children_recursive)
    export_glb(os.path.join(OUT, "t400_mid.glb"), objs)


main()
