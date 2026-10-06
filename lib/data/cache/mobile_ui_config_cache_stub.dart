import '../models/mobile_ui_config.dart';
import '../models/mobile_ui_design.dart';

/// Web/unsupported fallback. The employee mobile app uses the sqflite
/// implementation through conditional export; web admin can continue to read
/// the live Firestore config directly.
class MobileUiConfigCache {
  const MobileUiConfigCache();

  Future<MobileUiConfig?> read(String companyId) async => null;

  Future<void> write({
    required String companyId,
    required MobileUiConfig config,
  }) async {}

  Future<MobileUiDesign?> readDesign(String companyId) async => null;

  Future<void> writeDesign({
    required String companyId,
    required MobileUiDesign design,
  }) async {}

  Future<bool> promotePendingForNextLaunch(String companyId) async => false;

  Future<void> writePending({
    required String companyId,
    required MobileUiConfig config,
  }) async {}

  Future<void> writePendingDesign({
    required String companyId,
    required MobileUiDesign design,
  }) async {}

  Future<bool> hasPending(String companyId) async => false;

  Future<void> clear(String companyId) async {}
}
