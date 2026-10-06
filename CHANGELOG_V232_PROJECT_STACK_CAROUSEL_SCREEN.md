# v232 Project Stack Carousel Screen

- Rebuilt the server-driven Projects screen with the new creative project-card design.
- Added PageView-style stacked project carousel using drag/swipe behavior like the Board phase carousel.
- Center project card tap opens the project task/details sheet.
- Added selected-project details panel below the carousel with live task list and progress.
- Added recent projects horizontal strip using the same card language.
- Kept project search, status filters, and summary widgets.
- Uses real Firestore project/task data; no dummy rows/cards are injected.
- Admin mobile preview keeps mouse drag support for carousel interaction.

Changed file:
- lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart
