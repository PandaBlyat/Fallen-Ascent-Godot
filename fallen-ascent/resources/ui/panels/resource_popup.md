# Resource Detail Popup (`resource_popup.png`)

Popup that opens when the player clicks a resource chip in the top strip.
Built in `scripts/ui/ColonyHud.gd` (`ResourcePopup_*`, around line 824).

- Anchored: drops down from the clicked resource chip.
- Width varies with content. Keep a clear top edge that visually attaches
  to the chip above it.
