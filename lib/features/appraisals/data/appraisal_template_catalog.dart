import '../../../data/models/member.dart';

class AppraisalCompetency {
  const AppraisalCompetency({
    required this.id,
    required this.label,
    required this.description,
    this.weight = 1,
  });

  final String id;
  final String label;
  final String description;
  final double weight;
}

class AppraisalTemplate {
  const AppraisalTemplate({
    required this.id,
    required this.name,
    required this.industry,
    required this.competencies,
  });

  final String id;
  final String name;
  final String industry;
  final List<AppraisalCompetency> competencies;
}

class AppraisalTemplateCatalog {
  const AppraisalTemplateCatalog._();

  static const AppraisalTemplate general = AppraisalTemplate(
    id: 'general_operations',
    name: 'General Operations',
    industry: 'General',
    competencies: <AppraisalCompetency>[
      AppraisalCompetency(id: 'delivery', label: 'Delivery reliability', description: 'Completes assigned work predictably and on time.', weight: 1.3),
      AppraisalCompetency(id: 'quality', label: 'Quality of work', description: 'Produces accurate, review-ready outcomes.', weight: 1.3),
      AppraisalCompetency(id: 'ownership', label: 'Ownership', description: 'Takes responsibility for work, blockers, and outcomes.', weight: 1.1),
      AppraisalCompetency(id: 'collaboration', label: 'Collaboration', description: 'Communicates and works effectively with the team.', weight: 1),
      AppraisalCompetency(id: 'safety_compliance', label: 'Safety & compliance', description: 'Follows safety, policy, and operational controls.', weight: 1),
      AppraisalCompetency(id: 'improvement', label: 'Continuous improvement', description: 'Identifies and implements practical improvements.', weight: .9),
    ],
  );

