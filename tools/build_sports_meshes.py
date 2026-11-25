"""Generate original low-poly sports meshes with Blender 4.5.

Run: blender --background --python tools/build_sports_meshes.py
Exports glTF assets for Roblox Studio import. Coordinates are Roblox-style:
X field length, Y up, Z field width. Dimensions are in studs.
"""
import math
from pathlib import Path
import bpy
from mathutils import Matrix

OUT = Path(__file__).resolve().parents[1] / "assets/sports"
OUT.mkdir(parents=True, exist_ok=True)


def material(name, rgba):
    m = bpy.data.materials.new(name)
    m.diffuse_color = rgba
    return m


WHITE = material("worn court white", (.82, .83, .78, 1))
STEEL = material("dark galvanized steel", (.23, .26, .27, 1))
BOARD = material("weathered backboard", (.75, .78, .78, 1))
ORANGE = material("powder coated rim", (.8, .18, .045, 1))
NET = material("woven net", (.84, .82, .73, 1))
TRACK = material("rubber track", (.42, .12, .10, 1))
TRACK_ALT = material("rubber track alternate", (.45, .14, .11, 1))
PALETTE = [WHITE, STEEL, BOARD, ORANGE, NET, TRACK, TRACK_ALT]


def palette_texture():
    image = bpy.data.images.new("Sports palette", width=256, height=32, alpha=True)
    colors = [m.diffuse_color[:] for m in PALETTE]
    image.pixels = [channel for _y in range(32) for x in range(256)
                    for channel in colors[min(len(colors)-1, x*len(colors)//256)]]
    image.filepath_raw = str(OUT / "sports_palette.png")
    image.file_format = 'PNG'
    image.save()
    mat = bpy.data.materials.new("Sports atlas")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = image
    shader = nodes.get('Principled BSDF')
    mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
    shader.inputs['Roughness'].default_value = .88
    return mat


ATLAS = palette_texture()


def clean():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def cube(name, loc, scale, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    return o


def rod(name, start, end, radius, mat, sides=8):
    import mathutils
    a, b = mathutils.Vector(start), mathutils.Vector(end)
    direction = b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=direction.length,
                                        location=(a+b)/2)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = direction.to_track_quat('Z', 'Y').to_euler()
    o.data.materials.append(mat)
    return o


def stroke(name, points, radius, mat):
    c = bpy.data.curves.new(name, 'CURVE')
    c.dimensions = '3D'
    c.bevel_depth = radius
    c.bevel_resolution = 0
    s = c.splines.new('POLY')
    s.points.add(len(points)-1)
    for v, p in zip(s.points, points):
        v.co = (*p, 1)
    o = bpy.data.objects.new(name, c)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(mat)
    return o


def export(name):
    # Blender is Z-up; rotate authored Y-up vertices before glTF's axis
    # conversion so Roblox receives X=length, Y=height, Z=width.
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.convert(target='MESH')
    rotate = Matrix.Rotation(math.pi / 2, 4, 'X')
    for o in bpy.context.scene.objects:
        o.matrix_world = rotate @ o.matrix_world
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    bpy.context.object.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    combined = bpy.context.object.data
    old_materials = list(combined.materials)
    uv = combined.uv_layers.new(name="Palette UV")
    for poly in combined.polygons:
        mat = old_materials[poly.material_index]
        index = next((i for i, entry in enumerate(PALETTE) if entry == mat), 0)
        for loop_index in poly.loop_indices:
            uv.data[loop_index].uv = ((index + .5) / len(PALETTE), .5)
        poly.material_index = 0
    combined.materials.clear()
    combined.materials.append(ATLAS)
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + '.glb')), export_format='GLB',
                              use_selection=True, export_apply=True)


# Hoop origin is the base of the support. The backboard faces -X; the rim
# centre is 2.4 studs toward the court and exactly 10 studs above the surface.
clean()
rod("round support", (0, 0, 0), (0, 11.4, 0), .28, STEEL, 12)
rod("cantilever", (0, 11.4, 0), (-1.2, 11.4, 0), .19, STEEL, 10)
cube("72 inch backboard", (-1.2, 11.4, 0), (.12, 3.5, 6), BOARD)
stroke("backboard square", [(-1.29, 11.15, -1), (-1.29, 12.25, -1),
                            (-1.29, 12.25, 1), (-1.29, 11.15, 1)], .025, WHITE)
rod("rim arm", (-1.29, 10, 0), (-2.4, 10, 0), .12, ORANGE)
rim = [(-2.4+1.02*math.cos(i*2*math.pi/32), 10, 1.02*math.sin(i*2*math.pi/32))
       for i in range(33)]
