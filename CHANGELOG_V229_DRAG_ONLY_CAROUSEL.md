# v229 — Drag-Only PageView Stack Carousel

## Change

The phase/project stack carousel now stays PageView based, but side-card taps no longer auto-scroll or snap the deck.

## Behavior

- User changes carousel cards only by dragging/swiping.
- Center card tap still reveals/open details according to existing rules.
- Side card tap does nothing by default, so the carousel will not move automatically.
- Circular queue/PageView stack visual effect remains unchanged.

## Optional override

The old side-card tap-to-focus behavior can still be enabled from SDUI if needed:

```json
{
  "phaseStackSideTapFocusEnabled": true
}
```

Default is now `false`.

## Changed file

- `lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart`