  static const List<AppraisalTemplate> templates = <AppraisalTemplate>[
    general,
    AppraisalTemplate(
      id: 'civil_engineering',
      name: 'Civil Engineering & Site Delivery',
      industry: 'Civil Engineering',
      competencies: <AppraisalCompetency>[
        AppraisalCompetency(id: 'site_supervision', label: 'Site supervision', description: 'Plans, supervises, and coordinates site execution.', weight: 1.4),
        AppraisalCompetency(id: 'drawing_interpretation', label: 'Drawing interpretation', description: 'Correctly interprets structural and architectural drawings.', weight: 1.2),
        AppraisalCompetency(id: 'boq_accuracy', label: 'BOQ & estimation accuracy', description: 'Produces reliable quantity estimates, BOQs, and measurements.', weight: 1.3),
        AppraisalCompetency(id: 'quality_inspection', label: 'Quality inspection', description: 'Maintains workmanship, testing, and inspection standards.', weight: 1.3),
        AppraisalCompetency(id: 'safety_compliance', label: 'Site safety compliance', description: 'Enforces safe-work methods and statutory requirements.', weight: 1.4),
        AppraisalCompetency(id: 'contractor_coordination', label: 'Contractor coordination', description: 'Coordinates contractors, vendors, manpower, and dependencies.', weight: 1.1),
        AppraisalCompetency(id: 'material_management', label: 'Material management', description: 'Controls material planning, usage, wastage, and reconciliation.', weight: 1),
        AppraisalCompetency(id: 'schedule_control', label: 'Schedule control', description: 'Tracks look-ahead plans, milestones, and recovery actions.', weight: 1.2),
        AppraisalCompetency(id: 'documentation', label: 'Site documentation', description: 'Maintains DPRs, RFIs, checklists, and handover records.', weight: .9),
      ],
    ),
    AppraisalTemplate(
      id: 'software_engineering',
      name: 'Software Engineering',
      industry: 'Technology',
      competencies: <AppraisalCompetency>[
        AppraisalCompetency(id: 'code_quality', label: 'Code quality', description: 'Builds maintainable, tested, and reviewable software.', weight: 1.4),
        AppraisalCompetency(id: 'delivery', label: 'Delivery predictability', description: 'Estimates and delivers committed work reliably.', weight: 1.2),
        AppraisalCompetency(id: 'architecture', label: 'Architecture & design', description: 'Makes scalable and secure technical decisions.', weight: 1.2),
        AppraisalCompetency(id: 'defect_rate', label: 'Defect prevention', description: 'Prevents regressions and closes root causes.', weight: 1.2),
        AppraisalCompetency(id: 'security', label: 'Security & privacy', description: 'Applies secure engineering practices.', weight: 1),
        AppraisalCompetency(id: 'documentation', label: 'Documentation', description: 'Documents systems, APIs, and operational knowledge.', weight: .8),
        AppraisalCompetency(id: 'collaboration', label: 'Technical collaboration', description: 'Reviews, mentors, and communicates effectively.', weight: 1),
      ],
    ),
    AppraisalTemplate(
      id: 'quality_assurance',
      name: 'Quality Assurance',
      industry: 'Quality',
      competencies: <AppraisalCompetency>[
        AppraisalCompetency(id: 'test_coverage', label: 'Test coverage', description: 'Designs risk-based coverage across critical flows.', weight: 1.3),
        AppraisalCompetency(id: 'defect_discovery', label: 'Defect discovery', description: 'Finds meaningful defects before release.', weight: 1.3),
        AppraisalCompetency(id: 'regression_quality', label: 'Regression quality', description: 'Maintains reliable regression and release validation.', weight: 1.2),
        AppraisalCompetency(id: 'automation', label: 'Automation contribution', description: 'Improves repeatability and automation coverage.', weight: 1),
        AppraisalCompetency(id: 'release_validation', label: 'Release validation', description: 'Provides evidence-based go/no-go recommendations.', weight: 1.2),
        AppraisalCompetency(id: 'documentation', label: 'QA documentation', description: 'Maintains clear cases, evidence, and defect reports.', weight: .9),
      ],
    ),
    AppraisalTemplate(
      id: 'mechanical_engineering',
      name: 'Mechanical Engineering',
      industry: 'Mechanical',
      competencies: <AppraisalCompetency>[
        AppraisalCompetency(id: 'design_accuracy', label: 'Design accuracy', description: 'Produces accurate mechanical designs and calculations.', weight: 1.3),
        AppraisalCompetency(id: 'maintenance', label: 'Maintenance reliability', description: 'Improves uptime, preventive maintenance, and root-cause closure.', weight: 1.3),
        AppraisalCompetency(id: 'safety_compliance', label: 'Safety compliance', description: 'Follows mechanical safety and permit controls.', weight: 1.3),
        AppraisalCompetency(id: 'quality', label: 'Inspection & quality', description: 'Maintains inspection, testing, and acceptance standards.', weight: 1.2),
        AppraisalCompetency(id: 'cost_control', label: 'Cost control', description: 'Controls spares, wastage, and lifecycle cost.', weight: 1),
        AppraisalCompetency(id: 'documentation', label: 'Technical documentation', description: 'Maintains drawings, checklists, and maintenance history.', weight: .9),
      ],
    ),
    AppraisalTemplate(
      id: 'electrical_engineering',
      name: 'Electrical Engineering',
      industry: 'Electrical',
      competencies: <AppraisalCompetency>[
        AppraisalCompetency(id: 'design_accuracy', label: 'Electrical design accuracy', description: 'Produces compliant schematics, loads, and protection designs.', weight: 1.3),
        AppraisalCompetency(id: 'commissioning', label: 'Testing & commissioning', description: 'Plans and executes safe testing and commissioning.', weight: 1.3),
        AppraisalCompetency(id: 'safety_compliance', label: 'Electrical safety', description: 'Follows isolation, permit, and statutory controls.', weight: 1.4),
        AppraisalCompetency(id: 'fault_resolution', label: 'Fault resolution', description: 'Diagnoses and resolves faults with strong root-cause analysis.', weight: 1.2),
        AppraisalCompetency(id: 'energy_efficiency', label: 'Energy efficiency', description: 'Improves power quality and energy performance.', weight: 1),
        AppraisalCompetency(id: 'documentation', label: 'Technical documentation', description: 'Maintains SLDs, test records, and asset history.', weight: .9),
      ],
    ),
    AppraisalTemplate(
      id: 'human_resources',
      name: 'Human Resources & People Operations',
      industry: 'People Operations',
      competencies: <AppraisalCompetency>[
        AppraisalCompetency(id: 'recruitment', label: 'Recruitment effectiveness', description: 'Improves quality, speed, and candidate experience.', weight: 1.2),
        AppraisalCompetency(id: 'engagement', label: 'Employee engagement', description: 'Builds trust, communication, and retention.', weight: 1.2),
        AppraisalCompetency(id: 'policy_compliance', label: 'Policy compliance', description: 'Maintains fair and compliant people processes.', weight: 1.3),
        AppraisalCompetency(id: 'performance_cycles', label: 'Performance cycles', description: 'Runs timely, consistent appraisal and development cycles.', weight: 1.2),
        AppraisalCompetency(id: 'conflict_resolution', label: 'Conflict resolution', description: 'Resolves sensitive matters professionally and fairly.', weight: 1),
        AppraisalCompetency(id: 'analytics', label: 'People analytics', description: 'Uses data to improve people decisions.', weight: .9),
      ],
    ),
    AppraisalTemplate(
      id: 'sales_business',
      name: 'Sales & Business Development',
      industry: 'Sales',
      competencies: <AppraisalCompetency>[
        AppraisalCompetency(id: 'revenue', label: 'Revenue achievement', description: 'Delivers target revenue with healthy margins.', weight: 1.5),
        AppraisalCompetency(id: 'pipeline', label: 'Pipeline quality', description: 'Maintains qualified, forecastable opportunities.', weight: 1.2),
        AppraisalCompetency(id: 'conversion', label: 'Conversion effectiveness', description: 'Progresses opportunities and closes responsibly.', weight: 1.2),
        AppraisalCompetency(id: 'customer_success', label: 'Customer relationship', description: 'Builds long-term customer trust and value.', weight: 1.2),
        AppraisalCompetency(id: 'forecasting', label: 'Forecast accuracy', description: 'Provides timely and realistic forecasts.', weight: 1),
        AppraisalCompetency(id: 'documentation', label: 'CRM discipline', description: 'Maintains complete CRM and commercial records.', weight: .8),
      ],
    ),
    AppraisalTemplate(
      id: 'finance_accounts',
      name: 'Finance & Accounts',
      industry: 'Finance',
      competencies: <AppraisalCompetency>[
        AppraisalCompetency(id: 'accuracy', label: 'Financial accuracy', description: 'Maintains correct and well-supported financial records.', weight: 1.4),
        AppraisalCompetency(id: 'closing', label: 'Closing discipline', description: 'Completes period close reliably and on time.', weight: 1.2),
        AppraisalCompetency(id: 'compliance', label: 'Compliance & controls', description: 'Applies tax, audit, and internal-control requirements.', weight: 1.4),
        AppraisalCompetency(id: 'analysis', label: 'Financial analysis', description: 'Provides actionable variance and business insights.', weight: 1.1),
        AppraisalCompetency(id: 'cashflow', label: 'Cash-flow management', description: 'Improves collection, payment, and cash visibility.', weight: 1),
        AppraisalCompetency(id: 'documentation', label: 'Audit readiness', description: 'Maintains complete reconciliations and evidence.', weight: .9),
      ],
    ),
  ];

