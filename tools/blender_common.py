"""Ortak Blender yardımcıları (headless betikler için)."""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

TEX_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "textures"))
EMBED_TEXTURES = os.environ.get("EMBED_TEXTURES", "0") == "1"   # Godot tarafı MaterialLib ile dokuları uygular


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color=(0.8, 0.8, 0.8, 1), metallic=0.0, roughness=0.6, emission=None, emission_strength=1.0,
        alpha=1.0, tex=None, tex_scale=1.0, normal_strength=1.0):
    """Principled malzeme. tex: assets/textures içindeki set adı (albedo/normal/rough)."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    tree = m.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND"
        m.shadow_method = "NONE"
    if tex:
        m["pbr_set"] = tex
        m["pbr_scale"] = tex_scale
    if tex and EMBED_TEXTURES:
        tc = tree.nodes.new("ShaderNodeTexCoord")
        mp = tree.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (tex_scale, tex_scale, tex_scale)
        tree.links.new(tc.outputs["UV"], mp.inputs["Vector"])
        for kind, sock in (("albedo", "Base Color"), ("rough", "Roughness")):
            path = os.path.join(TEX_DIR, f"{tex}_{kind}.png")
            if not os.path.exists(path):
                continue
            img = bpy.data.images.load(path, check_existing=True)
            if kind != "albedo":
                img.colorspace_settings.name = "Non-Color"
            t = tree.nodes.new("ShaderNodeTexImage")
            t.image = img
            tree.links.new(mp.outputs["Vector"], t.inputs["Vector"])
            if kind == "albedo":
                mix = tree.nodes.new("ShaderNodeMix")
                mix.data_type = "RGBA"
                mix.blend_type = "MULTIPLY"
                mix.inputs["Factor"].default_value = 1.0
                mix.inputs["A"].default_value = color
                tree.links.new(t.outputs["Color"], mix.inputs["B"])
                tree.links.new(mix.outputs["Result"], bsdf.inputs[sock])
            else:
                tree.links.new(t.outputs["Color"], bsdf.inputs[sock])
        npath = os.path.join(TEX_DIR, f"{tex}_normal.png")
        if os.path.exists(npath):
            img = bpy.data.images.load(npath, check_existing=True)
            img.colorspace_settings.name = "Non-Color"
            t = tree.nodes.new("ShaderNodeTexImage")
            t.image = img
            tree.links.new(mp.outputs["Vector"], t.inputs["Vector"])
            nm = tree.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = normal_strength
            tree.links.new(t.outputs["Color"], nm.inputs["Color"])
            tree.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def obj_from_bmesh(name, bm, material=None, smooth=False, parent=None, collection=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(ob)
    if material:
        ob.data.materials.append(material)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if parent:
        ob.parent = parent
    return ob


def box(name, size, loc, material=None, parent=None, rot=(0, 0, 0), bevel=0.0, smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = obj_from_bmesh(name, bm, material, smooth=smooth, parent=parent)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel > 0:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
    return ob


def cylinder(name, radius, depth, loc, material=None, parent=None, rot=(0, 0, 0), segments=24, smooth=True, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=depth)
    ob = obj_from_bmesh(name, bm, material, smooth=smooth, parent=parent)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel > 0:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    return ob


def sphere(name, radius, loc, material=None, parent=None, segments=24, rings=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    ob = obj_from_bmesh(name, bm, material, smooth=True, parent=parent)
    ob.location = loc
    return ob


def plane(name, w, h, loc, material=None, parent=None, rot=(0, 0, 0)):
    """Tek yüzlü düzlem, 0..1 UV (doku üstü = +Y kenarı)."""
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    bmesh.ops.scale(bm, vec=Vector((w, h, 1)), verts=bm.verts)
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for l in f.loops:
            l[uv_layer].uv = (l.vert.co.x / w + 0.5, l.vert.co.y / h + 0.5)
    ob = obj_from_bmesh(name, bm, material, parent=parent)
    ob.location = loc
    ob.rotation_euler = rot
    return ob


def empty(name, loc, parent=None, rot=(0, 0, 0)):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = 0.1
    ob.location = loc
    ob.rotation_euler = rot
    ob.parent = parent
    bpy.context.scene.collection.objects.link(ob)
    return ob


def boolean_cut(target, cutter):
    mod = target.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    cutter.hide_render = True
    cutter.hide_viewport = True
    cutter.display_type = "WIRE"


def apply_all(ob):
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    for m in list(ob.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError as e:
            print("modifier apply failed", ob.name, m.name, e)
    ob.select_set(False)


def uv_box_project(ob, scale=1.0):
    """Basit kutu projeksiyon UV (dokulu kutular için)."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                uv[li].uv = (v.y * scale, v.z * scale)
            elif ax == 1:
                uv[li].uv = (v.x * scale, v.z * scale)
            else:
                uv[li].uv = (v.x * scale, v.y * scale)


def export_glb(path, objects=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    if objects:
        for o in objects:
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=bool(objects),
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_image_format="AUTO", export_animations=True, export_skins=True,
                              export_lights=False, export_cameras=False)
    print("[GLB]", path, os.path.getsize(path) // 1024, "KB")
