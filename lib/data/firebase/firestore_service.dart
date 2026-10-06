import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> collection(String path) => _firestore.collection(path);
  DocumentReference<Map<String, dynamic>> doc(String path) => _firestore.doc(path);

  Stream<List<T>> collectionStream<T>({
    required String path,
    required T Function(Map<String, dynamic> json) builder,
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> query)? queryBuilder,
  }) {
    Query<Map<String, dynamic>> query = collection(path);
    if (queryBuilder != null) query = queryBuilder(query);
    return query.snapshots().map((snapshot) {
      final items = <T>[];
      for (final doc in snapshot.docs) {
        try {
          items.add(builder({...doc.data(), 'id': doc.id}));
        } catch (error, stackTrace) {
          debugPrint('Firestore parser skipped $path/${doc.id}: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      return items;
    });
  }

  Future<void> setData({required String path, required Map<String, dynamic> data, bool merge = true}) {
    return doc(path).set(data, SetOptions(merge: merge));
  }

  Future<void> updateData({required String path, required Map<String, dynamic> data}) {
    return doc(path).update(data);
  }

  Future<void> deleteData({required String path}) {
    return doc(path).delete();
  }
}
