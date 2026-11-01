"""Bir GLB'yi Cycles ile hızlıca render eder (geometri/malzeme kontrolü).
blender -b --python tools/preview_glb.py -- model.glb out.png [cam_x cam_y cam_z] [look_x look_y look_z] [fov]
"""
import bpy, sys, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
cam_pos = Vector([float(v) for v in argv[2:5]]) if len(argv) >= 5 else Vector((14, -18, 6))
look = Vector([float(v) for v in argv[5:8]]) if len(argv) >= 8 else Vector((0, 0, 2))
fov = float(argv[8]) if len(argv) >= 9 else 50.0
samples = int(argv[9]) if len(argv) >= 10 else 24

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = samples
scene.cycles.use_denoising = False
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = out
world = bpy.data.worlds.new("W")
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.35, 0.38, 0.42, 1)
bg.inputs[1].default_value = 3.0
scene.world = world
# Zemin
bpy.ops.mesh.primitive_plane_add(size=200)
floor = bpy.context.active_object
m = bpy.data.materials.new("floor")
m.use_nodes = True
m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.2, 0.21, 1)
floor.data.materials.append(m)
# Işıklar
for pos, e in (((10, -12, 12), 3000), ((-12, 8, 10), 1500), ((0, 20, 8), 1200)):
    l = bpy.data.lights.new("l", "POINT")
    l.energy = e
    l.shadow_soft_size = 1.5
    lo = bpy.data.objects.new("l", l)
    lo.location = pos
    scene.collection.objects.link(lo)
cam = bpy.data.cameras.new("c")
cam.angle = math.radians(fov)
co = bpy.data.objects.new("c", cam)
co.location = cam_pos
d = look - cam_pos
co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
scene.collection.objects.link(co)
scene.camera = co
bpy.ops.render.render(write_still=True)
print("[PREVIEW]", out)
