import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/company_request_model.dart';

class CompanyProvisioningService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String> provisionNewCompany({
    required CompanyRequestModel request,
    required String adminPassword,
    required String platformAdminUid,
    required String preGeneratedUid,
  }) async {
    final String targetEmail = request.email.trim().toLowerCase();

    // 1. Generate unique company workspace ID
    final String companyId = 'CMP_${DateTime.now().millisecondsSinceEpoch}';
    final DocumentReference companyRef = _db.collection('companies').doc(companyId);

    final WriteBatch batch = _db.batch();

    // 2. Create Company Document
    batch.set(companyRef, {
      'companyId': companyId,
      'name': request.companyName,
      'ownerName': request.ownerName,
      'email': targetEmail,
      'plan': request.plan.toLowerCase(),
      'employeeLimit': request.employeeLimit,
      'storageLimit': request.storageLimit,
      'country': request.country,
      'status': 'active',
      'createdBy': platformAdminUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Create Settings: Bootstrap
    final DocumentReference bootstrapRef = companyRef.collection('settings').doc('bootstrap');
    batch.set(bootstrapRef, {
      'isInitialized': true,
      'provisionedBy': platformAdminUid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 4. Create Settings: Portal Posts
    final DocumentReference portalPostsRef = companyRef.collection('settings').doc('portalPosts');
    batch.set(portalPostsRef, {
      'enabledRoleValues': ['superAdmin', 'admin', 'itAdmin'],
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 5. Create Subscription Node
    final DocumentReference subscriptionRef = companyRef.collection('subscription').doc('current');
    batch.set(subscriptionRef, {
      'plan': request.plan.toLowerCase(),
      'employeeLimit': request.employeeLimit,
      'storageLimit': request.storageLimit,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 6. Create Member Document inside /companies/{companyId}/members/{preGeneratedUid}
    final DocumentReference memberRef = companyRef.collection('members').doc(preGeneratedUid);
    batch.set(memberRef, {
      'uid': preGeneratedUid,
      'companyId': companyId,
      'email': targetEmail,
      'name': request.ownerName,
      'role': 'superAdmin',
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 7. Write to PLURAL 'users/{uid}' (Required by app startup bootstrap check)
    final DocumentReference pluralUserRef = _db.collection('users').doc(preGeneratedUid);
    batch.set(pluralUserRef, {
      'uid': preGeneratedUid,
      'companyId': companyId,
      'email': targetEmail,
      'displayName': request.ownerName,
      'role': 'superAdmin',
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 8. Write to SINGULAR 'user/{uid}' (For backward compatibility)
    final DocumentReference singularUserRef = _db.collection('user').doc(preGeneratedUid);
    batch.set(singularUserRef, {
      'uid': preGeneratedUid,
      'companyId': companyId,
      'email': targetEmail,
      'displayName': request.ownerName,
      'role': 'superAdmin',
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Commit all writes atomically
    await batch.commit();
    return companyId;
  }
}