import 'package:flutter/material.dart';

import 'sdui_mobile_ui_config.dart';

/// Lightweight mock body for QA/admin preview when live task/project data is not loaded yet.
/// Replace this with your existing task/project/profile renderers in production.
class SduiEditorialPreviewBody extends StatelessWidget {
  const SduiEditorialPreviewBody({super.key, required this.config, required this.currentTab});

  final SduiMobileUiConfig config;
  final String currentTab;

  @override
  Widget build(BuildContext context) {
    switch (currentTab) {
      case 'tasks':
        return _TasksPreview(config: config);
      case 'projects':
        return _ProjectsPreview(config: config);
      case 'profile':
        return _ProfilePreview(config: config);
      case 'home':
      default:
        return _HomePreview(config: config);
    }
  }
}

class _HomePreview extends StatelessWidget {
  const _HomePreview({required this.config});
  final SduiMobileUiConfig config;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: config.horizontalPadding),
      children: const [
        _HeroDeadlineCard(),
        SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _MetricTile(title: 'Today', value: '06', label: 'Tasks')),
            SizedBox(width: 12),
            Expanded(child: _MetricTile(title: 'Open', value: '18', label: 'Assigned')),
          ],
        ),
        SizedBox(height: 18),
        _SectionTitle('Current work'),
        SizedBox(height: 10),
        _TaskRow(title: 'Finalize landing page', tag: 'High', progress: 0.72),
        _TaskRow(title: 'Review dashboard cards', tag: 'Medium', progress: 0.45),
        SizedBox(height: 18),
        _SectionTitle('Project progress'),
        SizedBox(height: 10),
        _ProjectCard(title: 'Website Redesign', subtitle: '12 of 18 tasks completed', progress: 0.66),
      ],
    );
  }
}

class _TasksPreview extends StatelessWidget {
  const _TasksPreview({required this.config});
  final SduiMobileUiConfig config;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: config.horizontalPadding),
      children: const [
        _SearchPill(label: 'Search tasks'),
        SizedBox(height: 14),
        _ChipRow(chips: ['New Arrival', 'In Progress', 'Completed']),
        SizedBox(height: 16),
        _TaskRow(title: 'Create profile card UI', tag: 'High', progress: 0.78),
        _TaskRow(title: 'Fix notification accept flow', tag: 'Urgent', progress: 0.32),
        _TaskRow(title: 'Add file upload state', tag: 'Normal', progress: 0.54),
      ],
    );
  }
}

class _ProjectsPreview extends StatelessWidget {
  const _ProjectsPreview({required this.config});
  final SduiMobileUiConfig config;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: config.horizontalPadding),
      children: const [
        _SearchPill(label: 'Search projects'),
        SizedBox(height: 14),
        _ChipRow(chips: ['All', 'In Progress', 'Completed']),
        SizedBox(height: 16),
        _ProjectCard(title: 'Website Redesign', subtitle: 'Frontend sprint active', progress: 0.64),
        _ProjectCard(title: 'Admin Panel', subtitle: 'Firebase publish flow', progress: 0.48),
        _ProjectCard(title: 'Mobile App', subtitle: 'SDUI renderer upgrade', progress: 0.71),
      ],
    );
  }
}

class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview({required this.config});
  final SduiMobileUiConfig config;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: config.horizontalPadding),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 28, backgroundColor: Color(0xFF151515), child: Text('D', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              SizedBox(height: 14),
              Text('Darshan Sangani', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
              SizedBox(height: 4),
              Text('Product Admin • Online', style: TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600)),
              SizedBox(height: 18),
              _ProfileLine(label: 'Company', value: 'Management Dashboard'),
              _ProfileLine(label: 'Department', value: 'Operations'),
              _ProfileLine(label: 'Role', value: 'Admin'),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroDeadlineCard extends StatelessWidget {
  const _HeroDeadlineCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 26, offset: const Offset(0, 14))],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Deadline timer', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
          SizedBox(height: 12),
          Text('02d 14h', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
          SizedBox(height: 6),
          Text('Website redesign sprint', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.title, required this.value, required this.label});
  final String title;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1)),
        Text(label, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.title, required this.tag, required this.progress});
  final String title;
  final String tag;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2))),
          _StatusPill(label: tag),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: const Color(0xFFF0ECE3), color: const Color(0xFF151515)),
        ),
      ]),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.title, required this.subtitle, required this.progress});
  final String title;
  final String subtitle;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Row(children: [
        SizedBox(
          height: 48,
          width: 48,
          child: CircularProgressIndicator(value: progress, strokeWidth: 6, backgroundColor: const Color(0xFFF0ECE3), color: const Color(0xFF151515)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600)),
        ])),
        const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Color(0xFF76736D)),
      ]),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: _cardDecoration(radius: 22),
      child: Row(children: [
        const Icon(Icons.search_rounded, color: Color(0xFF76736D)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips});
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < chips.length; i++)
          Chip(
            label: Text(chips[i]),
            backgroundColor: i == 0 ? const Color(0xFF151515) : Colors.white,
            labelStyle: TextStyle(color: i == 0 ? Colors.white : const Color(0xFF151515), fontWeight: FontWeight.w700),
            side: const BorderSide(color: Color(0xFFECE7DA)),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFF4F0E8), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5));
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w700))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

BoxDecoration _cardDecoration({double radius = 24}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: const Color(0xFFECE7DA)),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0, 8))],
  );
}
