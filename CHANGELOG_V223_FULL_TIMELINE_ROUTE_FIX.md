# V223 Full Timeline Route Fix

- Fixed View full timeline opening as a laptop-sized page in admin/emulator preview.
- View full timeline now uses a separate Navigator route, not a bottom sheet.
- On real phones/tablets, it fills the device viewport normally.
- On large desktop/admin hosts, the route content is constrained to a phone-sized frame so it does not stretch across the laptop screen.
- Kept v221 responsive Gantt date header, current date circle, and compact phone layout.
- Kept thick selected Gantt row and scrollable timeline rows.
