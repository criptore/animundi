## Independent, named random streams derived from one world seed.
##
## Every generator asks for its own stream by name (`rng.stream("rivers")`), so adding or changing
## one generator never shifts the random numbers another one gets.
extends RefCounted

var world_seed: int


func _init(seed_value: int) -> void:
	world_seed = seed_value


## A fresh RandomNumberGenerator for `name`. Same seed and name always give the same sequence.
func stream(name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed(name)
	return rng


## A stable integer seed for `name`, for things that take a seed directly (FastNoiseLite).
func sub_seed(name: String) -> int:
	return ("%d:%s" % [world_seed, name]).hash()


## Players type seeds as text: a number is used as is, any other text is hashed.
static func seed_from_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_valid_int():
		return t.to_int()
	return t.hash()
