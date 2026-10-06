# v210 Phase Project Stack Carousel

Implemented the new Task Board carousel behavior:

- Task Board cards are now phase cards, not task-detail cards.
- The carousel behaves as a circular horizontal stack queue.
- Tapping a side card focuses it; tapping the active center card opens a phase project sheet.
- The phase project sheet first shows projects that contain tasks for that phase.
- Tapping a project opens only the tasks that belong to that selected phase and project.
- Empty phase cards still open a sheet and show: `No task was in this phase.`
- Card visuals were simplified to match the supplied render direction: full-card art, phase title/subtitle/caption, no side status panel, no task priority/progress rail on the card.
- Added Hero transition support between the phase card and the project/task sheet header.

Files changed:

- `lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart`
- `lib/employee_app/server_driven/renderer/mobile_ui_support_registry.dart`
- `mobileEmployee_cleanWireframe_v210_phase_project_stack_carousel_FULL.json`
- `phase_project_stack_carousel_patch_v210.json`
- `firebase/sdui_v210/mobileEmployee_PUSH_THIS_v210.json`
