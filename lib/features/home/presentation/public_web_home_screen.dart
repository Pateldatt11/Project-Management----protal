import 'package:flutter/material.dart';

import '../../auth/presentation/auth_gate.dart';

class PublicWebHomeScreen extends StatelessWidget {
  const PublicWebHomeScreen({super.key, this.adminPortal = false});

  final bool adminPortal;

  void _openPortal(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/login'),
        builder: (_) => const AuthGate(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760;
    final pagePadding = compact ? 18.0 : size.width >= 1280 ? 72.0 : 38.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _HeroSection(
                compact: compact,
                pagePadding: pagePadding,
                adminPortal: adminPortal,
                onLogin: () => _openPortal(context),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePadding, compact ? 52 : 76, pagePadding, 0),
              sliver: const SliverToBoxAdapter(child: _TrustedStrip()),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePadding, compact ? 60 : 90, pagePadding, 0),
              sliver: SliverToBoxAdapter(child: _FeatureSection(compact: compact)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePadding, compact ? 64 : 92, pagePadding, 0),
              sliver: SliverToBoxAdapter(child: _WorkflowSection(compact: compact)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePadding, compact ? 64 : 92, pagePadding, 0),
              sliver: SliverToBoxAdapter(child: _RoleSection(compact: compact)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePadding, compact ? 64 : 92, pagePadding, 0),
              sliver: SliverToBoxAdapter(
                child: _SupportSection(compact: compact),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePadding, compact ? 64 : 92, pagePadding, 0),
              sliver: SliverToBoxAdapter(
                child: _FinalCta(onLogin: () => _openPortal(context)),
              ),
            ),
            SliverToBoxAdapter(child: _Footer(pagePadding: pagePadding)),
          ],
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.compact,
    required this.pagePadding,
    required this.adminPortal,
    required this.onLogin,
  });

  final bool compact;
  final double pagePadding;
  final bool adminPortal;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 720 : 760),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF07122D), Color(0xFF10295E), Color(0xFF193F91)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(top: -130, right: -70, child: _GlowOrb(size: 430, color: Color(0x335B8CFF))),
          const Positioned(bottom: -180, left: -100, child: _GlowOrb(size: 470, color: Color(0x2440D9B0))),
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pagePadding, 18, pagePadding, compact ? 54 : 70),
            child: Column(
              children: [
                _TopBar(compact: compact, onLogin: onLogin),
                SizedBox(height: compact ? 48 : 78),
                if (compact)
                  Column(
                    children: [
                      _HeroCopy(adminPortal: adminPortal, onLogin: onLogin, compact: compact),
                      const SizedBox(height: 38),
                      const _DashboardPreview(compact: true),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 10, child: _HeroCopy(adminPortal: adminPortal, onLogin: onLogin, compact: compact)),
                      const SizedBox(width: 54),
                      const Expanded(flex: 9, child: _DashboardPreview(compact: false)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.compact, required this.onLogin});
  final bool compact;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF6A8BFF), Color(0xFF54D8C2)]),
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [BoxShadow(color: Color(0x49618EFF), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: const Icon(Icons.auto_awesome_mosaic_rounded, color: Colors.white, size: 23),
        ),
        const SizedBox(width: 11),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PRIZAM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.7)),
            Text('WORKSPACE', style: TextStyle(color: Color(0xFF9EB5E8), fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 2.1)),
          ],
        ),
        const Spacer(),
        if (!compact) ...[
          const _NavText('Overview'),
          const _NavText('Workflow'),
          const _NavText('Teams'),
          const _NavText('IT Support'),
          const SizedBox(width: 14),
        ],
        OutlinedButton(
          onPressed: onLogin,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0x668EAAE9)),
            padding: EdgeInsets.symmetric(horizontal: compact ? 13 : 18, vertical: 15),
          ),
          child: Text(compact ? 'Login' : 'Sign in to portal', style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

class _NavText extends StatelessWidget {
  const _NavText(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(label, style: const TextStyle(color: Color(0xFFD5E1FF), fontWeight: FontWeight.w700)),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.adminPortal, required this.onLogin, required this.compact});
  final bool adminPortal;
  final VoidCallback onLogin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x1728D6A5),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x4A4CE2BC)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, color: Color(0xFF67E5C7), size: 17),
              SizedBox(width: 6),
              Text('ONE WORKSPACE • REAL-TIME DELIVERY', style: TextStyle(color: Color(0xFFB9F3E5), fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: .7)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          adminPortal ? 'Run projects, people, and support from one command center.' : 'Plan clearly. Deliver faster. Keep every team aligned.',
          style: TextStyle(color: Colors.white, fontSize: compact ? 40 : 58, fontWeight: FontWeight.w900, height: 1.02, letterSpacing: -1.6),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: const Text(
            'A modern project workspace for tasks, projects, timelines, employee collaboration, notifications, files, reports, and a dedicated IT support desk — built for web and mobile teams.',
            style: TextStyle(color: Color(0xFFC8D6F4), fontSize: 17, height: 1.55, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onLogin,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF173B89),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Open workspace', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            OutlinedButton.icon(
              onPressed: onLogin,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE5ECFF),
                side: const BorderSide(color: Color(0x557D9CD8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Role-based access', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const Wrap(
          spacing: 18,
          runSpacing: 9,
          children: [
            _HeroCheck('Responsive web portal'),
            _HeroCheck('Employee mobile app'),
            _HeroCheck('Realtime workspace data'),
          ],
        ),
      ],
    );
  }
}

class _HeroCheck extends StatelessWidget {
  const _HeroCheck(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFF59DDBD), size: 17),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Color(0xFFCAD8F7), fontWeight: FontWeight.w700, fontSize: 12)),
      ],
    );
  }
}

class _DashboardPreview extends StatelessWidget {
  const _DashboardPreview({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 650 : 720),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0x18FFFFFF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x3FFFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 44, offset: Offset(0, 22))],
      ),
      child: Container(
        height: compact ? 350 : 430,
        decoration: BoxDecoration(color: const Color(0xFFF7F9FD), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: compact ? 58 : 72,
              decoration: const BoxDecoration(
                color: Color(0xFF101D3D),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  const CircleAvatar(radius: 15, backgroundColor: Color(0xFF5C7EF5), child: Icon(Icons.auto_awesome_mosaic_rounded, size: 15, color: Colors.white)),
                  const SizedBox(height: 28),
                  for (final icon in [Icons.dashboard_rounded, Icons.folder_rounded, Icons.task_alt_rounded, Icons.timeline_rounded, Icons.support_agent_rounded])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Icon(icon, size: 19, color: icon == Icons.dashboard_rounded ? Colors.white : const Color(0xFF7084AF)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(compact ? 14 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: Text('Delivery overview', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF14213D)))),
                        Container(width: 34, height: 34, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE6ECFB)), child: const Icon(Icons.person_rounded, size: 18, color: Color(0xFF4563A8))),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(child: _PreviewMetric(label: 'Active projects', value: '12', accent: const Color(0xFF3159C8))),
                        const SizedBox(width: 9),
                        Expanded(child: _PreviewMetric(label: 'Tasks done', value: '84%', accent: const Color(0xFF129C7A))),
                        if (!compact) ...[
                          const SizedBox(width: 9),
                          const Expanded(child: _PreviewMetric(label: 'IT tickets', value: '07', accent: Color(0xFFE87A31))),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE7EBF3))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Project velocity', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF24314F))),
                                  const SizedBox(height: 14),
                                  Expanded(child: CustomPaint(painter: _ChartPainter(), child: const SizedBox.expand())),
                                ],
                              ),
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: const Color(0xFF14295A), borderRadius: BorderRadius.circular(15)),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('IT Support', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                                    SizedBox(height: 6),
                                    Text('Live service queue', style: TextStyle(color: Color(0xFF9FB5E6), fontSize: 11)),
                                    Spacer(),
                                    _QueueLine('Open', '4', Color(0xFF9D7BFF)),
                                    SizedBox(height: 9),
                                    _QueueLine('In progress', '2', Color(0xFF5A8FFF)),
                                    SizedBox(height: 9),
                                    _QueueLine('Resolved', '18', Color(0xFF46C9A5)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({required this.label, required this.value, required this.accent});
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFE7EBF3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF77839C), fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(color: accent, fontSize: 20, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class _QueueLine extends StatelessWidget {
  const _QueueLine(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 7),
      Expanded(child: Text(label, style: const TextStyle(color: Color(0xFFD6E2FF), fontSize: 11, fontWeight: FontWeight.w700))),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
    ]);
  }
}

