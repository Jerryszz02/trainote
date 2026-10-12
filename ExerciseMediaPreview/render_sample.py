# Render the locally supplied CC0 push-up source; does not download or execute upstream code.
import bpy, math, os, sys, argparse, json, struct
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--preview', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)
# The published GLB contains an empty morph-weight animation without morph targets.
# Remove only that invalid animation; retain every skeletal channel and binary mesh.
data = Path(args.source).read_bytes()
length, kind = struct.unpack_from('<II', data, 12)
document = json.loads(data[20:20 + length])
assert all(not primitive.get('targets') for mesh in document['meshes'] for primitive in mesh['primitives'])
document['animations'] = [animation for animation in document['animations']
    if any(channel['target']['path'] != 'weights' for channel in animation['channels'])]
header = json.dumps(document, separators=(',', ':')).encode()
header += b' ' * (-len(header) % 4)
chunks = struct.pack('<II', len(header), kind) + header + data[20 + length:]
clean = output / 'push-up-clean.glb'
clean.write_bytes(data[:8] + struct.pack('<I', 12 + len(chunks)) + chunks)
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(clean))
scene=bpy.context.scene
for obj in list(scene.objects):
 if obj.name=='Icosphere': bpy.data.objects.remove(obj,do_unlink=True)
scene.render.engine='CYCLES'
scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.resolution_x=960
scene.render.resolution_y=600
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
scene.world=bpy.data.worlds.new('White studio')
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(0.94,0.95,0.97,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=0.35
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
for obj in scene.objects:
 if obj.type=='MESH':
  for attr in obj.data.color_attributes:
   if attr.domain=='CORNER' or attr.domain=='POINT':
    for v in attr.data:
     r,g,b,a=v.color
     v.color=(r*0.4,g*0.4,b*0.4,a) if abs(r-g)<0.1 else (r*0.76,g*0.44,b*0.44,a)
  for poly in obj.data.polygons: poly.use_smooth=True
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-0.103))
floor=bpy.context.object
mat=bpy.data.materials.new('Warm white floor');mat.diffuse_color=(0.94,0.95,0.97,1);floor.data.materials.append(mat)
target=Vector((0,0.1,0.28))
cam_data=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',cam_data);scene.collection.objects.link(cam);cam.location=(3.2,-2.25,1.65);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam_data.type='ORTHO';cam_data.ortho_scale=2.48;scene.camera=cam
for name,loc,power,size in [('Key',(-3,-4,5),320,4),('Fill',(3,1,4),170,3)]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size; obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=loc;obj.rotation_euler=(target-obj.location).to_track_quat('-Z','Y').to_euler()
(output / 'frames').mkdir(exist_ok=True)
frames=[0,18,36,54] if args.preview else range(72)
for i in frames:
 f=0.8+36*i/72
 scene.frame_set(int(f),subframe=f%1)
 rig=bpy.data.objects.get('Human.rig')
 rig.rotation_mode='XYZ'
 rig.rotation_euler[0]=0
 rig.location.z=0
 bpy.context.view_layer.update()
 obj=bpy.data.objects.get('Human').evaluated_get(bpy.context.evaluated_depsgraph_get())
 points=[obj.matrix_world @ v.co for v in obj.data.vertices]
 hand=min([v for v in points if v.y < -0.1],key=lambda v:v.z)
 toe=min([v for v in points if v.y > 0.7],key=lambda v:v.z)
 angle=-math.atan2(toe.z-hand.z,toe.y-hand.y)
 rig.rotation_euler[0]=angle
 bpy.context.view_layer.update()
 obj=bpy.data.objects.get('Human').evaluated_get(bpy.context.evaluated_depsgraph_get())
 points=[obj.matrix_world @ v.co for v in obj.data.vertices]
 rig.location.z=-0.103-min(v.z for v in points)
 bpy.context.view_layer.update()
 scene.render.filepath=str(output / 'frames' / f'{i:03d}.png')
 bpy.ops.render.render(write_still=True)
