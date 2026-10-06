# v225 Google Web Startup Fix

- Fixed Flutter Web startup crash from `google_sign_in_web` when no `google-signin-client_id` meta tag is configured.
- AuthService no longer constructs `GoogleSignIn` during app startup.
- Web Google login now uses FirebaseAuth provider popup flow.
- Native Android/iOS Google login still uses `google_sign_in` + Firebase credential.
- Sign-out still cleans up native Google session on non-web platforms.

Changed file:

- `lib/data/firebase/auth_service.dart`