stroke("round metal rim", rim, .085, ORANGE)
for i in range(12):
    a = i*2*math.pi/12
    b = (i+.5)*2*math.pi/12
    top = (-2.4+1.02*math.cos(a), 9.92, 1.02*math.sin(a))
    low = (-2.4+.62*math.cos(b), 8.7, .62*math.sin(b))
    stroke("net cord", [top, low], .024, NET)
for y, r in [(9.45, .86), (8.7, .62)]:
    stroke("net ring", [(-2.4+r*math.cos(i*2*math.pi/24), y,
                         r*math.sin(i*2*math.pi/24)) for i in range(25)], .02, NET)
export("street_hoop")

# Painted markings are one noncolliding mesh, scaled to each mapped court.
clean()
def line(points):
    stroke("paint", [(x, .04, z) for x, z in points], .09, WHITE)

line([(-49,-29),(49,-29),(49,29),(-49,29),(-49,-29)])
line([(0,-29),(0,29)])
line([(6*math.cos(i*math.pi/24),6*math.sin(i*math.pi/24)) for i in range(49)])
for side in (-1,1):
    x = side*34
    line([(x,-8),(side*49,-8)])
    line([(x,8),(side*49,8)])
    line([(x,-8),(x,8)])
    line([(side*45,-29),(side*45,-22)])
    line([(side*45,29),(side*45,22)])
    line([(side*(45-22*math.cos(i*math.pi/32)),22*math.sin(i*math.pi/32))
          for i in range(-16,17)])
export("court_paint_100x60")

# American football lines and numbers, including 10-yard end zones. The
# single visual asset scales to each surveyed football footprint.
clean()
def football_line(points, radius=.12):
    stroke("football paint", [(x, .05, z) for x, z in points], radius, WHITE)

football_line([(-179,-79),(179,-79),(179,79),(-179,79),(-179,-79)])
for x in range(-150,151,15):
    football_line([(x,-79),(x,79)], .11 if x % 30 else .19)
    for z in (-25,25):
        football_line([(x-1.3,z),(x+1.3,z)], .1)
for x in (-150,150):
    football_line([(x,-79),(x,79)], .33)
for sign in (-1,1):
    for i, yard in enumerate((10,20,30,40,50,40,30,20,10)):
        t = bpy.data.curves.new("yard number", 'FONT')
        t.body = str(yard)
        t.size = 7
        t.align_x = 'CENTER'
        t.materials.append(WHITE)
        o = bpy.data.objects.new("yard number", t)
        bpy.context.collection.objects.link(o)
        o.location = (-120+i*30, .06, sign*58)
        o.rotation_euler[0] = -math.pi/2
export("football_paint_360x160")

# Six continuous curved lanes around the field. Each lane is a low-poly ring
# with 24 facets per semicircle; one MeshPart replaces four flat track strips.
clean()
verts, faces, mats = [], [], []
straight = (560-260)/2
def oval(radius):
    return [(straight+radius*math.cos(a), .02, radius*math.sin(a))
            for a in [(-math.pi/2+i*math.pi/24) for i in range(25)]] + [
            (-straight+radius*math.cos(a), .02, radius*math.sin(a))
            for a in [(math.pi/2+i*math.pi/24) for i in range(25)]]

for lane in range(6):
    inner = oval(94 + lane*6)
    outer = oval(100 + lane*6)
    start = len(verts)
    verts.extend(inner+outer)
    n = len(inner)
    for i in range(n):
        faces.append((start+i,start+(i+1)%n,start+n+(i+1)%n,start+n+i))
        mats.append(lane%2)
track_mesh = bpy.data.meshes.new("actual oval lane geometry")
track_mesh.from_pydata(verts, [], faces)
track_mesh.materials.append(TRACK)
track_mesh.materials.append(TRACK_ALT)
track_mesh.update()
o = bpy.data.objects.new("six lane oval 560x260", track_mesh)
bpy.context.collection.objects.link(o)
for poly, m in zip(track_mesh.polygons, mats):
    poly.material_index = m
for lane in range(7):
    stroke("lane stripe", oval(94+lane*6), .055, WHITE)
export("six_lane_oval_560x260")

# Simple repeated metal bench profile; a single asset per stand section.
clean()
for row in range(5):
    cube("aluminium bench", (0, 1.3+row*.65, row*2.1), (60, .18, .8), BOARD)
    cube("riser", (0, .7+row*.65, row*2.1+.45), (60, 1.0, .12), STEEL)
for x in (-28,0,28):
    for row in range(5):
        rod("steel support", (x, 0, row*2.1), (x, 1.3+row*.65, row*2.1), .1, STEEL)
export("bleacher_section_60")

print(f"Sports meshes written to {OUT}")