class _TrustedStrip extends StatelessWidget {
  const _TrustedStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7ECF5))),
      child: const Wrap(
        spacing: 28,
        runSpacing: 14,
        alignment: WrapAlignment.spaceAround,
        children: [
          _TrustItem(Icons.shield_rounded, 'Role-based workspace'),
          _TrustItem(Icons.sync_rounded, 'Realtime collaboration'),
          _TrustItem(Icons.devices_rounded, 'Web + mobile ready'),
          _TrustItem(Icons.support_agent_rounded, 'Built-in IT support'),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: const Color(0xFF3159C8), size: 20),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Color(0xFF42516F), fontWeight: FontWeight.w800)),
    ]);
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const features = [
      _FeatureData(Icons.folder_copy_rounded, 'Project control', 'Track project ownership, scope, progress, milestones, teams, and delivery risk from one place.'),
      _FeatureData(Icons.task_alt_rounded, 'Task execution', 'Assign work, follow status, manage priority, comments, attachments, timelines, and completion flow.'),
      _FeatureData(Icons.groups_rounded, 'People & teams', 'Keep roles, team members, managers, workload, collaboration, and employee information connected.'),
      _FeatureData(Icons.insert_chart_rounded, 'Reports & visibility', 'Give leaders the right level of progress, operational, appraisal, and delivery visibility.'),
      _FeatureData(Icons.notifications_active_rounded, 'Private notifications', 'Keep work updates and direct actions visible to the people who actually need them.'),
      _FeatureData(Icons.support_agent_rounded, 'Support ticket desk', 'Employees can raise IT requests while authorized operational roles can raise broader support tickets.'),
    ];

    return Column(
      children: [
        const _SectionHeading(kicker: 'EVERYTHING CONNECTED', title: 'One workspace for the full delivery cycle', subtitle: 'Move from planning to execution without scattering work across disconnected tools.'),
        const SizedBox(height: 34),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1060 ? 3 : constraints.maxWidth >= 650 ? 2 : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: features.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: compact ? 210 : 220,
              ),
              itemBuilder: (_, index) => _FeatureCard(data: features[index], index: index),
            );
          },
        ),
      ],
    );
  }
}

class _FeatureData {
  const _FeatureData(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.data, required this.index});
  final _FeatureData data;
  final int index;

  @override
  Widget build(BuildContext context) {
    const accents = [Color(0xFF3159C8), Color(0xFF0E9F79), Color(0xFF805AD5), Color(0xFFE27730), Color(0xFFCD4A78), Color(0xFF197D9C)];
    final accent = accents[index % accents.length];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: const [BoxShadow(color: Color(0x0A10234A), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)), child: Icon(data.icon, color: accent)),
        const SizedBox(height: 18),
        Text(data.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF16213B))),
        const SizedBox(height: 8),
        Text(data.text, style: const TextStyle(color: Color(0xFF66738C), height: 1.5, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _WorkflowSection extends StatelessWidget {
  const _WorkflowSection({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _SectionHeading(alignment: CrossAxisAlignment.start, kicker: 'A CLEARER WORKFLOW', title: 'From request to result, every step stays visible', subtitle: 'Projects, tasks, files, updates, support tickets, and decisions remain connected to the people responsible for them.'),
        SizedBox(height: 28),
        _WorkflowStep(number: '01', title: 'Plan and assign', text: 'Define the project, team, owner, tasks, priorities, and expected delivery.'),
        _WorkflowStep(number: '02', title: 'Execute and collaborate', text: 'Employees update work, upload files, receive notifications, and keep progress current.'),
        _WorkflowStep(number: '03', title: 'Resolve blockers quickly', text: 'Raise support tickets for IT issues, QA defects, delivery blockers, incidents, access, or infrastructure problems.'),
        _WorkflowStep(number: '04', title: 'Review and report', text: 'Managers and admins get the visibility needed to keep delivery moving.'),
      ],
    );

    final visual = Container(
      height: 470,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFEEF3FF), Color(0xFFEAFBF7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFDDE6F6)),
      ),
      child: Stack(
        children: const [
          Positioned(left: 36, top: 52, child: _FloatingWorkCard(icon: Icons.folder_rounded, title: 'Website Revamp', subtitle: 'Project • 74% complete', width: 255)),
          Positioned(right: 32, top: 150, child: _FloatingWorkCard(icon: Icons.task_alt_rounded, title: 'QA validation', subtitle: 'Task • In testing', width: 235)),
          Positioned(left: 66, bottom: 58, child: _FloatingWorkCard(icon: Icons.support_agent_rounded, title: 'IT-4821093', subtitle: 'VPN access • In progress', width: 260)),
          Positioned(right: 60, bottom: 24, child: _FloatingDot()),
        ],
      ),
    );

    if (compact) {
      return Column(children: [content, const SizedBox(height: 34), visual]);
    }
    return Row(children: [Expanded(child: content), const SizedBox(width: 56), Expanded(child: visual)]);
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({required this.number, required this.title, required this.text});
  final String number;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 38, height: 38, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFE9EFFF), borderRadius: BorderRadius.circular(11)), child: Text(number, style: const TextStyle(color: Color(0xFF3159C8), fontWeight: FontWeight.w900, fontSize: 11))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B2945), fontSize: 16)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(color: Color(0xFF6B7891), height: 1.45)),
        ])),
      ]),
    );
  }
}

