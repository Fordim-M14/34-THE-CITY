"""
bake_textures.py — Blender (headless) ile prosedürel PBR doku setleri pişirir.
Her set: <ad>_albedo.png, <ad>_normal.png, <ad>_rough.png (tileable, 1024 px).

    blender -b --python tools/bake_textures.py -- --out assets/textures --size 1024

Tüm dokular bu betikte node ağacıyla tanımlanır; dış kaynak yok (lisans sorunu yok).
"""
import bpy, sys, os, math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = "assets/textures"
SIZE = 1024
SAMPLES = 24
for i, a in enumerate(argv):
    if a == "--out":
        OUT = argv[i + 1]
    if a == "--size":
        SIZE = int(argv[i + 1])
    if a == "--samples":
        SAMPLES = int(argv[i + 1])
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------------------
# Sahne

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = False
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
scene.render.bake.margin = 8
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGB"

bpy.ops.mesh.primitive_plane_add(size=2)
plane = bpy.context.active_object
plane.name = "BakePlane"
# UV: tam 0..1
uv = plane.data.uv_layers.active
for loop in plane.data.loops:
    v = plane.data.vertices[loop.vertex_index].co
    uv.data[loop.index].uv = ((v.x + 1) / 2, (v.y + 1) / 2)

cam = bpy.data.cameras.new("c")
cam_obj = bpy.data.objects.new("c", cam)
scene.collection.objects.link(cam_obj)
scene.camera = cam_obj


def new_image(name):
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB"
    return img


def node(tree, t, **kw):
    n = tree.nodes.new(t)
    for k, v in kw.items():
        if hasattr(n, k):
            setattr(n, k, v)
        else:
            n.inputs[k].default_value = v
    return n


def link(tree, a, ao, b, bi):
    tree.links.new(a.outputs[ao], b.inputs[bi])


