import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/notification_backend_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../data/models/employment_action.dart';
import '../../../data/models/member.dart';

class CareerProgressionService {
  CareerProgressionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? httpClient,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _httpClient = httpClient ?? http.Client();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final http.Client _httpClient;

  CollectionReference<Map<String, dynamic>> _actions(String companyId) =>
      _db.collection('companies/$companyId/employmentActions');

  Stream<List<EmploymentAction>> watchActions({
    required String companyId,
    String? employeeId,
  }) {
    // Avoid a mandatory composite index for the employee-specific screen.
    // The company action volume is bounded and sorted safely on the client.
    Query<Map<String, dynamic>> query = _actions(companyId).limit(250);
    final cleanEmployeeId = (employeeId ?? '').trim();
    if (cleanEmployeeId.isNotEmpty) {
      query = _actions(companyId).where('employeeId', isEqualTo: cleanEmployeeId).limit(100);
    }
    return query.snapshots().map((snapshot) {
      final items = <EmploymentAction>[];
      for (final doc in snapshot.docs) {
        try {
          items.add(EmploymentAction.fromJson(<String, dynamic>{...doc.data(), 'actionId': doc.id}));
        } catch (_) {
          // One malformed historical record must not blank the appraisal screen.
        }
      }
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    });
  }

  Future<String> createRecommendation({
    required String companyId,
    required Member employee,
    required Member actor,
    required EmploymentActionType actionType,
    UserRole? proposedRole,
    String? proposedDepartment,
    String? proposedJobTitle,
    String? proposedGrade,
    String? proposedSalaryBand,
    String? proposedReportingManagerId,
    DateTime? effectiveDate,
    required String reason,
    required String managerRecommendation,
    required String appraisalPeriod,
    required int appraisalScore,
  }) async {
    if (!PermissionService.canRecommendCareerAction(actor)) {
      throw StateError('Your role cannot recommend promotion, demotion, or employment changes.');
    }
    if (employee.uid == actor.uid && !actor.role.isAdminLike && actor.role != UserRole.hrManager) {
      throw StateError('A manager or HR reviewer must create a career action for this employee.');
    }
    if (employee.status.trim().toLowerCase() != 'active') {
      throw StateError('Career actions can only be created for an active employee.');
    }
    if (<EmploymentActionType>{EmploymentActionType.promotion, EmploymentActionType.demotion}.contains(actionType) &&
        (employee.grade.trim().isEmpty || employee.employmentLevel.trim().isEmpty)) {
      throw StateError('Configure the employee grade and employment level before creating a promotion or demotion recommendation.');
    }

    await _ensureNoBlockingAction(
      companyId: companyId,
      employeeId: employee.uid,
    );

    final cleanReason = reason.trim();
    if (cleanReason.length < 8) {
      throw StateError('Add a clear reason with at least 8 characters.');
    }
    _validateProposal(
      actionType: actionType,
      employee: employee,
      proposedRole: proposedRole,
      proposedDepartment: proposedDepartment,
      proposedJobTitle: proposedJobTitle,
      proposedGrade: proposedGrade,
      proposedSalaryBand: proposedSalaryBand,
    );

    final ref = _actions(companyId).doc();
    final now = DateTime.now();
    final action = EmploymentAction(
      actionId: ref.id,
      companyId: companyId,
      employeeId: employee.uid,
      employeeName: employee.displayName,
      actionType: actionType,
      status: EmploymentActionStatus.recommended,
      createdAt: now,
      updatedAt: now,
      currentRole: employee.role,
      proposedRole: proposedRole,
      currentDepartment: employee.effectiveDepartment,
      proposedDepartment: _cleanNullable(proposedDepartment),
      currentJobTitle: employee.effectiveJobTitle,
      proposedJobTitle: _cleanNullable(proposedJobTitle),
      currentGrade: employee.grade,
      proposedGrade: _cleanNullable(proposedGrade),
      currentSalaryBand: employee.salaryBand,
      proposedSalaryBand: _cleanNullable(proposedSalaryBand),
      currentReportingManagerId: employee.reportingManagerId,
      proposedReportingManagerId: _cleanNullable(proposedReportingManagerId),
      effectiveDate: effectiveDate,
      reason: cleanReason,
      managerRecommendation: managerRecommendation.trim(),
      recommendedBy: actor.uid,
      recommendedAt: now,
      appraisalPeriod: appraisalPeriod.trim(),
      appraisalScore: appraisalScore.clamp(0, 100).toInt(),
    );

    await ref.set(<String, dynamic>{
      ...action.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'recommendedAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
    return ref.id;
  }

  Future<void> _ensureNoBlockingAction({
    required String companyId,
    required String employeeId,
  }) async {
    final snapshot = await _actions(companyId)
        .where('employeeId', isEqualTo: employeeId.trim())
        .limit(100)
        .get();

    for (final doc in snapshot.docs) {
      try {
        final action = EmploymentAction.fromJson(<String, dynamic>{
          ...doc.data(),
          'actionId': doc.id,
        });
        if (<EmploymentActionStatus>{
          EmploymentActionStatus.draft,
          EmploymentActionStatus.recommended,
          EmploymentActionStatus.underReview,
          EmploymentActionStatus.scheduled,
        }.contains(action.status)) {
          throw StateError(
            'An existing ${action.actionType.label.toLowerCase()} workflow is ${action.status.label.toLowerCase()}. Complete it before creating another recommendation.',
          );
        }
      } on StateError {
        rethrow;
      } catch (_) {
        // Ignore malformed historical records; the appraisal screen already
        // reports valid records and must not be blocked by unusable legacy data.
      }
    }
  }

  Future<void> markUnderReview({
    required String companyId,
    required EmploymentAction action,
    required Member actor,
    required String hrComments,
  }) async {
    if (!PermissionService.canReviewCareerAction(actor)) {
      throw StateError('Your role cannot review employment actions.');
    }
    if (action.isTerminal) throw StateError('This employment action is already closed.');
    await _processAction(
      companyId: companyId,
      actionId: action.actionId,
      command: 'review',
      comments: hrComments,
    );
  }

  Future<void> reject({
    required String companyId,
    required EmploymentAction action,
    required Member actor,
    required String reason,
  }) async {
    if (!PermissionService.canApproveCareerAction(actor)) {
      throw StateError('Only HR, Company Admin, or Super Admin can reject this action.');
    }
    if (action.isTerminal) throw StateError('This employment action is already closed.');
    await _processAction(
      companyId: companyId,
      actionId: action.actionId,
      command: 'reject',
      comments: reason,
    );
  }

  Future<void> approve({
    required String companyId,
    required EmploymentAction action,
    required Member actor,
  }) async {
    if (!PermissionService.canApproveCareerAction(actor)) {
      throw StateError('Only HR, Company Admin, or Super Admin can approve this action.');
    }
    if (action.isTerminal) throw StateError('This employment action is already closed.');
    await _processAction(
      companyId: companyId,
      actionId: action.actionId,
      command: 'approve',
    );
  }

  Future<void> _processAction({
    required String companyId,
    required String actionId,
    required String command,
    String comments = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before processing an employment action.');
    final token = await user.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Could not obtain the Firebase authentication token.');
    }

    final endpoint = NotificationBackendConfig.isConfigured
        ? NotificationBackendConfig.endpoint('/api/v1/appraisals/$actionId/process')
        : kDebugMode
            ? Uri.parse('http://127.0.0.1:8080/api/v1/appraisals/$actionId/process')
            : throw StateError(
                'The Oracle management backend URL is not configured. Build with '
                '--dart-define=NOTIFICATION_BACKEND_BASE_URL=https://api.your-domain.com.',
              );

    final response = await _httpClient
        .post(
          endpoint,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'companyId': companyId,
            'command': command,
            'comments': comments.trim(),
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          detail = decoded['error']?.toString() ?? detail;
        }
      } catch (_) {
        // Preserve the raw server response for diagnosis.
      }
      throw StateError('Employment action failed (${response.statusCode}): $detail');
    }
  }

