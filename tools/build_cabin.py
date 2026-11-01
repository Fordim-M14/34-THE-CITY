"""
build_cabin.py — ARS T-400 makinist kabini v4 (build_train.py tarafından çağrılır).

Hedef: "kutulardan oluşmuş" görünümden gerçek metro kabinine. Konsol profil ekstrüzyonu
(diz boşluğu, eğik ön yüz, yuvarlatılmış kenarlar), fiziksel master kol (kapılı yuva, körük,
kavrama), yön kolu, ikaz lambaları, aydınlatmalı düğmeler (bezel + halka + kapak), anahtar
şalter, parlaklık potansiyometresi, cam kubbeli hız saati, MMI + yumuşak tuşlar, CCTV monitörü
(sol A sütunu), telsiz ünitesi (ekran, düğmeler, ahize yuvası), koltuk (bolsterli, raylı,
kolçaklı), ölü adam pedalı, menteşeli kabin kapısı (CabDoorPivot), yan cam çerçeveleri + conta
+ sürgü, tavan armatürü, hoparlör, havalandırma, kablo kanalı, duvar panel derzleri + vidalar,
sigorta panosu, yangın tüpü + braket, güneşlik, bayrak, çay, sefer çizelgesi...

Godot'un aradığı adlar korunur: Cam_Eye, Ctl_lever, Ctl_reverser, Btn_*, Lamp_*, Speedo_Needle,
Speedo_Ticks, SpeedDigital, MMI_Screen, CabinLight, CabLightStrip, ARSPlate, Timetable.
Yeni adlar: CCTV_Screen, Sw_* (şalter), Knob_* (potansiyometre), Radio_Display, CabDoorPivot,
Pedal_deadman, CabSeat_* (koltuk).
"""
import bpy, bmesh, math
from mathutils import Vector
from blender_common import *


def prism_x(name, profile, x0, x1, material, parent=None, bevel=0.0, smooth=False):
    """(y,z) kapalı profili X ekseni boyunca x0..x1 arasında ekstrüde eder."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for (y, z) in profile]
    b = [bm.verts.new((x1, y, z)) for (y, z) in profile]
    n = len(profile)
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(n):
        bm.faces.new((a[i], b[i], b[(i + 1) % n], a[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bmesh(name, bm, material, smooth=smooth, parent=parent)
    if bevel > 0:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        mod.limit_method = "ANGLE"
    return ob


def rounded_box(name, size, loc, material, parent, rot=(0, 0, 0), bevel=0.02, segments=4):
    ob = box(name, size, loc, material, parent, rot=rot)
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = min(bevel, min(size) * 0.45)
    mod.segments = segments
    mod.limit_method = "ANGLE"
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.use_auto_smooth = True
    ob.data.auto_smooth_angle = math.radians(40)
    return ob


def torus(name, major, minor, loc, material, parent, rot=(0, 0, 0), segments=24, rings=8):
    bm = bmesh.new()
    verts = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        ring = []
        for j in range(rings):
            b = 2 * math.pi * j / rings
            r = major + minor * math.cos(b)
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        verts.append(ring)
    for i in range(segments):
        for j in range(rings):
            v1 = verts[i][j]
            v2 = verts[(i + 1) % segments][j]
            v3 = verts[(i + 1) % segments][(j + 1) % rings]
            v4 = verts[i][(j + 1) % rings]
            bm.faces.new((v1, v2, v3, v4))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bmesh(name, bm, material, smooth=True, parent=parent)
    ob.location = loc
    ob.rotation_euler = rot
    return ob


def build(M, parent, L, HW, FLOOR, ROOF, CAB_Y):
    yt = L / 2
    inner = HW - 0.06
    cab_len = yt - CAB_Y
    yc = CAB_Y + cab_len / 2
    F = FLOOR

    # ------------------------------------------------------------------ zemin / tavan
    fl = box("CabFloor", (inner * 2, cab_len, 0.03), (0, yc, F + 0.015), M["floor"], parent)
    uv_box_project(fl, 0.8)
    mat_ = box("FloorMat", (1.0, 1.1, 0.012), (-0.3, CAB_Y + 0.95, F + 0.036), M["rubber_ribbed"], parent, bevel=0.004)
    uv_box_project(mat_, 2.0)
    ce = box("CabCeiling", (inner * 2 - 0.4, cab_len - 0.3, 0.03), (0, yc, ROOF - 0.32), M["plastic_grey"], parent)
    uv_box_project(ce, 1.0)
    # Tavan armatürü: çerçeve + difüzör + iki vida
    rounded_box("CabLightFrame", (1.0, 0.32, 0.035), (0, CAB_Y + 1.0, ROOF - 0.335), M["metal_dark"], parent, bevel=0.008)
    box("CabLightStrip", (0.92, 0.24, 0.02), (0, CAB_Y + 1.0, ROOF - 0.345), M["light"], parent)
    empty("CabinLight", (0, CAB_Y + 1.0, ROOF - 0.5), parent)
    # Hoparlör (tavan), havalandırma menfezi, kablo kanalı
    cylinder("CabSpeaker", 0.07, 0.015, (-0.6, CAB_Y + 0.5, ROOF - 0.345), M["metal_dark"], parent, segments=24)
    for k in range(5):
        torus(f"SpeakerRing_{k}", 0.012 + k * 0.012, 0.0025, (-0.6, CAB_Y + 0.5, ROOF - 0.353), M["metal_dark"], parent, segments=20, rings=6)
    rounded_box("CeilVent", (0.42, 0.26, 0.02), (0.5, CAB_Y + 1.5, ROOF - 0.33), M["metal_dark"], parent, bevel=0.005)
    for k in range(7):
        s = box(f"VentSlat_{k}", (0.36, 0.014, 0.008), (0.5, CAB_Y + 1.4 + k * 0.034, ROOF - 0.342), M["metal"], parent)
        s.rotation_euler = (math.radians(35), 0, 0)
    for side in (-1, 1):
        box(f"CableDuct_{side}", (0.09, cab_len - 0.4, 0.06), (side * (inner - 0.25), yc, ROOF - 0.36), M["plastic_grey"], parent, bevel=0.006)

    # ------------------------------------------------------------------ göz noktası
    empty("Cam_Eye", (-0.3, CAB_Y + 0.65, F + 1.25), parent)

    # ------------------------------------------------------------------ A sütunları / ön cam çerçevesi / güneşlik
    for side in (-1, 1):
        rounded_box(f"APillar_{side}", (0.08, 0.32, 1.38), (side * 1.09, yt - 0.5, F + 1.56), M["plastic_grey"], parent, bevel=0.012)
        box(f"WsSeal_{side}", (0.02, 0.1, 1.34), (side * 1.045, yt - 0.42, F + 1.58), M["rubber"], parent)
    rounded_box("WsTop", (2.24, 0.36, 0.09), (0, yt - 0.5, ROOF - 0.24), M["plastic_grey"], parent, bevel=0.012)
    box("WsSealTop", (2.1, 0.1, 0.02), (0, yt - 0.42, ROOF - 0.285), M["rubber"], parent)
    rounded_box("VisorBox", (0.62, 0.07, 0.07), (-0.3, yt - 0.72, ROOF - 0.33), M["plastic_dark"], parent, bevel=0.01)
    vis = plane("SunVisor", 0.58, 0.16, (-0.3, yt - 0.73, ROOF - 0.45), M["visor"], parent, rot=(math.radians(90), 0, 0))
    M["visor"].use_backface_culling = False

    # ------------------------------------------------------------------ konsol gövdesi (profil ekstrüzyonu)
    desk_rear = CAB_Y + 1.1      # 9.10
    desk_front = yt - 0.95       # 9.80
    tilt = math.radians(28)
    pc_y, pc_z = desk_front - 0.2, F + 0.93      # panel merkezi
    prof = [
        (desk_rear + 0.22, F + 0.0), (desk_front + 0.12, F + 0.0), (desk_front + 0.12, F + 0.62),
        (desk_front + 0.06, F + 1.0), (pc_y + 0.21 * math.cos(tilt), F + 1.03),
        (pc_y - 0.21 * math.cos(tilt), F + 0.835), (desk_rear + 0.0, F + 0.82),
        (desk_rear - 0.02, F + 0.76), (desk_rear - 0.02, F + 0.62), (desk_rear + 0.22, F + 0.60),
    ]
    body = prism_x("DeskBody", prof, -(inner - 0.15), inner - 0.15, M["plastic_dark"], parent, bevel=0.025)
    uv_box_project(body, 2.0)
    # Yan kanatlar (hafif açılı, makinisti sarar)
    for side in (-1, 1):
        w = rounded_box(f"DeskWing_{side}", (0.26, 0.5, 0.06), (side * (inner - 0.17), desk_rear + 0.33, F + 0.80), M["plastic_dark"], parent, bevel=0.012)
        w.rotation_euler = (0, 0, math.radians(-14 * side))
    # Kol dayama (ön kenar yastığı), diz koruma
    rounded_box("DeskArmPad", (2.3, 0.09, 0.035), (0, desk_rear + 0.03, F + 0.845), M["rubber"], parent, bevel=0.012)
    box("DeskKneePanel", (2.2, 0.02, 0.56), (0, desk_rear + 0.21, F + 0.3), M["plastic_grey"], parent)
    # Eğik gösterge paneli (koyu, mat) + çerçeve
    pw = rounded_box("DeskPanel", (inner * 2 - 0.42, 0.42, 0.045), (0, pc_y, pc_z), M["panel"], parent, rot=(tilt, 0, 0), bevel=0.008)
    frame = rounded_box("DeskPanelFrame", (inner * 2 - 0.36, 0.46, 0.03), (0, pc_y, pc_z - 0.012), M["metal_painted"], parent, rot=(tilt, 0, 0), bevel=0.008)

    def on_panel(x, t, lift=0.03):
        y = pc_y + t * math.cos(tilt) - lift * math.sin(tilt)
        z = pc_z + t * math.sin(tilt) + lift * math.cos(tilt)
        return (x, y, z)

    def on_desk(x, y, lift=0.0):
        return (x, y, F + 0.835 + lift)

    # ------------------------------------------------------------------ MMI ekranı (sol)
    rounded_box("MMI_Frame", (0.50, 0.36, 0.03), on_panel(-0.55, 0.0, 0.015), M["plastic_dark"], parent, rot=(tilt, 0, 0), bevel=0.008)
    box("MMI_Bezel", (0.44, 0.30, 0.006), on_panel(-0.55, 0.0, 0.031), M["panel"], parent, rot=(tilt, 0, 0))
    plane("MMI_Screen", 0.40, 0.27, on_panel(-0.55, 0.005, 0.036), M["screen"], parent, rot=(tilt + math.radians(90), 0, 0))
    for i, bx in enumerate((-0.72, -0.615, -0.51, -0.405)):
        rounded_box(f"MMIKeyBase_{i}", (0.07, 0.03, 0.01), on_panel(bx, -0.165, 0.024), M["plastic_grey"], parent, rot=(tilt, 0, 0), bevel=0.003)
        rounded_box(f"Btn_mmi_{i}", (0.06, 0.022, 0.012), on_panel(bx, -0.165, 0.034), M["btn_grey"], parent, rot=(tilt, 0, 0), bevel=0.004)
    # Parlaklık potansiyometresi (MMI sağ altı)
    cylinder("KnobBase_brightness", 0.018, 0.008, on_panel(-0.30, -0.165, 0.025), M["metal_dark"], parent, rot=(tilt, 0, 0), segments=16)
    kb = cylinder("Knob_brightness", 0.014, 0.022, on_panel(-0.30, -0.165, 0.038), M["plastic_dark"], parent, rot=(tilt, 0, 0), segments=16, bevel=0.003)
    box("KnobMark_brightness", (0.003, 0.012, 0.004), (0, 0.004, 0.011), M["flag_white"], kb)

    # ------------------------------------------------------------------ hız saati (orta-sağ) + cam kubbe
    cylinder("SpeedoBezel", 0.145, 0.035, on_panel(0.18, 0.02, 0.018), M["metal_dark"], parent, rot=(tilt, 0, 0), segments=48, bevel=0.006)
    cylinder("SpeedoFace", 0.125, 0.012, on_panel(0.18, 0.02, 0.035), M["dial"], parent, rot=(tilt, 0, 0), segments=48)
    torus("SpeedoRing", 0.128, 0.004, on_panel(0.18, 0.02, 0.041), M["metal"], parent, rot=(tilt, 0, 0), segments=48, rings=8)
    needle_parent = empty("Speedo_Needle", on_panel(0.18, 0.02, 0.046), parent, rot=(tilt, 0, 0))
    box("NeedleBody", (0.007, 0.115, 0.003), (0, 0.045, 0), M["needle"], needle_parent)
    box("NeedleTail", (0.009, 0.03, 0.003), (0, -0.015, 0), M["metal_dark"], needle_parent)
    cylinder("NeedleHub", 0.013, 0.008, (0, 0, 0), M["metal_dark"], needle_parent, segments=12)
    ticks_parent = empty("Speedo_Ticks", on_panel(0.18, 0.02, 0.044), parent, rot=(tilt, 0, 0))
    for i in range(41):
        ang = math.radians(-135 + i * (270 / 40))
        major = i % 5 == 0
        t = box(f"Tick_{i}", (0.004 if major else 0.002, 0.022 if major else 0.012, 0.002), (0, 0, 0), M["interior_dark"], ticks_parent)
        t.location = (math.sin(ang) * (0.105 if major else 0.11), math.cos(ang) * (0.105 if major else 0.11), -0.004)
        t.rotation_euler = (0, 0, -ang)
    # Kırmızı bölge (70-80 km/s) yay parçaları
    for i in range(6):
        ang = math.radians(-135 + (35 + i) * (270 / 40))
        r = box(f"RedZone_{i}", (0.006, 0.016, 0.002), (0, 0, 0), M["needle"], ticks_parent)
        r.location = (math.sin(ang) * 0.118, math.cos(ang) * 0.118, -0.005)
        r.rotation_euler = (0, 0, -ang)
    gl = cylinder("SpeedoGlass", 0.13, 0.004, on_panel(0.18, 0.02, 0.058), M["glass_cab"], parent, rot=(tilt, 0, 0), segments=48)
    # Dijital hız göstergesi (saatin altında) + çerçeve
    rounded_box("SpeedDigitalFrame", (0.19, 0.08, 0.012), on_panel(0.18, -0.17, 0.024), M["plastic_dark"], parent, rot=(tilt, 0, 0), bevel=0.004)
    plane("SpeedDigital", 0.16, 0.06, on_panel(0.18, -0.17, 0.032), M["screen"], parent, rot=(tilt + math.radians(90), 0, 0))

    # ------------------------------------------------------------------ ikaz lambaları (sağ, 2x3) — çerçeveli lamba modülü
    rounded_box("LampCluster", (0.62, 0.30, 0.012), on_panel(0.80, 0.02, 0.022), M["plastic_grey"], parent, rot=(tilt, 0, 0), bevel=0.004)
    lamps = ["doors", "emergency", "atp", "traction", "fault", "message"]
    for i, lid in enumerate(lamps):
        col = i % 2
        row = i // 2
        cx = 0.66 + col * 0.28
        cy = 0.11 - row * 0.09
        rounded_box(f"LampFrame_{lid}", (0.25, 0.07, 0.008), on_panel(cx, cy, 0.027), M["metal_dark"], parent, rot=(tilt, 0, 0), bevel=0.003)
        rounded_box(f"Lamp_{lid}", (0.055, 0.035, 0.012), on_panel(cx - 0.085, cy, 0.034), M["lamp_off"], parent, rot=(tilt, 0, 0), bevel=0.003)

    # ------------------------------------------------------------------ master kol (sağ el)
    lx, ly = 0.22, desk_rear + 0.30
    rounded_box("LeverGate", (0.24, 0.46, 0.035), (lx, ly, F + 0.84), M["metal_painted"], parent, bevel=0.008)
    box("LeverSlot", (0.05, 0.36, 0.01), (lx, ly, F + 0.855), M["rubber"], parent)
    # Kademe çentikleri (P4..B7 etiketleri Godot'ta)
    for k in range(-7, 5):
        box(f"LeverNotch_{k + 7}", (0.03 if k == 0 else 0.018, 0.004, 0.003), (lx + 0.07, ly + k * 0.028, F + 0.859), M["flag_white"] if k == 0 else M["interior_dark"], parent)
    lev = empty("Ctl_lever", (lx, ly, F + 0.855), parent)
    # Körük (üst üste halkalar), gövde, kavrama
    for k in range(6):
        torus(f"LeverBellow_{k}", 0.024 - (k % 2) * 0.004, 0.006, (0, 0, 0.012 + k * 0.012), M["rubber"], lev, segments=20, rings=6)
    cylinder("LeverStem", 0.014, 0.22, (0, 0, 0.17), M["metal"], lev, segments=16)
    grip = rounded_box("LeverKnob", (0.13, 0.075, 0.055), (0, 0.0, 0.29), M["rubber"], parent=lev, bevel=0.02, segments=5)
    rounded_box("LeverGripPad", (0.08, 0.03, 0.035), (0, -0.045, 0.285), M["plastic_dark"], lev, bevel=0.01)
    cylinder("LeverButton", 0.008, 0.006, (0, 0.0, 0.32), M["btn_red"], lev, segments=12)

    # ------------------------------------------------------------------ yön kolu (sol el) — 3 konumlu plaka
    rx, ry = -0.85, desk_rear + 0.30
    rounded_box("RevGate", (0.16, 0.22, 0.035), (rx, ry, F + 0.84), M["metal_painted"], parent, bevel=0.008)
    for k, lbl in ((-1, "G"), (0, "N"), (1, "İ")):
        box(f"RevNotch_{k + 1}", (0.03, 0.004, 0.003), (rx + 0.05, ry + k * 0.05, F + 0.859), M["flag_white"], parent)
    rev = empty("Ctl_reverser", (rx, ry, F + 0.855), parent)
    cylinder("RevStem", 0.01, 0.13, (0, 0, 0.065), M["metal"], rev, segments=12)
    kn = cylinder("RevKnob", 0.022, 0.05, (0, 0, 0.15), M["rubber"], rev, segments=18, bevel=0.006)
    for k in range(12):
        a = 2 * math.pi * k / 12
        box(f"RevKnurl_{k}", (0.004, 0.004, 0.045), (math.cos(a) * 0.022, math.sin(a) * 0.022, 0.15), M["rubber"], rev, rot=(0, 0, a))

    # ------------------------------------------------------------------ düğmeler (aydınlatmalı)
    btns = [
        ("doors_left_open", "green", (-1.05, desk_rear + 0.20)), ("doors_left_close", "red", (-1.05, desk_rear + 0.36)),
        ("doors_right_open", "green", (1.05, desk_rear + 0.20)), ("doors_right_close", "red", (1.05, desk_rear + 0.36)),
        ("headlights", "yellow", (-0.50, desk_rear + 0.52)), ("cabin_light", "grey", (-0.36, desk_rear + 0.52)),
        ("horn", "grey", (0.48, desk_rear + 0.52)), ("acknowledge", "blue", (0.62, desk_rear + 0.52)),
        ("emergency_reset", "grey", (0.90, desk_rear + 0.30)),
        ("cctv_toggle", "grey", (-0.66, desk_rear + 0.52)), ("cctv_next", "blue", (-0.80, desk_rear + 0.52)),
        ("pis_announce", "yellow", (0.76, desk_rear + 0.52)),
    ]
    for bid, col, (bx, by) in btns:
        cylinder(f"BtnBezel_{bid}", 0.038, 0.014, (bx, by, F + 0.838), M["metal_dark"], parent, segments=24, bevel=0.003)
        torus(f"BtnRing_{bid}", 0.030, 0.0035, (bx, by, F + 0.847), M["btn_" + col], parent, segments=24, rings=6)
        cylinder(f"Btn_{bid}", 0.025, 0.022, (bx, by, F + 0.852), M["btn_" + col], parent, segments=24, bevel=0.005)
        box(f"BtnLabelPlate_{bid}", (0.085, 0.022, 0.004), (bx, by - 0.055, F + 0.836), M["plastic_grey"], parent)
    # Anahtar şalterler (rocker): far modu, silecek, kabin fanı, anons dili
    sws = [("headlight_mode", (-0.22, desk_rear + 0.52)), ("wiper", (-0.08, desk_rear + 0.52)),
           ("cab_fan", (0.12, desk_rear + 0.52)), ("pis_lang", (0.28, desk_rear + 0.52))]
    for sid, (sx, sy) in sws:
        rounded_box(f"SwBase_{sid}", (0.05, 0.08, 0.012), (sx, sy, F + 0.84), M["metal_dark"], parent, bevel=0.003)
        piv = empty(f"Sw_{sid}", (sx, sy, F + 0.846), parent)
        rounded_box(f"SwRocker_{sid}", (0.036, 0.062, 0.016), (0, 0, 0.008), M["plastic_dark"], piv, rot=(math.radians(-10), 0, 0), bevel=0.004)
        box(f"SwLabelPlate_{sid}", (0.07, 0.02, 0.004), (sx, sy - 0.06, F + 0.836), M["plastic_grey"], parent)
    # Anahtar (kontak) — sağ kanat
    cylinder("KeySwitchBase", 0.02, 0.01, (1.12, desk_rear + 0.52, F + 0.84), M["metal_dark"], parent, segments=16)
    cylinder("KeySwitch", 0.012, 0.012, (1.12, desk_rear + 0.52, F + 0.85), M["metal"], parent, segments=12)
    box("KeyBlade", (0.004, 0.025, 0.018), (1.12, desk_rear + 0.52, F + 0.862), M["metal"], parent)
    box("KeyFob", (0.012, 0.03, 0.004), (1.12, desk_rear + 0.56, F + 0.838), M["plastic_dark"], parent)

    # ------------------------------------------------------------------ acil fren mantarı
    ex, ey = 0.55, desk_rear + 0.30
    cylinder("EmergBase", 0.06, 0.02, (ex, ey, F + 0.845), M["accent"], parent, segments=28)
    torus("EmergRing", 0.058, 0.006, (ex, ey, F + 0.855), M["accent"], parent, segments=28, rings=8)
    cylinder("EmergCollar", 0.035, 0.03, (ex, ey, F + 0.87), M["metal_dark"], parent, segments=24)
    cylinder("Btn_emergency_brake", 0.062, 0.045, (ex, ey, F + 0.905), M["btn_red"], parent, segments=32, bevel=0.016)
    box("KeyPlate", (0.13, 0.085, 0.004), (0.90, desk_rear + 0.30, F + 0.834), M["plastic_grey"], parent)

    # ------------------------------------------------------------------ CCTV monitörü (sol A sütunu, makiniste dönük)
    cx, cy, cz = -1.12, yt - 1.05, F + 1.38
    yaw = math.radians(38)
    cylinder("CCTVArm", 0.012, 0.22, (cx, cy + 0.11, cz - 0.18), M["metal_dark"], parent, rot=(math.radians(90), 0, 0), segments=10)
    cylinder("CCTVArmPost", 0.012, 0.3, (cx, cy + 0.22, cz - 0.3), M["metal_dark"], parent, segments=10)
    mon = rounded_box("CCTV_Frame", (0.34, 0.035, 0.24), (cx, cy, cz), M["plastic_dark"], parent, rot=(0, 0, yaw), bevel=0.01)
    scr = plane("CCTV_Screen", 0.30, 0.20, (cx + 0.019 * math.sin(yaw), cy - 0.019 * math.cos(yaw), cz), M["screen"], parent, rot=(math.radians(90), 0, yaw))
    for k in range(4):
        cylinder(f"CCTVBtn_{k}", 0.006, 0.006, (cx + (0.05 + k * 0.035) * math.cos(yaw) + 0.02 * math.sin(yaw), cy + (0.05 + k * 0.035) * math.sin(yaw) - 0.02 * math.cos(yaw), cz - 0.105), M["btn_grey"], parent, rot=(math.radians(90), 0, yaw), segments=10)

    # ------------------------------------------------------------------ telsiz ünitesi (sol konsol üstü)
    rdx, rdy = -0.98, desk_front - 0.07
    ru = rounded_box("RadioUnit", (0.26, 0.17, 0.10), (rdx, rdy, F + 0.885), M["plastic_dark"], parent, rot=(math.radians(-20), 0, 0), bevel=0.008)
    plane("Radio_Display", 0.13, 0.04, (rdx - 0.04, rdy - 0.088, F + 0.905), M["screen"], parent, rot=(math.radians(70), 0, 0))
    for k in range(4):
        rounded_box(f"RadioKey_{k}", (0.02, 0.012, 0.014), (rdx - 0.09 + k * 0.03, rdy - 0.087, F + 0.862), M["btn_grey"], parent, rot=(math.radians(-20), 0, 0), bevel=0.003)
    cylinder("RadioKnob_vol", 0.012, 0.02, (rdx + 0.08, rdy - 0.082, F + 0.905), M["plastic_dark"], parent, rot=(math.radians(70), 0, 0), segments=14)
    cylinder("RadioKnob_ch", 0.012, 0.02, (rdx + 0.08, rdy - 0.082, F + 0.87), M["plastic_dark"], parent, rot=(math.radians(70), 0, 0), segments=14)
    # Ahize yuvası + ahize + spiral kablo
    rounded_box("HandsetCradle", (0.06, 0.17, 0.03), (rdx - 0.18, rdy - 0.02, F + 0.85), M["plastic_grey"], parent, bevel=0.006)
    hs = rounded_box("Handset", (0.05, 0.17, 0.035), (rdx - 0.18, rdy - 0.02, F + 0.878), M["plastic_dark"], parent, bevel=0.012, segments=5)
    cylinder("Btn_radio_ptt", 0.01, 0.006, (rdx - 0.18, rdy - 0.02, F + 0.898), M["btn_grey"], parent, segments=12)
    for i in range(14):
        t = i / 13.0
        cylinder(f"Cord_{i}", 0.011, 0.004, (rdx - 0.18 + 0.03 * math.sin(t * 9.0), rdy + 0.07 + t * 0.1, F + 0.845 + 0.015 * math.cos(t * 9.0)), M["rubber"], parent, segments=8)

    # ------------------------------------------------------------------ sefer çizelgesi, çay, bayrak, sol kanat
    cb = rounded_box("Clipboard", (0.21, 0.29, 0.006), (0.93, desk_rear + 0.64, F + 0.838), M["plastic_dark"], parent, rot=(0, 0, math.radians(-8)), bevel=0.003)
    pp = box("Timetable", (0.19, 0.26, 0.002), (0.93, desk_rear + 0.64, F + 0.842), M["paper"], parent, rot=(0, 0, math.radians(-8)))
    rounded_box("Clip", (0.06, 0.02, 0.012), (0.91, desk_rear + 0.77, F + 0.846), M["metal"], parent, bevel=0.003)
    tx, ty = -1.0, desk_rear + 0.64
    cylinder("TeaSaucer", 0.045, 0.006, (tx, ty, F + 0.838), M["flag_white"], parent, segments=24)
    cylinder("TeaHolder", 0.05, 0.03, (tx, ty, F + 0.852), M["metal_dark"], parent, segments=24)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=20, radius1=0.027, radius2=0.021, depth=0.05)
    gl = obj_from_bmesh("TeaGlassLow", bm, M["tea_glass"], smooth=True, parent=parent)
    gl.location = (tx, ty, F + 0.867)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=20, radius1=0.021, radius2=0.03, depth=0.045)
    gu = obj_from_bmesh("TeaGlassUp", bm, M["tea_glass"], smooth=True, parent=parent)
    gu.location = (tx, ty, F + 0.9145)
    cylinder("TeaLiquid", 0.02, 0.07, (tx, ty, F + 0.882), M["tea"], parent, segments=16)
    box("TeaSpoon", (0.008, 0.07, 0.003), (tx + 0.05, ty - 0.02, F + 0.844), M["metal"], parent, rot=(0, 0, math.radians(30)))
    rounded_box("SugarBox", (0.05, 0.035, 0.02), (tx + 0.1, ty + 0.03, F + 0.852), M["paper"], parent, bevel=0.003)
    # Türk bayrağı (masa bayrağı)
    fx, fy = -1.14, desk_front - 0.02
    cylinder("FlagPole", 0.006, 0.26, (fx, fy, F + 1.0), M["brass"], parent, segments=8)
    sphere("FlagTop", 0.012, (fx, fy, F + 1.135), M["brass"], parent, segments=10, rings=6)
    cylinder("FlagBase", 0.03, 0.012, (fx, fy, F + 0.876), M["brass"], parent, segments=12)
    flag = plane("FlagCloth", 0.17, 0.11, (fx + 0.09, fy, F + 1.07), M["flag_red"], parent, rot=(math.radians(90), 0, 0))
    flag.rotation_euler = (math.radians(90), math.radians(-6), math.radians(-10))
    M["flag_red"].use_backface_culling = False
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=24, radius=0.03)
    outer = obj_from_bmesh("FlagCrescentOuter", bm, M["flag_white"], parent=parent)
    outer.location = (fx + 0.065, fy - 0.002, F + 1.07)
    outer.rotation_euler = (math.radians(90), 0, 0)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=24, radius=0.024)
    inner_c = obj_from_bmesh("FlagCrescentInner", bm, M["flag_red"], parent=parent)
    inner_c.location = (fx + 0.073, fy - 0.004, F + 1.07)
    inner_c.rotation_euler = (math.radians(90), 0, 0)
    bm = bmesh.new()
    pts = []
    for i in range(10):
        r = 0.016 if i % 2 == 0 else 0.0065
        a = math.radians(90 + i * 36)
        pts.append(bm.verts.new((math.cos(a) * r, 0.0, math.sin(a) * r)))
    bm.faces.new(pts)
    star = obj_from_bmesh("FlagStar", bm, M["flag_white"], parent=parent)
    star.location = (fx + 0.112, fy - 0.004, F + 1.07)
    M["flag_white"].use_backface_culling = False

    # ------------------------------------------------------------------ makinist koltuğu
    sx, sy = -0.3, CAB_Y + 0.5
    rounded_box("SeatRailL", (0.05, 0.5, 0.03), (sx - 0.2, sy, F + 0.045), M["metal_dark"], parent, bevel=0.006)
    rounded_box("SeatRailR", (0.05, 0.5, 0.03), (sx + 0.2, sy, F + 0.045), M["metal_dark"], parent, bevel=0.006)
    rounded_box("SeatBasePlate", (0.44, 0.44, 0.03), (sx, sy, F + 0.075), M["metal_painted"], parent, bevel=0.008)
    cylinder("SeatPost", 0.055, 0.3, (sx, sy, F + 0.24), M["metal_dark"], parent, segments=20)
    cylinder("SeatPostInner", 0.04, 0.12, (sx, sy, F + 0.42), M["metal"], parent, segments=16)
    torus("SeatBellow", 0.06, 0.012, (sx, sy, F + 0.36), M["rubber"], parent, segments=20, rings=6)
    cylinder("SeatHeightLever", 0.008, 0.18, (sx + 0.14, sy + 0.1, F + 0.42), M["metal_dark"], parent, rot=(0, math.radians(90), 0), segments=8)
    rounded_box("SeatHeightKnob", (0.04, 0.025, 0.025), (sx + 0.24, sy + 0.1, F + 0.42), M["plastic_dark"], parent, bevel=0.008)
    rounded_box("SeatPanFrame", (0.5, 0.5, 0.04), (sx, sy, F + 0.47), M["plastic_dark"], parent, bevel=0.012)
    rounded_box("CabSeat_Pan", (0.46, 0.46, 0.10), (sx, sy, F + 0.535), M["leather"], parent, bevel=0.035, segments=5)
    for bs in (-1, 1):
        rounded_box(f"CabSeat_PanBolster_{bs}", (0.09, 0.44, 0.13), (sx + bs * 0.215, sy + 0.02, F + 0.56), M["leather"], parent, bevel=0.035, segments=5)
    back = rounded_box("CabSeat_Back", (0.46, 0.10, 0.62), (sx, sy - 0.26, F + 0.9), M["leather"], parent, rot=(math.radians(-8), 0, 0), bevel=0.035, segments=5)
    for bs in (-1, 1):
        rounded_box(f"CabSeat_BackBolster_{bs}", (0.08, 0.12, 0.56), (sx + bs * 0.21, sy - 0.25, F + 0.9), M["leather"], parent, rot=(math.radians(-8), 0, 0), bevel=0.03, segments=5)
    rounded_box("CabSeat_Lumbar", (0.3, 0.04, 0.18), (sx, sy - 0.2, F + 0.75), M["leather"], parent, rot=(math.radians(-8), 0, 0), bevel=0.015)
    rounded_box("SeatBackShell", (0.48, 0.03, 0.64), (sx, sy - 0.33, F + 0.9), M["plastic_dark"], parent, rot=(math.radians(-8), 0, 0), bevel=0.01)
    for hp in (-0.06, 0.06):
        cylinder(f"HeadrestPost_{hp}", 0.007, 0.14, (sx + hp, sy - 0.30, F + 1.22), M["metal"], parent, segments=8)
    rounded_box("CabSeat_Headrest", (0.3, 0.09, 0.17), (sx, sy - 0.31, F + 1.31), M["leather"], parent, bevel=0.03, segments=5)
    for ax in (-0.3, 0.3):
        cylinder(f"ArmPost_{ax}", 0.012, 0.22, (sx + ax, sy + 0.02, F + 0.64), M["metal_dark"], parent, segments=10)
        rounded_box(f"CabSeat_Arm_{ax}", (0.07, 0.3, 0.045), (sx + ax, sy + 0.06, F + 0.76), M["rubber"], parent, bevel=0.015, segments=4)
    # Ölü adam pedalı (konsol altı)
    rounded_box("PedalBase", (0.16, 0.2, 0.02), (sx, desk_rear + 0.42, F + 0.04), M["metal_dark"], parent, bevel=0.004)
    ped = rounded_box("Pedal_deadman", (0.14, 0.18, 0.02), (sx, desk_rear + 0.42, F + 0.065), M["rubber_ribbed"], parent, rot=(math.radians(14), 0, 0), bevel=0.004)

    # ------------------------------------------------------------------ yan camlar: çerçeve, conta, sürgü, mandal
    wy = yt - 1.75
    for side in (-1, 1):
        for dz in (-0.47, 0.47):
            rounded_box(f"CabWinFrameH_{side}_{dz}", (0.035, 1.2, 0.035), (side * (inner - 0.02), wy, F + 1.65 + dz), M["plastic_grey"], parent, bevel=0.006)
        for dy in (-0.59, 0.59):
            rounded_box(f"CabWinFrameV_{side}_{dy}", (0.035, 0.035, 0.97), (side * (inner - 0.02), wy + dy, F + 1.65), M["plastic_grey"], parent, bevel=0.006)
        for dz in (-0.43, 0.43):
            box(f"CabWinSealH_{side}_{dz}", (0.014, 1.16, 0.05), (side * (inner - 0.045), wy, F + 1.65 + dz), M["rubber"], parent)
        for dy in (-0.555, 0.555):
            box(f"CabWinSealV_{side}_{dy}", (0.014, 0.05, 0.91), (side * (inner - 0.045), wy + dy, F + 1.65), M["rubber"], parent)
        box(f"CabWinSealIn_{side}", (0.014, 1.10, 0.85), (side * (inner - 0.046), wy, F + 1.65), M["glass_cab"], parent)
        box(f"CabWinSash_{side}", (0.03, 0.025, 0.86), (side * (inner - 0.03), wy + 0.02, F + 1.65), M["metal"], parent)
        rounded_box(f"CabWinLatch_{side}", (0.03, 0.05, 0.025), (side * (inner - 0.05), wy + 0.06, F + 1.25), M["plastic_dark"], parent, bevel=0.006)
    # Duvar panelleri: derz çizgileri + vidalar (pencere altı), tutamak
    for side in (-1, 1):
        for py in (CAB_Y + 0.35, CAB_Y + 0.95, CAB_Y + 1.55, CAB_Y + 2.15):
            box(f"WallSeam_{side}_{py:.1f}", (0.012, 0.008, 1.0), (side * (inner - 0.005), py, F + 0.6), M["rubber"], parent)
            for pz in (F + 0.15, F + 1.05):
                cylinder(f"Screw_{side}_{py:.1f}_{pz:.1f}", 0.005, 0.004, (side * (inner - 0.003), py + 0.03, pz), M["metal"], parent, rot=(0, math.radians(90), 0), segments=8)
        box(f"WallSeamH_{side}", (0.012, cab_len - 0.3, 0.008), (side * (inner - 0.005), yc, F + 1.1), M["rubber"], parent)
    cylinder("GrabHandle", 0.012, 0.35, (1.2, CAB_Y + 0.25, F + 1.5), M["metal"], parent, segments=10)
    for hz in (-0.16, 0.16):
        cylinder(f"GrabHandleFoot_{hz}", 0.012, 0.06, (1.24, CAB_Y + 0.25, F + 1.5 + hz), M["metal"], parent, rot=(0, math.radians(90), 0), segments=8)

    # ------------------------------------------------------------------ sağ taraf: sigorta panosu, yangın tüpü, çekiç, askı
    rounded_box("FusePanel", (0.03, 0.55, 0.62), (inner - 0.03, CAB_Y + 0.75, F + 1.55), M["metal_painted"], parent, bevel=0.006)
    for r in range(4):
        for c in range(6):
            rounded_box(f"Breaker_{r}_{c}", (0.012, 0.035, 0.06), (inner - 0.052, CAB_Y + 0.53 + c * 0.085, F + 1.32 + r * 0.14), M["plastic_dark"], parent, bevel=0.003)
            box(f"BreakerLed_{r}_{c}", (0.004, 0.012, 0.008), (inner - 0.058, CAB_Y + 0.53 + c * 0.085, F + 1.355 + r * 0.14), M["btn_green"] if (r + c) % 3 else M["lamp_off"], parent)
    box("FuseLabel", (0.004, 0.4, 0.05), (inner - 0.05, CAB_Y + 0.75, F + 1.9), M["paper"], parent)
    # Yangın tüpü + braket
    cylinder("Extinguisher", 0.065, 0.42, (inner - 0.14, CAB_Y + 0.25, F + 0.33), M["btn_red"], parent, segments=20, bevel=0.012)
    cylinder("ExtTop", 0.035, 0.05, (inner - 0.14, CAB_Y + 0.25, F + 0.565), M["metal_dark"], parent, segments=14)
    rounded_box("ExtLever", (0.015, 0.08, 0.012), (inner - 0.14, CAB_Y + 0.29, F + 0.6), M["metal_dark"], parent, bevel=0.003)
    cylinder("ExtHose", 0.008, 0.25, (inner - 0.18, CAB_Y + 0.26, F + 0.45), M["rubber"], parent, rot=(math.radians(10), 0, 0), segments=8)
    box("ExtLabel", (0.004, 0.09, 0.14), (inner - 0.074, CAB_Y + 0.25, F + 0.33), M["paper"], parent)
    rounded_box("ExtBracket", (0.05, 0.16, 0.04), (inner - 0.08, CAB_Y + 0.25, F + 0.2), M["metal_dark"], parent, bevel=0.006)
    torus("ExtStrap", 0.068, 0.005, (inner - 0.14, CAB_Y + 0.25, F + 0.4), M["metal_dark"], parent, segments=24, rings=6)
    # Acil çekiç (kutu içinde), ceket askısı, döküman cebi
    rounded_box("HammerBox", (0.03, 0.12, 0.2), (inner - 0.03, CAB_Y + 1.35, F + 1.6), M["btn_red"], parent, bevel=0.004)
    box("HammerGlass", (0.012, 0.1, 0.17), (inner - 0.046, CAB_Y + 1.35, F + 1.6), M["glass"], parent)
    box("HammerHead", (0.02, 0.07, 0.025), (inner - 0.04, CAB_Y + 1.35, F + 1.66), M["metal_dark"], parent)
    box("HammerHandle", (0.012, 0.012, 0.12), (inner - 0.04, CAB_Y + 1.35, F + 1.59), M["rubber"], parent)
    cylinder("CoatHook", 0.008, 0.05, (inner - 0.03, CAB_Y + 0.15, F + 1.95), M["metal"], parent, rot=(0, math.radians(90), 0), segments=8)
    sphere("CoatHookBall", 0.012, (inner - 0.06, CAB_Y + 0.15, F + 1.95), M["metal"], parent, segments=10, rings=6)
    rounded_box("DocPocket", (0.03, 0.26, 0.18), (-(inner - 0.03), CAB_Y + 0.4, F + 1.45), M["plastic_grey"], parent, bevel=0.005)
    box("DocPaper", (0.01, 0.2, 0.2), (-(inner - 0.03), CAB_Y + 0.4, F + 1.5), M["paper"], parent)
    # Sol kanat dolabı (kapaklı) + kapak kolu
    rounded_box("SideCab_L", (0.26, 0.62, 0.52), (-(inner - 0.14), CAB_Y + 0.42, F + 0.27), M["metal_painted"], parent, bevel=0.008)
    box("SideCabSeam", (0.262, 0.004, 0.48), (-(inner - 0.14), CAB_Y + 0.42, F + 0.27), M["rubber"], parent)
    rounded_box("SideCabHandle", (0.04, 0.012, 0.08), (-(inner - 0.14) + 0.14, CAB_Y + 0.6, F + 0.35), M["metal"], parent, bevel=0.003)
    # ARS plakası (bölme duvarı)
    rounded_box("ARSPlate", (0.22, 0.004, 0.06), (-0.6, CAB_Y + 0.035, F + 1.55), M["brass"], parent, bevel=0.002)
    # Vantilatör (sağ üst köşe): kafes + bıçaklar + gövde
    cylinder("FanBody", 0.04, 0.06, (1.05, CAB_Y + 1.25, ROOF - 0.5), M["plastic_grey"], parent, rot=(math.radians(90), 0, 0), segments=16)
    torus("FanGuard", 0.1, 0.004, (1.05, CAB_Y + 1.2, ROOF - 0.5), M["metal_dark"], parent, rot=(math.radians(90), 0, 0), segments=28, rings=6)
    for k in range(8):
        a = 2 * math.pi * k / 8
        box(f"FanGuardSpoke_{k}", (0.004, 0.004, 0.2), (1.05 + math.cos(a) * 0.0, CAB_Y + 1.2, ROOF - 0.5), M["metal_dark"], parent, rot=(0, a, 0))
    fan = empty("Fan_Hub", (1.05, CAB_Y + 1.22, ROOF - 0.5), parent)
    for k in range(3):
        b = box(f"FanBlade_{k}", (0.03, 0.004, 0.14), (0, 0, 0.07), M["plastic_white"], fan)
        b.rotation_euler = (0, math.radians(k * 120), math.radians(18))
    cylinder("FanMount", 0.01, 0.12, (1.05, CAB_Y + 1.25, ROOF - 0.44), M["metal_dark"], parent, segments=8)

    return on_panel


def bulkhead_front(M, parent, HW, FLOOR, ROOF, CAB_Y):
    """Ön kabin bölme duvarı: menteşeli kapı (CabDoorPivot), cam, kol, tekme plakası.
    Kapı açıklığı x 0,12..0,84 (koridor hizasında; oyuncu koltukların yanından takılmadan geçer),
    menteşe solda (x=0,12), kapı salona doğru duvara yaslanarak açılır."""
    inner = HW - 0.06
    F = FLOOR
    y = CAB_Y
    h = ROOF - F - 0.3
    DX0, DX1 = 0.12, 0.84
    # Sağ parça (kapı sağı → duvar), kapı üstü, pencere etrafı dört parça (pencere x -1,04..-0,16, z F+1,41..F+1,99)
    box("Bulkhead_1_a", (inner - DX1, 0.06, h), ((DX1 + inner) / 2, y, F + h / 2), M["interior"], parent)
    box("Bulkhead_1_top", (DX1 - DX0, 0.06, h - 1.98), ((DX0 + DX1) / 2, y, F + 1.98 + (h - 1.98) / 2), M["interior"], parent)
    box("Bulkhead_1_b1", (inner - 1.04, 0.06, h), ((-inner - 1.04) / 2, y, F + h / 2), M["interior"], parent)
    box("Bulkhead_1_b2", (DX0 + 0.16, 0.06, h), ((DX0 - 0.16) / 2, y, F + h / 2), M["interior"], parent)
    box("Bulkhead_1_b3", (0.88, 0.06, 1.41), (-0.6, y, F + 1.41 / 2), M["interior"], parent)
    box("Bulkhead_1_b4", (0.88, 0.06, h - 1.99), (-0.6, y, F + 1.99 + (h - 1.99) / 2), M["interior"], parent)
    # Kapı çerçevesi
    for dx in (DX0 - 0.02, DX1 + 0.02):
        rounded_box(f"CabDoorJamb_{dx:.2f}", (0.04, 0.09, 1.98), (dx, y, F + 0.99), M["plastic_grey"], parent, bevel=0.006)
    rounded_box("CabDoorHead", (DX1 - DX0 + 0.08, 0.09, 0.04), ((DX0 + DX1) / 2, y, F + 1.99), M["plastic_grey"], parent, bevel=0.006)
    # Kapı (pivot menteşe tarafında x=DX0); kapı +x yönünde 0,70 m uzanır
    piv = empty("CabDoorPivot", (DX0, y, F), parent)
    rounded_box("CabDoor", (0.70, 0.045, 1.95), (0.35, 0, 0.975), M["plastic_grey"], piv, bevel=0.006)
    box("CabDoorGlassFrame", (0.42, 0.05, 0.72), (0.35, 0, 1.5), M["plastic_dark"], piv)
    box("CabDoorGlass", (0.36, 0.06, 0.64), (0.35, 0, 1.5), M["glass"], piv)
    box("CabDoorKick", (0.64, 0.048, 0.2), (0.35, 0, 0.12), M["metal"], piv)
    for s in (-1, 1):
        cylinder(f"CabDoorHandleStem_{s}", 0.01, 0.05, (0.62, s * 0.04, 1.0), M["metal"], piv, rot=(math.radians(90), 0, 0), segments=10)
        rounded_box(f"CabDoorHandle_{s}", (0.12, 0.018, 0.022), (0.57, s * 0.06, 1.0), M["metal"], piv, bevel=0.006)
    cylinder("CabDoorLockCyl", 0.012, 0.01, (0.62, 0.03, 0.92), M["metal"], piv, rot=(math.radians(90), 0, 0), segments=12)
    for hz in (0.25, 1.0, 1.75):
        cylinder(f"CabDoorHinge_{hz}", 0.012, 0.09, (0.0, 0.0, hz), M["metal_dark"], piv, segments=10)
    # Pencere (sol üst): cam + çerçeve
    rounded_box("BulkWinFrame", (0.96, 0.08, 0.66), (-0.6, y, F + 1.7), M["plastic_grey"], parent, bevel=0.008)
    box("BulkWin_1", (0.88, 0.09, 0.58), (-0.6, y, F + 1.7), M["glass"], parent)
    # Duvar panel derzleri
    for px in (-1.0, 1.1):
        box(f"BulkSeam_{px}", (0.008, 0.07, 1.25), (px, y, F + 0.65), M["rubber"], parent)