class _FloatingWorkCard extends StatelessWidget {
  const _FloatingWorkCard({required this.icon, required this.title, required this.subtitle, required this.width});
  final IconData icon;
  final String title;
  final String subtitle;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDCE4F2)), boxShadow: const [BoxShadow(color: Color(0x17102B5A), blurRadius: 24, offset: Offset(0, 12))]),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: const Color(0xFF3159C8), size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E2B47))),
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF7B879C), fontSize: 11, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }
}

class _FloatingDot extends StatelessWidget {
  const _FloatingDot();
  @override
  Widget build(BuildContext context) => Container(width: 72, height: 72, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF5E7CF0), Color(0xFF55D5BC)])));
}

class _RoleSection extends StatelessWidget {
  const _RoleSection({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const roles = [
      ('Admins', Icons.admin_panel_settings_rounded, 'Company-wide governance, settings, reports, people, projects, and IT ticket oversight.'),
      ('Managers & TLs', Icons.account_tree_rounded, 'Project and team execution visibility with task, timeline, and support queue awareness.'),
      ('QA / Testers', Icons.bug_report_rounded, 'Testing workflow plus access to review support tickets that can affect delivery.'),
      ('Employees', Icons.person_rounded, 'Focused mobile workspace for assigned work, files, notifications, and raising IT Support tickets.'),
      ('Support Teams', Icons.support_agent_rounded, 'Shared queue for IT and operational issues with controlled assignment, status, and replies.'),
    ];

    return Column(children: [
      const _SectionHeading(kicker: 'RIGHT ACCESS, RIGHT PEOPLE', title: 'A workspace that adapts to each role', subtitle: 'Every role sees the tools and information relevant to its responsibility.'),
      const SizedBox(height: 34),
      Wrap(
        spacing: 14,
        runSpacing: 14,
        alignment: WrapAlignment.center,
        children: roles
            .map((role) => Container(
                  width: compact ? 560 : 245,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFF111F43), borderRadius: BorderRadius.circular(20)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(role.$2, color: const Color(0xFF78A0FF), size: 28),
                    const SizedBox(height: 14),
                    Text(role.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                    const SizedBox(height: 7),
                    Text(role.$3, style: const TextStyle(color: Color(0xFFB8C6E6), height: 1.45, fontSize: 12)),
                  ]),
                ))
            .toList(),
      ),
    ]);
  }
}

