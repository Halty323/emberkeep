# Spellcraft (experimental)

This branch lets the forge write spellbooks that do more than throw a flying spell, and gives flying spells looks of their own. Every roll is random but stays logical: a kind of spell only takes the elements and traits that make sense for it, and a look suits both its element and its pattern.

![Rays, lightning, eruptions and the new looks](images/spell-archetypes.png)

## Kinds of spell

Besides the nine flying patterns (bolt, burst, fan, twin, ring, spiral, lance, lob, boomerang) the forge now writes three spells that do not fly:

| Kind | What it does | Elements | Traits it can take |
| --- | --- | --- | --- |
| Ray | An instant beam along your aim. It goes through the same flight a bolt does in one tick, so it stops at walls, pierces, glances off walls, relights lanterns, splits through glass and strikes everything a bolt would, then shows as a beam along the path it really took (bends and ricochets too). | radiance, frost, ember, glass, tide, venom | piercing, ricochet, chaining, splitting, volatile, keen, heavy, kindled |
| Lightning | Strikes the nearest foe within a narrow cone ahead and in sight, at once, as a jagged bolt with branches. With no foe it strikes where you aim, and lightning in water runs through the pool. | storm, radiance | chaining, volatile, splitting, keen, heavy, kindled |
| Eruption | A rune glows on the floor where you aim (under the first foe in the way), then something rises and strikes everything over it. Each element rises its own way: flame tongues, ice spikes, a bolt from above, venom bubbles, a pillar of light, crystal shards, a wax geyser, a waterspout. Water, wax and ice eruptions leave their residue behind. | all eight | lingering (rises twice), growing (wider), seeking (rises under the nearest foe), chaining, splitting (throws glass shards), keen, heavy, kindled |

Every seed's four starters include at least one spell that does not fly. Each kind is balanced against the same damage budget as before.

## Looks

A flying spell's heart takes one of six shapes, each with its own halo so it reads from behind as well as from the side:

| Look | Shape | Suits |
| --- | --- | --- |
| Orb | A swirling orb in a rune circle (as before) | ember, frost, venom, radiance, wax, tide |
| Shard | A long crystal in a turning diamond | frost, glass |
| Needle | A thin dart in a four-point star, with a long trail | frost, storm |
| Comet | A large orb in a flaring corona, with a long trail | ember, radiance, wax |
| Mote | A small soft spark | storm, venom |
| Disc | A flat disc spinning as it flies | glass, tide |

Patterns narrow it further: a lance is a needle or a shard, a lob an orb or a comet, a boomerang a disc or an orb, and sprays and rings lean to motes and shards.

## Compatibility

Forged ids now carry version 2. Version 1 ids (older saves, shops and the dark store's offers in old saves) still rebuild exactly as they were. Lances are no longer named "Ray" or "Beam" in version 2, since rays exist.

In co-op, a guest's rays, lightning and eruptions are cast by the host like any other spell, and every player draws them: the kind and the look travel with the spell as numbers.

## Code

- `scripts/items/forge.gd`: `ARCHETYPES`, `FORMS`, the element and pattern tables for looks, and version 2 rolls.
- `scripts/items/spell_forms.gd`: a cast's kind and look, carried in its stats.
- `scripts/shot.gd`: `trace_ray()`, `strike()`, `erupt_tick()`, and each look's heart (`form_basis()`).
- `scripts/items/spell_shapes.gd`: beams, bolts, ground runes and what each element raises.
- `shaders/shot_beam.gdshader`, `shaders/spell_rune.gdshader`, and the looks' halos in `shaders/shot_glow.gdshader`.

`tests/tower.gd` checks that every seed's starters include a spell that does not fly, that every element, trait and look suits its spell (starters, shop and dark-forged spellbooks), that version 1 ids rebuild unchanged, and that a ray, lightning and an eruption each strike a foe ahead. `tests/render_spells.gd` is an opt-in capture; set `EMBERKEEP_SPELLS_CAPTURE`.
