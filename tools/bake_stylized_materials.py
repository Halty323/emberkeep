#!/usr/bin/env python3
"""Bake original, seamless carved materials for the stylized-lighting branch.

No photographs, downloads, AI images, or gameplay RNG. The large forms are
explicit stone courses, chipped polygons, wood cuts, and hammer marks. Fine
detail is deliberately sparse. Height, normals, AO, and roughness describe
the SAME surface, so a moving light reveals the artwork rather than noise.

Authoring: Python 3, Pillow, numpy, scipy. Offline --check only needs Pillow.
2048px color/normal; renormalized 1024px mobile pair; 1024px packed ORMH.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFile

ImageFile.MAXBLOCK = 32 * 1024 * 1024
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/materials/stylized"
SEED = 18492
FAMILIES = ("masonry", "flagstone", "rock", "wood", "metal")
FILES = ("color.jpg", "normal.jpg", "color_mobile.jpg", "normal_mobile.jpg", "ormh.png")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def noise(rng, w, h, cells_x, cells_y):
    """Periodic low-frequency brush fields, NOT photographic grain."""
    import numpy as np
    from scipy.ndimage import map_coordinates
    grid = rng.random((cells_y, cells_x), dtype=np.float32)
    y, x = np.mgrid[:h, :w].astype(np.float32)
    return map_coordinates(grid, [y / h * cells_y, x / w * cells_x],
                           order=3, mode="grid-wrap").clip(0, 1)


def stone_polygons(rng, w, h, family, layout=None):
    import numpy as np
    if family == "rock":
        from scipy.spatial import Voronoi
        points = [(x / 5 * w + rng.uniform(.12, .88) * w / 5,
                   y / 5 * h + rng.uniform(.12, .88) * h / 5)
                  for y in range(5) for x in range(5)]
        tiled = np.array([(x + dx * w, y + dy * h) for dy in (-1, 0, 1)
                          for dx in (-1, 0, 1) for x, y in points])
        diagram = Voronoi(tiled)
        for i in range(100, 125):
            polygon = diagram.vertices[diagram.regions[diagram.point_region[i]]]
            center = tiled[i]
            polygon = center + (polygon - center) * .955
            # Break every long silhouette with two chisel-cut corners.
            cut = []
            for j, vertex in enumerate(polygon):
                cut.extend([vertex * .88 + polygon[j-1] * .12,
                            vertex * .88 + polygon[(j+1) % len(polygon)] * .12])
            yield np.array(cut)
        return
    rows, cols = layout or (4 if family == "masonry" else 3, 4)
    for row in range(rows):
        widths = rng.uniform(.78, 1.22, cols)
        bounds = np.r_[0, np.cumsum(widths / widths.sum() * w)]
        shift = (row % 2) * w * .127
        for column in range(cols):
            left, right = bounds[column] + shift, bounds[column+1] + shift
            top, bottom = row * h / rows, (row+1) * h / rows
            gutter = 9 if family == "masonry" else 11
            left += gutter + rng.uniform(0, 5)
            right -= gutter + rng.uniform(0, 5)
            top += gutter + rng.uniform(-4, 4)
            bottom -= gutter + rng.uniform(-4, 4)
            cut = rng.uniform(12, 32, 8)
            corners = np.array([(left+cut[0], top+2), (right-cut[1], top-2),
                                (right+2, top+cut[2]), (right-2, bottom-cut[3]),
                                (right-cut[4], bottom+2), (left+cut[5], bottom-2),
                                (left-2, bottom-cut[6]), (left+2, top+cut[7])])
            outline = []
            for j,p in enumerate(corners):
                following = corners[(j+1)%len(corners)]
                edge_vector = following-p
                length = np.linalg.norm(edge_vector)
                outline.append(p)
                if length > 140:
                    inward = np.array([-edge_vector[1],edge_vector[0]])/length
                    for t in (.27,.68):
                        center = p+edge_vector*t
                        size = rng.uniform(3,14)
                        outline.extend([center-edge_vector*.025,center+inward*size,
                                        center+edge_vector*.035+inward*size*.25])
            yield np.array(outline)


def carved_stone(rng, w, h, family, layout=None, palette=None):
    import numpy as np
    from scipy.ndimage import distance_transform_edt, gaussian_filter
    broad = noise(rng, w, h, 12, 8)
    brush = noise(rng, w, h, 72, 46)
    fine = noise(rng, w, h, 240, 150)
    height = np.full((h, w), .06, np.float32)
    ao = np.full((h, w), .55, np.float32)
    rough = np.full((h, w), .89, np.float32)
    color = np.empty((h, w, 3), np.float32)
    color[:] = (48, 58, 69)
    palettes = {
        "masonry": [(119,140,154),(138,153,159),(106,128,145),(129,143,151),(123,138,151),(147,153,155)],
        "flagstone": [(100,124,143),(120,140,152),(108,127,145),(132,146,151),(97,117,137)],
        "rock": [(99,118,140),(111,127,147),(126,136,153),(108,121,144),(123,131,146)],
    }
    for index, poly in enumerate(stone_polygons(rng, w, h, family, layout)):
        # Build each stone once, then wrap its patch. Border normals are
        # derived periodically below; repeating tiles have no lighting seam.
        lo = np.floor(poly.min(axis=0)-3).astype(int)
        hi = np.ceil(poly.max(axis=0)+3).astype(int)
        pw, ph = hi-lo
        mask_image = Image.new("L", (int(pw),int(ph)))
        ImageDraw.Draw(mask_image).polygon([tuple(p-lo) for p in poly], fill=255)
        inside = np.asarray(mask_image) > 0
        distance = distance_transform_edt(inside).astype(np.float32)
        yy, xx = np.mgrid[lo[1]:hi[1], lo[0]:hi[0]]
        ty, tx = yy % h, xx % w
        strokes = broad[ty, tx]
        cuts = brush[ty, tx]
        # Deep, wide hand-cut bevel; chipped boundaries have different
        # thicknesses, and the crown has broad facets instead of bumps.
        edge = np.clip((distance - (cuts-.35)*8) / (24 if family != "rock" else 30), 0, 1)
        bevel = edge * (2-edge)
        u = (xx-lo[0])/pw-.5
        v = (yy-lo[1])/ph-.5
        # Continuous intersecting planes form a low, irregular crown. Do
        # not quantize height noise: that creates topographic contour ridges.
        facets = 1-np.maximum.reduce([np.abs(u*.9+v*.25),np.abs(v*.85-u*.12),np.abs(u*.5-v*.65)])
        tilt_x, tilt_y = rng.uniform(-.065,.065,2)
        plate = (.65 + facets*.075 + (xx-lo[0])/pw*tilt_x
                 + (yy-lo[1])/ph*tilt_y + (cuts-.5)*.01 + (strokes-.5)*.018)
        face = .08 + bevel * (plate-.08)
        # A few carefully cut fractures, not a universal grunge overlay.
        incisions = Image.new("L", (int(pw),int(ph)))
        draw = ImageDraw.Draw(incisions)
        if rng.random() < .36:
            sx = rng.uniform(.2,.8)*pw
            length = rng.uniform(.22,.50)
            lean = rng.choice([-1,1])
            path = [(sx,5),(sx+pw*.06*lean,ph*length*.42),(sx-pw*.035*lean,ph*length*.7),(sx+pw*.02*lean,ph*length)]
            draw.line(path, fill=255, width=4)
            draw.line([path[2],(path[2][0]+pw*.12,path[2][1]+ph*.045)],fill=190,width=3)
        if family == "flagstone" and index == 3:
            # A modest incised mason's mark, catching light in its grooves.
            cx, cy = pw*.52, ph*.48
            r = min(pw,ph)*.14
            draw.line([(cx-r,cy),(cx,cy-r),(cx+r,cy),(cx,cy+r),(cx-r,cy)],fill=255,width=5)
            draw.line([(cx,cy-r*1.65),(cx,cy+r*1.65)],fill=255,width=4)
        groove = gaussian_filter(np.asarray(incisions,dtype=np.float32)/255,.85)
        face -= groove*.13
        # Edge paint is neutral wear, with no baked directional highlights.
        choices = palette or palettes[family]
        body = np.array(choices[int(rng.integers(len(choices)))],np.float32)
        tone = 1 + (np.round(cuts*7)/7-.5)*.10 + (fine[ty,tx]-.5)*.018
        patch_color = body[None,None,:]*tone[...,None]
        edge_paint = np.maximum(0,1-abs(distance-12)/13)*.20
        patch_color = patch_color*(1-edge_paint[...,None]) + np.array([181,187,184])*edge_paint[...,None]
        patch_color *= (1-groove*.19)[...,None]
        stone_ao = np.clip(.62+bevel*.38-groove*.25,0,1)
        stone_rough = np.clip(.68 + cuts*.15 - edge_paint*.65 + groove*.15,.36,.95)
        for dy in (-h,0,h):
            for dx in (-w,0,w):
                x0, y0 = max(0,lo[0]+dx), max(0,lo[1]+dy)
                x1, y1 = min(w,hi[0]+dx), min(h,hi[1]+dy)
                if x1 <= x0 or y1 <= y0: continue
                s = np.s_[y0-lo[1]-dy:y1-lo[1]-dy,x0-lo[0]-dx:x1-lo[0]-dx]
                m = inside[s]
                dest = np.s_[y0:y1,x0:x1]
                height[dest][m] = face[s][m]
                color[dest][m] = patch_color[s][m]
                ao[dest][m] = stone_ao[s][m]
                rough[dest][m] = stone_rough[s][m]
    # The height field is a chiseled model. A small periodic filter softens
    # pixel stair-steps without flattening its actual cuts and facets.
    height = gaussian_filter(height,1.15,mode="wrap")
    return color, height, ao, rough, .12 if family == "rock" else .095


def carved_wood(rng,w,h):
    import numpy as np
    from scipy.ndimage import gaussian_filter
    y,x = np.mgrid[:h,:w].astype(np.float32)
    u,v = x/w,y/h
    broad = noise(rng,w,h,7,11)
    brush = noise(rng,w,h,76,38)
    boards = 6
    plank = np.floor(u*boards).astype(int)
    edge_dist = np.minimum((u*boards)%1,1-(u*boards)%1)*w/boards
    bevel = np.clip(edge_dist/14,0,1)
    warp = np.sin(v*np.pi*2)*.035 + np.sin(v*np.pi*6+plank*1.7)*.008
    phase = (u+warp)*53*2*np.pi + np.sin(v*np.pi*4)*1.1
    grain = (.5+.5*np.sin(phase + np.sin(u*np.pi*12+v*np.pi*2)*.8))
    groove = np.maximum(0,(grain-.77)/.23)**1.5
    # Paired elliptical knots bend and interrupt the long carved ribbons.
    knot = np.zeros((h,w),np.float32)
    for cx,cy in [(.09,.33),(.42,.71),(.76,.19)]:
        dx = ((u-cx+.5)%1-.5)/.036
        dy = ((v-cy+.5)%1-.5)/.075
        d = np.sqrt(dx*dx+dy*dy)
        envelope = np.exp(-d*d*.4)
        knot += (.5+.5*np.sin(d*14))*envelope
    height = (.12 + bevel*(.55 - groove*.055 - knot*.08 + (broad-.5)*.05))
    ao = np.clip(.63+bevel*.37-groove*.07-knot*.15,0,1)
    rough = np.clip(.60+(1-groove)*.14 + (brush-.5)*.1-knot*.05,.35,.9)
    palette = np.array([(130,85,55),(144,97,64),(116,77,55),(151,103,65),(127,83,56),(139,91,57)],np.float32)
    color = palette[plank]*(.91+np.round(grain*6)/6*.13+(brush-.5)*.07)[...,None]
    color *= (1-groove*.16-knot*.22)[...,None]
    color = color*bevel[...,None] + np.array([48,37,35])*(1-bevel[...,None])
    return color,gaussian_filter(height,.9,mode="wrap"),ao,rough,.045


def forged_metal(rng,w,h):
    import numpy as np
    from scipy.ndimage import gaussian_filter
    hammer = noise(rng,w,h,27,27)
    brush = noise(rng,w,h,90,50)
    height = .5+hammer*.17+(brush-.5)*.012
    # Painterly blue steel: broad hammer dents, polished raised crowns.
    raised = np.clip((hammer-.48)*2,0,1)
    base = np.array([150,169,181],np.float32)
    color = base*(.88+np.round(hammer*7)/7*.17)[...,None]
    rough = np.clip(.47-raised*.24+(brush-.5)*.06,.22,.57)
    ao = np.clip(.91+hammer*.09,0,1)
    return color,gaussian_filter(height,1.0,mode="wrap"),ao,rough,.028


def normal_from_height(height,physical_size,depth):
    import numpy as np
    gx = (np.roll(height,-1,axis=1)-np.roll(height,1,axis=1))*.5*height.shape[1]/physical_size[0]*depth
    gy = (np.roll(height,-1,axis=0)-np.roll(height,1,axis=0))*.5*height.shape[0]/physical_size[1]*depth
    normal = np.stack([-gx,-gy,np.ones_like(height)],axis=-1)
    normal /= np.linalg.norm(normal,axis=2,keepdims=True)
    return normal


def resized(image,size):
    return image.resize(size,Image.Resampling.LANCZOS)


def imports(path,is_normal=False):
    # Godot fills its generated remap/deps sections on import. These source
    # settings ensure both desktop BC and Android ETC2 have mips and linear
    # normals/ORMH. Height is alpha; do not strip it as unused transparency.
    (path.parent/(path.name+".import")).write_text(
        '[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n'
        'compress/mode=2\ncompress/high_quality=false\n'
        f'compress/normal_map={1 if is_normal else 0}\n'
        'mipmaps/generate=true\nprocess/size_limit=2048\n'
        'process/normal_map_invert_y=false\n',encoding="utf8")


def bake():
    import numpy as np
    OUTPUT.mkdir(parents=True,exist_ok=True)
    manifest = {"schema":1,"style":"carved storybook","seed":SEED,
                "source":"Original deterministic Emberkeep artwork; no scanned inputs",
                "rights":"Original Emberkeep artwork; no third-party source images", "channels":"ORMH: occlusion, roughness, metallic, height",
                "families":{}}
    for index,family in enumerate(FAMILIES):
        rng = np.random.default_rng(SEED+index*97)
        w,h = 2048,1024 if family in ("masonry","flagstone") else 2048
        if family == "wood": result = carved_wood(rng,w,h)
        elif family == "metal": result = forged_metal(rng,w,h)
        else: result = carved_stone(rng,w,h,family)
        color,height,ao,rough,depth = result
        target = OUTPUT/family
        target.mkdir(exist_ok=True)
        rgb = Image.fromarray(np.uint8(np.clip(color,0,255)))
        normal = normal_from_height(height,(4,2 if h != w else 4),depth)
        normal_image = Image.fromarray(np.uint8(np.clip((normal+1)*127.5,0,255)))
        rgb.save(target/"color.jpg",quality=95,subsampling=0,optimize=True)
        normal_image.save(target/"normal.jpg",quality=97,subsampling=0,optimize=True)
        mobile_size = (1024,h//2)
        resized(rgb,mobile_size).save(target/"color_mobile.jpg",quality=95,subsampling=0,optimize=True)
        averaged = np.asarray(resized(normal_image,mobile_size),np.float32)/127.5-1
        averaged /= np.maximum(np.linalg.norm(averaged,axis=2,keepdims=True),1e-5)
        Image.fromarray(np.uint8(np.clip((averaged+1)*127.5,0,255))).save(
            target/"normal_mobile.jpg",quality=97,subsampling=0,optimize=True)
        channels = [ao,rough,np.full_like(ao,.82 if family == "metal" else 0),height]
        rgba = [resized(Image.fromarray(np.uint8(np.clip(c*255,0,255))),mobile_size) for c in channels]
        Image.merge("RGBA",rgba).save(target/"ormh.png",optimize=True)
        outputs = {}
        for filename in FILES:
            path = target/filename
            if not (path.parent/(path.name+".import")).exists(): imports(path,"normal" in filename)
            with Image.open(path) as image:
                outputs[filename] = {"sha256":digest(path),"bytes":path.stat().st_size,"size":list(image.size)}
        manifest["families"][family] = {"relief_metres":depth,"outputs":outputs}
        print(f"Baked {family}: {w}x{h}, {sum(v['bytes'] for v in outputs.values())/1048576:.2f} MiB")
    (OUTPUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf8")


def check():
    manifest = json.loads((OUTPUT/"manifest.json").read_text(encoding="utf8"))
    assert manifest["seed"] == SEED and list(manifest["families"]) == list(FAMILIES)
    total = 0
    for family in FAMILIES:
        outputs = manifest["families"][family]["outputs"]
        assert set(outputs) == set(FILES)
        for filename,record in outputs.items():
            path = OUTPUT/family/filename
            assert digest(path) == record["sha256"], str(path)+": artwork hash mismatch"
            width = 2048 if filename in ("color.jpg","normal.jpg") else 1024
            expected = (width,width//2 if family in ("masonry","flagstone") else width)
            with Image.open(path) as image:
                image.load()
                assert image.size == expected == tuple(record["size"]), str(path)+": wrong resolution"
                if filename == "ormh.png":
                    assert image.mode == "RGBA", "height alpha must survive packing"
                    ranges = [channel.getextrema() for channel in image.split()]
                    assert ranges[0][1]-ranges[0][0] >= 8, "authored cavity occlusion required"
                    assert ranges[1][1]-ranges[1][0] >= 20, "roughness must vary across the cuts"
                    assert ranges[3][1]-ranges[3][0] >= 30, "real height variation required"
            assert path.stat().st_size == record["bytes"]
            total += path.stat().st_size
    assert total < 16*1048576, "stylized source asset budget exceeded"
    print(f"STYLIZED MATERIALS: 25 original maps, verified hashes/channels/dimensions; {total/1048576:.2f} MiB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check",action="store_true",help="Verify committed artwork offline (Pillow only)")
    args = parser.parse_args()
    if not args.check: bake()
    check()
