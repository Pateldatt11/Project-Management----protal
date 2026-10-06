class FcmRuntimeTokenCache {
  const FcmRuntimeTokenCache();

  Future<String?> readActiveToken(String uid) async => null;

  Future<void> markActiveToken({
    required String uid,
    required String token,
    required String permissionStatus,
  }) async {}

  Future<Map<String, String>?> readPendingToken(String uid) async => null;

  Future<void> stagePendingToken({
    required String uid,
    required String token,
    required String permissionStatus,
  }) async {}

  Future<bool> canSyncWithServer(String uid, Duration minInterval) async => true;

  Future<void> markServerSynced(String uid) async {}

  Future<void> clearPendingToken(String uid) async {}
}
