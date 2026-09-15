"""Build DustStrike's skinned operators from Blender Studio's CC0 human base.
Run: blender -b --python build_operators.py -- --base /path/to/human_base_meshes_bundle.blend
Base: Body Male - Realistic by Dan Ulrich, CC0. Gear, clothing and animation: DustStrike.
"""
import argparse
import bpy, math, random, os, sys
import numpy as np
from mathutils import Vector, Matrix, Quaternion
from pathlib import Path
random.seed(724)
ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'assets'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('base_file',nargs='?',help='Blender Studio human_base_meshes_bundle.blend (positional alternative to --base)')
parser.add_argument('--base',help='Path to Blender Studio human_base_meshes_bundle.blend')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if bool(args.base)==bool(args.base_file):
 parser.error('Provide exactly one human base .blend path, using --base PATH or a positional PATH. Download Human Base Meshes from https://www.blender.org/download/demo-files/ and extract the archive first.')
BASE=Path(args.base or args.base_file).expanduser().resolve()
if BASE.suffix.lower()!='.blend' or not BASE.is_file():
 parser.error('Human base .blend file not found: '+str(BASE))
PROOFS=ROOT/'source_art'/'proofs'
PROOFS.mkdir(parents=True,exist_ok=True)
TAU=math.tau

def reset():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for a in list(bpy.data.actions):bpy.data.actions.remove(a)

def material(name,col,rough=.8,metal=0,fabric=False):
 m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 if fabric:
  n=256;y,x=np.mgrid[:n,:n];rng=np.random.default_rng(143)
  weave=(np.sin(x*math.pi/2)*np.sin(y*math.pi/2))*.035+np.sin((x+y)*math.pi/4)*.028+rng.normal(0,.014,(n,n))
  pixels=np.ones((n,n,4),dtype=np.float32)
  for j in range(3):pixels[:,:,j]=np.clip(col[j]*(1+weave),0,1)
  im=bpy.data.images.new(name+'_woven_albedo',width=n,height=n);im.pixels.foreach_set(pixels.ravel());im.pack()
  tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
  normals=np.ones((n,n,4),dtype=np.float32);normals[:,:,0]=.5+np.cos(x*math.pi/2)*.045;normals[:,:,1]=.5+np.cos(y*math.pi/2)*.045;normals[:,:,2]=.99
  ni=bpy.data.images.new(name+'_woven_normal',width=n,height=n);ni.colorspace_settings.name='Non-Color';ni.pixels.foreach_set(normals.ravel());ni.pack()
  nt=m.node_tree.nodes.new('ShaderNodeTexImage');nt.image=ni;nm=m.node_tree.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.32
  m.node_tree.links.new(nt.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],p.inputs['Normal'])
 return m

def finish(o,name,mat):
 o.name=name;o.data.materials.clear();o.data.materials.append(mat)
 for p in o.data.polygons:p.use_smooth=True
 return o

def apply(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)

def cube(name,loc,size,mat,bevel=.008):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size;apply(o);finish(o,name,mat)
 if bevel:
  mod=o.modifiers.new('Soft manufactured edges','BEVEL');mod.width=bevel;mod.segments=3
  bpy.ops.object.modifier_apply(modifier=mod.name)
  mod=o.modifiers.new('Face normals','WEIGHTED_NORMAL');bpy.ops.object.modifier_apply(modifier=mod.name)
 return o

def ellipsoid(name,loc,scale,mat,segments=24,rings=12):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc);o=bpy.context.object;o.scale=scale;apply(o);return finish(o,name,mat)

def tube(name,pts,r,mat):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=2;cu.bevel_depth=r;cu.bevel_resolution=2
 s=cu.splines.new('POLY');s.points.add(len(pts)-1)
 for p,co in zip(s.points,pts):p.co=(*co,1)
 o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o);cu.materials.append(mat)
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH')
 return o

def bind(o,bone,in_pose=False):
 apply(o)
 if in_pose:
  mat=rig.data.bones[bone].matrix_local @ rig.pose.bones[bone].matrix.inverted()
  for v in o.data.vertices:v.co=mat@v.co
 group=o.vertex_groups.new(name=bone);group.add(list(range(len(o.data.vertices))),1,'REPLACE')
 mod=o.modifiers.new('Operator skin','ARMATURE');mod.object=rig;o.parent=rig
 return o

