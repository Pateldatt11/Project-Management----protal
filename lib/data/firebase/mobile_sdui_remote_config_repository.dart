import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the employee mobile SDUI config from Firestore.
///
/// Default path:
/// companies/{companyId}/uiConfigs/mobileEmployee
class MobileSduiRemoteConfigRepository {
  MobileSduiRemoteConfigRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<Map<String, dynamic>> fetchMobileEmployeeConfig(String companyId) async {
    final doc = await _firestore.collection('companies').doc(companyId).collection('uiConfigs').doc('mobileEmployee').get();
    final data = doc.data();
    if (data == null || data.isEmpty) {
      throw StateError('No mobileEmployee UI config found for companyId=$companyId.');
    }
    return data;
  }
}
