# Star Web

The passive tree: the Star Heart plus **100 stars** (`src/shared/StarNet.luau`).

## Shape

- Four sectors, one per class:
  - **Wisdom**: top right, Spark Mage.
  - **Finesse**: bottom right, Ranger.
  - **Might**: bottom left, Knight.
  - **Nature**: top left, Mushroom Shaman.
- Every sector uses the same template of 23 stars:
  - 15 small stars.
  - 6 major stars.
  - 1 keystone.
  - The **class start point** in the middle.
- **Bridges** sit between neighbouring sectors. Each bridge is a small star and a major star on the sector border, and both link into the two sectors. They are the cross-class paths.
- Links are undirected. A star can be allocated next to any allocated star.

## Rules (`Shared/Progression`)

- **Roots** are the heart and the start point of the player's own class.
  - The own start point is free and always counts as allocated.
  - Other classes can take a start point for free once a path reaches it.
- **Cost**:
  - Small star: 1 point.
  - Start point: free.
  - Major star: 2 points.
  - The player gets 1 point per level from level 2.
- **Removing** a star is allowed only if every other allocated star stays connected to a root.
- **Class change**: `Progression.fitStars` frees the new own start point and refunds every star that no longer hangs on a root. This also cleans up old saves from the 22-star net.

## Window (`StarNetController`)

- The web sits in a scroll area (drag or swipe to pan) on a 1760×1760 canvas.
- The window opens on the player's own start point.
- Colors per sector come from the rarity palette. Bridges are gold.
