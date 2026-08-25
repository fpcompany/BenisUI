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
- Sort button (Blizzard's `C_Container.SortBags`), free-slot counter, gold
  display, draggable frame (position is saved), ESC / `B` / all default bag
  keybinds work, merchant/mailbox auto-open works.

Blizzard's container frames are kept alive but never rendered (events
unregistered, anchor points cleared) so the default open/close state machine
keeps working — the same approach ElvUI uses.

## Install

Symlink or copy the folder into your AddOns directory:

```
ln -s /path/to/BenisUI "<WoW>/_retail_/Interface/AddOns/BenisUI"
```

## Commands

- `/benisui` or `/bui` — toggle the inventory
