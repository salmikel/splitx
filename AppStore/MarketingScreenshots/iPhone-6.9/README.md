# SplitX — App Store marketing screenshots

Five promotional screenshots built from **real app snapshots** (captured on
device, dark mode) framed in an iPhone with feature captions. These are the
assets that show in App Store **search results** and on the product page.

## Files

| Order | File | Source snapshot | Caption |
|-------|------|-----------------|---------|
| 1 | `01_group.png` | `IMG_0058` (dashboard) | Split expenses with your group |
| 2 | `02_split.png` | `IMG_0059` (edit / split) | Fair splits, every time |
| 3 | `03_watch.png` | Watch `+` + keypad | Add it from your wrist |
| 4 | `04_offline.png` | `IMG_0060` (offline + pending sync) | Works offline, syncs later |
| 5 | `05_add.png` | `IMG_0061` (new expense / scan) | Scan a receipt, split in seconds |

Upload in this numbered order — the first 1–3 are what show in search.

Raw device captures are in `snapshots/` (4 iPhone @ 1206×2622, 3 Apple Watch
@ 410×502). The watch set also includes a description-entry keyboard shot not
used here.

## Format

- **1290 × 2796 px, PNG, RGB (no alpha)** — iPhone 6.9" display. This is the
  only iPhone size App Store Connect now requires; it auto-scales to the
  smaller iPhones. (Ask if you want a 13" iPad set at 2064 × 2752.)

## How to upload

App Store Connect → your app → the version → **App Previews and Screenshots** →
**iPhone 6.9" Display** → drag the five PNGs in, in order → Save.

## Regenerating / editing

`generate_real.py` frames the files in `snapshots/` with Pillow (system SF font,
`AppIcons/appstore.png` for the footer lockup):

```bash
python3 generate_real.py
```

- Swap a source snapshot: drop a new PNG in `snapshots/` and change the filename
  in the matching `compose(...)` call at the bottom.
- Change a caption, gradient, or ordering: edit that `compose(...)` call.
- Captions and gradients are the only non-app pixels; everything inside the
  frame is a genuine screenshot, so these satisfy App Store guideline 2.3.3.