def rigid_box(name,loc,size,mat,bone='Chest',bevel=.008):return bind(cube(name,loc,size,mat,bevel),bone)
def rigid_ball(name,loc,size,mat,bone='Head'):return bind(ellipsoid(name,loc,size,mat),bone)
def rigid_tube(name,pts,r,mat,bone='Chest'):return bind(tube(name,pts,r,mat),bone)

def distseg(p,a,b):
 v=b-a;t=max(0,min(1,(p-a).dot(v)/v.length_squared));return (p-(a+t*v)).length

def weight(o,region):
 groups={n:o.vertex_groups.new(name=n) for n in bones if n!='Root'}
 for v in o.data.vertices:
  p=v.co;x,y,z=p
  if region in ['Skin','Headwear']:cands=['Head','Neck']
  elif region=='Pants':cands=['Hips','Thigh_L','Shin_L','Thigh_R','Shin_R']
  elif abs(x)>.14 and z<1.52:cands=['UpperArm_'+('L' if x>0 else 'R'),'Forearm_'+('L' if x>0 else 'R'),'Chest','Spine']
  else:cands=['Hips','Spine','Chest','Neck']
  ds=sorted((distseg(p,Vector(bones[n][0]),Vector(bones[n][1])),n) for n in cands)[:2]
  vals=[1/max(.025,d)**5 for d,n in ds];total=sum(vals)
  for val,(d,n) in zip(vals,ds):groups[n].add([v.index],val/total,'REPLACE')
 mod=o.modifiers.new('Deforming character skin','ARMATURE');mod.object=rig;o.parent=rig


def surface(name,source,predicate,mat,inflate=0,region='Skin'):
 verts=[];faces=[];mapping={}
 for p in source.polygons:
  center=p.center
  if not predicate(center):continue
  ids=[]
  for vi in p.vertices:
   if vi not in mapping:
    v=source.vertices[vi];co=v.co.copy()
    # Low amplitude creases keep the anatomical silhouette beneath the fabric.
    crease=0
    if region in ['Shirt','Pants']:
     zone=math.exp(-((co.z-.56)/.11)**2)+.6*math.exp(-((co.z-1.08)/.13)**2)
     crease=(.007 if region=='Pants' else .0025)*zone*math.sin(co.z*105+co.x*21+co.y*34)
    co+=v.normal*(inflate+crease)
    if region=='Pants' and co.y<-.095:
     blend=math.exp(-((co.x/.085)**4))*math.exp(-(((co.z-.97)/.085)**4))
     co.y+=(max(co.y,-.095)-co.y)*blend
    mapping[vi]=len(verts);verts.append(co)
   ids.append(mapping[vi])
  faces.append(ids)
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);finish(o,name,mat)
 uv=mesh.uv_layers.new(name='FabricUV')
 for poly in mesh.polygons:
  for li in poly.loop_indices:
   co=mesh.vertices[mesh.loops[li].vertex_index].co
   uv.data[li].uv=(co.x*5+co.y*3,co.z*5)
 if region=='Skin':
  color=mesh.color_attributes.new(name='Complexion',type='FLOAT_COLOR',domain='POINT')
  for v in mesh.vertices:
   x,y,z=v.co
   n=math.sin(x*834+z*578)*math.sin(y*512-z*273)*.016
   # Warm cheeks and subtle dark beard shadow; geometry supplies nose/lips/ears.
   shade=1+n
   if team=='T' and 1.56<z<1.66 and y<-.075 and (abs(x)>.02 or z<1.60):shade*=.42+.06*math.sin(z*40)
   base=mat.diffuse_color
   color.data[v.index].color=(base[0]*shade,base[1]*shade*(.94 if y<-.08 else 1),base[2]*shade*.95,1)
  nodes=mat.node_tree.nodes;p=nodes.get('Principled BSDF');att=nodes.new('ShaderNodeVertexColor');att.layer_name='Complexion'
  mat.node_tree.links.new(att.outputs['Color'],p.inputs['Base Color'])
 if region=='Pants':
  vg=o.vertex_groups.new(name='Cloth smoothing')
  for v in mesh.vertices:
   amount=math.exp(-((v.co.x/.13)**4))*math.exp(-(((v.co.z-.96)/.15)**4))
   if v.co.y<0:vg.add([v.index],amount,'REPLACE')
  smooth=o.modifiers.new('Relax trouser front','SMOOTH');smooth.factor=1.0;smooth.iterations=35;smooth.vertex_group=vg.name
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=smooth.name)
  o.vertex_groups.remove(o.vertex_groups['Cloth smoothing'])
 weight(o,region)
 return o