  void _validateProposal({
    required EmploymentActionType actionType,
    required Member employee,
    UserRole? proposedRole,
    String? proposedDepartment,
    String? proposedJobTitle,
    String? proposedGrade,
    String? proposedSalaryBand,
  }) {
    final hasChange = proposedRole != null && proposedRole != employee.role ||
        _changed(proposedDepartment, employee.effectiveDepartment) ||
        _changed(proposedJobTitle, employee.effectiveJobTitle) ||
        _changed(proposedGrade, employee.grade) ||
        _changed(proposedSalaryBand, employee.salaryBand);
    if (!hasChange && actionType != EmploymentActionType.performanceImprovementPlan && actionType != EmploymentActionType.probationExtension && actionType != EmploymentActionType.contractRenewal && actionType != EmploymentActionType.exitRecommendation) {
      throw StateError('Select at least one proposed role, title, department, grade, or salary-band change.');
    }
    if (proposedRole == UserRole.superAdmin && employee.role != UserRole.superAdmin) {
      throw StateError('Super Admin cannot be assigned through an appraisal action.');
    }
  }

  bool _changed(String? proposed, String current) {
    final clean = (proposed ?? '').trim();
    return clean.isNotEmpty && clean.toLowerCase() != current.trim().toLowerCase();
  }

  String? _cleanNullable(String? value) {
    final clean = (value ?? '').trim();
    return clean.isEmpty ? null : clean;
  }
}
