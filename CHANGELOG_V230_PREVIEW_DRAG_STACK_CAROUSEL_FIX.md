# V230 Preview Drag Stack Carousel Fix

- Keeps v229 drag-only carousel behavior.
- Fixes admin/laptop preview where horizontal swipe/drag did not work.
- Adds mouse/stylus drag support to the carousel PageView through a local ScrollConfiguration.
- APK touch swipe remains unchanged.
- Side-card taps remain disabled, so carousel movement is still drag/swipe only.

Changed file:
- lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart
