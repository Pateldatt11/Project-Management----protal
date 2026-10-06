import '../../core/utils/json_value.dart';

class Company {
  const Company({
    required this.companyId,
    required this.name,
    required this.industry,
    required this.status,
    required this.timezone,
    this.logoUrl,
    this.legalName,
    this.email,
    this.phone,
    this.website,
    this.address,
    this.city,
    this.state,
    this.country,
    this.subscriptionStatus = 'active', // 'active', 'grace_period', 'restricted'
    this.renewalWarningCount = 0,       // Tracks renewal warnings (0 to 5)
    this.currentPeriodEnd,
  });

  final String companyId;
  final String name;
  final String industry;
  final String status;
  final String timezone;
  final String? logoUrl;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? website;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  
  // Subscription & Dunning Tracking Fields
  final String subscriptionStatus;
  final int renewalWarningCount;
  final DateTime? currentPeriodEnd;

  // Helper getters for your 5-warning dunning rules
  bool get isRestricted => renewalWarningCount >= 5 || subscriptionStatus == 'restricted';
  bool get isInGracePeriod => renewalWarningCount > 0 && renewalWarningCount < 5;

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        companyId: JsonValue.string(json['companyId'] ?? json['id']),
        name: JsonValue.string(json['name'] ?? json['companyName'], fallback: 'Company Workspace'),
        industry: JsonValue.string(json['industry'], fallback: 'Project Management'),
        status: JsonValue.string(json['status'], fallback: 'active'),
        timezone: JsonValue.string(json['timezone'], fallback: 'Asia/Kolkata'),
        logoUrl: JsonValue.optionalString(json['logoUrl']),
        legalName: JsonValue.optionalString(json['legalName']),
        email: JsonValue.optionalString(json['email']),
        phone: JsonValue.optionalString(json['phone']),
        website: JsonValue.optionalString(json['website']),
        address: JsonValue.optionalString(json['address']),
        city: JsonValue.optionalString(json['city']),
        state: JsonValue.optionalString(json['state']),
        country: JsonValue.optionalString(json['country']),
        subscriptionStatus: JsonValue.string(json['subscriptionStatus'], fallback: 'active'),
        renewalWarningCount: JsonValue.number(json['renewalWarningCount'], fallback: 0).toInt(),
        currentPeriodEnd: json['currentPeriodEnd'] != null ? DateTime.tryParse(json['currentPeriodEnd'].toString()) : null,
      );

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'name': name,
        'industry': industry,
        'status': status,
        'timezone': timezone,
        'logoUrl': logoUrl,
        'legalName': legalName,
        'email': email,
        'phone': phone,
        'website': website,
        'address': address,
        'city': city,
        'state': state,
        'country': country,
        'subscriptionStatus': subscriptionStatus,
        'renewalWarningCount': renewalWarningCount,
        'currentPeriodEnd': currentPeriodEnd?.toIso8601String(),
      };

  Company copyWith({
    String? companyId,
    String? name,
    String? industry,
    String? status,
    String? timezone,
    String? logoUrl,
    String? legalName,
    String? email,
    String? phone,
    String? website,
    String? address,
    String? city,
    String? state,
    String? country,
    String? subscriptionStatus,
    int? renewalWarningCount,
    DateTime? currentPeriodEnd, required String plan,
  }) {
    return Company(
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      industry: industry ?? this.industry,
      status: status ?? this.status,
      timezone: timezone ?? this.timezone,
      logoUrl: logoUrl ?? this.logoUrl,
      legalName: legalName ?? this.legalName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      website: website ?? this.website,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      renewalWarningCount: renewalWarningCount ?? this.renewalWarningCount,
      currentPeriodEnd: currentPeriodEnd ?? this.currentPeriodEnd,
    );
  }

  static const platform = Company(
    companyId: 'platform',
    name: 'Platform Administration',
    industry: 'SaaS Administration',
    status: 'setupRequired',
    timezone: 'Asia/Kolkata',
  );

  String? get plan => null;
}