def bake_set(name, build):
    """build(tree, out_bsdf) → node ağacını kurar; normal için Bump/Normal Map'e bağlı olmalı."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tree = mat.node_tree
    for n in list(tree.nodes):
        tree.nodes.remove(n)
    out = node(tree, "ShaderNodeOutputMaterial")
    bsdf = node(tree, "ShaderNodeBsdfPrincipled")
    link(tree, bsdf, "BSDF", out, "Surface")
    build(tree, bsdf)
    plane.data.materials.clear()
    plane.data.materials.append(mat)
    # Hedef görüntü düğümü
    for kind, bake_type, cs in (("albedo", "DIFFUSE", "sRGB"), ("rough", "ROUGHNESS", "Non-Color"), ("normal", "NORMAL", "Non-Color")):
        img = new_image(f"{name}_{kind}")
        img.colorspace_settings.name = cs
        tex = node(tree, "ShaderNodeTexImage")
        tex.image = img
        tree.nodes.active = tex
        bpy.context.view_layer.objects.active = plane
        plane.select_set(True)
        scene.render.bake.normal_space = "TANGENT"
        bpy.ops.object.bake(type=bake_type, use_clear=True)
        img.filepath_raw = os.path.join(OUT, f"{name}_{kind}.png")
        img.file_format = "PNG"
        img.save()
        tree.nodes.remove(tex)
        print(f"[BAKE] {name}_{kind}.png")


# ---------------------------------------------------------------------------
# Yardımcı: koordinat + ölçek

def coords(tree, scale=1.0):
    tc = node(tree, "ShaderNodeTexCoord")
    mp = node(tree, "ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    link(tree, tc, "UV", mp, "Vector")
    return mp


def bump(tree, bsdf, height_socket_node, height_out, strength=0.4, distance=0.02):
    b = node(tree, "ShaderNodeBump")
    b.inputs["Strength"].default_value = strength
    b.inputs["Distance"].default_value = distance
    link(tree, height_socket_node, height_out, b, "Height")
    link(tree, b, "Normal", bsdf, "Normal")
    return b


# ---------------------------------------------------------------------------
# 1) Tünel kaplaması: segment panelleri + derz + cıvata cepleri + leke

def concrete_lining(tree, bsdf):
    mp = coords(tree, 1.0)
    # Panel derzleri (Brick texture ile)
    brick = node(tree, "ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.006
    brick.inputs["Mortar Smooth"].default_value = 0.4
    brick.inputs["Bias"].default_value = 0.0
    brick.inputs["Brick Width"].default_value = 0.5
    brick.inputs["Row Height"].default_value = 0.25
    brick.inputs["Color1"].default_value = (1, 1, 1, 1)
    brick.inputs["Color2"].default_value = (0.93, 0.93, 0.93, 1)
    brick.inputs["Mortar"].default_value = (0.35, 0.35, 0.35, 1)
    link(tree, mp, "Vector", brick, "Vector")
    # Beton grenleri
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 28.0
    n1.inputs["Detail"].default_value = 8.0
    n1.inputs["Roughness"].default_value = 0.65
    link(tree, mp, "Vector", n1, "Vector")
    n2 = node(tree, "ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 3.0
    n2.inputs["Detail"].default_value = 4.0
    link(tree, mp, "Vector", n2, "Vector")
    # Renk: gri beton, büyük ölçekli leke
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.30, 0.30, 0.31, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.58, 0.58, 0.60, 1)
    link(tree, n2, "Fac", ramp, "Fac")
    mix = node(tree, "ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.35
    link(tree, ramp, "Color", mix, "A")
    link(tree, n1, "Color", mix, "B")
    mix2 = node(tree, "ShaderNodeMix")
    mix2.data_type = "RGBA"
    mix2.blend_type = "MULTIPLY"
    mix2.inputs["Factor"].default_value = 1.0
    link(tree, mix, "Result", mix2, "A")
    link(tree, brick, "Color", mix2, "B")
    link(tree, mix2, "Result", bsdf, "Base Color")
    # Pürüzlülük
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.25
    rr.inputs[2].default_value = 0.7
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    # Yükseklik: derz (derin) + gren (hafif)
    h = node(tree, "ShaderNodeMath")
    h.operation = "MULTIPLY_ADD"
    h.inputs[1].default_value = 0.12
    h.inputs[2].default_value = 0.0
    link(tree, n1, "Fac", h, 0)
    h2 = node(tree, "ShaderNodeMath")
    h2.operation = "ADD"
    link(tree, h, "Value", h2, 0)
    link(tree, brick, "Fac", h2, 1)
    bump(tree, bsdf, h2, "Value", 0.6, 0.03)


# 2) Kaba beton (duvar, istinat)
def concrete_rough(tree, bsdf):
    mp = coords(tree, 1.0)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 18.0
    n1.inputs["Detail"].default_value = 10.0
    n1.inputs["Roughness"].default_value = 0.75
    link(tree, mp, "Vector", n1, "Vector")
    v = node(tree, "ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 40.0
    v.feature = "F1"
    link(tree, mp, "Vector", v, "Vector")
    n2 = node(tree, "ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 2.2
    link(tree, mp, "Vector", n2, "Vector")
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (0.36, 0.35, 0.33, 1)
    ramp.color_ramp.elements[1].position = 0.8
    ramp.color_ramp.elements[1].color = (0.62, 0.60, 0.56, 1)
    link(tree, n2, "Fac", ramp, "Fac")
    mix = node(tree, "ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.45
    link(tree, ramp, "Color", mix, "A")
    link(tree, n1, "Color", mix, "B")
    link(tree, mix, "Result", bsdf, "Base Color")
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.2
    rr.inputs[2].default_value = 0.78
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    h = node(tree, "ShaderNodeMath")
    h.operation = "MULTIPLY_ADD"
    h.inputs[1].default_value = 0.5
    h.inputs[2].default_value = 0.0
    link(tree, n1, "Fac", h, 0)
    h2 = node(tree, "ShaderNodeMath")
    h2.operation = "MULTIPLY_ADD"
    h2.inputs[1].default_value = 0.35
    link(tree, v, "Distance", h2, 0)
    link(tree, h, "Value", h2, 2)
    bump(tree, bsdf, h2, "Value", 0.7, 0.04)


# 3) Küçük fayans (duvar) — beyaz taban, Godot'ta renklendirilir
def tiles_small(tree, bsdf):
    mp = coords(tree, 1.0)
    brick = node(tree, "ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 8.0
    brick.inputs["Mortar Size"].default_value = 0.02
    brick.inputs["Mortar Smooth"].default_value = 0.35
    brick.inputs["Brick Width"].default_value = 0.5
    brick.inputs["Row Height"].default_value = 0.5
    brick.offset = 0.0
    brick.inputs["Color1"].default_value = (0.92, 0.92, 0.9, 1)
    brick.inputs["Color2"].default_value = (0.85, 0.85, 0.84, 1)
    brick.inputs["Mortar"].default_value = (0.45, 0.45, 0.45, 1)
    link(tree, mp, "Vector", brick, "Vector")
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 60.0
    n1.inputs["Detail"].default_value = 3.0
    link(tree, mp, "Vector", n1, "Vector")
    mix = node(tree, "ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.12
    link(tree, brick, "Color", mix, "A")
    link(tree, n1, "Color", mix, "B")
    link(tree, mix, "Result", bsdf, "Base Color")
    # Fayans parlak, derz mat
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.6
    rr.inputs[2].default_value = 0.18
    link(tree, brick, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    h = node(tree, "ShaderNodeMath")
    h.operation = "SUBTRACT"
    h.inputs[0].default_value = 1.0
    link(tree, brick, "Fac", h, 1)
    bump(tree, bsdf, h, "Value", 0.8, 0.02)


# 4) Peron döşemesi (30 cm gri plaka, kirli)
def paving(tree, bsdf):
    mp = coords(tree, 1.0)
    brick = node(tree, "ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 4.0
    brick.inputs["Mortar Size"].default_value = 0.01
    brick.inputs["Mortar Smooth"].default_value = 0.3
    brick.inputs["Brick Width"].default_value = 0.5
    brick.inputs["Row Height"].default_value = 0.5
    brick.inputs["Color1"].default_value = (0.62, 0.62, 0.60, 1)
    brick.inputs["Color2"].default_value = (0.55, 0.55, 0.54, 1)
    brick.inputs["Mortar"].default_value = (0.3, 0.3, 0.3, 1)
    link(tree, mp, "Vector", brick, "Vector")
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 24.0
    n1.inputs["Detail"].default_value = 7.0
    link(tree, mp, "Vector", n1, "Vector")
    n2 = node(tree, "ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 1.8
    link(tree, mp, "Vector", n2, "Vector")
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.4
    ramp.color_ramp.elements[0].color = (0.55, 0.55, 0.55, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1)
    link(tree, n2, "Fac", ramp, "Fac")
    mix = node(tree, "ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    link(tree, brick, "Color", mix, "A")
    link(tree, ramp, "Color", mix, "B")
    mix2 = node(tree, "ShaderNodeMix")
    mix2.data_type = "RGBA"
    mix2.blend_type = "MULTIPLY"
    mix2.inputs["Factor"].default_value = 0.2
    link(tree, mix, "Result", mix2, "A")
    link(tree, n1, "Color", mix2, "B")
    link(tree, mix2, "Result", bsdf, "Base Color")
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.25
    rr.inputs[2].default_value = 0.55
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    h = node(tree, "ShaderNodeMath")
    h.operation = "MULTIPLY_ADD"
    h.inputs[1].default_value = 0.15
    link(tree, n1, "Fac", h, 0)
    link(tree, brick, "Fac", h, 2)
    bump(tree, bsdf, h, "Value", 0.5, 0.02)


# 5) Hissedilebilir yüzey (sarı kabartmalı)
def tactile(tree, bsdf):
    mp = coords(tree, 1.0)
    v = node(tree, "ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 8.0
    v.feature = "F1"
    v.distance = "EUCLIDEAN"
    link(tree, mp, "Vector", v, "Vector")
    # Kabartma: merkeze yakın yüksek
    m = node(tree, "ShaderNodeMath")
    m.operation = "SMOOTH_MIN"
    m.inputs[1].default_value = 0.09
    m.inputs[2].default_value = 0.02
    link(tree, v, "Distance", m, 0)
    inv = node(tree, "ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 0.09
    link(tree, m, "Value", inv, 1)
    sc = node(tree, "ShaderNodeMath")
    sc.operation = "MULTIPLY"
    sc.inputs[1].default_value = 10.0
    link(tree, inv, "Value", sc, 0)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 40.0
    link(tree, mp, "Vector", n1, "Vector")
    col = node(tree, "ShaderNodeMix")
    col.data_type = "RGBA"
    col.blend_type = "MULTIPLY"
    col.inputs["Factor"].default_value = 0.2
    col.inputs["A"].default_value = (0.95, 0.75, 0.12, 1)
    link(tree, n1, "Color", col, "B")
    link(tree, col, "Result", bsdf, "Base Color")
    bsdf.inputs["Roughness"].default_value = 0.6
    bump(tree, bsdf, sc, "Value", 0.9, 0.03)


# 6) Balast (çakıl)
def ballast(tree, bsdf):
    mp = coords(tree, 1.0)
    v = node(tree, "ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 26.0
    v.feature = "F1"
    v.inputs["Randomness"].default_value = 1.0
    link(tree, mp, "Vector", v, "Vector")
    v2 = node(tree, "ShaderNodeTexVoronoi")
    v2.inputs["Scale"].default_value = 26.0
    v2.feature = "F1"
    v2.inputs["Randomness"].default_value = 1.0
    link(tree, mp, "Vector", v2, "Vector")
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 50.0
    n1.inputs["Detail"].default_value = 6.0
    link(tree, mp, "Vector", n1, "Vector")
    # Her taş farklı gri ton (voronoi Color)
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.28, 0.27, 0.26, 1)
    ramp.color_ramp.elements[1].color = (0.6, 0.58, 0.55, 1)
    sep = node(tree, "ShaderNodeSeparateColor")
    link(tree, v2, "Color", sep, "Color")
    link(tree, sep, "Red", ramp, "Fac")
    mix = node(tree, "ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.4
    link(tree, ramp, "Color", mix, "A")
    link(tree, n1, "Color", mix, "B")
    link(tree, mix, "Result", bsdf, "Base Color")
    bsdf.inputs["Roughness"].default_value = 0.9
    # Yükseklik: taş = 1 - mesafe (yuvarlak)
    inv = node(tree, "ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    link(tree, v, "Distance", inv, 1)
    pw = node(tree, "ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 2.0
    link(tree, inv, "Value", pw, 0)
    bump(tree, bsdf, pw, "Value", 1.0, 0.06)


# 7) Fırçalanmış metal
def metal_brushed(tree, bsdf):
    mp = coords(tree, 1.0)
    mp.inputs["Scale"].default_value = (1.0, 60.0, 1.0)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 12.0
    n1.inputs["Detail"].default_value = 6.0
    link(tree, mp, "Vector", n1, "Vector")
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.55, 0.56, 0.58, 1)
    ramp.color_ramp.elements[1].color = (0.75, 0.76, 0.78, 1)
    link(tree, n1, "Fac", ramp, "Fac")
    link(tree, ramp, "Color", bsdf, "Base Color")
    bsdf.inputs["Metallic"].default_value = 0.0   # (albedo pişirme için; Godot'ta metallic=1)
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.25
    rr.inputs[2].default_value = 0.25
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    bump(tree, bsdf, n1, "Fac", 0.15, 0.005)


# 8) Kauçuk zemin (kabin / araç içi, yuvarlak kabartmalı)
def rubber_floor(tree, bsdf):
    mp = coords(tree, 1.0)
    v = node(tree, "ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 24.0
    v.feature = "F1"
    v.inputs["Randomness"].default_value = 0.0
    link(tree, mp, "Vector", v, "Vector")
    m = node(tree, "ShaderNodeMath")
    m.operation = "LESS_THAN"
    m.inputs[1].default_value = 0.3
    link(tree, v, "Distance", m, 0)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 80.0
    link(tree, mp, "Vector", n1, "Vector")
    col = node(tree, "ShaderNodeMix")
    col.data_type = "RGBA"
    col.blend_type = "MULTIPLY"
    col.inputs["Factor"].default_value = 0.15
    col.inputs["A"].default_value = (0.16, 0.17, 0.18, 1)
    link(tree, n1, "Color", col, "B")
    link(tree, col, "Result", bsdf, "Base Color")
    bsdf.inputs["Roughness"].default_value = 0.75
    bump(tree, bsdf, m, "Value", 0.5, 0.01)


# 9) Delikli metal tavan paneli
def ceiling_perforated(tree, bsdf):
    mp = coords(tree, 1.0)
    v = node(tree, "ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 40.0
    v.feature = "F1"
    v.inputs["Randomness"].default_value = 0.0
    link(tree, mp, "Vector", v, "Vector")
    m = node(tree, "ShaderNodeMath")
    m.operation = "LESS_THAN"
    m.inputs[1].default_value = 0.22
    link(tree, v, "Distance", m, 0)
    inv = node(tree, "ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    link(tree, m, "Value", inv, 1)
    col = node(tree, "ShaderNodeMix")
    col.data_type = "RGBA"
    col.inputs["A"].default_value = (0.82, 0.83, 0.85, 1)
    col.inputs["B"].default_value = (0.2, 0.2, 0.22, 1)
    link(tree, m, "Value", col, "Factor")
    link(tree, col, "Result", bsdf, "Base Color")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.45
    bump(tree, bsdf, inv, "Value", 0.6, 0.01)


# 10) Koltuk kumaşı
def seat_fabric(tree, bsdf):
    mp = coords(tree, 1.0)
    w = node(tree, "ShaderNodeTexWave")
    w.inputs["Scale"].default_value = 60.0
    w.inputs["Distortion"].default_value = 1.5
    link(tree, mp, "Vector", w, "Vector")
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 90.0
    link(tree, mp, "Vector", n1, "Vector")
    col = node(tree, "ShaderNodeMix")
    col.data_type = "RGBA"
    col.blend_type = "MULTIPLY"
    col.inputs["Factor"].default_value = 0.25
    col.inputs["A"].default_value = (0.85, 0.85, 0.85, 1)
    link(tree, n1, "Color", col, "B")
    link(tree, col, "Result", bsdf, "Base Color")
    bsdf.inputs["Roughness"].default_value = 0.95
    bump(tree, bsdf, w, "Fac", 0.3, 0.005)


# 11) Boyalı metal (tren gövdesi; hafif portakal kabuğu + kir)
def paint_metal(tree, bsdf):
    mp = coords(tree, 1.0)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 120.0
    n1.inputs["Detail"].default_value = 2.0
    link(tree, mp, "Vector", n1, "Vector")
    n2 = node(tree, "ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 4.0
    link(tree, mp, "Vector", n2, "Vector")
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45
    ramp.color_ramp.elements[0].color = (0.88, 0.88, 0.88, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    link(tree, n2, "Fac", ramp, "Fac")
    link(tree, ramp, "Color", bsdf, "Base Color")
    bsdf.inputs["Metallic"].default_value = 0.3
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.15
    rr.inputs[2].default_value = 0.25
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    bump(tree, bsdf, n1, "Fac", 0.08, 0.002)


# 12) Plastik (ince tanecikli kabin plastiği, hafif aşınma)
def plastic_grain(tree, bsdf):
    mp = coords(tree, 1.0)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 300.0
    n1.inputs["Detail"].default_value = 3.0
    n1.inputs["Roughness"].default_value = 0.7
    link(tree, mp, "Vector", n1, "Vector")
    n2 = node(tree, "ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 3.0
    n2.inputs["Detail"].default_value = 4.0
    link(tree, mp, "Vector", n2, "Vector")
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.82, 0.82, 0.82, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1)
    link(tree, n2, "Fac", ramp, "Fac")
    link(tree, ramp, "Color", bsdf, "Base Color")
    bsdf.inputs["Metallic"].default_value = 0.0
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.3
    rr.inputs[2].default_value = 0.6
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    bump(tree, bsdf, n1, "Fac", 0.25, 0.002)


# 13) Deri / vinil koltuk (makinist koltuğu)
def leather(tree, bsdf):
    mp = coords(tree, 1.0)
    v = node(tree, "ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 140.0
    v.feature = "DISTANCE_TO_EDGE"
    link(tree, mp, "Vector", v, "Vector")
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 6.0
    n1.inputs["Detail"].default_value = 5.0
    link(tree, mp, "Vector", n1, "Vector")
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (0.75, 0.75, 0.75, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    link(tree, n1, "Fac", ramp, "Fac")
    link(tree, ramp, "Color", bsdf, "Base Color")
    bsdf.inputs["Metallic"].default_value = 0.0
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.2
    rr.inputs[2].default_value = 0.45
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    cl = node(tree, "ShaderNodeMath")
    cl.operation = "MINIMUM"
    cl.inputs[1].default_value = 0.06
    link(tree, v, "Distance", cl, 0)
    bump(tree, bsdf, cl, "Value", 0.6, 0.01)


# 14) Aşınmış boyalı metal (çizik, kir; konsol çerçeveleri, dolaplar)
def metal_worn(tree, bsdf):
    mp = coords(tree, 1.0)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 5.0
    n1.inputs["Detail"].default_value = 6.0
    link(tree, mp, "Vector", n1, "Vector")
    mp2 = coords(tree, 1.0)
    mp2.inputs["Scale"].default_value = (40.0, 1.5, 1.0)
    n2 = node(tree, "ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 8.0
    n2.inputs["Detail"].default_value = 4.0
    link(tree, mp2, "Vector", n2, "Vector")
    scr = node(tree, "ShaderNodeMath")
    scr.operation = "GREATER_THAN"
    scr.inputs[1].default_value = 0.68
    link(tree, n2, "Fac", scr, 0)
    ramp = node(tree, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (0.7, 0.7, 0.7, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    link(tree, n1, "Fac", ramp, "Fac")
    mix = node(tree, "ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["B"].default_value = (0.55, 0.55, 0.56, 1)
    link(tree, ramp, "Color", mix, "A")
    link(tree, scr, "Value", mix, "Factor")
    link(tree, mix, "Result", bsdf, "Base Color")
    bsdf.inputs["Metallic"].default_value = 0.0
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.3
    rr.inputs[2].default_value = 0.3
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    bump(tree, bsdf, scr, "Value", 0.3, 0.003)


# 15) Oluklu kauçuk (paspas, pedal, basamak)
def rubber_ribbed(tree, bsdf):
    mp = coords(tree, 1.0)
    w = node(tree, "ShaderNodeTexWave")
    w.wave_type = "BANDS"
    w.bands_direction = "Y"
    w.wave_profile = "SAW"
    w.inputs["Scale"].default_value = 30.0
    link(tree, mp, "Vector", w, "Vector")
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 120.0
    link(tree, mp, "Vector", n1, "Vector")
    col = node(tree, "ShaderNodeMix")
    col.data_type = "RGBA"
    col.blend_type = "MULTIPLY"
    col.inputs["Factor"].default_value = 0.2
    col.inputs["A"].default_value = (0.2, 0.2, 0.21, 1)
    link(tree, n1, "Color", col, "B")
    link(tree, col, "Result", bsdf, "Base Color")
    bsdf.inputs["Roughness"].default_value = 0.85
    bump(tree, bsdf, w, "Fac", 0.7, 0.01)


# 16) Oluklu/tekstürlü plastik duvar paneli (vagon içi)
def panel_lines(tree, bsdf):
    mp = coords(tree, 1.0)
    w = node(tree, "ShaderNodeTexWave")
    w.wave_type = "BANDS"
    w.bands_direction = "X"
    w.wave_profile = "SIN"
    w.inputs["Scale"].default_value = 8.0
    link(tree, mp, "Vector", w, "Vector")
    gt = node(tree, "ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    gt.inputs[1].default_value = 0.97
    link(tree, w, "Fac", gt, 0)
    inv = node(tree, "ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    link(tree, gt, "Value", inv, 1)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 200.0
    link(tree, mp, "Vector", n1, "Vector")
    col = node(tree, "ShaderNodeMix")
    col.data_type = "RGBA"
    col.inputs["A"].default_value = (0.9, 0.9, 0.9, 1)
    col.inputs["B"].default_value = (0.5, 0.5, 0.5, 1)
    link(tree, gt, "Value", col, "Factor")
    link(tree, col, "Result", bsdf, "Base Color")
    bsdf.inputs["Roughness"].default_value = 0.5
    rr = node(tree, "ShaderNodeMath")
    rr.operation = "MULTIPLY_ADD"
    rr.inputs[1].default_value = 0.2
    rr.inputs[2].default_value = 0.4
    link(tree, n1, "Fac", rr, 0)
    link(tree, rr, "Value", bsdf, "Roughness")
    bump(tree, bsdf, inv, "Value", 0.5, 0.01)


# 17) Metro koltuk kumaşı (desenli: çapraz dokuma + nokta deseni, hafif aşınma)
def seat_pattern(tree, bsdf):
    mp = coords(tree, 1.0)
    w = node(tree, "ShaderNodeTexWave")
    w.wave_type = "BANDS"
    w.bands_direction = "DIAGONAL"
    w.inputs["Scale"].default_value = 70.0
    w.inputs["Distortion"].default_value = 0.8
    link(tree, mp, "Vector", w, "Vector")
    v = node(tree, "ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 9.0
    v.feature = "F1"
    v.inputs["Randomness"].default_value = 0.0
    link(tree, mp, "Vector", v, "Vector")
    dots = node(tree, "ShaderNodeMath")
    dots.operation = "LESS_THAN"
    dots.inputs[1].default_value = 0.16
    link(tree, v, "Distance", dots, 0)
    n1 = node(tree, "ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 140.0
    link(tree, mp, "Vector", n1, "Vector")
    base = node(tree, "ShaderNodeMix")
    base.data_type = "RGBA"
    base.blend_type = "MULTIPLY"
    base.inputs["Factor"].default_value = 0.3
    base.inputs["A"].default_value = (0.8, 0.8, 0.8, 1)
    link(tree, n1, "Color", base, "B")
    col = node(tree, "ShaderNodeMix")
    col.data_type = "RGBA"
    col.inputs["B"].default_value = (1.6, 1.5, 1.2, 1)   # açık nokta deseni
    link(tree, base, "Result", col, "A")
    link(tree, dots, "Value", col, "Factor")
    link(tree, col, "Result", bsdf, "Base Color")
    bsdf.inputs["Roughness"].default_value = 0.95
    bump(tree, bsdf, w, "Fac", 0.35, 0.004)


SETS = {
    "concrete_lining": concrete_lining,
    "concrete_rough": concrete_rough,
    "tiles_small": tiles_small,
    "paving": paving,
    "tactile": tactile,
    "ballast": ballast,
    "metal_brushed": metal_brushed,
    "rubber_floor": rubber_floor,
    "ceiling_perforated": ceiling_perforated,
    "seat_fabric": seat_fabric,
    "paint_metal": paint_metal,
    "plastic_grain": plastic_grain,
    "leather": leather,
    "metal_worn": metal_worn,
    "rubber_ribbed": rubber_ribbed,
    "panel_lines": panel_lines,
    "seat_pattern": seat_pattern,
}

only = [a for a in argv if a in SETS]
for name, fn in SETS.items():
    if only and name not in only:
        continue
    bake_set(name, fn)
print("[BAKE] done")
