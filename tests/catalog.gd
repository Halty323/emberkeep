extends SceneTree
## Content catalog: every shipped family loads and validates, and the
## validators reject the broken records they exist to catch.
var checks = 0
var failures = 0
var catalog

func _initialize() -> void:
	call_deferred("test_catalog")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

## Loads deliberately broken records, captures the errors, then restores the
## shipped catalog so later checks see real data.
func rejected(family: String, records: Array, label: String) -> void:
	catalog.errors = PackedStringArray()
	catalog.ingest(family, records)
	var problems: PackedStringArray = catalog.errors
	problems.append_array(catalog.validate())
	check(not problems.is_empty(), "validator rejects " + label)
	catalog.load_catalog()

func test_catalog() -> void:
	catalog = root.get_node("Content")
	check(catalog.errors.is_empty(), "shipped catalog validates without errors: " + "; ".join(catalog.errors))
	for family in catalog.FAMILIES:
		check(not catalog.families[family].is_empty(), "family loaded: " + family)
	check(catalog.revision.length() == 8, "catalog has a pinned content revision")
	check(catalog.stable_hash("emberkeep") == catalog.stable_hash("emberkeep") and catalog.stable_hash("a") != catalog.stable_hash("b"),
		"stable hash is deterministic")
	check(catalog.stable_hash("a") == 0xe40c292c, "stable hash matches the published FNV-1a vector")
	# Room templates: 1x1, 2x1, 1x2, 2x2 and a rotatable three-cell L.
	var shapes := {}
	for template in catalog.families.rooms:
		shapes[template.cells.size()] = shapes.get(template.cells.size(), 0) + 1
		check(template.cells[0] is Vector2i, "room cells convert to typed grid coordinates: " + template.id)
	check(catalog.record("rooms", "hearth_1x1").cells == [Vector2i(0, 0)], "single-cell template exists")
	check(catalog.record("rooms", "bend_l3").rotations == [0, 1, 2, 3], "L template allows every rotation")
	check(shapes.get(2, 0) >= 2 and shapes.get(4, 0) >= 1 and shapes.get(3, 0) >= 1, "multi-cell footprints are present")
	var good: Dictionary = {"id": "x", "cells": [[0, 0]], "rotations": [0], "roles": ["combat"], "weight": 1, "lights": [], "pedestal": [0, 0, 0, 0]}
	var dupe = [good, good.duplicate()]
	rejected("rooms", dupe, "duplicate room ids")
	var split = good.duplicate(true); split.cells = [[0, 0], [2, 0]]
	rejected("rooms", [split], "footprints that are not edge-connected")
	var turned = good.duplicate(true); turned.rotations = [5]
	rejected("rooms", [turned], "invalid rotations")
	var role = good.duplicate(true); role.roles = ["ballroom"]
	rejected("rooms", [role], "unknown room roles")
	var stray = good.duplicate(true); stray.lights = [[1, 0, 0, 0]]
	rejected("rooms", [stray], "anchors outside the footprint")
	rejected("rooms", [{"cells": [[0, 0]]}], "records without an id")
	check(catalog.errors.is_empty(), "catalog restores cleanly after negative checks")
	print("EMBERKEEP CATALOG TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
