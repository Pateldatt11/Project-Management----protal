import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseBootstrapService {
  static Future<void> bootstrapDatabase() async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    // 1. Initialize System Health Telemetry
    await db.collection('system').doc('health').set({
      'database': 'Online',
      'auth': 'Online',
      'storage': 'Online',
      'gatewayStatus': 'Online',
      'lastInitialized': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. Initialize Default SaaS Subscription Plans
    await db.collection('plans').doc('free').set({
      'name': 'Free Allocation',
      'price': '\$0',
      'description': 'Free tier workspace allocation with standard features.',
      'isPopular': false,
    }, SetOptions(merge: true));

    await db.collection('plans').doc('pro').set({
      'name': 'Pro Tier',
      'price': '\$49',
      'description': 'Advanced workspace features for growing teams.',
      'isPopular': true,
    }, SetOptions(merge: true));
  }
}