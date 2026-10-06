# V272 - Browser Print Preview with Existing PDF Design

## Scope

- Kept `lib/features/reports/pdf/dynamic_report_pdf_builder.dart` unchanged.
- The supplied report PDF layout, colors, sections, page order, typography, charts, cards, and data mapping remain unchanged.
- On Flutter Web, report actions now call `Printing.layoutPdf(...)` so Chrome, Edge, Firefox, or the current browser opens its standard print preview.
- In the browser print preview, users can print to a physical printer or choose **Save as PDF**.
- Android, iOS, Windows, macOS, and Linux continue to use the existing in-app `PdfPreviewScreen` flow.

## Updated file

- `lib/features/reports/presentation/reports_screen.dart`

## Unchanged design source

- `lib/features/reports/pdf/dynamic_report_pdf_builder.dart`

## Web behavior

1. Generate report.
2. Existing PDF builder creates the same report bytes.
3. Browser-native print preview opens.
4. User selects printer or **Save as PDF**.
