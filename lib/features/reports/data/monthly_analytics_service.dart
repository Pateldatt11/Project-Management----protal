import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/models/monthly_analytics_snapshot.dart';

class MonthlyAnalyticsService {
  MonthlyAnalyticsService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Stream<MonthlyAnalyticsSnapshot?> watchMonth({
    required String companyId,
    required String monthId,
  }) {
    return _db.doc('companies/$companyId/monthlyAnalytics/$monthId').snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      try {
        return MonthlyAnalyticsSnapshot.fromJson(<String, dynamic>{...data, 'monthId': snapshot.id});
      } catch (_) {
        return null;
      }
    });
  }

  Future<MonthlyAnalyticsSnapshot?> loadMonth({
    required String companyId,
    required String monthId,
  }) async {
    try {
      final rootRef = _db.doc('companies/$companyId/monthlyAnalytics/$monthId');
      final snapshot = await rootRef.get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      final root = MonthlyAnalyticsSnapshot.fromJson(<String, dynamic>{...data, 'monthId': snapshot.id});
      if (root.breakdownStorage != 'subcollections' || root.generationId.isEmpty) return root;

      final details = await Future.wait<List<Map<String, dynamic>>>([
        _loadBreakdown(rootRef, 'projects', root.generationId),
        _loadBreakdown(rootRef, 'employees', root.generationId),
        _loadBreakdown(rootRef, 'tasks', root.generationId),
        _loadBreakdown(rootRef, 'employmentActions', root.generationId),
      ]);
      return root.withDetails(
        projects: details[0],
        employees: details[1],
        tasks: details[2],
        employmentActions: details[3],
      );
    } catch (_) {
      // Local Flutter Web reports remain available if Firebase is offline,
      // permission-restricted, or no canonical monthly snapshot exists yet.
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadBreakdown(
    DocumentReference<Map<String, dynamic>> rootRef,
    String collectionName,
    String generationId,
  ) async {
    try {
      final query = await rootRef
          .collection(collectionName)
          .where('generationId', isEqualTo: generationId)
          .get();
      return query.docs
          .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id})
          .toList(growable: false);
    } catch (_) {
      // Inline previews remain usable if an older ruleset or a transient network
      // problem blocks one detail collection.
      return const <Map<String, dynamic>>[];
    }
  }

}
