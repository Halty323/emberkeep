#!/usr/bin/env python3
"""Original themed architecture, sharing the carved-material lighting pipeline.

Each floor has independently authored wall and ground forms. Color, tangent
normal, cavities, roughness and relief describe the same periodic surface.
No downloads, photographs or runtime generation. --check needs only Pillow.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

import bake_stylized_materials as base

ROOT = base.OUTPUT / "themes"
THEMES = ("cellar", "cistern", "halls", "crypt", "archive", "kiln", "belfry", "hearth")
SEED = 73109
DESCRIPTIONS = {
    "cellar": ("warm rubble walls", "packed earth with embedded stone chips"),
    "cistern": ("long water-worn courses", "rounded river cobbles"),
    "halls": ("split overgrown stone", "large broken flagstones"),
    "crypt": ("weathered memorial blocks with sparse inscriptions", "incised burial slabs"),
    "archive": ("pale tall ashlar", "silvered timber boards"),
    "kiln": ("small soot-darkened firebricks", "fractured charcoal basalt"),
    "belfry": ("riveted hammered iron panels", "timber with brass inlay"),
    "hearth": ("warm plaster and exposed timber", "terracotta paving"),
}


def earth(rng, w, h):
    import numpy as np
    from scipy.ndimage import gaussian_filter
    broad = base.noise(rng, w, h, 11, 6)
    brush = base.noise(rng, w, h, 94, 47)
    height = .37 + broad * .15 + brush * .018
    color = np.array([111, 91, 64], np.float32) * (.81 + broad[..., None] * .31)
    chips = Image.new("L", (w, h))
    draw = ImageDraw.Draw(chips)
    for _ in range(105):
        x, y = rng.integers(40, w - 40), rng.integers(40, h - 40)
        r = rng.uniform(6, 22)
        draw.polygon([(x-r,y), (x-r*.3,y-r*.55), (x+r,y-r*.2),
                      (x+r*.45,y+r*.7), (x-r*.5,y+r*.5)], fill=255)
    mask = gaussian_filter(np.asarray(chips, np.float32) / 255, 1.3)
    height += mask * .12
    color = color * (1 - mask[..., None] * .65) + np.array([111, 111, 98]) * mask[..., None] * .65
    ao = np.clip(.72 + broad * .25 - mask * .06, 0, 1)
    rough = np.clip(.78 + brush * .18 - mask * .10, 0, 1)
    return color, height, ao, rough, .055


def plaster(rng, w, h):
    import numpy as np
    from scipy.ndimage import gaussian_filter
    y, x = np.mgrid[:h, :w].astype(np.float32)
    brush = base.noise(rng, w, h, 68, 34)
    broad = base.noise(rng, w, h, 9, 5)
    u, v = x / w, y / h
    distance = np.minimum(np.minimum(u, 1-u) * w, np.minimum(v, 1-v) * h)
    timber = np.clip((34-distance)/7, 0, 1)
    grain = .5 + .5 * np.sin(v * 100 + np.sin(u*40)*2)
    height = .40 + broad*.05 + brush*.012 + timber*(.26+grain*.022)
    color = np.array([191,177,145])*(.91+broad[...,None]*.12)
    wood = np.array([102,73,45])*(.87+grain[...,None]*.21)
    color = color*(1-timber[...,None])+wood*timber[...,None]
    rough = np.clip(.74+brush*.17-timber*.16,0,1)
    ao = np.clip(.98-timber*.08-np.exp(-((distance-37)/8)**2)*.21,0,1)
    return color, gaussian_filter(height,1,mode="wrap"), ao, rough, .11


def ornament(result, theme, surface):
    import numpy as np
    from scipy.ndimage import gaussian_filter
    color, height, ao, rough, depth = result
    h, w = height.shape
    marks = Image.new("L", (w,h))
    draw = ImageDraw.Draw(marks)
    if theme == "crypt" and surface == "floor":
        # These cuts have matching physical depth, not painted-on highlights.
        rows, cols = (3,3) if surface == "wall" else (2,2)
        for row in range(rows):
            for col in range(cols):
                cx = (col+.5)*w/cols+(row%2)*w*.127
                cy = (row+.5)*h/rows
                radius = h/rows*.19
                for shift in [-w,0,w]:
                    draw.line([(cx+shift-radius,cy),(cx+shift,cy-radius),
                               (cx+shift+radius,cy),(cx+shift,cy+radius),
                               (cx+shift-radius,cy)], fill=255,width=7)
    elif theme == "belfry":
        if surface == "wall":
            for x in [w*.05,w*.48,w*.55,w*.98]:
                for y in [h*.09,h*.48,h*.59,h*.98]:
                    draw.ellipse((x-11,y-11,x+11,y+11),fill=255)
        else:
            for x in [w*.17,w*.50,w*.83]:
                draw.line([(x,0),(x,h)],fill=255,width=11)
    mask = gaussian_filter(np.asarray(marks,np.float32)/255,1.1,mode="wrap")
    metal = np.full_like(height,.65 if theme == "belfry" and surface == "wall" else 0)
    if theme == "belfry":
        height += mask*.09
        color = color*(1-mask[...,None]*.85)+np.array([165,130,65])*mask[...,None]*.85
        rough = rough*(1-mask)+mask*.34
        metal = np.maximum(metal,mask*.75)
    elif theme == "crypt":
        height -= mask*.11
        color *= (1-mask[...,None]*.22)
        ao *= (1-mask*.20)
    return color,height,ao,rough,depth,metal


def surface(rng,w,h,theme,kind):
    import numpy as np
    stone = base.carved_stone
    if theme == "cellar":
        result = earth(rng,w,h) if kind == "floor" else stone(rng,w,h,"rock",palette=[(141,129,104),(125,119,104),(153,137,111),(127,128,111)])
    elif theme == "cistern":
        result = stone(rng,w,h,"rock" if kind == "floor" else "masonry",(2,4),[(103,128,128),(126,144,139),(106,128,137),(121,139,138)])
    elif theme == "halls":
        result = stone(rng,w,h,"flagstone" if kind == "floor" else "rock",(2,3),[(133,140,119),(117,127,112),(146,149,124),(128,137,116)])
    elif theme == "crypt":
        result = stone(rng,w,h,"flagstone" if kind == "floor" else "masonry",(2,2) if kind == "floor" else (3,3),[(141,132,141),(153,145,147),(129,127,139),(149,142,137)])
    elif theme == "archive":
        result = base.carved_wood(rng,w,h) if kind == "floor" else stone(rng,w,h,"masonry",(3,2),[(174,183,183),(158,173,180),(182,188,182),(164,177,183)])
        if kind == "floor":
            c,he,ao,ro,de = result
            result = (c*.43+np.array([102,116,124]),he,ao,np.minimum(ro+.07,.96),de)
    elif theme == "kiln":
        result = stone(rng,w,h,"rock" if kind == "floor" else "masonry",(8,6),[(139,88,64),(161,101,68),(119,79,64),(148,95,73)] if kind == "wall" else [(73,74,72),(87,82,76),(77,76,73),(94,86,78)])
    elif theme == "belfry":
        result = base.forged_metal(rng,w,h) if kind == "wall" else base.carved_wood(rng,w,h)
        if kind == "wall":
            c,he,ao,ro,de = result
            y,x = np.mgrid[:h,:w]
            distance = np.minimum(x%(w//2),(w//2)-x%(w//2))
            distance = np.minimum(distance,np.minimum(y%(h//2),(h//2)-y%(h//2)))
            edge = np.clip(distance/11,0,1)
            result = (c*(.55+edge[...,None]*.35),he*edge,ao*(.6+edge*.4),np.clip(ro+.12,0,1),.065)
    else:
        result = plaster(rng,w,h) if kind == "wall" else stone(rng,w,h,"flagstone",(4,8),[(171,119,83),(186,133,92),(166,112,78),(194,141,100)])
    return ornament(result,theme,kind)


def weather_wall(rng, theme, result):
    """Seeded layered erosion, mineral flecks and rare, physically cut marks.

    Color, cavity, roughness and normal relief all describe the same surface.
    Broad facets and soft brush marks retain a stylized hand-carved look.
    """
    import numpy as np
    from scipy.ndimage import gaussian_filter
    color, height, ao, rough, depth, metal = result
    h, w = height.shape
    cloud = base.noise(rng,w,h,17,9)
    strata = base.noise(rng,w,h,74,27)
    grain = base.noise(rng,w,h,320,170)
    pores = np.maximum(0.0, (.34-grain)*3.2)
    face = np.clip((height-.16)/.24,0,1)
    # Different wear belongs to each material, rather than one grunge stamp.
    strength = {"cellar":.10,"cistern":.065,"halls":.085,"crypt":.075,
                "archive":.045,"kiln":.095,"belfry":.04,"hearth":.055}[theme]
    ridges = (strata-.5)*strength + (cloud-.5)*strength*.7
    chips = gaussian_filter(pores, .65, mode="wrap")
    height += face*(ridges-chips*strength*.9 + (grain-.5)*.018)
    color *= (1 + face*((cloud-.5)*.26 + (strata-.5)*.12 - chips*.30))[...,None]
    mineral = np.array({"cellar":[.10,.05,-.04],"cistern":[-.06,.07,.05],
                       "halls":[-.03,.08,-.03],"crypt":[.04,.02,.06],
                       "archive":[.02,.05,.08],"kiln":[.11,-.02,-.08],
                       "belfry":[.10,.015,-.09],"hearth":[.07,.035,-.02]}[theme])
    color *= 1 + (cloud[...,None]-.5)*mineral
    ao = np.clip(ao-face*chips*.22,0,1)
    rough = np.clip(rough+face*((strata-.5)*.19+chips*.16),.28,.98)
    # One small memorial/tool mark per 4x2m sheet, with several shapes.
    # All other bricks carry material wear, never a mandatory center stamp.
    marks = Image.new("L",(w,h))
    draw = ImageDraw.Draw(marks)
    cx,cy = int(w*.51),int(h*.49)
    for _ in range(24):
        x,y = int(rng.integers(w*.14,w*.86)),int(rng.integers(h*.16,h*.84))
        if face[y,x] > .9: cx,cy = x,y; break
    r = 32
    motif = list(THEMES).index(theme) % 4
    if motif == 0:
        for x in [-18,0,18]: draw.line([(cx+x,cy-21),(cx+x-5,cy+20)],fill=210,width=3)
        draw.line([(cx-27,cy+12),(cx+28,cy-13)],fill=190,width=3)
    elif motif == 1:
        draw.arc((cx-r,cy-r,cx+r,cy+r),35,285,fill=200,width=3)
        draw.line([(cx-12,cy+14),(cx+20,cy-17)],fill=180,width=3)
    elif motif == 2:
        draw.line([(cx-24,cy+16),(cx-3,cy-23),(cx+21,cy+16)],fill=190,width=3)
        draw.line([(cx-13,cy+3),(cx+11,cy+3)],fill=200,width=3)
    else:
        for row in [-14,0,14]:
            draw.line([(cx-28,cy+row),(cx+int(rng.integers(8,30)),cy+row-2)],fill=190,width=3)
        draw.line([(cx-17,cy-23),(cx-17,cy+23)],fill=170,width=3)
    cut = gaussian_filter(np.asarray(marks,np.float32)/255,.85,mode="wrap")*face
    height -= cut*.07
    color *= (1-cut*.18)[...,None]
    ao *= 1-cut*.18
    rough = np.clip(rough+cut*.08,0,1)
    return color,height,ao,rough,depth,metal


def bake(walls_only=False):
    import numpy as np
    ROOT.mkdir(parents=True,exist_ok=True)
    manifest = json.loads((ROOT/"manifest.json").read_text()) if walls_only else {"schema":1,"seed":SEED,"source":"Original deterministic Emberkeep themed artwork",
                "channels":"ORMH: occlusion, roughness, metallic, height","themes":{}}
    for i,theme in enumerate(THEMES):
        manifest["themes"].setdefault(theme, {})
        for j,kind in enumerate(("wall","floor")):
            if walls_only and kind != "wall": continue
            rng = np.random.default_rng(SEED+i*211+j*89)
            color,height,ao,rough,depth,metal = surface(rng,2048,1024,theme,kind)
            if kind == "wall":
                color,height,ao,rough,depth,metal = weather_wall(rng,theme,(color,height,ao,rough,depth,metal))
            target = ROOT/theme/kind
            target.mkdir(parents=True,exist_ok=True)
            rgb = Image.fromarray(np.uint8(np.clip(color,0,255)))
            normal = base.normal_from_height(height,(4,2),depth)
            normal_image = Image.fromarray(np.uint8(np.clip((normal+1)*127.5,0,255)))
            rgb.save(target/"color.jpg",quality=95,subsampling=0,optimize=True)
            normal_image.save(target/"normal.jpg",quality=97,subsampling=0,optimize=True)
            mobile_size = (1024,512)
            base.resized(rgb,mobile_size).save(target/"color_mobile.jpg",quality=95,subsampling=0,optimize=True)
            averaged = np.asarray(base.resized(normal_image,mobile_size),np.float32)/127.5-1
            averaged /= np.maximum(np.linalg.norm(averaged,axis=2,keepdims=True),1e-5)
            Image.fromarray(np.uint8(np.clip((averaged+1)*127.5,0,255))).save(target/"normal_mobile.jpg",quality=97,subsampling=0,optimize=True)
            channels = [base.resized(Image.fromarray(np.uint8(np.clip(c*255,0,255))),mobile_size) for c in [ao,rough,metal,height]]
            Image.merge("RGBA",channels).save(target/"ormh.png",optimize=True)
            outputs = {}
            for filename in base.FILES:
                path = target/filename
                if not path.with_name(path.name+".import").exists(): base.imports(path,"normal" in filename)
                with Image.open(path) as image:
                    outputs[filename] = {"sha256":base.digest(path),"bytes":path.stat().st_size,"size":list(image.size)}
            manifest["themes"][theme][kind] = {"description":DESCRIPTIONS[theme][j],"relief_metres":depth,"outputs":outputs}
            if kind == "wall":
                manifest["themes"][theme][kind]["weathering_version"] = 2
                manifest["themes"][theme][kind]["inscriptions_per_sheet"] = 1
            print("Baked",theme,kind,flush=True)
    (ROOT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")


def check():
    manifest = json.loads((ROOT/"manifest.json").read_text())
    assert manifest["seed"] == SEED and list(manifest["themes"]) == list(THEMES)
    unique = {"wall":set(),"floor":set()}
    total = 0
    for theme in THEMES:
        for kind in unique:
            record = manifest["themes"][theme][kind]
            if kind == "wall":
                assert record.get("weathering_version") == 2
                assert record.get("inscriptions_per_sheet", 99) <= 1
            records = record["outputs"]
            assert set(records) == set(base.FILES)
            for filename,record in records.items():
                path = ROOT/theme/kind/filename
                assert base.digest(path) == record["sha256"], str(path)+": hash mismatch"
                width = 2048 if filename in ("color.jpg","normal.jpg") else 1024
                with Image.open(path) as image:
                    image.load()
                    assert image.size == (width,width//2) == tuple(record["size"])
                    if filename == "ormh.png":
                        assert image.mode == "RGBA"
                        extrema = [channel.getextrema() for channel in image.split()]
                        assert extrema[0][1]-extrema[0][0]>=8
                        assert extrema[1][1]-extrema[1][0]>=20
                        assert extrema[3][1]-extrema[3][0]>=30
                assert path.stat().st_size == record["bytes"]
                total += record["bytes"]
            unique[kind].add(records["color.jpg"]["sha256"])
    assert all(len(hashes)==8 for hashes in unique.values()), "each theme needs independently authored forms"
    assert total < 48*1048576, "themed source asset budget exceeded"
    print(f"THEMED MATERIALS: 16 distinct surfaces / 80 maps, verified; {total/1048576:.2f} MiB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check",action="store_true")
    parser.add_argument("--walls-only",action="store_true",help="Rebake walls while preserving all floor image bytes")
    args = parser.parse_args()
    if not args.check: bake(args.walls_only)
    check()
