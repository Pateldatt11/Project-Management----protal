# v211 Exact Phase Stack Carousel

- Fixed the carousel visual to behave as a real stacked deck: all 8 phase cards are visible in one circular queue stack, not only a center card with two side cards.
- Retuned the card transforms: tighter X spacing, small Y depth, rotation, scale, and depth overlay for a proper layered stack.
- Removed footer/tap/status text from the card body so the cards stay clean like the supplied render.
- Reworked phase artwork for Backlog, Planning, Todo, In Progress, Creative, Testing, and Completed to match the reference card language more closely.
- Kept the v210 project-first flow: phase card opens projects in that phase; project opens tasks inside that phase/project; empty phase still opens and shows `No task was in this phase.`
- Added Firebase-ready SDUI files under `firebase/sdui_v211/`.
