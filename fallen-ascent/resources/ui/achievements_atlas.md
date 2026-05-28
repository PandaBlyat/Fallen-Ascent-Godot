# achievements_atlas.png

Placeholder icon strip for achievements. One row of **32×32** cells, indexed
left-to-right. Cell index `i` maps to `AchievementManager.ACHIEVEMENTS[i]`
(same order), loaded as an `AtlasTexture` by `Main._achievement_icon`.

Current cells (in registry order):

| Cell | Achievement id        | Name             |
|------|-----------------------|------------------|
| 0    | `first_mine`          | Into the Rock    |
| 1    | `first_build`         | Foundations      |
| 2    | `first_stockpile`     | Hoarder          |
| 3    | `first_embark`        | Into the Dark    |
| 4    | `first_room`          | Shelter          |
| 5    | `first_workshop`      | Workshop         |
| 6    | `first_worker_dead`   | Sacrifice        |
| 7    | `first_hostile_killed`| Survivors        |
| 8    | `first_tech_unlock`   | Curious Minds    |
| 9    | `first_save`          | No Bot Left Behind |
| 10   | `workers_5`           | Growing Crew     |
| 11   | `first_cradle_spawn`  | New Life         |
| 12   | `workers_10`          | Small Colony     |

These are flat-color placeholders (hue-spread diamond emblems) — replace with
real pixel art later. **Append-only:** when adding an achievement, append its
icon cell by widening the canvas (keep 32 px alignment); don't reshuffle
existing cells or the indices drift out of sync with the registry order.
