## The game's 2D sprites (assets/sprites/, cut from the reference sheets by art/extract_sprites.py)
## and how they stand in the 3D world: as upright quads facing the fixed camera, base on the ground.
extends RefCounted

const PixelCamera = preload("res://scripts/ui/pixel_camera.gd")

const ROOT := "res://assets/sprites"

## World units (tiles) per sprite pixel, by group: sets how big each kind of sprite stands.
const SCALE := {
	"trees": 0.03,
	"plants": 0.0275,
	"peoples": 0.028,
	"races": 0.028,
	"animals": 0.022,
	"monsters": 0.03,
	# Drawn at display size by art/creatures.py: one sprite pixel = one world pixel (1/8 tile).
	"creatures": 0.125,
	# Drawn at display size by art/buildings.py.
	"buildings": 0.125,
}
## Size overrides for single sprites (multiplies the group scale).
const SIZE := {
	"plants/Grass": 0.8,
	"plants/Flowers": 0.8,
	"plants/Boulder": 1.4,
	# Mushrooms stay smaller than the peoples who will walk among them.
	"plants/Red_mushroom": 0.5,
	"plants/Pink_mushroom": 0.5,
	"plants/Purple_mushroom": 0.5,
	"monsters/Dragon": 1.6,
	"monsters/Golem": 1.3,
	"monsters/Yeti": 1.25,
	"animals/Horse": 1.15,
	"animals/Bear": 1.2,
}

static var _textures := {}
static var _meshes := {}


## Sprite id is "<group>/<Name>", e.g. "trees/Oak", "peoples/Elves_Warrior".
static func texture(id: String) -> Texture2D:
	if not _textures.has(id):
		_textures[id] = load("%s/%s.png" % [ROOT, id.replace(" ", "_")])
	return _textures[id]


static func exists(id: String) -> bool:
	return ResourceLoader.exists("%s/%s.png" % [ROOT, id.replace(" ", "_")])


## World size of a sprite (width, height).
static func world_size(id: String) -> Vector2:
	var t := texture(id)
	var group := id.get_slice("/", 0)
	return Vector2(t.get_width(), t.get_height()) * SCALE.get(group, 0.03) * SIZE.get(id, 1.0)


## A quad of the sprite's size with its bottom edge at the origin, facing +Z.
static func mesh(id: String) -> QuadMesh:
	if not _meshes.has(id):
		var q := QuadMesh.new()
		q.size = world_size(id)
		q.center_offset = Vector3(0.0, q.size.y / 2.0, 0.0)
		_meshes[id] = q
	return _meshes[id]


## Orientation of a standing sprite: upright (so it never leans into the slope behind it) and
## stretched vertically by 1 / cos(camera pitch), so the tilted camera sees it at its true
## proportions. `flip` mirrors it horizontally, `scale` resizes it.
static func basis(flip := false, scale := 1.0) -> Basis:
	var stretch := 1.0 / cos(deg_to_rad(PixelCamera.PITCH))
	return Basis.from_scale(Vector3(-scale if flip else scale, scale * stretch, scale))


## All sprite ids of a group, sorted.
static func list(group: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("%s/%s" % [ROOT, group])
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".png"):
			out.append("%s/%s" % [group, f.get_basename()])
	out.sort()
	return out
