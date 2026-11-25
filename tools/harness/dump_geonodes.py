"""Dump Geometry Nodes trees used by objects in a .blend (node types, key inputs, links).

    blender -b --factory-startup <file.blend> -P tools/harness/dump_geonodes.py -- [object-name-substring]
"""
import bpy, sys

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SUB = ARGV[0] if ARGV else ""
seen = set()
for o in bpy.data.objects:
    for m in getattr(o, "modifiers", []):
        if m.type != "NODES" or SUB not in o.name:
            continue
        ng = m.node_group
        print("OBJ", o.name, "mod", m.name, "group", ng.name if ng else None)
        for k in m.keys():
            try:
                print("   input", k, m[k])
            except Exception:
                pass
        if not ng or ng.name in seen:
            continue
        seen.add(ng.name)
        for n in ng.nodes:
            vals = {}
            for i in n.inputs:
                if not i.is_linked and hasattr(i, "default_value"):
                    try:
                        v = i.default_value
                        vals[i.name] = v.name if hasattr(v, "name") else (tuple(v) if hasattr(v, "__len__") and not isinstance(v, str) else v)
                    except Exception:
                        pass
            extra = {a: getattr(n, a) for a in ("data_type", "domain", "operation", "mode") if hasattr(n, a)}
            print("  NODE", n.bl_idname, n.name, extra, vals)
        for l in ng.links:
            print("  LINK", l.from_node.name, l.from_socket.name, "->", l.to_node.name, l.to_socket.name)
