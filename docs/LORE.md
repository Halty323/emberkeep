# The tower and its floors

Emberkeep is a tower built to keep light. Its keepers gathered every stray spark they could find, shut them away and burned them a little at a time, rationing warmth by the clock. The player is one of those sparks, waking at the bottom of the tower and climbing toward the hearth at the top, where all the gathered warmth ended up.

Every floor of the tower was something to the keepers: a store, a workshop, a record, a grave. Each floor theme in `content/floors.json` carries that story in three lines of its own:

- **epigraph**: one sentence, shown under the floor's name when it spells itself across the screen.
- **arrival**: the two-line notice when a run begins on that floor.
- **lore**: a paragraph for the journal and for writers, explaining what the floor was and what lives there now.

## The climb

A run climbs five floors (the `tower` climb). The first floor is drawn from the **first** band, the top floor from the **summit** band, and the three between from the **middle** band, never the same theme twice. The seed alone decides the order, so a seed always climbs the same tower.

| Band | Floor | What it was | Boss |
|---|---|---|---|
| first | The Waking Cellar | Where the keepers stored their little lights | The Hearth Warden, the jailer |
| first | The Drowned Cistern | The water that fed the tower, flooded to drown escaped sparks | The Sluice Mother |
| middle | The Mosslit Halls | The great halls, left to moss that feeds on stray light | The Mosskeeper |
| middle | The Candle Crypt | Where dead keepers lie, each with a candle that never went out | The Chandler |
| middle | The Frostbound Archive | The record of every flame put out, kept cold so ink cannot burn | The Hoarfrost Archivist |
| middle | The Ashen Kiln | Where the lanterns were fired, and the flawed ones thrown back in | The Kilnmother |
| middle | The Clockwork Belfry | The clock and bell that told every light when to go out | The Hour Keeper |
| summit | The Last Hearth | Where all the warmth ended up | The Last Light |

Light follows height, not theme. The bottom of any climb has the cellar's dark; halfway up is as lit as the halls; the top has the hearth's daylight. A theme only tints the colours. A middle floor can therefore come second or fourth: its boss's health grows 16% per floor of depth, and ordinary foes grow 30% and move 8% faster per floor, so difficulty rises with depth whatever the order.

Each floor also brings back, rarely and one at a time, the signature foes of the floors already climbed in that run, so a run's later floors remember its earlier ones.

## Twists

Every floor below the first draws one twist, and the first floor sometimes does. A twist is never repeated in a run and never doubles a theme's own hazard (the Cistern is never "Flooded").

| Twist | Effect |
|---|---|
| Guttering | Half the lanterns are dead and the ambient light is lower. |
| Overgrown | Lasting moss pools in every room. |
| Gilded | Many more elites, and foes pay out more coins. |
| Flooded | Lasting water pools in every room. |
| Swarming | More foes, each a little frailer. |
| Restless | Foes move and act faster. |
| Windswept | A draught pushes every shot in flight, and the kindle cools faster. |

## Adding to the tower

The structure is meant to grow:

- **A new floor** is a record in `content/floors.json`: a band, words, a roster of foe kinds, a boss, a hazard, colours and light. The content catalog rejects unknown foes, bosses, hazards, twists, bands or colours. New foe and boss scripts are registered in `scripts/foes/foes.gd`.
- **A new band** (for example *below*, under the cellar, or *beyond*, above the hearth) is a name added to `Content.FLOOR_BANDS` and used by a climb.
- **A longer or different climb** is a new record in the `climbs` list. A climb is either a list of bands or a fixed order of themes; `legacy_tower` is the fixed three-floor climb that runs saved before themes existed keep.
- **Progression** can gate themes or climbs later: the run already asks for its climb by name (`Run.CLIMB`), and every floor's theme, twist and depth are saved with the run.

The Stalker, a foe that hunts the player across rooms, is planned for multiplayer and is not built yet.