  static AppraisalTemplate byId(String? id) {
    final clean = (id ?? '').trim();
    for (final template in templates) {
      if (template.id == clean) return template;
    }
    return general;
  }

  static AppraisalTemplate forMember(Member member) {
    final explicit = member.appraisalTemplateId.trim();
    if (explicit.isNotEmpty) return byId(explicit);
    final haystack = '${member.industryDiscipline} ${member.effectiveDepartment} ${member.effectiveJobTitle}'.toLowerCase();
    if (haystack.contains('civil') || haystack.contains('construction') || haystack.contains('site')) return byId('civil_engineering');
    if (haystack.contains('mechanical')) return byId('mechanical_engineering');
    if (haystack.contains('electrical')) return byId('electrical_engineering');
    if (haystack.contains('quality') || haystack.contains('tester') || haystack.contains('qa')) return byId('quality_assurance');
    if (haystack.contains('human resource') || haystack.contains('people') || haystack.contains('hr')) return byId('human_resources');
    if (haystack.contains('sales') || haystack.contains('business development')) return byId('sales_business');
    if (haystack.contains('finance') || haystack.contains('account')) return byId('finance_accounts');
    if (haystack.contains('software') || haystack.contains('developer') || haystack.contains('engineering') || haystack.contains('it')) return byId('software_engineering');
    return general;
  }
}
