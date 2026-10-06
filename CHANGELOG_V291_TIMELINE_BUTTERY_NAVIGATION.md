# V291 — Timeline buttery navigation animation

Changed file:

- `lib/app/app_shell.dart`

## Fix

- Replaced per-frame sidebar content relayout with a single explicit animation controller.
- Keeps expanded and collapsed navigation trees at stable widths.
- Animates only rail width, opacity, and translation.
- Timeline remains laid out at the final compact inset while the rail animates as an overlay.
- Prevents the blank midpoint flash by cross-fading the expanded and compact rails.
- Uses a Windows-style decelerating curve: `Cubic(0.16, 1.0, 0.30, 1.0)`.
- Removes double easing from the previous animation.
- The change is web shell only; mobile SDUI/APK navigation files are not modified.
