# v266 Carousel Gesture Lock

- Adds Task Board carousel directional gesture lock.
- Parent vertical `ListView` is temporarily disabled only when horizontal intent is detected inside the carousel.
- Keeps v265 PageView-style no-vertical-motion behavior.
- Keeps carousel boundaries invisible in production UI.
- No page padding change and no title padding change.

Build:

```bash
flutter clean
flutter pub get
flutter build apk --release --build-name=1.4.266 --build-number=266
```