def pose_arm(side,elbow,wrist):
 for n,a,b in [('UpperArm_'+side,bones['UpperArm_'+side][0],elbow),('Forearm_'+side,elbow,wrist)]:
  pb=rig.pose.bones[n];rest=rig.data.bones[n]
  delta=(rest.tail_local-rest.head_local).rotation_difference(Vector(b)-Vector(a))
  pb.matrix=Matrix.Translation(Vector(a))@delta.to_matrix().to_4x4()@rest.matrix_local.to_3x3().to_4x4()
  bpy.context.view_layer.update()

def gloves(side,center):
 # Individually curled fingers around the pistol grip / handguard.
 x,y,z=center;name='Forearm_'+side
 o=ellipsoid('Glove palm '+side,(x,y,z),(.048,.047,.03),leather);bind(o,name,True)
 for f in range(4):
  xx=x-.027+f*.018
  o=tube('Curled finger '+side+str(f),[(xx,y-.024,z+.012),(xx,y-.049,z+.002),(xx,y-.05,z-.021),(xx,y-.031,z-.035)],.009,leather);bind(o,name,True)
  o=ellipsoid('Knuckle guard '+side+str(f),(xx,y-.018,z+.028),(.009,.012,.005),rubber,16,8);bind(o,name,True)
 o=tube('Glove thumb '+side,[(x+.045,y+.015,z),(x+.053,y-.025,z-.015),(x+.028,y-.043,z-.024)],.012,leather);bind(o,name,True)

def save_action(name,seconds,pose_func,loop=False):
 rig.animation_data_create();act=bpy.data.actions.new(name);rig.animation_data.action=act
 frames=round(seconds*30)
 for f in range(0,frames+1,2):
  t=f/max(1,frames)
  for pb in rig.pose.bones:
   pb.matrix_basis=rest_pose[pb.name].copy()
  pose_func(t)
  for pb in rig.pose.bones:
   pb.rotation_mode='QUATERNION';pb.keyframe_insert(data_path='rotation_quaternion',frame=f);pb.keyframe_insert(data_path='location',frame=f)
 act.use_fake_user=True
 track=rig.animation_data.nla_tracks.new();track.name=name;strip=track.strips.new(name,0,act);strip.name=name;strip.action_frame_start=0;strip.action_frame_end=frames
 track.mute=True
 rig.animation_data.action=None
 return act

def spin(name,axis,angle):
 pb=rig.pose.bones[name];pb.rotation_mode='QUATERNION';pb.rotation_quaternion=pb.rotation_quaternion@Quaternion(axis,angle)

