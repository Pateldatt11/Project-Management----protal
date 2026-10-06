# v264 Invisible Carousel-Only Expansion Zone

- Keeps v262 carousel-only expansion-zone architecture.
- Removes any visible zone/boundary/guide from the production UI.
- Zone is layout-only: no border, no divider, no background wash, no debug overlay.
- Nav bar, Task Board title, and normal page content remain in their original areas.
- Carousel can still expand downward inside its own invisible layout box during swipe.

Build:

```bash
flutter clean
flutter pub get
flutter build apk --release --build-name=1.4.264 --build-number=263
```