class _SupportSection extends StatelessWidget {
  const _SupportSection({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final left = Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1C3473), Color(0xFF2759C7)]),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.support_agent_rounded, color: Color(0xFFBFD1FF), size: 34),
        SizedBox(height: 18),
        Text('Support tickets built into the same workspace', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28, height: 1.12)),
        SizedBox(height: 12),
        Text('Support requests are routed by ticket type and become visible in the authorized shared queue.', style: TextStyle(color: Color(0xFFD4E0FF), height: 1.5)),
        SizedBox(height: 22),
        _SupportPoint('Employees raise IT Support; authorized roles can raise operational ticket types'),
        _SupportPoint('IT Admin / DevOps can assign and change status'),
        _SupportPoint('Admins, managers, TLs, and QA can review the queue'),
        _SupportPoint('Ticket conversation stays attached to the issue'),
      ]),
    );

    final right = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Example support flow', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E293B))),
        SizedBox(height: 18),
        _TicketDemoRow(code: 'IT-4821093', title: 'VPN login failed', meta: 'High • Open', accent: Color(0xFFDC6B2F)),
        SizedBox(height: 10),
        _TicketDemoRow(code: 'IT-4820754', title: 'Software access request', meta: 'Medium • In progress', accent: Color(0xFF3159C8)),
        SizedBox(height: 10),
        _TicketDemoRow(code: 'IT-4819420', title: 'Wi-Fi disconnecting', meta: 'Medium • Resolved', accent: Color(0xFF129C7A)),
      ]),
    );

    if (compact) return Column(children: [left, const SizedBox(height: 18), right]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 11, child: left), const SizedBox(width: 18), Expanded(flex: 9, child: right)]);
  }
}

class _SupportPoint extends StatelessWidget {
  const _SupportPoint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFF63DFC1), size: 18),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: const TextStyle(color: Color(0xFFE3EAFF), fontWeight: FontWeight.w700, height: 1.4))),
      ]),
    );
  }
}

class _TicketDemoRow extends StatelessWidget {
  const _TicketDemoRow({required this.code, required this.title, required this.meta, required this.accent});
  final String code;
  final String title;
  final String meta;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE8EDF5))),
      child: Row(children: [
        Container(width: 8, height: 42, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(99))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code, style: const TextStyle(color: Color(0xFF71809A), fontSize: 10, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(title, style: const TextStyle(color: Color(0xFF23304A), fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(meta, style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800)),
        ])),
        const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
      ]),
    );
  }
}

class _FinalCta extends StatelessWidget {
  const _FinalCta({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0F1D3E), Color(0xFF1F4EA9)]),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 22,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          const SizedBox(
            width: 620,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your workspace is ready when you are.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 30)),
              SizedBox(height: 8),
              Text('Sign in to continue to your company dashboard or employee workspace.', style: TextStyle(color: Color(0xFFC4D3F4), height: 1.45)),
            ]),
          ),
          FilledButton.icon(
            onPressed: onLogin,
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF173B89), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in to workspace', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.kicker, required this.title, required this.subtitle, this.alignment = CrossAxisAlignment.center});
  final String kicker;
  final String title;
  final String subtitle;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final align = alignment == CrossAxisAlignment.center ? TextAlign.center : TextAlign.left;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(kicker, textAlign: align, style: const TextStyle(color: Color(0xFF3159C8), fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 11)),
        const SizedBox(height: 9),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Text(title, textAlign: align, style: const TextStyle(color: Color(0xFF14213D), fontSize: 34, fontWeight: FontWeight.w900, height: 1.12, letterSpacing: -.6))),
        const SizedBox(height: 10),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Text(subtitle, textAlign: align, style: const TextStyle(color: Color(0xFF6A7892), fontSize: 15, height: 1.55))),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.pagePadding});
  final double pagePadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pagePadding, 34, pagePadding, 36),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_mosaic_rounded, color: Color(0xFF3159C8), size: 20),
              SizedBox(width: 8),
              Text('PRIZAM WORKSPACE', style: TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w900, letterSpacing: .7)),
            ],
          ),
          Text('Project management • IT support • Team delivery', style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0DFFFFFF)..strokeWidth = 1;
    const step = 46.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFFE9EEF7)..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final line = Paint()
      ..color = const Color(0xFF3159C8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(0, size.height * .74)
      ..cubicTo(size.width * .18, size.height * .68, size.width * .20, size.height * .42, size.width * .34, size.height * .49)
      ..cubicTo(size.width * .50, size.height * .58, size.width * .55, size.height * .25, size.width * .68, size.height * .31)
      ..cubicTo(size.width * .80, size.height * .37, size.width * .86, size.height * .12, size.width, size.height * .18);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
