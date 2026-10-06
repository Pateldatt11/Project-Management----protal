# v271/v93 - Hardcoded biometric app lock in Profile + Admin preview

- Fixed missing Admin Mobile UI Designer preview for the fingerprint app-lock option.
- Changed biometric setting from SDUI-declared widget to hardcoded Flutter profile setting.
- Profile → Settings now always injects `BiometricSettingsTile` from the renderer.
- Admin preview uses `previewMode: true`, which prevents the OS biometric prompt and shows a preview-only toggle.
- APK mode still uses `local_auth` with Android/iOS biometric prompts.
- Cleaned config JSON so `biometricSettingsTile` is no longer required in `screenOverrides.profile.sections`.
