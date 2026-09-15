import bpy, math, json, random, os
from mathutils import Vector
random.seed(42)
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A=ROOT+'/assets'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def mat(name,col,metal=0,rough=.8):
 m=bpy.data.materials.new(name); m.diffuse_color=(*col,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*col,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
 return m
stone=mat('Sun-worn sandstone',(.64,.52,.35))
if os.path.exists(A+'/stone_diff.jpg'):
 p=stone.node_tree.nodes.get('Principled BSDF')
 for filename,socket in [('stone_diff.jpg','Base Color'),('stone_rough.jpg','Roughness')]:
  t=stone.node_tree.nodes.new('ShaderNodeTexImage'); t.image=bpy.data.images.load(A+'/'+filename)
  if socket!='Base Color': t.image.colorspace_settings.name='Non-Color'
  stone.node_tree.links.new(t.outputs['Color'],p.inputs[socket])
plaster=mat('Ivory plaster',(.70,.64,.50)); ochre=mat('Warm ochre',(.60,.43,.26)); cream=mat('Pale trim',(.82,.76,.61))
blue=mat('Faded blue',(.15,.28,.35)); dark=mat('Shadow recess',(.045,.055,.052)); wood=mat('Dark cedar',(.24,.13,.055))
iron=mat('Weathered iron',(.12,.14,.14),.65,.45); olive=mat('Olive crate',(.28,.29,.16)); red=mat('Oxide red',(.56,.12,.055))
ground=mat('Dusty street',(.53,.46,.34)); black=mat('Gunmetal',(.06,.07,.073),.75,.33); steel=mat('Machined steel',(.23,.25,.26),.85,.25)
polymer=mat('Black polymer',(.025,.03,.032),.05,.64); walnut=mat('Walnut furniture',(.32,.11,.035),.1,.45); tan=mat('Coyote polymer',(.38,.32,.19),.05,.58)
glass=mat('Scope glass',(.03,.18,.15),.7,.13); brass=mat('Brass',(.55,.35,.09),.8,.32)
collisions=[]
def box(name,pos,size,material,collide=False,bevel=0):
 # all input in Godot's Y-up, forward -Z coordinates
 bpy.ops.mesh.primitive_cube_add(size=1,location=(pos[0],-pos[2],pos[1])); o=bpy.context.object; o.name=name; o.scale=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(material)
 if material==stone:
  for poly in o.data.polygons:
   n=poly.normal
   for li in poly.loop_indices:
    co=o.data.vertices[o.data.loops[li].vertex_index].co
    if abs(n.z)>.5: uv=(co.x/3,co.y/3)
    elif abs(n.x)>.5: uv=(co.y/3,co.z/3)
    else: uv=(co.x/3,co.z/3)
    o.data.uv_layers.active.data[li].uv=uv
 if bevel:
  mod=o.modifiers.new('Edge highlights','BEVEL'); mod.width=bevel; mod.segments=2
 if collide: collisions.append({'p':list(pos),'s':list(size)})
 return o
def cyl(name,pos,r,depth,material,axis='y',vertices=16):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=(pos[0],-pos[2],pos[1])); o=bpy.context.object; o.name=name; o.data.materials.append(material)
 if axis=='z': o.rotation_euler.x=math.pi/2
 if axis=='x': o.rotation_euler.y=math.pi/2
 return o
def sphere(name,pos,scale,material):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,location=(pos[0],-pos[2],pos[1])); o=bpy.context.object; o.name=name; o.scale=(scale[0],scale[2],scale[1]); o.data.materials.append(material)
 for p in o.data.polygons:p.use_smooth=True
 return o
def line(name,start,end,r,material):
 a=Vector((start[0],-start[2],start[1])); b=Vector((end[0],-end[2],end[1])); d=b-a
 bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=r,depth=d.length,location=(a+b)/2); o=bpy.context.object; o.name=name; o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(material);return o
