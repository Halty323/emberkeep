class_name DungeonTextures
extends RefCounted
## Small painted material sheets: block variation, chipped lips, soot and
## moisture are baked once. Runtime lighting supplies the moving highlights.
static var walls: Dictionary = {}
const SIZE := 256

static func wall(family: String) -> Dictionary:
	if family not in ["cellar", "cistern", "halls", "crypt", "archive", "kiln", "belfry", "hearth", "masonry", "dressed"]: family = "masonry"
	if walls.has(family): return walls[family]
	var paint_path = "res://assets/materials/wall_%s_paint.png" % family
	var normal_path = "res://assets/materials/wall_%s_normal.png" % family
	if OS.get_environment("EMBERKEEP_BAKE_MATERIALS") != "1" and ResourceLoader.exists(paint_path) and ResourceLoader.exists(normal_path):
		walls[family] = {"paint": load(paint_path), "normal": load(normal_path)}
		return walls[family]
	var paint = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var bump = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var noise = FastNoiseLite.new()
	noise.seed = 317
	noise.frequency = .035
	var rows = 4 if family != "kiln" else 8
	var columns = 3 if family not in ["archive", "hearth"] else 2
	for y in SIZE:
		var row = y * rows / SIZE
		var h = float(SIZE) / rows
		var fy = fposmod(y, h)
		for x in SIZE:
			var w = float(SIZE) / columns
			var shifted = fposmod(x + (w * .5 if row % 2 else 0.0), SIZE)
			var column = floori(shifted / w)
			var fx = fposmod(shifted, w)
			var grain = noise.get_noise_2d(x,y) * .5 + .5
			var slow = noise.get_noise_2d(x * .35 + 500,y * .35) * .5 + .5
			var seed_value = float(column + row * 11)
			var tone = .79 + .19 * fposmod(sin(seed_value * 17.1) * 417.31, 1.0)
			var edge = minf(minf(fx,w-fx),minf(fy,h-fy))
			var bevel = smoothstep(.7 + grain * .6, 3.8 + grain, edge)
			var lip = maxf(0, 1.0 - absf(fy - 4.8) / 2.2) * .075
			var brush = .87 + .16 * grain + .08 * slow
			var stain = smoothstep(.42,.82,slow) * .16
			var color = Color(1.0,.98,.92) * (tone * brush * lerpf(.32,1.0,bevel) + lip - stain)
			if family == "cistern":
				var tide = .12 * smoothstep(.15,.8,slow) * (.5+.5*sin(y*.025))
				color = color.lerp(Color(.35,.48,.42),tide)
			elif family == "halls":
				color = color.lerp(Color(.38,.46,.25),smoothstep(.55,.83,slow) * .22)
			elif family == "kiln":
				color = color.lerp(Color(.53,.32,.21),.22 + slow*.14)
			elif family == "archive":
				color = color.lerp(Color(.77,.85,.88),.12)
				var scratch = absf(fposmod(fx + fy*.45,61.0)-30.0)
				if scratch < .45 and edge > 9: color *= .86
			elif family == "crypt":
				# A shallow diamond tracery, cut into selected memorial stones.
				var diamond = absf(absf(fx-w/2) + absf(fy-h/2) - h*.31)
				if posmod(column * 73 + row * 151 + 19, 17) == 0 and diamond < 1.0: color *= .76
			elif family == "belfry":
				if (absf(fx-7)<1.0 or absf(fx-w+7)<1.0) and absf(fy-h/2)<1.3: color = Color(.65,.52,.31)
			elif family == "hearth":
				color = color.lerp(Color(.93,.81,.61),.14)
			paint.set_pixel(x,y,Color(clampf(color.r,0,1),clampf(color.g,0,1),clampf(color.b,0,1)))
			var relief = bevel * (.92 + grain*.08)
			bump.set_pixel(x,y,Color(relief,relief,relief))
	paint.generate_mipmaps()
	bump.bump_map_to_normal_map(1.2)
	bump.generate_mipmaps()
	walls[family] = {"paint": ImageTexture.create_from_image(paint), "normal": ImageTexture.create_from_image(bump)}
	return walls[family]

static var aging_texture: Texture2D
static func aging() -> Texture2D:
	if aging_texture: return aging_texture
	if OS.get_environment("EMBERKEEP_BAKE_MATERIALS") != "1" and ResourceLoader.exists("res://assets/materials/aging.png"):
		aging_texture = load("res://assets/materials/aging.png")
		return aging_texture
	var image = Image.create(64,64,false,Image.FORMAT_RGB8)
	var noise = FastNoiseLite.new()
	noise.seed = 916
	noise.frequency = .085
	for y in 64:
		for x in 64:
			var brush = noise.get_noise_2d(x,y) * .5 + .5
			var value = .88 + brush * .12
			image.set_pixel(x,y,Color(value,value,value))
	image.generate_mipmaps()
	aging_texture = ImageTexture.create_from_image(image)
	return aging_texture

# Historical original-sheet authoring path, unused by current gameplay.
static var legacy_floors: Dictionary = {}
static func legacy_floor(kind: int) -> Dictionary:
	if legacy_floors.has(kind): return legacy_floors[kind]
	var paint_path = "res://assets/materials/floor_%d_paint.png" % kind
	var normal_path = "res://assets/materials/floor_%d_normal.png" % kind
	if OS.get_environment("EMBERKEEP_BAKE_MATERIALS") != "1" and ResourceLoader.exists(paint_path) and ResourceLoader.exists(normal_path):
		legacy_floors[kind] = {"paint": load(paint_path), "normal": load(normal_path)}
		return legacy_floors[kind]
	const SIZE := 256
	var paint = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var height = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var noise = FastNoiseLite.new()
	noise.seed = 417 + kind
	noise.frequency = .085
	for y in SIZE:
		for x in SIZE:
			var row = y / 64
			var shifted = posmod(x + (32 if row % 2 else 0), SIZE)
			var edge = minf(minf(shifted % 64, 63 - shifted % 64), minf(y % 64, 63 - y % 64))
			var grain = noise.get_noise_2d(x, y) * .5 + .5
			var id = (shifted / 64) + row * 7
			var tone = .82 + .18 * fposmod(sin(float(id) * 17.31) * 431.7, 1.0)
			var bevel = smoothstep(.8 + grain * .7, 3.4, edge)
			if kind == 1:
				bevel = .66 + .34 * smoothstep(.2, .75, grain)
			elif kind == 2:
				bevel = .7 + .3 * grain
			# Light brushwork at the lip and pooled dirt in the joint.
			var value = tone * (.9 + grain * .16) * lerpf(.38, 1.0, bevel)
			var lip = maxf(0, 1.0 - absf(edge - 5.5) / 2.0) * .08 if kind == 0 else 0.0
			paint.set_pixel(x, y, Color(clampf(value + lip, 0, 1), 1.0 - bevel, fposmod(id * .317, 1.0) if kind == 0 else grain, .72 + .25 * (1.0 - bevel)))
			height.set_pixel(x, y, Color(bevel * (.8 + grain * .2), bevel * (.8 + grain * .2), bevel * (.8 + grain * .2)))
	paint.generate_mipmaps()
	height.bump_map_to_normal_map(2.0)
	height.generate_mipmaps()
	legacy_floors[kind] = {"paint": ImageTexture.create_from_image(paint), "normal": ImageTexture.create_from_image(height)}
	return legacy_floors[kind]
