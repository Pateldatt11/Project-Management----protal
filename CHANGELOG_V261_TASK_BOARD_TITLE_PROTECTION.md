# v261 Task Board Title Protection

- Added a visible `Task Board` page title above the phase carousel.
- Reduced the renderer-only blank top protection padding and moved that space into the title header.
- Kept fixed carousel protection for the floating top/search bar during horizontal swipes.
- Empty phase card tap now opens the phase sheet/dialog and shows `No task was in this phase.`
- Added JSON flags: `taskBoardTitleProtectionEnabled`, `taskBoardPageTitle`, `taskBoardPageSubtitle`, `taskBoardTitleTopProtectionPadding`, and `emptyPhaseCardTapOpensDialog`.

Push file: `mobileEmployee_PUSH_THIS_v261.json` or `firebase/sdui_v261/mobileEmployee_PUSH_THIS_v261.json`.
