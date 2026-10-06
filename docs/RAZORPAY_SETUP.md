# Razorpay Setup

This app now reads the Razorpay public key ID from a build-time define and keeps the secret off the Flutter client.

## Client app

Build or run with your public key ID:

```bash
flutter run -d chrome --dart-define=RAZORPAY_KEY_ID=rzp_test_xxxxx
```

The client only needs the key ID. Do not put the Razorpay secret in Flutter code, widgets, or `--dart-define` values.

## Server side

If you later add order creation or payment verification in Cloud Functions or another backend, store the Razorpay secret only on the server as an environment secret, for example `RAZORPAY_KEY_SECRET`.

Never commit the secret to this repository.