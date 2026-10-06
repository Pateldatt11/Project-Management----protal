import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/razorpay_config.dart';

class RazorpayService {
  RazorpayService({
    String? keyId,
    required this.onPaymentSuccess,
    required this.onPaymentError,
    required this.onExternalWallet,
  }) : _keyId = (keyId ?? RazorpayConfig.keyId).trim() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  late final Razorpay _razorpay;
  final String _keyId;
  final ValueChanged<PaymentSuccessResponse> onPaymentSuccess;
  final ValueChanged<PaymentFailureResponse> onPaymentError;
  final ValueChanged<ExternalWalletResponse> onExternalWallet;

  /// Opens the Razorpay checkout window using the configured public key ID.
  void openCheckout({
    required String companyId,
    required String companyName,
    required String adminEmail,
    required String adminPhone,
    required num amountInINR, // e.g. 999 for ₹999
  }) {
    if (_keyId.isEmpty) {
      throw StateError('RAZORPAY_KEY_ID is not configured. Build the app with --dart-define=RAZORPAY_KEY_ID=...');
    }

    final options = {
      'key': _keyId,
      'amount': (amountInINR * 100).toInt(), // Razorpay expects paisa (₹999 = 99900)
      'name': companyName,
      'description': 'Enterprise Workspace Subscription Renewal',
      'timeout': 300, // 5 minutes
      'prefill': {
        'contact': adminPhone,
        'email': adminEmail,
      },
      'notes': {
        'companyId': companyId,
        'gateway': 'razorpay_client_test_mode',
      },
      'theme': {
        'color': '#673AB7', // Admin control center purple theme
      },
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error launching Razorpay checkout: $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    onPaymentSuccess(response);
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    onPaymentError(response);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    onExternalWallet(response);
  }

  void dispose() {
    _razorpay.clear();
  }
}