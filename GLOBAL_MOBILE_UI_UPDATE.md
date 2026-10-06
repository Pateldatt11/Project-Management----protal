# Global Mobile UI / APK Emulator update

This project now uses one Platform Super Admin-controlled mobile UI configuration for every customer application.

## Global Firestore source

All mobile SDUI documents are now read and published under:

- `platformUiConfigs/mobileEmployee`
- `platformUiConfigs/mobileEmployeeDesign`
- `platformUiConfigs/mobileEmployeeScreens`
- test equivalents such as `mobileEmployeeNext`

The selected company in the Platform APK Emulator is used only to preview that customer's workspace data. Publishing the UI is global and does not create a company-specific UI override.

## Access

- Platform Super Admin can publish/update `platformUiConfigs`.
- Signed-in customer apps can read `platformUiConfigs`.
- Company Admin and IT Admin cannot publish or override the APK UI.
- Company Settings no longer exposes Mobile UI Control / Designer.
- Platform Super Admin APK Emulator includes the global Designer and Global Quick Control.

## Important rollout note

Existing installed app builds that still point to `companies/{companyId}/uiConfigs` need one app update to this codebase. After customers are on this global-reader build, future UI changes are published once from Platform Super Admin and are consumed by all customer apps without per-company editing.

The release APK keeps the existing stability policy: it polls for UI changes and stages production updates for the next cold launch. Test APK behavior remains immediate according to the existing test-target logic.

## Deploy

Deploy the included Firestore rules after deploying this code:

`firebase deploy --only firestore:rules`

Then open Platform Super Admin > APK Emulator and publish the Release UI once to create/populate the global `platformUiConfigs` documents.
