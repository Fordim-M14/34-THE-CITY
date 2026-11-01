"""
build_saloon.py — ARS T-400 yolcu salonu v4 (build_train.py tarafından çağrılır).

Tekil kalıp koltuklar (kabuk + kumaş + alt ısıtıcı ızgarası + kolçak), çerçeveli pencereler
(conta + alüminyum çerçeve), kapı mekanizması (üst kılavuz ray, makaralar, kauçuk kenar
contaları, tekme plakası, kapı cebi, acil kapı açma kutusu), kapı üstü hat haritası
(RouteMap_*) ve LED PIS ekranları (PIS_*), tavan panelleri + gömme LED armatürler + kablo
kanalı, üç kollu orta direkler, tutamak halkaları, reklam panoları (AdPanel_*), CCTV kubbeleri,
yangın tüpü, acil çağrı kutusu, vagonlar arası geçiş (körük + geçiş plakası).
"""
import bpy, bmesh, math
from mathutils import Vector
from blender_common import *
from build_cabin import rounded_box, torus, prism_x


def window_spans(front_cab, rear_cab, door_ys, L):
    ys = sorted(door_ys)
    spans = []
    start = -L / 2 + 0.6 if not rear_cab else -L / 2 + 2.6
    end = L / 2 - 0.6 if not front_cab else L / 2 - 2.6
    prev = start
    for y in ys:
        spans.append((prev, y - 0.75))
        prev = y + 0.75
    spans.append((prev, end))
    out = []
    for (a, b) in spans:
        w = b - a - 0.5
        if w < 0.6:
            continue
        if w > 2.6:
            w2 = (w - 0.25) / 2
            for k in (0, 1):
                out.append((a + 0.25 + w2 / 2 + k * (w2 + 0.25), w2))
        else:
            out.append(((a + b) / 2, w))
    return out


def seat_unit(name, x, y, side, M, parent, FLOOR):
    """Tek yolcu koltuğu (duvara sırtı dönük, salona bakar). side: -1 sol duvar, +1 sağ duvar."""
    F = FLOOR
    # Kabuk (koyu plastik), oturma kumaşı, sırt kabuğu, sırt kumaşı
    rounded_box(f"{name}_Shell", (0.44, 0.44, 0.05), (x, y, F + 0.43), M["plastic_dark"], parent, bevel=0.015)
    rounded_box(f"{name}_Cush", (0.40, 0.40, 0.06), (x - side * 0.01, y, F + 0.48), M["seat"], parent, bevel=0.025, segments=4)
    bs = rounded_box(f"{name}_BackShell", (0.05, 0.44, 0.52), (x + side * 0.2, y, F + 0.74), M["plastic_dark"], parent, rot=(0, math.radians(-10 * side), 0), bevel=0.015)
    rounded_box(f"{name}_BackCush", (0.05, 0.40, 0.46), (x + side * 0.165, y, F + 0.75), M["seat"], parent, rot=(0, math.radians(-10 * side), 0), bevel=0.02, segments=4)
    empty(f"SeatPos_{name[5:]}", (x - side * 0.02, y, F + 0.51), parent, rot=(0, 0, math.radians(90 if side > 0 else -90)))
    # Alt ısıtıcı ızgarası
    rounded_box(f"{name}_Heater", (0.3, 0.42, 0.14), (x + side * 0.06, y, F + 0.3), M["metal_painted"], parent, bevel=0.004)
    for k in range(4):
        box(f"{name}_HeatSlat_{k}", (0.32, 0.40, 0.006), (x + side * 0.06, y, F + 0.25 + k * 0.03), M["plastic_dark"], parent)


def build_interior(front_cab, rear_cab, door_ys, M, parent, L, HW, FLOOR, ROOF, CAB_Y):
    F = FLOOR
    y_a = -L / 2 + 0.3 if not rear_cab else -CAB_Y
    y_b = L / 2 - 0.3 if not front_cab else CAB_Y
    length = y_b - y_a
    yc = (y_a + y_b) / 2
    inner = HW - 0.06
    ys = sorted(door_ys)

    # ---------------------------------------------------------------- zemin / tavan
    fl = box("Floor", (inner * 2, length, 0.03), (0, yc, F + 0.015), M["floor"], parent)
    uv_box_project(fl, 0.8)
    aisle = box("FloorAisle", (0.9, length - 0.4, 0.004), (0, yc, F + 0.032), M["floor_dark"], parent)
    uv_box_project(aisle, 0.8)
    ce = box("Ceiling", (inner * 2 - 0.9, length, 0.03), (0, yc, ROOF - 0.32), M["ceiling"], parent)
    uv_box_project(ce, 1.0)
    # Tavan kavisi (yan panel, iki kademe) + kablo/klima kanalı
    for side in (-1, 1):
        c1 = box(f"CeilSide_{side}", (0.5, length, 0.02), (side * (inner - 0.3), yc, ROOF - 0.42), M["wall_panel"], parent, rot=(0, math.radians(-28 * side), 0))
        uv_box_project(c1, 1.0)
        box(f"CeilDuct_{side}", (0.26, length - 0.2, 0.08), (side * 0.75, yc, ROOF - 0.36), M["plastic_grey"], parent, bevel=0.01)
        # Klima menfez şeritleri
        for k in range(int(length / 1.6)):
            yy = y_a + 0.8 + k * 1.6
            rounded_box(f"AirVent_{side}_{k}", (0.2, 0.9, 0.012), (side * 0.75, yy, ROOF - 0.405), M["metal_dark"], parent, bevel=0.003)
            for j in range(5):
                box(f"AirVentSlat_{side}_{k}_{j}", (0.18, 0.012, 0.006), (side * 0.75, yy - 0.3 + j * 0.15, ROOF - 0.412), M["metal"], parent)
    # Gömme LED armatürler (iki sıra) + Godot ışık empties
    n = max(1, int(length / 3.5))
    for sx in (-0.45, 0.45):
        for k in range(n):
            y = y_a + length * (k + 0.5) / n
            rounded_box(f"CeilLightFrame_{sx}_{k}", (0.22, 2.7, 0.025), (sx, y, ROOF - 0.335), M["metal_dark"], parent, bevel=0.004)
            box(f"CeilLight_{sx}_{k}", (0.17, 2.6, 0.02), (sx, y, ROOF - 0.345), M["light"], parent)
            if sx > 0:
                empty(f"InteriorLight_{k}", (0, y, ROOF - 0.5), parent)
    # Hoparlörler, CCTV kubbeleri
    for k in range(2):
        yy = y_a + length * (0.25 + 0.5 * k)
        cylinder(f"Speaker_{k}", 0.07, 0.012, (-0.2, yy, ROOF - 0.345), M["metal_dark"], parent, segments=20)
        sphere(f"CCTVDome_{k}", 0.07, (0.2, yy + 0.6, ROOF - 0.34), M["glass_dark"], parent, segments=18, rings=8)
        cylinder(f"CCTVDomeBase_{k}", 0.085, 0.015, (0.2, yy + 0.6, ROOF - 0.34), M["plastic_white"], parent, segments=20)
        empty(f"CCTV_Cam_{k}", (0.2, yy + 0.6, ROOF - 0.4), parent)

    # ---------------------------------------------------------------- duvar panelleri (pencere altı) + pencere çerçeveleri
    for side in (-1, 1):
        wp = box(f"WallPanelLow_{side}", (0.02, length - 0.1, 1.02), (side * (inner - 0.015), yc, F + 0.56), M["wall_panel"], parent)
        uv_box_project(wp, 1.0)
        box(f"WallSkirt_{side}", (0.03, length - 0.1, 0.08), (side * (inner - 0.02), yc, F + 0.07), M["rubber"], parent)
        box(f"WallBelt_{side}", (0.025, length - 0.1, 0.03), (side * (inner - 0.02), yc, F + 1.14), M["metal"], parent)
        for (cy, w) in window_spans(front_cab, rear_cab, door_ys, L):
            # Alüminyum çerçeve + conta
            for dz in (-0.5, 0.5):
                rounded_box(f"WinFrameH_{side}_{cy:.1f}_{dz}", (0.03, w + 0.1, 0.035), (side * (inner - 0.02), cy, F + 1.65 + dz), M["metal"], parent, bevel=0.005)
            for dy in (-1, 1):
                rounded_box(f"WinFrameV_{side}_{cy:.1f}_{dy}", (0.03, 0.035, 1.0), (side * (inner - 0.02), cy + dy * (w / 2 + 0.03), F + 1.65), M["metal"], parent, bevel=0.005)
            for dz in (-0.47, 0.47):
                box(f"WinSealH_{side}_{cy:.1f}_{dz}", (0.014, w + 0.04, 0.05), (side * (inner - 0.045), cy, F + 1.65 + dz), M["rubber"], parent)
            for dy in (-1, 1):
                box(f"WinSealV_{side}_{cy:.1f}_{dy}", (0.014, 0.05, 0.99), (side * (inner - 0.045), cy + dy * (w / 2 - 0.005), F + 1.65), M["rubber"], parent)
            # Pencere üstü reklam panosu
            rounded_box(f"AdFrame_{side}_{cy:.1f}", (0.02, min(w, 1.2), 0.22), (side * (inner - 0.02), cy, F + 2.28), M["plastic_white"], parent, bevel=0.003)
            plane(f"AdPanel_{side}_{cy:.1f}", min(w, 1.2) - 0.03, 0.19, (side * (inner - 0.032), cy, F + 2.28), M["paper"], parent, rot=(math.radians(90), 0, math.radians(90 if side < 0 else -90)))

    # ---------------------------------------------------------------- koltuklar
    spans = []
    prev = y_a + 0.4
    for y in ys:
        spans.append((prev, y - 0.9))
        prev = y + 0.9
    spans.append((prev, y_b - 0.4))
    seat_i = 0
    for side in (-1, 1):
        for (a, b) in spans:
            w = b - a
            if w < 0.8:
                continue
            nseat = max(1, int(w / 0.47))
            pitch = w / nseat
            for i in range(nseat):
                yy = a + pitch * (i + 0.5)
                seat_unit(f"Seat_{seat_i}", side * (inner - 0.3), yy, side, M, parent, F)
                seat_i += 1
            # Bölücü/kolçak panelleri (uçlarda) ve koltuk altı kiriş
            for yy in (a, b):
                rounded_box(f"SeatDiv_{side}_{yy:.1f}", (0.48, 0.03, 0.38), (side * (inner - 0.28), yy, F + 0.6), M["plastic_grey"], parent, bevel=0.008)
                box(f"SeatDivGlass_{side}_{yy:.1f}", (0.4, 0.012, 0.6), (side * (inner - 0.32), yy, F + 1.05), M["glass"], parent)
            box(f"SeatBeam_{side}_{a:.1f}", (0.06, w, 0.05), (side * (inner - 0.3), (a + b) / 2, F + 0.38), M["metal_dark"], parent)

    # ---------------------------------------------------------------- direkler, tutamak rayları, halkalar
    for y in ys:
        for sx in (-0.72, 0.72):
            yy = y + 0.8 * (1 if sx > 0 else -1)
            cylinder(f"Pole_{y}_{sx}", 0.018, ROOF - F - 0.36, (sx, yy, F + (ROOF - F - 0.36) / 2), M["metal"], parent, segments=14)
            cylinder(f"PoleFoot_{y}_{sx}", 0.035, 0.02, (sx, yy, F + 0.04), M["metal_dark"], parent, segments=14)
    # Üç kollu orta direk (kapı aralarında, salon ortası)
    mids = []
    for (a, b) in spans:
        if b - a > 2.5:
            mids.append((a + b) / 2)
    for i, ym in enumerate(mids):
        # Direk gövdesi zeminden kol ayrımına (zemin +1,95 m) kadar; kollar baş hizasının üstünde
        split = F + 1.95
        cylinder(f"TriPole_{i}", 0.02, split - F - 0.05, (0, ym, F + 0.05 + (split - F - 0.05) / 2), M["metal"], parent, segments=14)
        cylinder(f"TriPoleFoot_{i}", 0.04, 0.02, (0, ym, F + 0.04), M["metal_dark"], parent, segments=14)
        cylinder(f"TriHub_{i}", 0.035, 0.05, (0, ym, split), M["metal_dark"], parent, segments=14)
        for k in range(3):
            a = math.radians(90 + k * 120)
            cylinder(f"TriArm_{i}_{k}", 0.016, 0.3, (math.cos(a) * 0.12, ym + math.sin(a) * 0.12, split + 0.1), M["metal"], parent, rot=(math.radians(-50) * math.sin(a), math.radians(50) * math.cos(a), 0), segments=12)
            cylinder(f"TriArmUp_{i}_{k}", 0.016, ROOF - 0.33 - (split + 0.2), (math.cos(a) * 0.24, ym + math.sin(a) * 0.24, (split + 0.2 + ROOF - 0.33) / 2), M["metal"], parent, segments=12)
    for sx in (-0.92, 0.92):
        cylinder(f"Handrail_{sx}", 0.016, length - 0.8, (sx, yc, ROOF - 0.62), M["metal"], parent, rot=(math.radians(90), 0, 0), segments=12)
        for k in range(int((length - 0.8) / 2.2) + 1):
            yk = y_a + 0.5 + k * 2.2
            cylinder(f"HandrailPost_{sx}_{k}", 0.012, 0.25, (sx, yk, ROOF - 0.49), M["metal"], parent, segments=8)
        for k in range(int(length / 0.7)):
            y = y_a + 0.45 + k * 0.7
            box(f"Strap_{sx}_{k}", (0.025, 0.012, 0.16), (sx, y, ROOF - 0.71), M["plastic_dark"], parent)
            torus(f"StrapRing_{sx}_{k}", 0.055, 0.009, (sx, y, ROOF - 0.84), M["accent"], parent, rot=(0, math.radians(90), 0), segments=20, rings=6)

    # ---------------------------------------------------------------- kapı mekanizması + eşik + kapı üstü ekipman
    for y in ys:
        for side in (-1, 1):
            box(f"Threshold_{side}_{y}", (0.25, 1.4, 0.012), (side * (inner - 0.12), y, F + 0.036), M["accent"], parent)
            # Kapı cebi çerçevesi (açıklığın iki yanı) ve kauçuk kenar
            for dy in (-1, 1):
                rounded_box(f"DoorJamb_{side}_{y}_{dy}", (0.05, 0.06, 1.98), (side * (inner - 0.03), y + dy * 0.69, F + 0.99), M["plastic_grey"], parent, bevel=0.006)
            rounded_box(f"DoorHead_{side}_{y}", (0.05, 1.44, 0.06), (side * (inner - 0.03), y, F + 2.0), M["plastic_grey"], parent, bevel=0.006)
            # Üst kılavuz ray kutusu + makaralar
            rounded_box(f"DoorRailBox_{side}_{y}", (0.08, 2.9, 0.12), (side * (inner - 0.08), y, F + 2.1), M["metal_painted"], parent, bevel=0.006)
            for k in range(4):
                cylinder(f"DoorRoller_{side}_{y}_{k}", 0.02, 0.015, (side * (inner - 0.05), y - 0.9 + k * 0.6, F + 2.06), M["metal"], parent, rot=(0, math.radians(90), 0), segments=12)
            # Kapı üstü: acil kapı açma kutusu (kırmızı) + "kapılara yaslanmayın" plakası
            rounded_box(f"EmergRelease_{side}_{y}", (0.04, 0.12, 0.09), (side * (inner - 0.04), y + 0.85, F + 2.2), M["btn_red"], parent, bevel=0.004)
            cylinder(f"EmergReleaseHandle_{side}_{y}", 0.01, 0.05, (side * (inner - 0.065), y + 0.85, F + 2.2), M["plastic_white"], parent, rot=(0, math.radians(90), 0), segments=8)
            box(f"DoorSign_{side}_{y}", (0.004, 0.2, 0.06), (side * (inner - 0.062), y - 0.85, F + 2.2), M["paper"], parent)
        # Acil çağrı kutusu (sağ kapı yanı, bir kapıda)
    if ys:
        y0 = ys[len(ys) // 2]
        rounded_box("IntercomBox", (0.03, 0.14, 0.2), (inner - 0.03, y0 + 1.0, F + 1.35), M["metal_painted"], parent, bevel=0.004)
        cylinder("IntercomBtn", 0.02, 0.012, (inner - 0.05, y0 + 1.0, F + 1.38), M["btn_red"], parent, rot=(0, math.radians(90), 0), segments=14)
        cylinder("IntercomGrille", 0.035, 0.004, (inner - 0.046, y0 + 1.0, F + 1.3), M["metal_dark"], parent, rot=(0, math.radians(90), 0), segments=16)
        # Yangın tüpü (sol kapı yanı)
        cylinder("SaloonExt", 0.06, 0.4, (-(inner - 0.1), y0 - 1.05, F + 0.75), M["btn_red"], parent, segments=18, bevel=0.01)
        rounded_box("SaloonExtBracket", (0.05, 0.14, 0.03), (-(inner - 0.04), y0 - 1.05, F + 0.62), M["metal_dark"], parent, bevel=0.004)
        cylinder("SaloonExtTop", 0.03, 0.05, (-(inner - 0.1), y0 - 1.05, F + 0.98), M["metal_dark"], parent, segments=12)
    # Kapı üstü ekranlar: LED PIS (her kapı) + hat haritası (her iki kapıda bir)
    for i, y in enumerate(ys):
        for side in (-1, 1):
            rounded_box(f"PISBox_{side}_{y}", (0.06, 0.9, 0.16), (side * 0.55, y, ROOF - 0.5), M["plastic_dark"], parent, rot=(0, math.radians(-25 * side), 0), bevel=0.006)
            plane(f"PIS_{side}_{y}", 0.84, 0.11, (side * 0.52, y, ROOF - 0.5), M["dest"], parent, rot=(math.radians(90), 0, math.radians(90 if side < 0 else -90)))
            plane(f"RouteMap_{side}_{y}", 1.3, 0.14, (side * (inner - 0.11), y, F + 2.28), M["paper"], parent, rot=(math.radians(90), 0, math.radians(90 if side < 0 else -90)))
            rounded_box(f"RouteMapFrame_{side}_{y}", (0.02, 1.34, 0.18), (side * (inner - 0.1), y, F + 2.28), M["plastic_white"], parent, bevel=0.003)

    # ---------------------------------------------------------------- uç duvarlar / geçiş
    if front_cab:
        pass   # bölme duvarı build_cabin.bulkhead_front ile
    if rear_cab:
        pass
    for (y_e, s, has) in ((-L / 2, -1, not rear_cab), (L / 2, 1, not front_cab)):
        if not has:
            continue
        gangway(M, parent, y_e, s, inner, F, ROOF)


def gangway(M, parent, y_e, s, inner, F, ROOF):
    """Vagonlar arası geçiş: uç duvar çerçevesi, körük halkaları, geçiş plakası, yan paneller."""
    tag = "R" if s < 0 else "F"
    # Uç duvar (açıklık 1.3 x 2.05 ortada)
    h = ROOF - F - 0.3
    for sx in (-1, 1):
        box(f"EndWall_{tag}_{sx}", (inner - 0.65, 0.06, h), (sx * (0.65 + inner) / 2, y_e - s * 0.2, F + h / 2), M["interior"], parent)
    box(f"EndWallTop_{tag}", (1.3, 0.06, h - 2.05), (0, y_e - s * 0.2, F + 2.05 + (h - 2.05) / 2), M["interior"], parent)
    for sx in (-0.67, 0.67):
        rounded_box(f"GangJamb_{tag}_{sx}", (0.06, 0.1, 2.06), (sx, y_e - s * 0.2, F + 1.03), M["plastic_grey"], parent, bevel=0.006)
    rounded_box(f"GangHead_{tag}", (1.4, 0.1, 0.06), (0, y_e - s * 0.2, F + 2.07), M["plastic_grey"], parent, bevel=0.006)
    # Geçiş plakası (araç dışına 0.32 m taşar; karşı plaka ile buluşur)
    gp = rounded_box(f"GangPlate_{tag}", (1.2, 0.56, 0.03), (0, y_e + s * 0.08, F + 0.02), M["rubber_ribbed"], parent, bevel=0.004)
    uv_box_project(gp, 2.0)
    # Körük: dikdörtgen halkalar (kauçuk), 4 adet
    for k in range(4):
        yy = y_e - s * 0.08 + s * k * 0.11
        for (sz, loc) in (((0.05, 0.04, 2.15), (-0.72, yy, F + 1.05)), ((0.05, 0.04, 2.15), (0.72, yy, F + 1.05)),
                          ((1.5, 0.04, 0.05), (0, yy, F + 2.15)), ((1.5, 0.04, 0.05), (0, yy, F - 0.02))):
            rounded_box(f"Bellow_{tag}_{k}_{loc[0]:.1f}_{loc[2]:.1f}", sz, loc, M["rubber"], parent, bevel=0.01)
    # Yan paneller + tavan (körük içi)
    for sx in (-1, 1):
        box(f"GangWall_{tag}_{sx}", (0.02, 0.6, 2.05), (sx * 0.68, y_e + s * 0.1, F + 1.03), M["plastic_grey"], parent)
    box(f"GangCeil_{tag}", (1.36, 0.6, 0.02), (0, y_e + s * 0.1, F + 2.08), M["plastic_grey"], parent)
    # Tutamak (geçiş kenarı)
    for sx in (-0.6, 0.6):
        cylinder(f"GangHandle_{tag}_{sx}", 0.014, 0.6, (sx, y_e - s * 0.26, F + 1.3), M["metal"], parent, segments=10)
