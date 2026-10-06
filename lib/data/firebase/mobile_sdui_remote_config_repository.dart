import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the employee mobile SDUI config from Firestore.
///
/// Global path:
/// platformUiConfigs/mobileEmployee
class MobileSduiRemoteConfigRepository {
  MobileSduiRemoteConfigRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<Map<String, dynamic>> fetchMobileEmployeeConfig(String companyId) async {
    final doc = await _firestore.collection('platformUiConfigs').doc('mobileEmployee').get();
    final data = doc.data();
    if (data == null || data.isEmpty) {
      throw StateError('No global mobileEmployee UI config found at platformUiConfigs/mobileEmployee.');
    }
    return data;
  }
}
