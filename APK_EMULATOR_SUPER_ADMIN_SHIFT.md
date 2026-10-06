# APK Emulator moved to Platform Super Admin

## Access behavior
- Company Admin: APK Emulator / Mobile UI Control hidden and blocked.
- IT Admin: APK Emulator / Mobile UI Control hidden and blocked.
- Platform Super Admin: full APK Emulator + Mobile UI Designer access.
- Firestore uiConfigs writes: Platform Super Admin only.

## Platform Super Admin dashboard
A dedicated `APK Emulator` navigation item was added to the Platform Super Admin control center.
The Platform Super Admin can select a company workspace and load that tenant's live employee APK UI configuration into the existing emulator/designer.

## Defense in depth
1. Company Settings no longer renders Mobile UI controls for Company Admin/IT Admin.
2. MobileUiControlScreen has a direct access guard.
3. MobileUiDesignerScreen has a direct access guard.
4. Workspace publish/update methods require UserRole.superAdmin.
5. Firestore `uiConfigs` and `uiConfigMeta` writes require root Platform Super Admin authorization.
6. `main_super_admin.dart` verifies `users/{uid}.role` before showing the Platform Super Admin dashboard.

## Deploy rules
After updating the project, deploy Firestore rules:

firebase deploy --only firestore:rules