reset()
for team in ['CT','T']:
 reset()
 with bpy.data.libraries.load(str(BASE),link=False) as (a,b):b.collections=['Body Male - Realistic']
 col=b.collections[0];bpy.context.scene.collection.children.link(col)
 body=next(o for o in col.all_objects if o.name.startswith('GEO-body_male_realistic') and '.eye' not in o.name)
 body.location=(0,0,0)
 for m in body.modifiers:
  if m.type=='MULTIRES':m.levels=1;m.render_levels=1
 bpy.context.view_layer.update()
 source=bpy.data.meshes.new_from_object(body.evaluated_get(bpy.context.evaluated_depsgraph_get()))
 low=min(v.co.z for v in source.vertices);height=max(v.co.z for v in source.vertices)-low;scale=1.80/height
 for v in source.vertices:v.co=Vector((v.co.x*scale,v.co.y*scale,(v.co.z-low)*scale))
 source.update()
 # The library collection is a data source only; generated meshes are self-contained.
 for o in list(col.all_objects):bpy.data.objects.remove(o,do_unlink=True)
 bpy.data.collections.remove(col)
 cloth=material(team+' ripstop jacket',(.09,.13,.18) if team=='CT' else (.36,.285,.175),fabric=True)
 pantsmat=material(team+' cargo fabric',(.065,.09,.12) if team=='CT' else (.13,.16,.105),fabric=True)
 vestmat=material(team+' woven carrier',(.045,.060,.058) if team=='CT' else (.20,.175,.105),fabric=True)
 webbing=material('Webbing '+team,(.11,.12,.10) if team=='CT' else (.26,.235,.16),fabric=True)
 leather=material('Glove leather '+team,(.045,.040,.030),.68)
 rubber=material('Rubber '+team,(.018,.022,.024),.8)
 metal=material('Matte hardware '+team,(.07,.075,.073),.45,.65)
 skin=material('Skin '+team,(.50,.31,.215) if team=='T' else (.57,.39,.29),.62)
 white=material('Eye white '+team,(.64,.62,.55),.35)
 iris=material('Brown iris '+team,(.09,.06,.035),.24)
 pupil=material('Pupil '+team,(.003,.004,.004),.16)
 labelmat=material('Patch embroidery '+team,(.65,.70,.68) if team=='CT' else (.64,.56,.38),.9)
 bones={'Root':((0,0,0),(0,0,.2),None),'Hips':((0,0,.98),(0,0,1.13),'Root'),'Spine':((0,0,1.13),(0,0,1.30),'Hips'),'Chest':((0,0,1.30),(0,0,1.48),'Spine'),'Neck':((0,0,1.48),(0,-.025,1.59),'Chest'),'Head':((0,-.025,1.59),(0,-.025,1.79),'Neck')}
 for side,s in [('L',1),('R',-1)]:
  bones.update({'Thigh_'+side:((s*.105,.015,.98),(s*.153,-.015,.55),'Hips'),'Shin_'+side:((s*.153,-.015,.55),(s*.158,.048,.14),'Thigh_'+side),'Foot_'+side:((s*.158,.048,.14),(s*.16,-.115,.07),'Shin_'+side),'UpperArm_'+side:((s*.215,0,1.43),(s*.335,-.035,1.115),'Chest'),'Forearm_'+side:((s*.335,-.035,1.115),(s*.427,-.075,.868),'UpperArm_'+side)})
 arm=bpy.data.armatures.new('OperatorSkeleton');rig=bpy.data.objects.new('OperatorRig',arm);bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 for name,(a,b,parent) in bones.items():
  bone=arm.edit_bones.new(name);bone.head=a;bone.tail=b
  if parent:bone.parent=arm.edit_bones[parent]
 bpy.ops.object.mode_set(mode='OBJECT')
 surface('Face and neck',source,lambda c:c.z>1.515 and abs(c.x)<.14,skin,region='Skin')
 surface('Fitted field jacket',source,lambda c:(1.00<c.z<1.535 and abs(c.x)<.245) or (c.z>.92 and abs(c.x)>.205),cloth,.021,'Shirt')
 surface('Cargo trousers',source,lambda c:.22<c.z<1.04 and abs(c.x)<.255,pantsmat,.034,'Pants')
 # Eyes retain the source scan's realistic spacing.
 for s in [-1,1]:
  x=s*.0329*scale;z=(1.5737-low)*scale;y=-.12182*scale
  rigid_ball('Eyeball',(x,y,z),(.0135,.0135,.0135),white)
  rigid_ball('Iris',(x,y-.0128,z),(.006,.0018,.006),iris)
  rigid_ball('Pupil',(x,y-.0145,z),(.0026,.0008,.0026),pupil)
  rigid_tube('Eyebrow',[(x-s*.023,-.13*scale,z+.021),(x,-.143*scale,z+.026),(x+s*.022,-.13*scale,z+.022)],.004,leather,'Head')
 # Plate carrier shaped to the torso, with layered fabric, webbing and seams.
 rigid_box('Front plate carrier',(0,-.135,1.295),(.365,.09,.355),vestmat,bevel=.035)
 rigid_box('Rear plate carrier',(0,.105,1.305),(.35,.08,.37),vestmat,bevel=.035)
 for s in [-1,1]:
  rigid_tube('Shoulder strap',[(s*.14,-.17,1.35),(s*.15,-.13,1.47),(s*.15,0,1.49),(s*.14,.14,1.42)],.025,webbing)
  rigid_box('Carrier side panel',(s*.195,-.005,1.24),(.055,.26,.19),vestmat,bevel=.012)
 for x in [-.12,0,.12]:
  rigid_box('Magazine pouch',(x,-.208,1.22),(.105,.065,.175),vestmat,bevel=.012)
  rigid_box('Pouch flap',(x,-.244,1.278),(.099,.017,.055),webbing,bevel=.005)
  rigid_box('Pouch pull tab',(x,-.259,1.264),(.018,.012,.035),rubber,bevel=.003)
 for z in [1.34,1.38,1.42]:
  for x in [-.112,0,.112]:rigid_box('MOLLE webbing',(x,-.185,z),(.102,.009,.017),webbing,bevel=.002)
 rigid_box('Radio',(-.177,-.175,1.38),(.06,.043,.14),rubber,bevel=.006)
 rigid_tube('Radio antenna',[(-.175,-.171,1.44),(-.175,-.171,1.62)],.004,metal)
 rigid_tube('Comms cable',[(-.172,-.17,1.43),(-.205,-.16,1.48),(-.18,-.07,1.52),(-.11,-.06,1.65)],.003,rubber)
 # Stitched seams on the pouch flaps and a raised fabric collar.
 for xx in [-.12,0,.12]:
  for zz in [1.15,1.28]:rigid_tube('Pouch stitching',[(xx-.038,-.244,zz),(xx+.038,-.244,zz)],.0011,webbing)
 for z in [1.483,1.495,1.507]:
  pts=[(.097*math.cos(i*TAU/48),.006+.085*math.sin(i*TAU/48),z-.012*max(0,-math.sin(i*TAU/48))) for i in range(49)]
  rigid_tube('Jacket collar',pts,.012,cloth,'Neck')
 # Belt wraps all the way around the waist.
 pts=[(.192*math.cos(i*TAU/48),.12*math.sin(i*TAU/48),1.02) for i in range(49)]
 rigid_tube('Equipment belt',pts,.026,leather,'Hips')
 rigid_box('Belt buckle',(0,-.149,1.025),(.065,.022,.045),metal,'Hips',.004)
 for s in [-1,1]:
  side='L' if s>0 else 'R'
  rigid_box('Thigh cargo pocket',(s*.23,-.003,.81),(.075,.15,.19),pantsmat,'Thigh_'+side,.018)
  rigid_box('Cargo pocket flap',(s*.269,-.003,.88),(.018,.15,.058),webbing,'Thigh_'+side,.007)
  rigid_box('Knee pad backing',(s*.156,-.09,.56),(.13,.038,.175),leather,'Shin_'+side,.025)
  rigid_box('Knee pad shell',(s*.156,-.117,.56),(.11,.025,.13),rubber,'Shin_'+side,.025)
  for z in [.515,.55,.585]:rigid_box('Knee articulation',(s*.156,-.132,z),(.07,.005,.006),metal,'Shin_'+side,.002)
  rigid_ball('Boot ankle',(s*.162,.039,.185),(.082,.09,.155),leather,'Foot_'+side)
  rigid_box('Boot upper',(s*.163,-.031,.105),(.165,.29,.16),leather,'Foot_'+side,.040)
  rigid_box('Boot sole',(s*.163,-.033,.036),(.172,.30,.052),rubber,'Foot_'+side,.018)
  rigid_box('Boot toe cap',(s*.163,-.133,.086),(.164,.102,.074),rubber,'Foot_'+side,.026)
  for z in [.14,.168,.196,.224]:
   rigid_tube('Boot laces',[(s*.163-.04,-.059,z),(s*.163+.04,-.069,z+.016)],.0027,webbing,'Foot_'+side)
  for y in [-.145,-.095,-.045,.005,.055]:rigid_box('Sole tread',(s*.163,y,.011),(.15,.018,.017),rubber,'Foot_'+side,.003)
 # Distinct headwear and equipment silhouettes.
 if team=='CT':
  helmet=surface('Ballistic helmet shell',source,lambda c:c.z>1.705 and abs(c.x)<.14,vestmat,.018,'Headwear')
  # Shell follows the skull; visor/goggle bridge sits below the rim.
  for s in [-1,1]:
   rigid_box('Helmet side rail',(s*.11,-.012,1.745),(.025,.11,.034),metal,'Head',.006)
   rigid_box('Goggle frame',(s*.041,-.157,1.69),(.079,.032,.045),rubber,'Head',.009)
   glass=material('Goggle lens '+str(s),(.06,.11,.105),.16,.4)
   rigid_box('Goggle lens',(s*.041,-.175,1.691),(.065,.009,.031),glass,'Head',.007)
   rigid_ball('Headset earcup',(s*.117,-.006,1.657),(.022,.04,.048),rubber)
   rigid_tube('Chin strap',[(s*.105,.005,1.72),(s*.09,-.03,1.59),(s*.04,-.1,1.56)],.008,webbing,'Head')
  rigid_box('NVG mounting bracket',(0,-.127,1.759),(.033,.024,.049),metal,'Head',.004)
  rigid_tube('Boom microphone',[(-.124,-.01,1.65),(-.14,-.075,1.61),(-.073,-.153,1.605)],.004,rubber,'Head')
  rigid_ball('Microphone foam',(-.073,-.153,1.605),(.016,.01,.009),rubber)
 else:
  hat=surface('Knitted watch cap',source,lambda c:c.z>1.721 and abs(c.x)<.14,leather,.009,'Headwear')
  for j in range(3):
   pts=[(.097*math.cos(i*TAU/48),-.035+.093*math.sin(i*TAU/48),1.722+j*.006) for i in range(49)]
   rigid_tube('Cap ribbed brim',pts,.0045,leather,'Head')
  for j in range(5):
   pts=[(.118*math.cos(i*TAU/48),.008+.115*math.sin(i*TAU/48),1.515+j*.012+.011*math.sin(i*TAU/48*2+j)) for i in range(49)]
   rigid_tube('Woven neck scarf',pts,.014,webbing,'Neck')
  rigid_box('Utility shoulder bag',(.235,.035,1.13),(.15,.17,.22),vestmat,'Spine',.025)
  rigid_tube('Sling strap',[(-.15,-.13,1.45),(-.02,-.21,1.32),(.15,-.20,1.13),(.24,0,1.1)],.015,webbing)
 # Embroidered team identifiers, readable at normal distance.
 def patch(text,at,back=False):
  cu=bpy.data.curves.new(text,'FONT');cu.body=text;cu.align_x='CENTER';cu.size=.041;cu.extrude=.0004
  ob=bpy.data.objects.new('Embroidered '+text,cu);bpy.context.collection.objects.link(ob);ob.location=at;ob.rotation_euler=(math.pi/2,0,math.pi if back else 0);cu.materials.append(labelmat)
  bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob;bpy.ops.object.convert(target='MESH');bind(ob,'Chest')
 rigid_box('Chest ID patch',(0,-.193,1.435),(.142,.008,.050),rubber,bevel=.003);patch('CT' if team=='CT' else 'T',(0,-.20,1.42))
 if team=='CT':patch('POLICE',(0,.153,1.385),True)
 # Weapon geometry is shared with the player's arsenal, replacing the old block rifle.
 with bpy.data.libraries.load(str(ROOT/'source_art/arsenal.blend'),link=False) as (a,b):b.objects=['W_m4' if team=='CT' else 'W_ak']
 gun=b.objects[0];bpy.context.collection.objects.link(gun);gun.name='Service rifle '+team;gun.rotation_euler.z=math.pi;gun.location=(-.09,-.16,1.31);gun.scale=(.82,.82,.82);bind(gun,'Chest')
 pose_arm('R',(-.29,-.14,1.17),(-.085,-.325,1.255))
 pose_arm('L',(.26,-.20,1.19),(-.08,-.57,1.29))
 gloves('R',(-.085,-.325,1.255));gloves('L',(-.08,-.57,1.29))
 rest_pose={pb.name:pb.matrix_basis.copy() for pb in rig.pose.bones}
 def idle(t):
  spin('Chest',(1,0,0),math.sin(t*TAU)*.008);spin('Head',(0,1,0),math.sin(t*TAU)*.012)
 def run(t):
  phase=t*TAU
  for side,offset in [('L',0),('R',math.pi)]:
   s=math.sin(phase+offset)
   spin('Thigh_'+side,(1,0,0),s*.48)
   spin('Shin_'+side,(1,0,0),max(0,-s)*.84)
   spin('Foot_'+side,(1,0,0),-.12*s)
  spin('Hips',(0,1,0),math.sin(phase)*.04)
  spin('Chest',(1,0,0),-.07+math.cos(phase*2)*.018)
  rig.pose.bones['Root'].location.y=.010*math.cos(phase*2)
 def fire(t):
  kick=math.sin(min(1,t*3)*math.pi)*.045*max(0,1-t)
  spin('Chest',(1,0,0),kick);rig.pose.bones['Chest'].location.y=kick*.16
 def reload(t):
  f=math.sin(t*math.pi)
  spin('Chest',(0,1,0),f*.10);spin('Forearm_L',(1,0,0),-f*.6);spin('UpperArm_L',(0,0,1),f*.26)
  spin('Head',(1,0,0),f*.13)
 def death(t):
  f=t*t*(3-2*t)
  spin('Root',(0,0,1),-f*1.50);rig.pose.bones['Root'].location.y=.25*f
  spin('Thigh_L',(1,0,0),-.20*math.sin(t*math.pi))
  spin('Chest',(0,0,1),f*.12)
 actions=[save_action('Idle',2.4,idle,True),save_action('Aim',2.4,idle,True),save_action('Run',.8,run,True),save_action('Fire',.2,fire),save_action('Reload',2.6,reload),save_action('Death',.8,death)]
 # Share one skinned mesh and material surfaces across all nine actors.
 bpy.ops.object.select_all(action='DESELECT')
 parts=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.parent==rig]
 for o in parts:o.select_set(True)
 bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();bpy.context.object.name='OperatorSurface'
 # Blender faces -Y. Rotate the model root so Godot faces -Z.
 root=bpy.data.objects.new('Operator_'+team,None);bpy.context.collection.objects.link(root);rig.parent=root;root.rotation_euler.z=math.pi
 rig.animation_data.action=actions[0];bpy.context.scene.frame_set(0)
 bpy.context.scene.render.fps=30;bpy.context.scene.frame_start=0;bpy.context.scene.frame_end=72
 bpy.ops.object.select_all(action='DESELECT')
 for o in bpy.context.scene.objects:
  if o.type in {'MESH','ARMATURE','EMPTY'}:o.select_set(True)
 bpy.context.view_layer.objects.active=rig
 bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source_art'/('operator_'+team.lower()+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(ASSETS/('operator_'+team.lower()+'.glb')),export_format='GLB',use_selection=True,export_apply=False,export_yup=True,export_cameras=False,export_lights=False,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_skins=True,export_all_influences=False,export_materials='EXPORT')
 print('OPERATOR COMPLETE',team,'triangles',sum(len(o.data.polygons)*2 for o in bpy.context.scene.objects if o.type=='MESH'))
 # Studio proof image uses the exact exported geometry and resting pose.
 root.rotation_euler.z=0
 bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.data.materials.append(material('Studio floor',(.07,.085,.085)))
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24
 scene.world.color=(.18,.18,.18)
 for loc,power,size in [((3,-4,5),650,4),((-3,-1,3),400,3),((0,3,4),650,3)]:
  bpy.ops.object.light_add(type='AREA',location=loc);l=bpy.context.object;l.data.energy=power;l.data.shape='DISK';l.data.size=size;l.rotation_euler=(Vector((0,0,1))-l.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add(location=(2.5,-4.5,2.3));cam=bpy.context.object;cam.rotation_euler=(Vector((0,-.08,.95))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.2;scene.camera=cam
 scene.render.resolution_x=850;scene.render.resolution_y=1050;scene.render.resolution_percentage=100;scene.render.filepath=str(PROOFS/('operator_'+team.lower()+'_proof.png'));bpy.ops.render.render(write_still=True)
print('OPERATORS BUILT')
