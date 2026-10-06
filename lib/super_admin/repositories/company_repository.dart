import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/company_model.dart';

class CompanyRepository {
  CompanyRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String companiesCollection = 'companies';

  CollectionReference<Map<String, dynamic>> get _companies =>
      _firestore.collection(companiesCollection);

  Future<void> createCompany(CompanyModel company) async {
    await _companies.doc(company.id).set(company.toMap());
  }

  Future<void> updateCompany(CompanyModel company) async {
    await _companies.doc(company.id).update(company.toMap());
  }

  Future<void> deleteCompany(String companyId) async {
    await _companies.doc(companyId).delete();
  }

  Future<void> activateCompany(String companyId) async {
    await _companies.doc(companyId).update({
      'isActive': true,
      'isSuspended': false,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> suspendCompany(String companyId) async {
    await _companies.doc(companyId).update({
      'isActive': false,
      'isSuspended': true,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<CompanyModel?> getCompany(String companyId) async {
    final snapshot = await _companies.doc(companyId).get();

    if (!snapshot.exists) {
      return null;
    }

    return CompanyModel.fromMap(snapshot.data()!);
  }

  Future<bool> companyExists(String companyId) async {
    final snapshot = await _companies.doc(companyId).get();
    return snapshot.exists;
  }

  Future<List<CompanyModel>> getAllCompanies() async {
    final snapshot = await _companies
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => CompanyModel.fromMap(doc.data()))
        .toList();
  }

  Future<List<CompanyModel>> getActiveCompanies() async {
    final snapshot = await _companies
        .where('isActive', isEqualTo: true)
        .get();

    return snapshot.docs
        .map((doc) => CompanyModel.fromMap(doc.data()))
        .toList();
  }

  Future<List<CompanyModel>> getSuspendedCompanies() async {
    final snapshot = await _companies
        .where('isSuspended', isEqualTo: true)
        .get();

    return snapshot.docs
        .map((doc) => CompanyModel.fromMap(doc.data()))
        .toList();
  }

  Stream<List<CompanyModel>> companiesStream() {
    return _companies
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CompanyModel.fromMap(doc.data()))
              .toList(),
        );
  }

  Future<int> totalCompanies() async {
    final snapshot = await _companies.get();
    return snapshot.docs.length;
  }

  Future<int> activeCompaniesCount() async {
    final snapshot = await _companies
        .where('isActive', isEqualTo: true)
        .get();

    return snapshot.docs.length;
  }

  Future<int> suspendedCompaniesCount() async {
    final snapshot = await _companies
        .where('isSuspended', isEqualTo: true)
        .get();

    return snapshot.docs.length;
  }
}