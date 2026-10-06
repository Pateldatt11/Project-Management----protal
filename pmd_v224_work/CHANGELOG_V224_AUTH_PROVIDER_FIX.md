# v224 Auth Provider Fix

## Fixed
- Replaced fragile Google provider web-flow login with native Google Sign-In on Android/iOS/macOS using `google_sign_in` and Firebase credentials.
- Kept Firebase provider flow for Apple and Facebook, but wrapped failures with clearer provider-specific Firebase errors.
- Added local Google sign-out cleanup before Firebase sign-out.
- Improved friendly auth error text for Google SHA/client configuration issues and provider flow failures.

## Files changed
- `lib/data/firebase/auth_service.dart`
- `pubspec.yaml`

## Required Firebase Console checks
- Enable Email/Password, Google, Facebook, and Apple in Firebase Authentication.
- For Google Android sign-in, add debug/release SHA-1 and SHA-256 to Firebase Android app and download the latest `google-services.json`.
- For Facebook and Apple, complete provider-specific OAuth setup in Firebase.
