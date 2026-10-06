import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FcmTokenSyncService {
  FcmTokenSyncService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  Future<String?> syncCurrentUserToken({
    required String companyId,
    required String uid,
    String platform = 'android',
    String? appVersion,
  }) async {
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return null;

    await saveToken(
      companyId: companyId,
      uid: uid,
      token: token,
      platform: platform,
      appVersion: appVersion,
    );

    return token;
  }

  void listenAndSyncTokenRefresh({
    required String companyId,
    required String uid,
    String platform = 'android',
    String? appVersion,
  }) {
    _messaging.onTokenRefresh.listen((token) {
      saveToken(
        companyId: companyId,
        uid: uid,
        token: token,
        platform: platform,
        appVersion: appVersion,
      );
    });
  }

  Future<void> saveToken({
    required String companyId,
    required String uid,
    required String token,
    String platform = 'android',
    String? appVersion,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return;

    final tokenId = _tokenDocId(cleanToken);
    final payload = <String, dynamic>{
      'token': cleanToken,
      'fcmToken': cleanToken,
      'platform': platform,
      'appVersion': appVersion ?? '',
      'enabled': true,
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();

    // Legacy/global path kept because older Cloud Functions in this project read it.
    batch.set(
      _firestore.doc('users/$uid/fcmTokens/$tokenId'),
      payload,
      SetOptions(merge: true),
    );

    // Company member scoped path used by the direct Admin SDK sender.
    batch.set(
      _firestore.doc('companies/$companyId/members/$uid/fcmTokens/$tokenId'),
      <String, dynamic>{
        ...payload,
        'companyId': companyId,
        'uid': uid,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<void> disableToken({
    required String companyId,
    required String uid,
    required String token,
  }) async {
    final tokenId = _tokenDocId(token.trim());
    final payload = <String, dynamic>{
      'enabled': false,
      'active': false,
      'disabledAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    batch.set(_firestore.doc('users/$uid/fcmTokens/$tokenId'), payload, SetOptions(merge: true));
    batch.set(
      _firestore.doc('companies/$companyId/members/$uid/fcmTokens/$tokenId'),
      payload,
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  String _tokenDocId(String token) {
    return base64Url.encode(utf8.encode(token)).replaceAll('=', '');
  }
}
