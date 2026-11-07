## The fixed pool of 12 races (docs/GAME_DESIGN.md § 8): base colours and visual traits.
## Same data as the 2D sprites in art/sprites.py; each world varies them later.
extends RefCounted

const ROLES := ["Villager", "Warrior", "Chief", "Shaman"]

## skin, hair, clothes, legs, banner (shield / cape), magic (staff orb), traits
const RACES := {
	"Humans": {"skin": "#f0c39b", "hair": "#6b4423", "clothes": "#4a86d0", "legs": "#5a3a1e",
			"banner": "#d85a4a", "magic": "#8fd8ff", "traits": []},
	"Elves": {"skin": "#f3cfa8", "hair": "#f0d264", "clothes": "#5aae55", "legs": "#2c6e35",
			"banner": "#9ad65a", "magic": "#9ad65a", "traits": ["ears"]},
	"Dwarves": {"skin": "#d49a6a", "hair": "#e8823a", "clothes": "#c8503e", "legs": "#5a3a1e",
			"banner": "#e8a923", "magic": "#f08a2a", "traits": ["short", "beard"]},
	"Orcs": {"skin": "#6fae55", "hair": "#2a2a30", "clothes": "#8b5a2b", "legs": "#5a3a1e",
			"banner": "#8c2323", "magic": "#d83a3a", "traits": ["tusks"]},
	"Goblins": {"skin": "#a6d46a", "hair": "#55663a", "clothes": "#c4a65a", "legs": "#5a3a1e",
			"banner": "#f0d264", "magic": "#9ad65a", "traits": ["short", "big_ears"]},
	"Lizardfolk": {"skin": "#4dbfb0", "hair": "#2a7d72", "clothes": "#c9b458", "legs": "#4dbfb0",
			"banner": "#f08a2a", "magic": "#f0d264", "traits": ["crest", "tail"]},
	"Felines": {"skin": "#f0a050", "hair": "#f0a050", "clothes": "#9b59c6", "legs": "#f0a050",
			"banner": "#f0d264", "magic": "#f49ac1", "traits": ["cat_ears", "tail"]},
	"Merfolk": {"skin": "#8fd8ff", "hair": "#3b8fe0", "clothes": "#4dbfb0", "legs": "#8fd8ff",
			"banner": "#3b8fe0", "magic": "#8fd8ff", "traits": ["fins"]},
	"Treefolk": {"skin": "#9a6a3a", "hair": "#5aae55", "clothes": "#3f7a3f", "legs": "#5a3a1e",
			"banner": "#9ad65a", "magic": "#9ad65a", "traits": ["foliage"]},
	"Fairies": {"skin": "#f8c8d8", "hair": "#b07ad0", "clothes": "#a8e0f8", "legs": "#f8c8d8",
			"banner": "#f49ac1", "magic": "#fff0a0", "traits": ["short", "wings"]},
	"Bullfolk": {"skin": "#b07a50", "hair": "#5a3a1e", "clothes": "#a03a32", "legs": "#5a3a1e",
			"banner": "#f08a2a", "magic": "#d83a3a", "traits": ["horns"]},
	"Undead": {"skin": "#e8e0c8", "hair": "#3d3d4a", "clothes": "#5e3a7a", "legs": "#3d3d4a",
			"banner": "#4f2470", "magic": "#b07ad0", "traits": ["sockets"]},
}
