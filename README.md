# BenisUI

A UI overhaul addon for World of Warcraft: Midnight (Interface 120100).

## Modules

### Bags (combined inventory)

Replaces the default inventory with a single combined frame:

- All held bags (backpack + bags 1-4) rendered as one grid; the reagent bag
  gets its own labeled section below.
- Every item gets a border colored by its item quality (poor through
  heirloom, using Blizzard's `ColorManager` quality colors).
- Items that belong to an equipment set (saved in the Equipment Manager) get
  a 5x thicker border.
- Item buttons use Blizzard's `ContainerFrameItemButtonTemplate`, so
  tooltips, clicking/using items, stack splitting, dragging, and selling to
  vendors all behave exactly like the default UI.
- Bag bar under the title: Blizzard's equipped-bag buttons (bags 1-4 and the
  reagent bag) moved into the frame. Drag bags on/off to equip or swap them,
  drop an item on one to put it in that bag, and hover one to dim everything
  outside it. The bank window shows the active section's bank tabs in the
  same spot; hover one to highlight its items, click it to open Blizzard's
  tab settings (name, icon, deposit filters).
- WoW Forever has no warband bank or reagent tabs and its bank tabs are bag
  slots, so there `Modules/BagsForever.lua` turns the bank into a single
  section with a row of bank bag slots (drag bags on/off, hover to highlight)
  and a "Buy Bag Slot" button.
- Recipe filter (`Modules/BagsRecipe.lua`): while a recipe is selected in the
  crafting window, items it does not use are greyed out and darkened in the
  inventory and bank, leaving only its reagents and tools. Typing in the
  search box overrides it.
- Category view (`Modules/BagsCategories.lua`): the bag button next to Sort
  groups the inventory into labeled blocks that flow side by side: Key Items,
  Class (spell reagents, ammo, poisons, shards), Free (one empty slot for
  splitting stacks), Quest, Equipment, Consumables, Reagents (reagent bag plus
  all crafting materials), Other and Junk. Items keep bag order inside each
  block. Shaman totems are hidden. The mode is saved per character.
- Upgrade arrows: a green arrow on gear that beats what you wear. On retail
  that means a higher item level. On WoW Forever it means a higher score from
  the stat weights of [LibBenisScore](https://github.com/fpcompany/LibBenisScore),
  which BenisAH uses too. Pick your spec's preset and edit the weights with
  `/bscore`. They're saved per character and shared with BenisAH. Item
  tooltips show the score change too ("Upgrade for Main hand: score x -> y").
- Sort button (Blizzard's `C_Container.SortBags`), free-slot counter, gold
  display, draggable frame (position is saved), ESC / `B` / all default bag
  keybinds work, merchant/mailbox auto-open works.

Blizzard's container frames are kept alive but never rendered (events
unregistered, anchor points cleared) so the default open/close state machine
keeps working — the same approach ElvUI uses.

### Party and raid frames

`Modules/GroupFrames.lua` replaces Blizzard's party and raid frames with flat
bars in the same style as the unit frames, without portraits. Each member
shows name, an online / offline dot, life number on a class-colored health
bar, role (T / H / D), level and PvP flag, with a thin mana / rage / energy bar
underneath. Party members stack downward with
no gaps; in a raid each group is a column growing down and the groups line up
to the right, four to a line, with groups 5-8 on a second line below a gap. Shift-drag any member to move the block, or open Edit Mode and
drag the Party / Raid preview.

### Nameplates

`Modules/Nameplates.lua` (with `NameplatesCast.lua` and `NameplatesAuras.lua`)
replaces Blizzard's nameplates with flat ones in the ElvUI manner: a health bar
in a one-pixel black border with the name above it on the left, the level on
the right and health percent on the bar. Bars are coloured by reaction, class
for players, grey when tapped, and by threat in combat (red when it is on you,
or green if you are the tank). A thin cast bar sits underneath with the spell
icon beside both bars: gold while the cast can be interrupted, red in a red
border while it cannot. Your own debuffs line up above each enemy with stacks
and a countdown, enemy players' dispellable buffs (the ones you or your group can purge) in a row above that, your target gets a white glow and every other plate dims.

Sizes are in physical pixels, so borders stay one pixel at any resolution; the
default size follows the screen height. Your own plate (class resources) and
objective-widget plates are left to Blizzard, as are friendly players inside
instances, which addons cannot touch.

Enemy names, health and casts are secret values on 12.x, so the module only
ever hands them to widgets; the rules it follows are listed at the top of
`Modules/Nameplates.lua`.

### Loot rolls

A small panel lists every item up for a group loot roll with each player's
choice (Need / Greed / Disenchant / Transmog / Pass), their roll once the
numbers are out, and the winner. Finished rolls stay for a minute. Built from
the loot chat lines, so it works on retail and WoW Forever alike.
Shift-drag to move.

## Install

Symlink or copy the folder into your AddOns directory:

```
ln -s /path/to/BenisUI "<WoW>/_retail_/Interface/AddOns/BenisUI"
```

LibBenisScore is a git submodule in `Libs/LibBenisScore`. Clone with
`--recurse-submodules`, or run `git submodule update --init` after cloning.

## Commands

- `/benisui` or `/bui` — toggle the inventory
- `/bscore` — stat weights for the upgrade arrows
- `/bui rolltest` — fill the loot roll panel with fake rolls
- `/bui plates on | off` — these nameplates or the default ones (`/reload`)
- `/bui plates scale <0.5-3 | auto>` — nameplate size (`/reload`)
- `/bui plates debuffs on | off` — your debuffs above enemies (`/reload`)
- `/bui plates buffs on | off` — dispellable buffs above enemy players (`/reload`)
- `/bui plates tank on | off | auto` — threat colours for a tank; `auto` uses
  your spec or assigned role
- `/bait` — send a confidently wrong "the game is ruined by exploiters" complaint to the currently selected chat channel
- `/reddit` — announce a reddit thread for a terrible idea ("Please upvote") in the currently selected chat channel