def text_obj(text,pos,size,material,rot=0):
 cu=bpy.data.curves.new('Painted lettering','FONT');cu.body=text;cu.size=size;cu.align_x='CENTER';cu.extrude=.001
 ob=bpy.data.objects.new('Sign_'+text,cu);bpy.context.collection.objects.link(ob); ob.location=(pos[0],-pos[2],pos[1]);ob.rotation_euler=(math.pi/2,0,rot);ob.data.materials.append(material)
 bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.convert(target='MESH');ob.select_set(False)
 return ob
def export(path):
 bpy.ops.object.select_all(action='SELECT')
 bpy.ops.export_scene.gltf(filepath=path,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
def clear():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

box('Ground',(0,-.3,0),(102,.6,102),ground,True)
for pos,size in [((0,5,-48),(96,10,2)),((0,5,48),(96,10,2)),((-48,5,0),(2,10,96)),((48,5,0),(2,10,96))]:box('Perimeter',pos,size,stone,True)
buildings=[(-18,0,20,32,8),(18,4,19,29,9),(-23,38,22,12,7),(23,38,21,12,8),(-32,-42,28,10,9),(31,-42,30,10,10),(-43,6,8,49,9),(44,-2,7,61,8),(-16,-30,7,12,7),(17,-31,9,12,8)]
for i,(x,z,w,d,h) in enumerate(buildings):
 material=stone if i%3==0 else plaster if i%3==1 else ochre
 box('Building_%02d'%i,(x,h/2,z),(w,h,d),material,True,.07)
 box('Cornice',(x,h-.1,z),(w+.32,.3,d+.32),cream)
 for px,pz,sx,sz in [(x,z-d/2,w,.22),(x,z+d/2,w,.22),(x-w/2,z,.22,d),(x+w/2,z,.22,d)]:
  box('Parapet',(px,h+.48,pz),(sx,.9,sz),material)
 # windows on north/south faces, shutter slats and frames
 for zz,face in [(z-d/2-.025,-1),(z+d/2+.025,1)]:
  for xx in range(int(x-w/2+2),int(x+w/2-1),3):
   for yy in [3.4,6.1]:
    if yy+1>h:continue
    box('Window recess',(xx,yy,zz),(1.03,1.45,.06),dark)
    box('Window sill',(xx,yy-.79,zz+face*.09),(1.24,.13,.27),cream)
    for k in range(7):box('Shutter slat',(xx,yy-.6+k*.2,zz+face*.04),(.93,.13,.04),blue if i%2 else wood)
 # side windows visible down lanes
 for xx,face in [(x-w/2-.025,-1),(x+w/2+.025,1)]:
  for zz in range(int(z-d/2+2),int(z+d/2-1),4):
   box('Side window',(xx,4,zz),(.06,1.4,.95),dark)
   for k in range(6):box('Side shutter',(xx+face*.04,3.45+k*.2,zz),(.04,.13,.87),blue)
 # roof utilities
 cyl('Water tank',(x+1,h+1.3,z),.9,1.6,iron)
 for zz in [z-d/2+.5,z+d/2-.5]:line('Drainpipe',(x+w/2+.15,.2,zz),(x+w/2+.15,h-.5,zz),.06,iron)

# Mid double doors: narrow tactical passage, two solid leaves with central gap.
for x,w in [(-5.9,7.0),(5.9,7.0)]:box('Mid gate wall',(x,2.7,-20),(w,5.4,1.1),stone,True)
box('Mid arch lintel',(0,5.1,-20),(5.1,1.3,1.1),stone,True)
for x in [-1.8,1.8]:
 box('Mid wooden door',(x,1.9,-20),(.95,3.8,.24),wood,True,.03)
 for y in [.6,1.8,3.1]:box('Door iron strap',(x,y,-19.85),(1,.12,.045),iron)
 for xx in [x-.36,x,x+.36]:
  for y in [.6,1.8,3.1]:sphere('Rivet',(xx,y,-19.80),(.035,.035,.018),steel)

# Long A double doorway and enclosed approach.
box('Long gate left',(30,2.9,22),(4,5.8,1.5),stone,True)
box('Long gate right',(40.5,2.9,22),(5,5.8,1.5),stone,True)
box('Long gate upper',(35,5.3,22),(6,1,1.5),stone,True)
for x in [32.8,37.3]:
 box('Long gate cedar',(x,2,22),(1.1,4,.3),wood,True)
 for y in [.6,2,3.3]:box('Long gate steel',(x,y,22.18),(1.13,.15,.05),iron)

# B tunnel, broken roof and columns.
box('Tunnel ceiling',(-33,4.5,8),(10,.65,32),stone,True)
for z in [-6,1,9,17,23]:
 for x in [-37.7,-28.5]:
  box('Tunnel pilaster',(x,2,z),(.65,4,.7),stone,True)
  box('Column cap',(x,3.8,z),(.95,.35,.95),cream)
 box('Tunnel beam',(-33,3.9,z),(10,.4,.6),ochre)
box('Lower tunnel dividing wall',(-21,2,21),(15,4,1.2),stone,True)

def crate(x,z,w=2.4,h=2.3,d=2.2):
 box('Cargo crate',(x,h/2,z),(w,h,d),olive,True,.04)
 for zz in [z-d/2-.03,z+d/2+.03]:
  for xx in [x-w/2+.15,x+w/2-.15]:box('Crate steel edge',(xx,h/2,zz),(.15,h+.06,.07),iron)
  for yy in [.16,h-.16]:box('Crate frame',(x,yy,zz),(w,.17,.08),wood)
  for xx in [x-w*.22,x+w*.22]:box('Crate reinforcement',(xx,h/2,zz),(.12,h,.07),wood)
 for xx in [x-w/2-.03,x+w/2+.03]:
  for zz in [z-d/2+.1,z+d/2-.1]:box('Crate edge',(xx,h/2,zz),(.07,h,.15),iron)

for q in [(30,-28,4,2.5,3),(36,-25,3,2.3,3),(26,-31,2,3.2,2),(-33,-28,3.4,2.5,3),(-27,-33,4,2.2,2),(-39,-24,2,3,2),(-7,5,2,2,2),(7,-10,2,1.5,2),(38,7,2,2,2),(-33,28,3,2,2)]:crate(*q)
for x,z in [(38,-31),(39,-31),(-25,-25),(-26,-25),(28,27),(29,27),(-6,16)]:
 cyl('Blue barrel',(x,.62,z),.43,1.24,blue);collisions.append({'p':[x,.62,z],'s':[.86,1.24,.86]})
 for y in [.15,.45,.95,1.18]:cyl('Barrel ring',(x,y,z),.443,.035,iron)

# Shopfronts, readable map landmarks and wall paint.
box('Hotel sign board',(31,6.5,-36.91),(14,1.4,.1),blue)
text_obj('HOTEL AURORE',(31,6.2,-36.82),.84,cream)
box('Shop sign',(18,3.3,18.57),(12,.9,.1),blue)
text_obj('MARCHE  •  SAHARA',(18,3.02,18.65),.55,cream)
for x,z,t in [(30,-36.8,'A'),(-32,-36.8,'B')]:text_obj(t,(x,2.2,z),2.8,red)
text_obj('A  →',(3,2,-19.35),.95,red)
text_obj('←  B',(-5,2,-19.35),.85,red)
for x in [13,17,21]:
 box('Roller shop door',(x,1.3,18.6),(2.4,2.6,.12),blue)
 for y in range(13):box('Roller seam',(x,.1+y*.2,18.68),(2.35,.024,.02),iron)

# Car at long A, distinct bodywork.
carblue=mat('Abandoned car paint',(.38,.47,.49),.4,.7)
box('Car body',(40,.65,-12),(2.1,.8,4.1),carblue,True,.18)
box('Car cabin',(40,1.28,-12.3),(1.85,.7,2.1),carblue,False,.16)
box('Windshield',(40,1.35,-11.23),(1.65,.48,.03),dark)
box('Rear window',(40,1.35,-13.38),(1.65,.42,.03),dark)
for x in [38.98,41.02]:
 for z in [-13.3,-10.8]:cyl('Car tire',(x,.4,z),.42,.24,polymer,'x');cyl('Car hub',(x+(x-40)*.13,.4,z),.23,.02,steel,'x')
for x in [39.3,40.7]:box('Headlight',(x,.75,-9.92),(.42,.22,.04),cream)

# Poles and catenary wires, rubble, roof dishes.
for x,z in [(-8,29),(8,22),(39,-3),(-26,-15),(13,-29)]:
 cyl('Utility pole',(x,5,z),.14,10,wood)
 box('Pole crossbar',(x,9,z),(2,.12,.13),wood)
for a,b in [((-8,9,29),(8,9,22)),((8,9,22),(39,9,-3)),((-26,9,-15),(13,9,-29))]:
 for off in [-.7,0,.7]:
  for k in range(12):
   t=k/12;u=(k+1)/12
   p=[a[j]*(1-t)+b[j]*t for j in range(3)];q=[a[j]*(1-u)+b[j]*u for j in range(3)]
   p[0]+=off;q[0]+=off;p[1]-=math.sin(t*math.pi)*1.3;q[1]-=math.sin(u*math.pi)*1.3;line('Power cable',p,q,.016,iron)
for k in range(150):
 x=random.uniform(-45,45);z=random.uniform(-45,45)
 if abs(x)<9 or x>28 or x<-28:
  o=box('Street rubble',(x,.035,z),(random.uniform(.04,.18),.045,random.uniform(.04,.15)),cream);o.rotation_euler.z=random.random()*6
# Site circles as small inlaid segments
for x,z in [(31,-27),(-32,-28)]:
 for i in range(48):
  a=i*math.tau/48;b=(i+1)*math.tau/48
  line('Bombsite boundary',(x+5*math.cos(a),.015,z+5*math.sin(a)),(x+5*math.cos(b),.015,z+5*math.sin(b)),.045,red)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/source_art/dust_map.blend')
export(A+'/dust_map.glb')
json.dump(collisions,open(A+'/collision.json','w'))
clear()

# Weapon statistics approximate classic competitive behavior; all 34 firearms.
rows=[
('glock','Glock-18','Pistols',200,20,120,30,400,.17,2.3,0,'T'),('usp','USP-S','Pistols',200,12,60,35,352,.16,2.2,0,'CT'),('p2000','P2000','Pistols',200,13,65,35,352,.17,2.2,0,'CT'),('p250','P250','Pistols',300,13,52,38,400,.2,2.2,0,'ALL'),('dual','Dual Berettas','Pistols',300,30,120,38,500,.19,2.8,0,'ALL'),('fiveseven','Five-SeveN','Pistols',500,20,100,32,400,.18,2.2,0,'CT'),('tec9','Tec-9','Pistols',500,18,90,33,500,.22,2.5,0,'T'),('cz','CZ75-Auto','Pistols',500,12,36,31,600,.25,2.7,1,'ALL'),('deagle','Desert Eagle','Pistols',700,7,35,53,267,.75,2.3,0,'ALL'),('r8','R8 Revolver','Pistols',600,8,40,86,150,.65,2.3,0,'ALL'),
('mac10','MAC-10','SMGs',1050,30,100,29,800,.32,2.6,1,'T'),('mp9','MP9','SMGs',1250,30,120,26,857,.28,2.1,1,'CT'),('mp7','MP7','SMGs',1500,30,120,29,750,.28,3.1,1,'ALL'),('mp5','MP5-SD','SMGs',1500,30,120,27,750,.24,2.9,1,'ALL'),('ump','UMP-45','SMGs',1200,25,100,35,667,.3,3.1,1,'ALL'),('p90','P90','SMGs',2350,50,100,26,857,.26,3.3,1,'ALL'),('bizon','PP-Bizon','SMGs',1400,64,120,27,750,.25,2.4,1,'ALL'),
('ak','AK-47','Rifles',2700,30,90,36,600,.52,2.5,1,'T'),('m4','M4A4','Rifles',3100,30,90,33,666,.38,3.1,1,'CT'),('m4s','M4A1-S','Rifles',2900,20,80,38,600,.3,3.1,1,'CT'),('galil','Galil AR','Rifles',1800,35,90,30,666,.44,3,1,'T'),('famas','FAMAS','Rifles',2050,25,90,30,666,.37,3.3,1,'CT'),('aug','AUG','Rifles',3300,30,90,28,600,.3,3.8,1,'CT'),('sg','SG 553','Rifles',3000,30,90,30,545,.4,2.8,1,'T'),
('ssg','SSG 08','Snipers',1700,10,90,88,48,1.6,3.7,0,'ALL'),('awp','AWP','Snipers',4750,5,30,115,41,2.2,3.7,0,'ALL'),('g3','G3SG1','Snipers',5000,20,80,80,240,.9,4.7,1,'T'),('scar','SCAR-20','Snipers',5000,20,80,80,240,.9,3.1,1,'CT'),
('nova','Nova','Heavy',1050,8,32,26,68,1.3,3.2,0,'ALL'),('xm','XM1014','Heavy',2000,7,32,20,171,1.1,3.1,1,'ALL'),('mag7','MAG-7','Heavy',1300,5,32,30,71,1.4,2.4,0,'CT'),('sawed','Sawed-Off','Heavy',1100,7,32,32,71,1.5,3.2,0,'T'),('m249','M249','Heavy',5200,100,200,32,750,.55,5.7,1,'ALL'),('negev','Negev','Heavy',1700,150,200,35,800,.48,5.7,1,'ALL')]
weapons=[]
for row in rows:
 wid,name,cat,price,mag,res,damage,rpm,recoil,reload,auto,team=row
 weapons.append(dict(id=wid,name=name,category=cat,price=price,mag=mag,reserve=res,damage=damage,rpm=rpm,recoil=recoil,reload=reload,auto=auto,team=team))
 start=set(bpy.context.scene.objects)
 pistol=cat=='Pistols'; sniper=cat=='Snipers'; smg=cat=='SMGs'; shotgun=wid in ['nova','xm','mag7','sawed']; heavy=wid in ['m249','negev']
 furniture=walnut if wid in ['ak','nova','sawed'] else tan if wid in ['scar','awp','ssg'] else polymer
 if pistol:
  box('Slide',(0,.07,-.17),(.065,.075,.28 if wid!='deagle' else .36),black,bevel=.008)
  box('Lower',(0,.015,-.14),(.06,.045,.22),polymer,bevel=.007)
  o=box('Grip',(0,-.08,-.075),(.065,.17,.09),furniture,bevel=.01);o.rotation_euler.x=-.19
  cyl('Barrel',(0,.069,-.325),.021,.04,steel,'z')
  if wid=='usp':cyl('Suppressor',(0,.069,-.43),.027,.23,black,'z')
  for z in [-.035,-.29]:box('Sight',(0,.119,z),(.021,.018,.025),steel)
  for z in [-.06,-.08,-.1]:box('Slide serration',(.034,.078,z),(.004,.052,.006),steel)
  if wid=='r8':cyl('Cylinder',(0,.034,-.145),.055,.09,steel,'z')
 else:
  L=.68 if smg else 1.05 if sniper else .9
  box('Receiver',(0,.06,-.30),(.075,.12,.34),black,bevel=.009)
  box('Ejection port',(.041,.087,-.31),(.005,.042,.10),dark)
  box('Bolt',(.046,.08,-.29),(.012,.024,.064),steel)
  box('Handguard',(0,.055,-.52),(.085,.105,.22 if not sniper else .35),furniture,bevel=.012)
  for j in range(7):
   box('Foregrip groove',(.045,.066,-.43-j*.027),(.008,.065,.009),black)
   box('Rail tooth',(0,.13,-.17-j*.035),(.055,.012,.016),steel)
  cyl('Barrel',(0,.065,-L+.11),.019,.30 if not sniper else .46,steel,'z')
  cyl('Muzzle',(0,.065,-L-.045),.026,.045,black,'z')
  if wid in ['m4s','mp5']:cyl('Suppressor',(0,.065,-L-.15),.034,.25,black,'z')
  o=box('Pistol grip',(0,-.075,-.20),(.066,.17,.085),furniture,bevel=.009);o.rotation_euler.x=-.22
  if not shotgun:
   if wid=='ak':
    for j in range(5):
     o=box('Curved magazine',(0,-.04-j*.039,-.38+j*j*.004),(.06,.056,.115),black,bevel=.004);o.rotation_euler.x=-j*.12
   elif wid=='p90':box('Top magazine',(0,.16,-.37),(.09,.04,.34),tan,bevel=.005)
   elif wid=='bizon':cyl('Helical magazine',(0,-.045,-.51),.052,.30,black,'z')
   elif heavy:box('Ammo box',(0,-.095,-.39),(.19,.2,.19),olive,bevel=.012)
   else:box('Magazine',(0,-.09,-.37),(.06,.22,.1),black,bevel=.006)
  else:cyl('Tube magazine',(0,.008,-.64),.025,.40,black,'z')
  box('Stock tube',(0,.057,-.025),(.039,.046,.25),steel)
  box('Buttstock',(0,.035,.08),(.073,.16,.20),furniture,bevel=.01)
  box('Buttpad',(0,.024,.188),(.083,.18,.022),polymer,bevel=.005)
  if sniper or wid in ['aug','sg']:
   for z in [-.20,-.38]:box('Scope mount',(0,.16,z),(.045,.065,.026),steel)
   cyl('Scope',(0,.218,-.29),.034,.32,black,'z')
   cyl('Scope objective',(0,.218,-.48),.049,.075,black,'z')
   cyl('Scope lens',(0,.218,-.52),.043,.005,glass,'z')
   cyl('Scope dial',(0,.264,-.29),.021,.035,black)
  else:
   for z in [-.19,-.67]:box('Iron sight',(0,.153,z),(.029,.045,.023),black)
  if heavy:
   for j in range(6):cyl('Ammo belt',(.08+j*.019,.08,-.36),.008,.065,brass,'z')
 # trigger guard and trigger, screws
 box('Trigger guard',(0,-.049,-.28),(.05,.015,.095),steel)
 box('Trigger',(0,-.025,-.29),(.012,.055,.012),steel)
 for z in [-.19,-.31]:sphere('Fastener',(.04,.05,z),(.003,.01,.01),steel)
 new=[o for o in bpy.context.scene.objects if o not in start]
 bpy.ops.object.select_all(action='DESELECT')
 for o in new:o.select_set(True)
 bpy.context.view_layer.objects.active=new[0]
 bpy.ops.object.convert(target='MESH');bpy.ops.object.join();o=bpy.context.object;o.name='W_'+wid
 # reset origin to firearm coordinate origin
 bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 o.select_set(False)
json.dump(weapons,open(A+'/weapons.json','w'),indent=2)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/source_art/arsenal.blend');export(A+'/arsenal.glb');clear()

# Operators are built separately by build_operators.py from the CC0 human base.
# Keep map/arsenal regeneration from replacing the modern skinned characters.
print('MAP AND ARSENAL COMPLETE; operators unchanged')
