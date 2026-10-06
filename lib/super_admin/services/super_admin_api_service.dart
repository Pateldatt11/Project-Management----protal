import 'package:cloud_firestore/cloud_firestore.dart';

class AdminApiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. Stream all tenant companies for the Super Admin dashboard directory
  Stream<QuerySnapshot> streamAllCompanies() {
    return _db.collection('companies').snapshots();
  }

  // 2. Update a tenant company's subscription plan and limits atomically
  Future<void> updateCompanySubscription({
    required String companyId,
    required String newPlan,
    required int employeeLimit,
    required int storageLimit,
  }) async {
    final WriteBatch batch = _db.batch();

    final DocumentReference companyRef = _db.collection('companies').doc(companyId);
    batch.update(companyRef, {
      'plan': newPlan,
      'employeeLimit': employeeLimit,
      'storageLimit': storageLimit,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final DocumentReference subRef = companyRef.collection('subscription').doc('current');
    batch.set(subRef, {
      'plan': newPlan,
      'employeeLimit': employeeLimit,
      'storageLimit': storageLimit,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // 3. Update tenant company status (e.g., active, suspended, disabled)
  Future<void> updateCompanyStatus({
    required String companyId,
    required String status,
  }) async {
    await _db.collection('companies').doc(companyId).update({
      'status': status,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 4. Fetch platform-wide system health metrics
  Future<Map<String, dynamic>?> fetchSystemHealth() async {
    try {
      final DocumentSnapshot doc = await _db.collection('system').doc('health').get();
      return doc.data() as Map<String, dynamic>?;
    } catch (e) {
      throw Exception("Failed to fetch system health: $e");
    }
  }
}