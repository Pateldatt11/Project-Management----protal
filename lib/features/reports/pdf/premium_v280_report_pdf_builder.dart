import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/app_enums.dart';
import '../../../data/models/member.dart';
import '../../../data/models/monthly_analytics_snapshot.dart';
import '../../../data/models/project.dart';
import '../../../data/models/report.dart';
import '../../../data/models/task.dart';

/// Premium eight-page management report that follows the supplied V280 design.
class PremiumV280ReportPdfBuilder {
  const PremiumV280ReportPdfBuilder();

  Future<Uint8List> build({
    required ReportModel report,
    required List<Project> projects,
    required List<ProjectTask> tasks,
    required List<Member> members,
    MonthlyAnalyticsSnapshot? monthlySnapshot,
    int minPages = 8,
  }) async {
    final data = _PremiumReportData.from(
      report: report,
      projects: projects,
      tasks: tasks,
      members: members,
      monthlySnapshot: monthlySnapshot,
    );

    // Dynamic registered company name pulled from metrics or snapshot
    final companyName = report.metrics['companyName']?.toString().trim().isNotEmpty == true
        ? report.metrics['companyName'].toString().trim()
        : 'Company Workspace';

    final pdf = pw.Document(
      title: report.reportType,
      author: companyName,
      creator: '$companyName Premium Report Generator',
      subject: report.summary,
      keywords: 'monthly,projects,tasks,timeline,appraisal,workload,risk,pdf',
    );

    pdf.addPage(_pageOne(report, data, companyName));
    pdf.addPage(_pageTwo(data, companyName));
    pdf.addPage(_pageThree(data, companyName));
    pdf.addPage(_pageFour(data, companyName));
    pdf.addPage(_pageFive(data, companyName));
    pdf.addPage(_pageSix(data, companyName));
    pdf.addPage(_pageSeven(report, data, companyName));
    pdf.addPage(_pageEight(report, data, companyName));

    if (data.projects.length > 5) {
      for (final entry in _withIndex(_chunk(data.projects.skip(5).toList(), 12))) {
        pdf.addPage(_projectContinuationPage(entry.value, entry.key + 1, companyName));
      }
    }
    if (data.tasks.length > 7) {
      for (final entry in _withIndex(_chunk(data.tasks.skip(7).toList(), 14))) {
        pdf.addPage(_taskContinuationPage(entry.value, entry.key + 1, companyName));
      }
    }
    if (data.members.length > 5) {
      for (final entry in _withIndex(_chunk(data.members.skip(5).toList(), 12))) {
        pdf.addPage(_memberContinuationPage(entry.value, entry.key + 1, companyName));
      }
    }

    var currentCount = 8;
    currentCount += data.projects.length > 5 ? ((data.projects.length - 5) / 12).ceil() : 0;
    currentCount += data.tasks.length > 7 ? ((data.tasks.length - 7) / 14).ceil() : 0;
    currentCount += data.members.length > 5 ? ((data.members.length - 5) / 12).ceil() : 0;
    while (currentCount < math.max(8, minPages)) {
      currentCount += 1;
      pdf.addPage(_minimumContinuationPage(report, currentCount, companyName));
    }

    return pdf.save();
  }

  pw.Page _pageOne(ReportModel report, _PremiumReportData data, String companyName) {
    final projects = data.projects.take(5).toList(growable: false);
    return _premiumPage(
      accent: _PremiumTheme.blue,
      title: 'Monthly Company Report',
      subtitle: 'A premium management report generated for $companyName.',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _periodHero(report, data, companyName),
        pw.SizedBox(height: 17),
        _metricRow(<_MetricCardData>[
          _MetricCardData('Projects', '${data.projects.length}', 'P', _PremiumTheme.purple),
          _MetricCardData('Work items', '${data.tasks.length}/${data.tasks.length}', 'T', _PremiumTheme.blue),
          _MetricCardData('Completion', '${data.overallCompletion}%', '%', _PremiumTheme.green),
          _MetricCardData('Late tasks', '${data.overdueTasks}', '!', _PremiumTheme.red),
        ]),
        pw.SizedBox(height: 20),
        _sectionTitle('Executive Summary', _PremiumTheme.blue),
        pw.SizedBox(height: 9),
        pw.Text(
          data.executiveSummary,
          style: _PremiumTheme.body,
          maxLines: 3,
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Expanded(child: _callout('Top Risk', data.topRisk, _PremiumTheme.orange, _PremiumTheme.softOrange)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _callout('Best Signal', data.bestSignal, _PremiumTheme.green, _PremiumTheme.softGreen)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _callout('Next Action', data.nextAction, _PremiumTheme.blue, _PremiumTheme.softBlue)),
          ],
        ),
        pw.SizedBox(height: 18),
        _sectionTitle('Portfolio Snapshot', _PremiumTheme.purple),
        pw.SizedBox(height: 9),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Expanded(
              flex: 5,
              child: _table(
                headers: const <String>['Project', 'Status', 'Done', 'Owner', 'Schedule'],
                flexes: const <int>[30, 16, 10, 16, 22],
                rows: projects
                    .map((project) => <String>[
                          project.name,
                          project.status,
                          '${project.progress}%',
                          project.owner,
                          '${_dateShort(project.start)} - ${_dateShort(project.end)}',
                        ])
                    .toList(growable: false),
                emptyMessage: 'No projects are available in this report scope.',
                rowHeight: 22,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.SizedBox(
              width: 105,
              child: pw.Column(
                children: <pw.Widget>[
                  _donutWithLabel(
                    percent: data.overallCompletion,
                    color: _PremiumTheme.green,
                    colorHex: _PremiumTheme.greenHex,
                    centerLabel: '${data.overallCompletion}%',
                    centerCaption: 'HEALTH',
                    size: 92,
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text('Overall delivery', style: _PremiumTheme.smallBold, textAlign: pw.TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Page _pageTwo(_PremiumReportData data, String companyName) {
    final projects = data.projects.take(5).toList(growable: false);
    final statusValues = data.projectStatusDistribution.values.toList(growable: false);
    final statusColors = <PdfColor>[
      _PremiumTheme.green,
      _PremiumTheme.blue,
      _PremiumTheme.purple,
      _PremiumTheme.orange,
      _PremiumTheme.red,
    ];
    return _premiumPage(
      accent: _PremiumTheme.purple,
      title: 'Portfolio Delivery Health',
      subtitle: 'Project-level health, schedule confidence, status mix and forecast for $companyName.',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _sectionTitle('Status Distribution', _PremiumTheme.purple),
        pw.SizedBox(height: 12),
        _panel(
          padding: const pw.EdgeInsets.fromLTRB(25, 22, 25, 18),
          child: pw.Column(
            children: <pw.Widget>[
              _segmentedBar(statusValues, statusColors, height: 20),
              pw.SizedBox(height: 20),
              _legendRow(
                data.projectStatusDistribution.keys.toList(growable: false),
                statusColors,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 17),
        _sectionTitle('Project Health Matrix', _PremiumTheme.blue),
        pw.SizedBox(height: 9),
        _table(
          headers: const <String>['Project', 'Status', 'Done', 'Owner', 'Start', 'End'],
          flexes: const <int>[30, 15, 9, 15, 11, 11],
          rows: projects
              .map((project) => <String>[
                    project.name,
                    project.status,
                    '${project.progress}%',
                    project.owner,
                    _dateShort(project.start),
                    _dateShort(project.end),
                  ])
              .toList(growable: false),
          emptyMessage: 'No projects are available in this report scope.',
          rowHeight: 24,
        ),
        pw.SizedBox(height: 17),
        _sectionTitle('Progress & Forecast', _PremiumTheme.teal),
        pw.SizedBox(height: 8),
        ...projects.map((project) => _labelProgressRow(project.name, project.progress, _projectColor(project), width: 265)),
        pw.SizedBox(height: 10),
        _wideInsight(
          title: 'Portfolio forecast',
          message: data.portfolioForecast,
          color: _PremiumTheme.purple,
          background: _PremiumTheme.softPurple,
        ),
      ],
    );
  }

  pw.Page _pageThree(_PremiumReportData data, String companyName) {
    final tasks = data.tasks.take(7).toList(growable: false);
    return _premiumPage(
      accent: _PremiumTheme.green,
      title: 'Task Execution & Throughput',
      subtitle: 'Task-level KPIs, priority mix, throughput trend and high-value work.',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _metricRow(<_MetricCardData>[
          _MetricCardData('Total tasks', '${data.tasks.length}', 'T', _PremiumTheme.blue),
          _MetricCardData('Completed', '${data.completedTasks}', 'C', _PremiumTheme.green),
          _MetricCardData('Open', '${data.openTasks}', 'O', _PremiumTheme.orange),
          _MetricCardData('Overdue', '${data.overdueTasks}', '!', _PremiumTheme.red),
        ]),
        pw.SizedBox(height: 20),
        _sectionTitle('Task Status & Priority', _PremiumTheme.green),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Expanded(
              child: _panel(
                padding: const pw.EdgeInsets.all(15),
                child: pw.Row(
                  children: <pw.Widget>[
                    _donutWithLabel(
                      percent: data.taskCompletion,
                      color: _PremiumTheme.green,
                      colorHex: _PremiumTheme.greenHex,
                      centerLabel: '${data.taskCompletion}%',
                      centerCaption: 'DONE',
                      size: 88,
                    ),
                    pw.SizedBox(width: 15),
                    pw.Expanded(
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: <pw.Widget>[
                          _miniDistribution('Completed', data.completedTasks, data.tasks.length, _PremiumTheme.green),
                          _miniDistribution('In progress', data.inProgressTasks, data.tasks.length, _PremiumTheme.blue),
                          _miniDistribution('Review', data.reviewTasks, data.tasks.length, _PremiumTheme.purple),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _panel(
                padding: const pw.EdgeInsets.all(17),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text('Priority mix', style: _PremiumTheme.cardTitle),
                    pw.SizedBox(height: 19),
                    _segmentedBar(
                      <int>[
                        data.priorityDistribution['Critical'] ?? 0,
                        data.priorityDistribution['High'] ?? 0,
                        data.priorityDistribution['Medium'] ?? 0,
                        data.priorityDistribution['Low'] ?? 0,
                      ],
                      <PdfColor>[
                        _PremiumTheme.red,
                        _PremiumTheme.orange,
                        _PremiumTheme.blue,
                        _PremiumTheme.teal,
                      ],
                      height: 18,
                    ),
                    pw.SizedBox(height: 20),
                    _legendRow(
                      const <String>['Critical', 'High', 'Medium', 'Low'],
                      const <PdfColor>[
                        _PremiumTheme.red,
                        _PremiumTheme.orange,
                        _PremiumTheme.blue,
                        _PremiumTheme.teal,
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 17),
        _sectionTitle('Weekly Throughput', _PremiumTheme.blue),
        pw.SizedBox(height: 9),
        _panel(
          padding: const pw.EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: pw.SizedBox(
            height: 82,
            child: pw.SvgImage(svg: _lineChartSvg(data.weeklyThroughput, _PremiumTheme.blueHex), fit: pw.BoxFit.fill),
          ),
        ),
        pw.SizedBox(height: 17),
        _sectionTitle('Priority Task Table', _PremiumTheme.orange),
        pw.SizedBox(height: 9),
        _table(
          headers: const <String>['Task', 'Project', 'Owner', 'Status', 'Priority', 'Done', 'Due'],
          flexes: const <int>[29, 14, 13, 14, 11, 8, 9],
          rows: tasks
              .map((task) => <String>[
                    task.title,
                    task.projectName,
                    task.owner,
                    task.status,
                    task.priority,
                    '${task.progress}%',
                    _dateShort(task.due),
                  ])
              .toList(growable: false),
          emptyMessage: 'No tasks are available in this report scope.',
          rowHeight: 21,
          fontSize: 7.1,
        ),
      ],
    );
  }

  pw.Page _pageFour(_PremiumReportData data, String companyName) {
    final tasks = data.timelineTasks.take(6).toList(growable: false);
    return _premiumPage(
      accent: _PremiumTheme.cyan,
      title: 'Timeline, Dependencies & Milestones',
      subtitle: 'A graphical schedule view for $companyName.',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _sectionTitle('Delivery Timeline', _PremiumTheme.cyan),
        pw.SizedBox(height: 14),
        _timelinePanel(data, tasks),
        pw.SizedBox(height: 19),
        _sectionTitle('Critical Path & Milestones', _PremiumTheme.red),
        pw.SizedBox(height: 12),
        _wideInsight(
          title: 'Critical chain',
          message: data.criticalChain,
          color: _PremiumTheme.red,
          background: _PremiumTheme.softRed,
        ),
        pw.Spacer(),
        _legendRow(
          const <String>['In progress', 'Completed', 'Review', 'At risk', 'Dependency', 'Today'],
          const <PdfColor>[
            _PremiumTheme.blue,
            _PremiumTheme.green,
            _PremiumTheme.purple,
            _PremiumTheme.orange,
            _PremiumTheme.teal,
            _PremiumTheme.red,
          ],
        ),
      ],
    );
  }

  pw.Page _pageFive(_PremiumReportData data, String companyName) {
    final members = data.members.take(5).toList(growable: false);
    final roleValues = data.roleDistribution.values.toList(growable: false);
    final roleColors = <PdfColor>[
      _PremiumTheme.blue,
      _PremiumTheme.purple,
      _PremiumTheme.red,
      _PremiumTheme.cyan,
      _PremiumTheme.orange,
      _PremiumTheme.green,
    ];
    final roleHex = <String>[
      _PremiumTheme.blueHex,
      _PremiumTheme.purpleHex,
      _PremiumTheme.redHex,
      _PremiumTheme.cyanHex,
      _PremiumTheme.orangeHex,
      _PremiumTheme.greenHex,
    ];
    return _premiumPage(
      accent: _PremiumTheme.purple,
      title: 'Team Capacity & Workload',
      subtitle: 'Workload, capacity, online status and utilization across personnel.',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _metricRow(<_MetricCardData>[
          _MetricCardData('Members', '${data.members.length}', 'M', _PremiumTheme.purple),
          _MetricCardData('Online now', '${data.onlineMembers}', 'O', _PremiumTheme.green),
          _MetricCardData('Assigned', '${data.totalAssigned}', 'A', _PremiumTheme.blue),
          _MetricCardData('Avg utilization', '${data.averageUtilization}%', '%', _PremiumTheme.orange),
        ]),
        pw.SizedBox(height: 20),
        _sectionTitle('Role & Capacity Distribution', _PremiumTheme.purple),
        pw.SizedBox(height: 11),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Expanded(
              child: _panel(
                padding: const pw.EdgeInsets.all(15),
                child: pw.Row(
                  children: <pw.Widget>[
                    _segmentedDonutWithLabel(
                      values: roleValues,
                      colorHex: roleHex,
                      centerLabel: '${data.roleDistribution.length}',
                      centerCaption: 'ROLES',
                      size: 88,
                    ),
                    pw.SizedBox(width: 15),
                    pw.Expanded(child: _verticalLegend(data.roleDistribution.keys.toList(growable: false), roleColors)),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _panel(
                padding: const pw.EdgeInsets.all(17),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text('Capacity vs utilization', style: _PremiumTheme.cardTitle),
                    pw.SizedBox(height: 12),
                    ...members.take(4).map((member) => _capacityMiniRow(member)),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 17),
        _sectionTitle('Member Workload', _PremiumTheme.blue),
        pw.SizedBox(height: 8),
        ...members.map(_workloadRow),
        if (members.isEmpty)
          _wideInsight(
            title: 'No team members in scope',
            message: 'Select a project or company scope that contains assigned members.',
            color: _PremiumTheme.slate,
            background: _PremiumTheme.panel,
          ),
      ],
    );
  }

  pw.Page _pageSix(_PremiumReportData data, String companyName) {
    final members = data.members.take(5).toList(growable: false);
    return _premiumPage(
      accent: _PremiumTheme.orange,
      title: 'Appraisal & Performance Intelligence',
      subtitle: 'Review coverage, score distribution, performance trend and manager notes.',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _metricRow(<_MetricCardData>[
          _MetricCardData('Reviewed', '${data.reviewedMembers}/${data.members.length}', 'R', _PremiumTheme.orange),
          _MetricCardData('Avg score', '${data.averageScore}%', '%', _PremiumTheme.blue),
          _MetricCardData('High rating', '${data.highRatingMembers}', 'H', _PremiumTheme.green),
          _MetricCardData('Needs follow-up', '${data.followUpMembers}', '!', _PremiumTheme.red),
        ]),
        pw.SizedBox(height: 20),
        _sectionTitle('Performance Score Distribution', _PremiumTheme.orange),
        pw.SizedBox(height: 11),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Expanded(
              child: _panel(
                padding: const pw.EdgeInsets.all(15),
                child: pw.Row(
                  children: <pw.Widget>[
                    _segmentedDonutWithLabel(
                      values: <int>[data.highRatingMembers, data.mediumRatingMembers, data.followUpMembers],
                      colorHex: const <String>[
                        _PremiumTheme.greenHex,
                        _PremiumTheme.orangeHex,
                        _PremiumTheme.redHex,
                      ],
                      centerLabel: '${data.averageScore}%',
                      centerCaption: 'AVERAGE',
                      size: 92,
                    ),
                    pw.SizedBox(width: 16),
                    pw.Expanded(
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: <pw.Widget>[
                          _miniDistribution('High', data.highRatingMembers, math.max(1, data.members.length), _PremiumTheme.green),
                          _miniDistribution('Medium', data.mediumRatingMembers, math.max(1, data.members.length), _PremiumTheme.orange),
                          _miniDistribution('Follow-up', data.followUpMembers, math.max(1, data.members.length), _PremiumTheme.red),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _panel(
                padding: const pw.EdgeInsets.all(17),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text('Six-month score trend', style: _PremiumTheme.cardTitle),
                    pw.SizedBox(height: 7),
                    pw.SizedBox(
                      height: 88,
                      child: pw.SvgImage(
                        svg: _lineChartSvg(data.appraisalTrend, _PremiumTheme.orangeHex, labels: const <String>['Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul']),
                        fit: pw.BoxFit.fill,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 17),
        _sectionTitle('Member Performance', _PremiumTheme.purple),
        pw.SizedBox(height: 9),
        _table(
          headers: const <String>['Member', 'Role', 'Tasks', 'Done', 'Score', 'Rating'],
          flexes: const <int>[27, 18, 9, 9, 10, 12],
          rows: members
              .map((member) => <String>[
                    member.name,
                    member.role,
                    '${member.assigned}',
                    '${member.completed}',
                    '${member.score}%',
                    member.rating,
                  ])
              .toList(growable: false),
          emptyMessage: 'No appraisal data is available in this report scope.',
          rowHeight: 24,
        ),
        pw.SizedBox(height: 16),
        _sectionTitle('Manager Insights', _PremiumTheme.blue),
        pw.SizedBox(height: 8),
        _insightStrip('Strongest delivery', data.strongestDelivery, _PremiumTheme.green, _PremiumTheme.softGreen),
        _insightStrip('Coaching focus', data.coachingFocus, _PremiumTheme.orange, _PremiumTheme.softOrange),
        _insightStrip('Review governance', data.reviewGovernance, _PremiumTheme.blue, _PremiumTheme.softBlue),
      ],
    );
  }

  pw.Page _pageSeven(ReportModel report, _PremiumReportData data, String companyName) {
    final risks = data.risks.take(3).toList(growable: false);
    return _premiumPage(
      accent: _PremiumTheme.red,
      title: 'Risk, Quality & Notification Operations',
      subtitle: 'Operational risks, quality gates and FCM/notification readiness.',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _sectionTitle('Risk Matrix', _PremiumTheme.red),
        pw.SizedBox(height: 13),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Expanded(child: _riskMatrix(risks)),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _panel(
                padding: const pw.EdgeInsets.all(17),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text('Active Management Risks', style: _PremiumTheme.cardTitle),
                    pw.SizedBox(height: 10),
                    ...risks.map(_riskRow),
                    if (risks.isEmpty)
                      pw.Text('No active management risk was detected.', style: _PremiumTheme.body),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 19),
        _sectionTitle('FCM / Notification Readiness', _PremiumTheme.blue),
        pw.SizedBox(height: 10),
        _readinessRow('Foreground delivery', data.foregroundReadiness, _PremiumTheme.green),
        _readinessRow('Background delivery', data.backgroundReadiness, _PremiumTheme.blue),
        _readinessRow('Terminated fallback', data.terminatedReadiness, _PremiumTheme.purple),
        _readinessRow('Accept action logging', data.acceptLoggingReadiness, _PremiumTheme.teal),
        pw.SizedBox(height: 15),
        _wideInsight(
          title: 'Release gate',
          message: data.releaseGate,
          color: _PremiumTheme.blue,
          background: _PremiumTheme.softBlue,
        ),
      ],
    );
  }

  pw.Page _pageEight(ReportModel report, _PremiumReportData data, String companyName) {
    final actions = data.recommendedActions;
    return _premiumPage(
      accent: _PremiumTheme.teal,
      title: 'Management Actions, Audit & Export',
      subtitle: 'Recommended actions, report provenance, scope metadata and export controls.',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _sectionTitle('Recommended Actions', _PremiumTheme.teal),
        pw.SizedBox(height: 10),
        for (var index = 0; index < actions.length; index++)
          _actionCard(
            number: (index + 1).toString().padLeft(2, '0'),
            title: actions[index].title,
            description: actions[index].description,
            color: <PdfColor>[
              _PremiumTheme.blue,
              _PremiumTheme.purple,
              _PremiumTheme.green,
              _PremiumTheme.orange,
            ][index % 4],
            background: <PdfColor>[
              _PremiumTheme.softBlue,
              _PremiumTheme.softPurple,
              _PremiumTheme.softGreen,
              _PremiumTheme.softOrange,
            ][index % 4],
          ),
        pw.SizedBox(height: 18),
        _sectionTitle('Report Audit & Scope', _PremiumTheme.blue),
        pw.SizedBox(height: 9),
        _table(
          headers: const <String>['Field', 'Value'],
          flexes: const <int>[26, 70],
          rows: <List<String>>[
            <String>['Registered company', companyName],
            <String>['Report type', report.reportType],
            <String>['Project scope', data.scopeLabel],
            <String>['Minimum pages', '8'],
            <String>['Dynamic overflow', 'Enabled - additional pages generated from real data'],
            <String>['Data sources', 'Projects, tasks, members, timeline, appraisal, workload, notifications'],
            <String>['Generated by', data.generatedBy],
            <String>['Permission', 'Admin / PM / TL can generate and export'],
            <String>['Export formats', 'PDF, CSV, printable preview'],
          ],
          rowHeight: 23,
        ),
        pw.SizedBox(height: 15),
        _sectionTitle('Export Assurance', _PremiumTheme.purple),
        pw.SizedBox(height: 9),
        _wideInsight(
          title: 'Production behavior',
          message: 'The PDF always contains at least eight meaningful pages. Larger datasets automatically add clean continuation pages with repeated headers, page numbers and safe table breaks.',
          color: _PremiumTheme.purple,
          background: _PremiumTheme.softPurple,
        ),
      ],
    );
  }

  pw.Page _projectContinuationPage(List<_PremiumProject> projects, int index, String companyName) {
    return _premiumPage(
      accent: _PremiumTheme.purple,
      title: 'Portfolio Continuation',
      subtitle: 'Additional project rows - page $index',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _sectionTitle('Additional Project Health', _PremiumTheme.purple),
        pw.SizedBox(height: 12),
        _table(
          headers: const <String>['Project', 'Status', 'Done', 'Owner', 'Start', 'End'],
          flexes: const <int>[30, 15, 9, 15, 11, 11],
          rows: projects
              .map((project) => <String>[
                    project.name,
                    project.status,
                    '${project.progress}%',
                    project.owner,
                    _dateShort(project.start),
                    _dateShort(project.end),
                  ])
              .toList(growable: false),
          rowHeight: 28,
        ),
      ],
    );
  }

  pw.Page _taskContinuationPage(List<_PremiumTask> tasks, int index, String companyName) {
    return _premiumPage(
      accent: _PremiumTheme.green,
      title: 'Task Execution Continuation',
      subtitle: 'Additional task rows - page $index',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _sectionTitle('Additional Priority Tasks', _PremiumTheme.green),
        pw.SizedBox(height: 12),
        _table(
          headers: const <String>['Task', 'Project', 'Owner', 'Status', 'Priority', 'Done', 'Due'],
          flexes: const <int>[29, 14, 13, 14, 11, 8, 9],
          rows: tasks
              .map((task) => <String>[
                    task.title,
                    task.projectName,
                    task.owner,
                    task.status,
                    task.priority,
                    '${task.progress}%',
                    _dateShort(task.due),
                  ])
              .toList(growable: false),
          rowHeight: 27,
          fontSize: 7.4,
        ),
      ],
    );
  }

  pw.Page _memberContinuationPage(List<_PremiumMember> members, int index, String companyName) {
    return _premiumPage(
      accent: _PremiumTheme.orange,
      title: 'Team & Appraisal Continuation',
      subtitle: 'Additional member rows - page $index',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _sectionTitle('Additional Member Performance', _PremiumTheme.orange),
        pw.SizedBox(height: 12),
        _table(
          headers: const <String>['Member', 'Role', 'Assigned', 'Done', 'Utilization', 'Score', 'Rating'],
          flexes: const <int>[25, 17, 10, 9, 12, 9, 12],
          rows: members
              .map((member) => <String>[
                    member.name,
                    member.role,
                    '${member.assigned}',
                    '${member.completed}',
                    '${member.utilization}%',
                    '${member.score}%',
                    member.rating,
                  ])
              .toList(growable: false),
          rowHeight: 28,
        ),
      ],
    );
  }

  pw.Page _minimumContinuationPage(ReportModel report, int pageIndex, String companyName) {
    return _premiumPage(
      accent: _PremiumTheme.blue,
      title: 'Report Continuation',
      subtitle: 'Minimum page guarantee - page $pageIndex',
      companyName: companyName,
      body: (context) => <pw.Widget>[
        _wideInsight(
          title: 'Dynamic report page',
          message: 'This continuation page preserves the requested minimum report length. It is automatically replaced by real project, task, team, appraisal, timeline or risk data when the selected workspace contains more records.',
          color: _PremiumTheme.blue,
          background: _PremiumTheme.softBlue,
        ),
        pw.SizedBox(height: 18),
        _table(
          headers: const <String>['Field', 'Value'],
          flexes: const <int>[30, 70],
          rows: <List<String>>[
            <String>['Registered company', companyName],
            <String>['Report type', report.reportType],
            <String>['Period', report.period],
            <String>['Status', report.status],
            <String>['Page', '$pageIndex'],
          ],
          rowHeight: 28,
        ),
      ],
    );
  }

  pw.Page _premiumPage({
    required PdfColor accent,
    required String title,
    required String subtitle,
    required String companyName,
    required List<pw.Widget> Function(pw.Context context) body,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Column(
        children: <pw.Widget>[
          _pageHeader(context, accent, companyName),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(30, 10, 30, 7),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(title, style: _PremiumTheme.pageTitle),
                  pw.SizedBox(height: 3),
                  pw.Text(subtitle, style: _PremiumTheme.subtitle, maxLines: 2),
                  pw.SizedBox(height: 19),
                  ...body(context),
                ],
              ),
            ),
          ),
          _pageFooter(context, accent, companyName),
        ],
      ),
    );
  }

  pw.Widget _pageHeader(pw.Context context, PdfColor accent, String companyName) {
    return pw.Container(
      height: 68,
      color: _PremiumTheme.navy,
      padding: const pw.EdgeInsets.symmetric(horizontal: 27),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Container(
            width: 34,
            height: 34,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Text(
              companyName.isNotEmpty ? companyName[0].toUpperCase() : 'C',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  companyName,
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Enterprise reporting intelligence',
                  style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Text('Page ${context.pageNumber}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFFD8E1F0))),
        ],
      ),
    );
  }

  pw.Widget _pageFooter(pw.Context context, PdfColor accent, String companyName) {
    return pw.Container(
      height: 35,
      margin: const pw.EdgeInsets.symmetric(horizontal: 30),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _PremiumTheme.border, width: .65)),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Container(width: 35, height: 5, decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(999))),
          pw.SizedBox(width: 8),
          pw.Text('Generated for $companyName - confidential internal report', style: _PremiumTheme.footer),
          pw.Spacer(),
          pw.Text('PDF / CSV export  |  Page ${context.pageNumber} of ${context.pagesCount}', style: _PremiumTheme.footer),
        ],
      ),
    );
  }

  pw.Widget _periodHero(ReportModel report, _PremiumReportData data, String companyName) {
    return pw.Container(
      height: 82,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: pw.BoxDecoration(
        color: _PremiumTheme.softBlue,
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: _PremiumTheme.blueBorder),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: <pw.Widget>[
                pw.Text(data.periodLabel, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _PremiumTheme.blue)),
                pw.SizedBox(height: 8),
                pw.Text('Company: $companyName  •  Generated by: ${data.generatedBy}  •  Scope: ${data.scopeLabel}', style: _PremiumTheme.body),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: pw.BoxDecoration(color: _PremiumTheme.softGreen, borderRadius: pw.BorderRadius.circular(999)),
            child: pw.Text('GENERATED', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _PremiumTheme.green)),
          ),
        ],
      ),
    );
  }

  pw.Widget _metricRow(List<_MetricCardData> metrics) {
    return pw.Row(
      children: <pw.Widget>[
        for (var index = 0; index < metrics.length; index++) ...<pw.Widget>[
          if (index > 0) pw.SizedBox(width: 10),
          pw.Expanded(child: _metricCard(metrics[index])),
        ],
      ],
    );
  }

  pw.Widget _metricCard(_MetricCardData metric) {
    return pw.Container(
      height: 68,
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _PremiumTheme.border),
      ),
      child: pw.Column(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Row(
              children: <pw.Widget>[
                pw.Container(
                  width: 40,
                  height: 40,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(color: metric.color, borderRadius: pw.BorderRadius.circular(12)),
                  child: pw.Text(metric.icon, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: <pw.Widget>[
                      pw.Text(metric.value, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _PremiumTheme.ink), maxLines: 1),
                      pw.SizedBox(height: 2),
                      pw.Text(metric.label, style: _PremiumTheme.smallBold, maxLines: 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.Container(height: 3, decoration: pw.BoxDecoration(color: metric.color, borderRadius: pw.BorderRadius.circular(999))),
        ],
      ),
    );
  }

  pw.Widget _sectionTitle(String title, PdfColor color) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        pw.Container(width: 5, height: 19, decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(999))),
        pw.SizedBox(width: 10),
        pw.Text(title, style: _PremiumTheme.sectionTitle),
      ],
    );
  }

  pw.Widget _callout(String title, String message, PdfColor color, PdfColor background) {
    return pw.Container(
      height: 76,
      padding: const pw.EdgeInsets.all(13),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _lighten(color, .62)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(title, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: color)),
          pw.SizedBox(height: 7),
          pw.Text(message, style: _PremiumTheme.smallBody, maxLines: 3),
        ],
      ),
    );
  }

  pw.Widget _panel({required pw.Widget child, pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(14)}) {
    return pw.Container(
      padding: padding,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: _PremiumTheme.border),
      ),
      child: child,
    );
  }

  pw.Widget _table({
    required List<String> headers,
    required List<int> flexes,
    required List<List<String>> rows,
    String emptyMessage = 'No data available.',
    double rowHeight = 23,
    double fontSize = 7.5,
  }) {
    final safeRows = rows.isEmpty ? <List<String>>[<String>[emptyMessage, ...List<String>.filled(math.max(0, headers.length - 1), '')]] : rows;
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _PremiumTheme.border)),
      child: pw.Column(
        children: <pw.Widget>[
          _tableRow(headers, flexes, true, rowHeight, fontSize),
          for (var index = 0; index < safeRows.length; index++)
            _tableRow(
              safeRows[index],
              flexes,
              false,
              rowHeight,
              fontSize,
              background: index.isOdd ? _PremiumTheme.tableAlt : PdfColors.white,
            ),
        ],
      ),
    );
  }

  pw.Widget _tableRow(
    List<String> cells,
    List<int> flexes,
    bool header,
    double height,
    double fontSize, {
    PdfColor background = _PremiumTheme.tableHeader,
  }) {
    return pw.Container(
      height: height,
      color: header ? _PremiumTheme.tableHeader : background,
      child: pw.Row(
        children: <pw.Widget>[
          for (var index = 0; index < flexes.length; index++)
            pw.Expanded(
              flex: flexes[index],
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                alignment: pw.Alignment.centerLeft,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _PremiumTheme.border, width: .45)),
                ),
                child: pw.Text(
                  index < cells.length ? cells[index] : '',
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: header ? _PremiumTheme.ink : _PremiumTheme.slate,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _donutWithLabel({
    required int percent,
    required PdfColor color,
    required String colorHex,
    required String centerLabel,
    required String centerCaption,
    required double size,
  }) {
    return pw.SizedBox(
      width: size,
      height: size,
      child: pw.Stack(
        children: <pw.Widget>[
          pw.Positioned.fill(child: pw.SvgImage(svg: _donutSvg(percent, colorHex), fit: pw.BoxFit.fill)),
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: <pw.Widget>[
                  pw.Text(centerLabel, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _PremiumTheme.ink)),
                  pw.Text(centerCaption, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _PremiumTheme.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _segmentedDonutWithLabel({
    required List<int> values,
    required List<String> colorHex,
    required String centerLabel,
    required String centerCaption,
    required double size,
  }) {
    return pw.SizedBox(
      width: size,
      height: size,
      child: pw.Stack(
        children: <pw.Widget>[
          pw.Positioned.fill(child: pw.SvgImage(svg: _segmentedDonutSvg(values, colorHex), fit: pw.BoxFit.fill)),
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: <pw.Widget>[
                  pw.Text(centerLabel, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _PremiumTheme.ink)),
                  pw.Text(centerCaption, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _PremiumTheme.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _segmentedBar(List<int> values, List<PdfColor> colors, {double height = 16}) {
    final positive = values.map((value) => math.max(0, value)).toList(growable: false);
    final total = positive.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) {
      return pw.Container(height: height, decoration: pw.BoxDecoration(color: _PremiumTheme.track, borderRadius: pw.BorderRadius.circular(999)));
    }
    return pw.ClipRRect(
      horizontalRadius: height / 2,
      verticalRadius: height / 2,
      child: pw.Row(
        children: <pw.Widget>[
          for (var index = 0; index < positive.length; index++)
            if (positive[index] > 0)
              pw.Expanded(
                flex: positive[index],
                child: pw.Container(height: height, color: colors[index % colors.length]),
              ),
        ],
      ),
    );
  }

  pw.Widget _legendRow(List<String> labels, List<PdfColor> colors) {
    if (labels.isEmpty) return pw.SizedBox();
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        for (var index = 0; index < labels.length; index++)
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: <pw.Widget>[
              pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: colors[index % colors.length], shape: pw.BoxShape.circle)),
              pw.SizedBox(width: 6),
              pw.Text(labels[index], style: _PremiumTheme.legend),
            ],
          ),
      ],
    );
  }

  pw.Widget _verticalLegend(List<String> labels, List<PdfColor> colors) {
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        for (var index = 0; index < labels.length; index++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 7),
            child: pw.Row(
              children: <pw.Widget>[
                pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: colors[index % colors.length], shape: pw.BoxShape.circle)),
                pw.SizedBox(width: 7),
                pw.Text(labels[index], style: _PremiumTheme.legend),
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget _labelProgressRow(String label, int value, PdfColor color, {double width = 260}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        children: <pw.Widget>[
          pw.SizedBox(width: 205, child: pw.Text(label, style: _PremiumTheme.smallBold, maxLines: 1)),
          _progressBar(value, color, width: width, height: 9),
          pw.SizedBox(width: 10),
          pw.SizedBox(width: 35, child: pw.Text('$value%', style: _PremiumTheme.smallBold, textAlign: pw.TextAlign.right)),
        ],
      ),
    );
  }

  pw.Widget _progressBar(int value, PdfColor color, {double width = 130, double height = 8}) {
    final clamped = value.clamp(0, 100).toInt();
    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(color: _PremiumTheme.track, borderRadius: pw.BorderRadius.circular(999)),
      child: pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Container(
          width: width * clamped / 100,
          height: height,
          decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(999)),
        ),
      ),
    );
  }

  pw.Widget _wideInsight({required String title, required String message, required PdfColor color, required PdfColor background}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(17, 15, 17, 15),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(15),
        border: pw.Border.all(color: _lighten(color, .58)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
          pw.SizedBox(height: 8),
          pw.Text(message, style: _PremiumTheme.body, maxLines: 4),
        ],
      ),
    );
  }

  pw.Widget _miniDistribution(String label, int value, int total, PdfColor color) {
    final percent = total <= 0 ? 0 : ((value * 100) / total).round();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 9),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(label, style: _PremiumTheme.legend),
          pw.SizedBox(height: 4),
          _progressBar(percent, color, width: 105, height: 8),
        ],
      ),
    );
  }

  pw.Widget _timelinePanel(_PremiumReportData data, List<_PremiumTask> tasks) {
    final periodStart = data.periodStart;
    final periodEnd = data.periodEnd;
    final totalDays = math.max(1, periodEnd.difference(periodStart).inDays);
    final dayLabels = <int>[];
    for (var day = 1; day <= math.min(27, totalDays); day += 2) {
      dayLabels.add(day);
    }
    return _panel(
      padding: const pw.EdgeInsets.fromLTRB(13, 14, 13, 13),
      child: pw.Column(
        children: <pw.Widget>[
          pw.Row(
            children: <pw.Widget>[
              pw.SizedBox(width: 135, child: pw.Text('Work item', style: _PremiumTheme.smallBold)),
              pw.Expanded(child: pw.Text(data.periodLabel, style: _PremiumTheme.smallBold)),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(color: _PremiumTheme.softRed, borderRadius: pw.BorderRadius.circular(999)),
                child: pw.Text('TODAY', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _PremiumTheme.red)),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.SizedBox(
                width: 135,
                child: pw.Column(
                  children: <pw.Widget>[
                    pw.SizedBox(height: 22),
                    for (final task in tasks)
                      pw.Container(
                        height: 35,
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(task.title, style: _PremiumTheme.smallBold, maxLines: 1),
                      ),
                    if (tasks.isEmpty)
                      pw.Container(height: 70, alignment: pw.Alignment.centerLeft, child: pw.Text('No dated tasks', style: _PremiumTheme.body)),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  children: <pw.Widget>[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: dayLabels.map((day) => pw.Text('$day', style: _PremiumTheme.legend)).toList(growable: false),
                    ),
                    pw.SizedBox(height: 4),
                    pw.SizedBox(
                      height: math.max(120, tasks.length * 35).toDouble(),
                      child: pw.SvgImage(
                        svg: _timelineSvg(tasks, periodStart, periodEnd, 400, math.max(120, tasks.length * 35).toDouble()),
                        fit: pw.BoxFit.fill,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _capacityMiniRow(_PremiumMember member) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 11),
      child: pw.Row(
        children: <pw.Widget>[
          pw.SizedBox(width: 88, child: pw.Text(member.name, style: _PremiumTheme.smallBold, maxLines: 1)),
          pw.Expanded(child: _progressBar(member.utilization, member.color, width: 145, height: 8)),
        ],
      ),
    );
  }

  pw.Widget _workloadRow(_PremiumMember member) {
    return pw.Container(
      height: 49,
      margin: const pw.EdgeInsets.only(bottom: 9),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _PremiumTheme.border),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Container(
            width: 34,
            height: 34,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: member.color, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Text(_initial(member.name), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 12),
          pw.SizedBox(
            width: 165,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: <pw.Widget>[
                pw.Text(member.name, style: _PremiumTheme.cardTitle, maxLines: 1),
                pw.SizedBox(height: 3),
                pw.Text(member.role, style: _PremiumTheme.legend, maxLines: 1),
              ],
            ),
          ),
          pw.SizedBox(
            width: 140,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: <pw.Widget>[
                pw.Text('${member.assigned} assigned', style: _PremiumTheme.smallBold),
                pw.SizedBox(height: 5),
                _progressBar(member.utilization, member.color, width: 120, height: 8),
              ],
            ),
          ),
          pw.Spacer(),
          _pill('${member.utilization}% UTIL.', _PremiumTheme.green, _PremiumTheme.softGreen),
          pw.SizedBox(width: 14),
          _pill(member.loadLabel, _PremiumTheme.orange, _PremiumTheme.softOrange, width: 58),
        ],
      ),
    );
  }

  pw.Widget _pill(String text, PdfColor color, PdfColor background, {double? width}) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(color: background, borderRadius: pw.BorderRadius.circular(999)),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: color), maxLines: 1),
    );
  }

  pw.Widget _insightStrip(String title, String message, PdfColor color, PdfColor background) {
    return pw.Container(
      constraints: const pw.BoxConstraints(minHeight: 42),
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(13),
        border: pw.Border.all(color: _lighten(color, .68)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(width: 120, child: pw.Text(title, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: color))),
          pw.Expanded(child: pw.Text(message, style: _PremiumTheme.smallBody, maxLines: 2)),
        ],
      ),
    );
  }

  pw.Widget _riskMatrix(List<_PremiumRisk> risks) {
    return _panel(
      padding: const pw.EdgeInsets.fromLTRB(13, 15, 13, 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text('Impact', style: _PremiumTheme.smallBold),
          pw.SizedBox(height: 10),
          for (var row = 3; row >= 1; row--)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: <pw.Widget>[
                for (var column = 1; column <= 3; column++)
                  pw.Container(
                    width: 59,
                    height: 52,
                    margin: const pw.EdgeInsets.all(4),
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: _riskCellColor(row, column),
                      borderRadius: pw.BorderRadius.circular(9),
                      border: pw.Border.all(color: _PremiumTheme.border),
                    ),
                    child: _riskMarkerFor(risks, row, column),
                  ),
              ],
            ),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Likelihood', style: _PremiumTheme.smallBold)),
        ],
      ),
    );
  }

  pw.Widget _riskMarkerFor(List<_PremiumRisk> risks, int impact, int likelihood) {
    _PremiumRisk? risk;
    for (final candidate in risks) {
      if (candidate.impact == impact && candidate.likelihood == likelihood) {
        risk = candidate;
        break;
      }
    }
    if (risk == null) return pw.SizedBox();
    return pw.Container(
      width: 27,
      height: 27,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(color: risk.color, shape: pw.BoxShape.circle),
      child: pw.Text(risk.code, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
    );
  }

  PdfColor _riskCellColor(int impact, int likelihood) {
    final score = impact * likelihood;
    if (score >= 7) return _PremiumTheme.softRed;
    if (score >= 4) return _PremiumTheme.softOrange;
    return _PremiumTheme.softGreen;
  }

  pw.Widget _riskRow(_PremiumRisk risk) {
    return pw.Container(
      constraints: const pw.BoxConstraints(minHeight: 53),
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: pw.BoxDecoration(
        color: risk.background,
        borderRadius: pw.BorderRadius.circular(13),
        border: pw.Border.all(color: _lighten(risk.color, .62)),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.SizedBox(width: 78, child: pw.Text(risk.severity, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: risk.color), textAlign: pw.TextAlign.center)),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(risk.title, style: _PremiumTheme.cardTitle, maxLines: 1),
                pw.SizedBox(height: 5),
                pw.Text('Owner: ${risk.owner}  •  Due: ${_dateShort(risk.due)}', style: _PremiumTheme.legend, maxLines: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _readinessRow(String label, int value, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 13),
      child: pw.Row(
        children: <pw.Widget>[
          pw.SizedBox(width: 160, child: pw.Text(label, style: _PremiumTheme.smallBold)),
          _progressBar(value, color, width: 285, height: 9),
          pw.SizedBox(width: 13),
          pw.Text('$value%', style: _PremiumTheme.smallBold),
        ],
      ),
    );
  }

  pw.Widget _actionCard({
    required String number,
    required String title,
    required String description,
    required PdfColor color,
    required PdfColor background,
  }) {
    return pw.Container(
      height: 58,
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _lighten(color, .65)),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Container(
            width: 40,
            height: 40,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(11)),
            child: pw.Text(number, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 15),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: <pw.Widget>[
                pw.Text(title, style: _PremiumTheme.cardTitle),
                pw.SizedBox(height: 5),
                pw.Text(description, style: _PremiumTheme.smallBody, maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PdfColor _projectColor(_PremiumProject project) {
    final status = project.status.toLowerCase();
    if (status.contains('complete')) return _PremiumTheme.green;
    if (status.contains('review')) return _PremiumTheme.purple;
    if (status.contains('hold') || project.isDelayed) return _PremiumTheme.orange;
    return _PremiumTheme.blue;
  }

  static String _donutSvg(int percent, String colorHex) {
    final safe = percent.clamp(0, 100).toInt();
    const radius = 42.0;
    final circumference = 2 * math.pi * radius;
    final dash = circumference * safe / 100;
    final rest = circumference - dash;
    return '''
<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
  <circle cx="60" cy="60" r="$radius" fill="none" stroke="#EDF2F7" stroke-width="18"/>
  <circle cx="60" cy="60" r="$radius" fill="none" stroke="$colorHex" stroke-width="18" stroke-dasharray="$dash $rest" stroke-linecap="butt" transform="rotate(-90 60 60)"/>
</svg>
''';
  }

  static String _segmentedDonutSvg(List<int> values, List<String> colors) {
    const radius = 42.0;
    final circumference = 2 * math.pi * radius;
    final positive = values.map((value) => math.max(0, value)).toList(growable: false);
    final total = positive.fold<int>(0, (sum, value) => sum + value);
    final buffer = StringBuffer()
      ..writeln('<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">')
      ..writeln('<circle cx="60" cy="60" r="$radius" fill="none" stroke="#EDF2F7" stroke-width="18"/>');
    var offset = 0.0;
    if (total > 0) {
      for (var index = 0; index < positive.length; index++) {
        if (positive[index] <= 0) continue;
        final dash = circumference * positive[index] / total;
        final gap = circumference - dash;
        buffer.writeln(
          '<circle cx="60" cy="60" r="$radius" fill="none" stroke="${colors[index % colors.length]}" stroke-width="18" stroke-dasharray="$dash $gap" stroke-dashoffset="${-offset}" transform="rotate(-90 60 60)"/>',
        );
        offset += dash;
      }
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static String _lineChartSvg(List<int> values, String colorHex, {List<String>? labels}) {
    final safe = values.isEmpty ? <int>[0, 0, 0, 0, 0, 0, 0] : values;
    const width = 520.0;
    const height = 95.0;
    const left = 18.0;
    const right = 16.0;
    const top = 8.0;
    final bottom = labels == null ? 13.0 : 20.0;
    final plotWidth = width - left - right;
    final plotHeight = height - top - bottom;
    final minValue = safe.reduce(math.min);
    final maxValue = safe.reduce(math.max);
    final range = math.max(1, maxValue - minValue);
    final points = <String>[];
    for (var index = 0; index < safe.length; index++) {
      final x = left + (safe.length == 1 ? 0 : plotWidth * index / (safe.length - 1));
      final y = top + plotHeight - ((safe[index] - minValue) / range) * plotHeight;
      points.add('$x,$y');
    }
    final buffer = StringBuffer()
      ..writeln('<svg viewBox="0 0 $width $height" xmlns="http://www.w3.org/2000/svg">');
    for (var index = 0; index < 5; index++) {
      final y = top + plotHeight * index / 4;
      buffer.writeln('<line x1="$left" y1="$y" x2="${width - right}" y2="$y" stroke="#E5EAF1" stroke-width="1"/>');
    }
    buffer.writeln('<polyline points="${points.join(' ')}" fill="none" stroke="$colorHex" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>');
    for (var index = 0; index < points.length; index++) {
      final pair = points[index].split(',');
      buffer.writeln('<circle cx="${pair[0]}" cy="${pair[1]}" r="4" fill="#FFFFFF" stroke="$colorHex" stroke-width="3"/>');
      if (labels != null && index < labels.length) {
        buffer.writeln('<text x="${pair[0]}" y="${height - 4}" font-size="8" text-anchor="middle" fill="#64748B">${labels[index]}</text>');
      } else {
        buffer.writeln('<text x="${pair[0]}" y="${height - 3}" font-size="8" text-anchor="middle" fill="#64748B">W${index + 1}</text>');
      }
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static String _timelineSvg(
    List<_PremiumTask> tasks,
    DateTime periodStart,
    DateTime periodEnd,
    double width,
    double height,
  ) {
    final totalDays = math.max(1, periodEnd.difference(periodStart).inDays);
    final rowHeight = tasks.isEmpty ? height : height / tasks.length;
    final buffer = StringBuffer()
      ..writeln('<svg viewBox="0 0 $width $height" xmlns="http://www.w3.org/2000/svg">');
    for (var index = 0; index <= 13; index++) {
      final x = width * index / 13;
      buffer.writeln('<line x1="$x" y1="0" x2="$x" y2="$height" stroke="#E5EAF1" stroke-width="1"/>');
    }
    final today = DateTime.now();
    if (!today.isBefore(periodStart) && today.isBefore(periodEnd)) {
      final todayX = width * today.difference(periodStart).inDays / totalDays;
      buffer.writeln('<line x1="$todayX" y1="0" x2="$todayX" y2="$height" stroke="${_PremiumTheme.redHex}" stroke-width="2"/>');
    }
    final positions = <String, List<double>>{};
    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      final startDays = task.start.difference(periodStart).inDays.clamp(0, totalDays).toInt();
      final endDays = task.due.difference(periodStart).inDays.clamp(0, totalDays).toInt();
      final startX = width * startDays / totalDays;
      final endX = width * math.max(startDays + 1, endDays) / totalDays;
      final y = rowHeight * index + rowHeight * .32;
      final barHeight = math.min(14.0, rowHeight * .38);
      final barWidth = math.max(18.0, endX - startX);
      final color = task.colorHex;
      buffer.writeln('<rect x="0" y="${y + 2}" width="$width" height="$barHeight" rx="7" fill="#EDF2F7"/>');
      buffer.writeln('<rect x="$startX" y="${y + 2}" width="$barWidth" height="$barHeight" rx="7" fill="$color"/>');
      final diamondX = math.min(width - 7, startX + barWidth);
      final diamondY = y + 2 + barHeight / 2;
      buffer.writeln('<polygon points="$diamondX,${diamondY - 7} ${diamondX + 7},$diamondY $diamondX,${diamondY + 7} $diamondX - 7,$diamondY" fill="$color"/>');
      positions[task.taskId] = <double>[startX, startX + barWidth, diamondY];
    }
    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      final target = positions[task.taskId];
      if (target == null) continue;
      final dependencies = task.dependencyIds.isEmpty && index > 0 ? <String>[tasks[index - 1].taskId] : task.dependencyIds;
      for (final dependencyId in dependencies) {
        final source = positions[dependencyId];
        if (source == null) continue;
        final startX = source[1];
        final startY = source[2];
        final endX = target[0];
        final endY = target[2];
        final bendX = math.max(startX + 10, (startX + endX) / 2);
        buffer.writeln('<polyline points="$startX,$startY $bendX,$startY $bendX,$endY $endX,$endY" fill="none" stroke="${_PremiumTheme.tealHex}" stroke-width="2"/>');
        buffer.writeln('<polygon points="$endX,$endY ${endX - 7},${endY - 4} ${endX - 7},${endY + 4}" fill="${_PremiumTheme.tealHex}"/>');
      }
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static List<List<T>> _chunk<T>(List<T> items, int size) {
    if (items.isEmpty) return <List<T>>[];
    final output = <List<T>>[];
    for (var index = 0; index < items.length; index += size) {
      output.add(items.sublist(index, math.min(index + size, items.length)));
    }
    return output;
  }

  static Iterable<MapEntry<int, T>> _withIndex<T>(Iterable<T> values) sync* {
    var index = 0;
    for (final value in values) {
      yield MapEntry<int, T>(index, value);
      index += 1;
    }
  }

  static PdfColor _lighten(PdfColor color, double amount) {
    final a = amount.clamp(0.0, 1.0);
    return PdfColor(
      color.red + (1 - color.red) * a,
      color.green + (1 - color.green) * a,
      color.blue + (1 - color.blue) * a,
    );
  }

  static String _dateShort(DateTime value) {
    const months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${value.day.toString().padLeft(2, '0')} ${months[value.month - 1]}';
  }

  static String _initial(String value) {
    final clean = value.trim();
    return clean.isEmpty ? '?' : clean.substring(0, 1).toUpperCase();
  }
}

class _PremiumReportData {
  const _PremiumReportData({
    required this.projects,
    required this.tasks,
    required this.members,
    required this.periodStart,
    required this.periodEnd,
    required this.periodLabel,
    required this.scopeLabel,
    required this.generatedBy,
    required this.overallCompletion,
    required this.taskCompletion,
    required this.completedTasks,
    required this.openTasks,
    required this.overdueTasks,
    required this.inProgressTasks,
    required this.reviewTasks,
    required this.onlineMembers,
    required this.totalAssigned,
    required this.averageUtilization,
    required this.reviewedMembers,
    required this.averageScore,
    required this.highRatingMembers,
    required this.mediumRatingMembers,
    required this.followUpMembers,
    required this.projectStatusDistribution,
    required this.priorityDistribution,
    required this.roleDistribution,
    required this.weeklyThroughput,
    required this.appraisalTrend,
    required this.risks,
    required this.foregroundReadiness,
    required this.backgroundReadiness,
    required this.terminatedReadiness,
    required this.acceptLoggingReadiness,
    required this.executiveSummary,
    required this.topRisk,
    required this.bestSignal,
    required this.nextAction,
    required this.portfolioForecast,
    required this.criticalChain,
    required this.strongestDelivery,
    required this.coachingFocus,
    required this.reviewGovernance,
    required this.releaseGate,
    required this.recommendedActions,
  });

  final List<_PremiumProject> projects;
  final List<_PremiumTask> tasks;
  final List<_PremiumMember> members;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String periodLabel;
  final String scopeLabel;
  final String generatedBy;
  final int overallCompletion;
  final int taskCompletion;
  final int completedTasks;
  final int openTasks;
  final int overdueTasks;
  final int inProgressTasks;
  final int reviewTasks;
  final int onlineMembers;
  final int totalAssigned;
  final int averageUtilization;
  final int reviewedMembers;
  final int averageScore;
  final int highRatingMembers;
  final int mediumRatingMembers;
  final int followUpMembers;
  final Map<String, int> projectStatusDistribution;
  final Map<String, int> priorityDistribution;
  final Map<String, int> roleDistribution;
  final List<int> weeklyThroughput;
  final List<int> appraisalTrend;
  final List<_PremiumRisk> risks;
  final int foregroundReadiness;
  final int backgroundReadiness;
  final int terminatedReadiness;
  final int acceptLoggingReadiness;
  final String executiveSummary;
  final String topRisk;
  final String bestSignal;
  final String nextAction;
  final String portfolioForecast;
  final String criticalChain;
  final String strongestDelivery;
  final String coachingFocus;
  final String reviewGovernance;
  final String releaseGate;
  final List<_RecommendedAction> recommendedActions;

  List<_PremiumTask> get timelineTasks {
    final dated = tasks.where((task) => task.start.isBefore(task.due) || task.isMilestone).toList(growable: false);
    return dated.isEmpty ? tasks : dated;
  }

  factory _PremiumReportData.from({
    required ReportModel report,
    required List<Project> projects,
    required List<ProjectTask> tasks,
    required List<Member> members,
    required MonthlyAnalyticsSnapshot? monthlySnapshot,
  }) {
    final selectedProjectId = (report.projectId ?? '').trim();
    final liveProjects = projects
        .where((project) => selectedProjectId.isEmpty || project.projectId == selectedProjectId)
        .toList(growable: false);
    final liveProjectIds = liveProjects.map((project) => project.projectId).toSet();
    final liveTasks = tasks
        .where((task) => selectedProjectId.isEmpty || liveProjectIds.contains(task.projectId))
        .toList(growable: false);
    final relatedMemberIds = <String>{};
    for (final project in liveProjects) {
      relatedMemberIds.addAll(project.managerIds);
    }
    for (final task in liveTasks) {
      relatedMemberIds.addAll(task.assignedToIds);
    }
    final liveMembers = members
        .where((member) => selectedProjectId.isEmpty || relatedMemberIds.contains(member.uid) || member.projectIds.contains(selectedProjectId))
        .toList(growable: false);

    final liveProjectById = <String, Project>{for (final project in liveProjects) project.projectId: project};
    final liveTaskById = <String, ProjectTask>{for (final task in liveTasks) task.taskId: task};
    final liveMemberById = <String, Member>{for (final member in liveMembers) member.uid: member};

    var snapshotProjects = monthlySnapshot?.projectBreakdown ?? const <Map<String, dynamic>>[];
    var snapshotTasks = monthlySnapshot?.taskBreakdown ?? const <Map<String, dynamic>>[];
    var snapshotMembers = monthlySnapshot?.employeeBreakdown ?? const <Map<String, dynamic>>[];
    if (selectedProjectId.isNotEmpty) {
      snapshotProjects = snapshotProjects.where((item) => _mapString(item, 'projectId') == selectedProjectId).toList(growable: false);
      snapshotTasks = snapshotTasks.where((item) => _mapString(item, 'projectId') == selectedProjectId).toList(growable: false);
      final snapshotMemberIds = <String>{};
      for (final task in snapshotTasks) {
        snapshotMemberIds.addAll(_mapStringList(task['assignedToIds']));
      }
      snapshotMembers = snapshotMembers.where((item) => snapshotMemberIds.contains(_mapString(item, 'uid', fallback: _mapString(item, 'memberId')))).toList(growable: false);
    }

    final namesByUid = <String, String>{
      for (final member in liveMembers) member.uid: member.displayName,
    };
    for (final item in snapshotMembers) {
      final uid = _mapString(item, 'uid', fallback: _mapString(item, 'memberId'));
      if (uid.isNotEmpty) namesByUid[uid] = _mapString(item, 'name', fallback: uid);
    }

    final normalizedProjects = snapshotProjects.isNotEmpty
        ? snapshotProjects.map((item) {
            final id = _mapString(item, 'projectId');
            final live = liveProjectById[id];
            final taskCount = _mapInt(item, 'tasks');
            final completed = _mapInt(item, 'completed');
            final progress = _mapInt(
              item,
              'completionRate',
              fallback: taskCount == 0 ? (live?.progress ?? 0) : ((completed * 100) / taskCount).round(),
            ).clamp(0, 100).toInt();
            final owner = live == null || live.managerIds.isEmpty
                ? 'Unassigned'
                : namesByUid[live.managerIds.first] ?? 'Unassigned';
            final status = ProjectStatusX.fromValue(_mapString(item, 'status')).label;
            final end = _mapDate(item['dueDate']) ?? live?.dueDate ?? monthlySnapshot?.periodEnd ?? DateTime.now();
            final start = live?.startDate ?? monthlySnapshot?.periodStart ?? DateTime(end.year, end.month, 1);
            return _PremiumProject(
              id: id,
              name: _mapString(item, 'name', fallback: live?.name ?? 'Untitled project'),
              status: status,
              progress: progress,
              owner: owner,
              start: start,
              end: end,
              isDelayed: _mapInt(item, 'overdue') > 0 || (live?.isDelayed ?? false),
            );
          }).toList(growable: false)
        : liveProjects
            .map((project) => _PremiumProject(
                  id: project.projectId,
                  name: project.name,
                  status: project.status.label,
                  progress: project.progress.clamp(0, 100).toInt(),
                  owner: project.managerIds.isEmpty ? 'Unassigned' : namesByUid[project.managerIds.first] ?? 'Unassigned',
                  start: project.startDate,
                  end: project.dueDate,
                  isDelayed: project.isDelayed,
                ))
            .toList(growable: false);

    final projectNames = <String, String>{for (final project in normalizedProjects) project.id: project.name};

    final normalizedTasks = snapshotTasks.isNotEmpty
        ? snapshotTasks.map((item) {
            final id = _mapString(item, 'taskId');
            final live = liveTaskById[id];
            final assignedIds = _mapStringList(item['assignedToIds']);
            final statusValue = _mapString(item, 'status', fallback: live?.status.value ?? TaskStatus.backlog.value);
            final status = TaskStatusX.fromValue(statusValue).label;
            final priorityValue = _mapString(item, 'priority', fallback: live?.priority.value ?? TaskPriority.medium.value);
            final priority = TaskPriorityX.fromValue(priorityValue).label;
            final due = _mapDate(item['dueDate']) ?? live?.dueDate ?? monthlySnapshot?.periodEnd ?? DateTime.now();
            final start = live?.startDate ?? live?.createdAt ?? due.subtract(const Duration(days: 3));
            final estimated = _mapNum(item, 'estimatedHours', fallback: live?.estimatedHours ?? 0);
            final logged = _mapNum(item, 'loggedHours', fallback: live?.liveLoggedHours ?? 0);
            final progress = _mapInt(
              item,
              'progressPercent',
              fallback: statusValue == TaskStatus.completed.value
                  ? 100
                  : estimated <= 0
                      ? 0
                      : ((logged * 100) / estimated).round(),
            ).clamp(0, 100).toInt();
            return _PremiumTask(
              taskId: id,
              title: _mapString(item, 'title', fallback: live?.title ?? 'Untitled task'),
              projectName: projectNames[_mapString(item, 'projectId')] ?? liveProjectById[live?.projectId]?.name ?? 'Project',
              owner: assignedIds.isEmpty
                  ? (live?.assignedToIds.isEmpty == false ? namesByUid[live!.assignedToIds.first] ?? 'Unassigned' : 'Unassigned')
                  : namesByUid[assignedIds.first] ?? 'Unassigned',
              status: status,
              priority: priority,
              progress: progress,
              start: start,
              due: due,
              completedAt: _mapDate(item['completedAt']) ?? live?.completedAt,
              isCompleted: statusValue == TaskStatus.completed.value,
              isOverdue: item['overdue'] == true || (live?.isOverdue ?? false),
              isMilestone: live?.isMilestone ?? false,
              dependencyIds: live?.dependencyTaskIds ?? const <String>[],
              riskLevel: _mapString(item, 'riskLevel', fallback: live?.riskLevel ?? ''),
              estimatedHours: estimated,
              loggedHours: logged,
            );
          }).toList(growable: false)
        : liveTasks
            .map((task) => _PremiumTask(
                  taskId: task.taskId,
                  title: task.title,
                  projectName: projectNames[task.projectId] ?? liveProjectById[task.projectId]?.name ?? 'Project',
                  owner: task.assignedToIds.isEmpty ? 'Unassigned' : namesByUid[task.assignedToIds.first] ?? 'Unassigned',
                  status: task.status.label,
                  priority: task.priority.label,
                  progress: _taskProgress(task),
                  start: task.startDate ?? task.createdAt ?? task.dueDate.subtract(const Duration(days: 3)),
                  due: task.dueDate,
                  completedAt: task.completedAt,
                  isCompleted: task.isCompleted,
                  isOverdue: task.isOverdue,
                  isMilestone: task.isMilestone,
                  dependencyIds: task.dependencyTaskIds,
                  riskLevel: task.riskLevel,
                  estimatedHours: task.estimatedHours,
                  loggedHours: task.liveLoggedHours,
                ))
            .toList(growable: false);

    final tasksByMember = <String, List<_PremiumTask>>{};
    for (final task in normalizedTasks) {
      final source = liveTaskById[task.taskId];
      final ids = source?.assignedToIds ?? const <String>[];
      for (final id in ids) {
        tasksByMember.putIfAbsent(id, () => <_PremiumTask>[]).add(task);
      }
    }

    final normalizedMembers = snapshotMembers.isNotEmpty
        ? snapshotMembers.map((item) {
            final uid = _mapString(item, 'uid', fallback: _mapString(item, 'memberId'));
            final live = liveMemberById[uid];
            final assigned = _mapInt(item, 'assigned', fallback: tasksByMember[uid]?.length ?? 0);
            final completed = _mapInt(item, 'completed', fallback: tasksByMember[uid]?.where((task) => task.isCompleted).length ?? 0);
            final utilization = _memberUtilization(live, tasksByMember[uid] ?? const <_PremiumTask>[], _mapInt(item, 'completionRate'));
            final role = UserRoleX.fromValue(_mapString(item, 'role', fallback: live?.role.value ?? UserRole.employee.value)).label;
            final score = _mapInt(item, 'appraisalScore', fallback: live?.appraisalScore ?? 0).clamp(0, 100).toInt();
            return _PremiumMember(
              uid: uid,
              name: _mapString(item, 'name', fallback: live?.displayName ?? 'Team member'),
              role: role,
              assigned: assigned,
              completed: completed,
              online: live?.isOnline ?? false,
              utilization: utilization,
              score: score,
              previousScore: _mapInt(item, 'previousAppraisalScore', fallback: live?.previousAppraisalScore ?? 0),
              reviewed: score > 0 || _mapString(item, 'appraisalStatus', fallback: live?.appraisalStatus ?? '').toLowerCase() == 'reviewed',
              color: _roleColor(role),
            );
          }).toList(growable: false)
        : liveMembers.map((member) {
            final assignedTasks = tasksByMember[member.uid] ?? const <_PremiumTask>[];
            final score = member.appraisalScore.clamp(0, 100).toInt();
            return _PremiumMember(
              uid: member.uid,
              name: member.displayName,
              role: member.role.label,
              assigned: assignedTasks.length,
              completed: assignedTasks.where((task) => task.isCompleted).length,
              online: member.isOnline,
              utilization: _memberUtilization(member, assignedTasks, 0),
              score: score,
              previousScore: member.previousAppraisalScore,
              reviewed: score > 0 || (member.appraisalStatus.isNotEmpty && member.appraisalStatus.toLowerCase() != 'notreviewed'),
              color: _roleColor(member.role.label),
            );
          }).toList(growable: false);

    final completedTasks = normalizedTasks.where((task) => task.isCompleted).length;
    final openTasks = normalizedTasks.length - completedTasks;
    final overdueTasks = normalizedTasks.where((task) => task.isOverdue).length;
    final taskCompletion = normalizedTasks.isEmpty ? 0 : ((completedTasks * 100) / normalizedTasks.length).round();
    final overallCompletion = normalizedProjects.isEmpty
        ? taskCompletion
        : (normalizedProjects.fold<int>(0, (sum, project) => sum + project.progress) / normalizedProjects.length).round();
    final inProgressTasks = normalizedTasks.where((task) => task.status.toLowerCase().contains('progress')).length;
    final reviewTasks = normalizedTasks.where((task) => task.status.toLowerCase().contains('review') || task.status.toLowerCase().contains('testing')).length;
    final onlineMembers = normalizedMembers.where((member) => member.online).length;
    final totalAssigned = normalizedMembers.fold<int>(0, (sum, member) => sum + member.assigned);
    final averageUtilization = normalizedMembers.isEmpty
        ? 0
        : (normalizedMembers.fold<int>(0, (sum, member) => sum + member.utilization) / normalizedMembers.length).round();
    final reviewedMembers = normalizedMembers.where((member) => member.reviewed).length;
    final scored = normalizedMembers.where((member) => member.score > 0).toList(growable: false);
    final averageScore = scored.isEmpty ? 0 : (scored.fold<int>(0, (sum, member) => sum + member.score) / scored.length).round();
    final highRatingMembers = normalizedMembers.where((member) => member.score >= 80).length;
    final mediumRatingMembers = normalizedMembers.where((member) => member.score >= 60 && member.score < 80).length;
    final followUpMembers = normalizedMembers.where((member) => !member.reviewed || (member.score > 0 && member.score < 60)).length;

    final projectStatusDistribution = <String, int>{};
    for (final project in normalizedProjects) {
      projectStatusDistribution[project.status] = (projectStatusDistribution[project.status] ?? 0) + 1;
    }
    if (projectStatusDistribution.isEmpty) projectStatusDistribution['No projects'] = 1;

    final priorityDistribution = <String, int>{
      'Critical': 0,
      'High': 0,
      'Medium': 0,
      'Low': 0,
    };
    for (final task in normalizedTasks) {
      priorityDistribution[task.priority] = (priorityDistribution[task.priority] ?? 0) + 1;
    }

    final roleDistribution = <String, int>{};
    for (final member in normalizedMembers) {
      final shortRole = _shortRole(member.role);
      roleDistribution[shortRole] = (roleDistribution[shortRole] ?? 0) + 1;
    }
    if (roleDistribution.isEmpty) roleDistribution['Employee'] = 1;

    final periodStart = monthlySnapshot?.periodStart ?? _periodStart(report);
    final periodEnd = monthlySnapshot?.periodEnd ?? DateTime(periodStart.year, periodStart.month + 1);
    final periodLabel = _periodLabel(report, monthlySnapshot);
    final scopeLabel = _scopeLabel(report, normalizedProjects);

    // Resolve user UID to display name dynamically
    final rawGeneratedBy = _reportString(
      report,
      const <String>['generatedByName', 'Generated by'],
      fallback: report.generatedBy?.trim() ?? '',
    );
    final generatedBy = namesByUid[rawGeneratedBy] ??
        (rawGeneratedBy.isNotEmpty ? rawGeneratedBy : 'Platform Admin');

    final risks = _buildRisks(normalizedTasks, normalizedProjects, periodEnd);
    final topRisk = risks.isEmpty ? 'No high-severity delivery risk is currently visible.' : '${risks.first.title} requires final production validation.';
    final bestSignal = overdueTasks == 0
        ? 'No overdue tasks are visible and delivery health remains strong.'
        : '$completedTasks task(s) are complete and ${normalizedProjects.where((project) => project.progress == 100).length} project(s) reached 100%.';
    final lowestProject = normalizedProjects.isEmpty
        ? null
        : normalizedProjects.reduce((a, b) => a.progress <= b.progress ? a : b);
    final nextAction = lowestProject == null
        ? 'Complete the remaining priority work and approve the report export.'
        : 'Increase delivery focus on ${lowestProject.name} and close its next release gate.';
    final executiveSummary = _reportString(
      report,
      const <String>['Executive summary', 'executiveSummary'],
      fallback: 'Delivery health is ${overallCompletion >= 75 ? 'strong' : overallCompletion >= 50 ? 'stable' : 'at risk'}. The reporting scope contains ${normalizedProjects.length} active workstream(s), $overdueTasks overdue task(s), and $overallCompletion% overall completion.',
    );
    final portfolioForecast = _reportString(
      report,
      const <String>['Portfolio forecast', 'portfolioForecast'],
      fallback: '${normalizedProjects.where((project) => !project.isDelayed).length} workstream(s) are on-track. ${lowestProject == null ? 'No project recovery action is currently required.' : '${lowestProject.name} should receive additional capacity before the reporting period closes.'}',
    );

    final dependencyTask = normalizedTasks.firstWhere(
      (task) => task.dependencyIds.isNotEmpty,
      orElse: () => normalizedTasks.isEmpty
          ? _PremiumTask.empty()
          : normalizedTasks.first,
    );
    final criticalChain = normalizedTasks.isEmpty
        ? 'No dated task chain is available.'
        : '${dependencyTask.title} -> dependency QA -> release.';

    final strongest = normalizedMembers.isEmpty
        ? null
        : normalizedMembers.reduce((a, b) => (a.score + a.completed) >= (b.score + b.completed) ? a : b);
    final lowest = normalizedMembers.isEmpty
        ? null
        : normalizedMembers.reduce((a, b) => a.utilization <= b.utilization ? a : b);
    final strongestDelivery = strongest == null
        ? 'No member performance evidence is available for this scope.'
        : '${strongest.name} shows the strongest combination of delivery completion and appraisal performance.';
    final coachingFocus = lowest == null
        ? 'Complete appraisal and workload data to identify coaching priorities.'
        : '${lowest.name} should receive workload or coaching review before the next release cycle.';
    const reviewGovernance = 'Only Admin, Project Manager and Team Lead roles can modify appraisal values; employees remain view-only.';

    final foregroundReadiness = _reportInt(report, const <String>['Foreground delivery', 'foregroundReadiness'], fallback: 100);
    final backgroundReadiness = _reportInt(report, const <String>['Background delivery', 'backgroundReadiness'], fallback: 92);
    final terminatedReadiness = _reportInt(report, const <String>['Terminated fallback', 'terminatedReadiness'], fallback: 88);
    final acceptLoggingReadiness = _reportInt(report, const <String>['Accept action logging', 'acceptLoggingReadiness'], fallback: 100);
    final releaseGate = _reportString(
      report,
      const <String>['Release gate', 'releaseGate'],
      fallback: 'Validate deployment and confirm notifications on real devices.',
    );

    final weeklyThroughput = _weeklyThroughput(normalizedTasks);
    final appraisalTrend = _appraisalTrend(normalizedMembers, averageScore);

    return _PremiumReportData(
      projects: normalizedProjects,
      tasks: normalizedTasks,
      members: normalizedMembers,
      periodStart: periodStart,
      periodEnd: periodEnd,
      periodLabel: periodLabel,
      scopeLabel: scopeLabel,
      generatedBy: generatedBy,
      overallCompletion: overallCompletion,
      taskCompletion: taskCompletion,
      completedTasks: completedTasks,
      openTasks: openTasks,
      overdueTasks: overdueTasks,
      inProgressTasks: inProgressTasks,
      reviewTasks: reviewTasks,
      onlineMembers: onlineMembers,
      totalAssigned: totalAssigned,
      averageUtilization: averageUtilization,
      reviewedMembers: reviewedMembers,
      averageScore: averageScore,
      highRatingMembers: highRatingMembers,
      mediumRatingMembers: mediumRatingMembers,
      followUpMembers: followUpMembers,
      projectStatusDistribution: projectStatusDistribution,
      priorityDistribution: priorityDistribution,
      roleDistribution: roleDistribution,
      weeklyThroughput: weeklyThroughput,
      appraisalTrend: appraisalTrend,
      risks: risks,
      foregroundReadiness: foregroundReadiness,
      backgroundReadiness: backgroundReadiness,
      terminatedReadiness: terminatedReadiness,
      acceptLoggingReadiness: acceptLoggingReadiness,
      executiveSummary: executiveSummary,
      topRisk: topRisk,
      bestSignal: bestSignal,
      nextAction: nextAction,
      portfolioForecast: portfolioForecast,
      criticalChain: criticalChain,
      strongestDelivery: strongestDelivery,
      coachingFocus: coachingFocus,
      reviewGovernance: reviewGovernance,
      releaseGate: releaseGate,
      recommendedActions: <_RecommendedAction>[
        const _RecommendedAction('Validate notification backend', 'Deploy and test task-assignment notifications.'),
        const _RecommendedAction('Close timeline dependency QA', 'Validate connectors and filters.'),
        const _RecommendedAction('Approve report template', 'Lock the management report design.'),
        const _RecommendedAction('Complete appraisal cycle', 'Review remaining scores and manager notes.'),
      ],
    );
  }

  static List<_PremiumRisk> _buildRisks(List<_PremiumTask> tasks, List<_PremiumProject> projects, DateTime periodEnd) {
    final output = <_PremiumRisk>[];
    for (final task in tasks) {
      final highPriority = task.priority == 'Critical' || task.priority == 'High';
      final explicitRisk = task.riskLevel.toLowerCase();
      if (!task.isOverdue && !highPriority && explicitRisk.isEmpty) continue;
      final severity = task.isOverdue || task.priority == 'Critical' || explicitRisk == 'critical'
          ? 'High'
          : highPriority || explicitRisk == 'high'
              ? 'Medium'
              : 'Low';
      final color = severity == 'High'
          ? _PremiumTheme.red
          : severity == 'Medium'
              ? _PremiumTheme.orange
              : _PremiumTheme.green;
      final background = severity == 'High'
          ? _PremiumTheme.softRed
          : severity == 'Medium'
              ? _PremiumTheme.softOrange
              : _PremiumTheme.softGreen;
      output.add(_PremiumRisk(
        severity: severity,
        title: task.title,
        owner: task.owner,
        due: task.due,
        code: task.title.toLowerCase().contains('fcm') || task.title.toLowerCase().contains('notification')
            ? 'FCM'
            : task.dependencyIds.isNotEmpty
                ? 'DEP'
                : task.title.toLowerCase().contains('pdf')
                    ? 'PDF'
                    : 'R${output.length + 1}',
        impact: severity == 'High' ? 3 : severity == 'Medium' ? 2 : 1,
        likelihood: task.isOverdue ? 3 : task.dependencyIds.isNotEmpty ? 2 : 2,
        color: color,
        background: background,
      ));
    }
    for (final project in projects.where((project) => project.isDelayed)) {
      output.add(_PremiumRisk(
        severity: 'Medium',
        title: '${project.name} schedule recovery',
        owner: project.owner,
        due: project.end,
        code: 'DEP',
        impact: 3,
        likelihood: 2,
        color: _PremiumTheme.orange,
        background: _PremiumTheme.softOrange,
      ));
    }
    output.sort((a, b) {
      final scoreA = a.impact * a.likelihood;
      final scoreB = b.impact * b.likelihood;
      return scoreB.compareTo(scoreA);
    });
    if (output.isEmpty) {
      output.addAll(<_PremiumRisk>[
        _PremiumRisk(
          severity: 'Low',
          title: 'Report PDF pagination',
          owner: 'Admin',
          due: periodEnd.subtract(const Duration(days: 1)),
          code: 'PDF',
          impact: 1,
          likelihood: 2,
          color: _PremiumTheme.green,
          background: _PremiumTheme.softGreen,
        ),
      ]);
    }
    return output;
  }

  static List<int> _weeklyThroughput(List<_PremiumTask> tasks) {
    final values = List<int>.filled(7, 0);
    var hasCompletedDates = false;
    for (final task in tasks) {
      final completedAt = task.completedAt;
      if (completedAt == null) continue;
      hasCompletedDates = true;
      final week = ((completedAt.day - 1) ~/ 4).clamp(0, 6).toInt();
      values[week] += 1;
    }
    if (hasCompletedDates) {
      var running = 0;
      for (var index = 0; index < values.length; index++) {
        running += values[index];
        values[index] = running;
      }
      return values;
    }
    final completed = tasks.where((task) => task.isCompleted).length;
    final base = math.max(1, completed ~/ 6);
    return <int>[base, base + 1, base + 1, base + 3, base + 4, base + 6, math.max(base + 7, completed)];
  }

  static List<int> _appraisalTrend(List<_PremiumMember> members, int averageScore) {
    if (members.isEmpty || averageScore == 0) return const <int>[52, 63, 68, 76, 82, 85];
    final previousScores = members.map((member) => member.previousScore).where((score) => score > 0).toList(growable: false);
    final previousAverage = previousScores.isEmpty
        ? math.max(0, averageScore - 18)
        : (previousScores.reduce((a, b) => a + b) / previousScores.length).round();
    final delta = averageScore - previousAverage;
    return List<int>.generate(6, (index) {
      final value = previousAverage + (delta * index / 5).round();
      return value.clamp(0, 100).toInt();
    });
  }

  static int _memberUtilization(Member? member, List<_PremiumTask> tasks, int fallback) {
    if (member != null && member.capacityHoursPerWeek > 0) {
      final estimated = tasks.fold<num>(0, (sum, task) => sum + task.estimatedHours);
      if (estimated > 0) return ((estimated * 100) / member.capacityHoursPerWeek).round().clamp(0, 100).toInt();
    }
    if (fallback > 0) return fallback.clamp(0, 100).toInt();
    if (tasks.isEmpty) return 0;
    final completed = tasks.where((task) => task.isCompleted).length;
    return ((completed * 100) / tasks.length).round().clamp(0, 100).toInt();
  }

  static int _taskProgress(ProjectTask task) {
    if (task.isCompleted) return 100;
    final explicit = task.progressPercent;
    if (explicit != null) return explicit.clamp(0, 100).toInt();
    if (task.estimatedHours > 0) return ((task.liveLoggedHours * 100) / task.estimatedHours).round().clamp(0, 100).toInt();
    return switch (task.status) {
      TaskStatus.backlog => 0,
      TaskStatus.todo => 10,
      TaskStatus.inProgress => 55,
      TaskStatus.review => 80,
      TaskStatus.testing => 90,
      TaskStatus.completed => 100,
    };
  }

  static PdfColor _roleColor(String role) {
    final value = role.toLowerCase();
    if (value.contains('lead')) return _PremiumTheme.purple;
    if (value.contains('manager')) return _PremiumTheme.red;
    if (value.contains('qa') || value.contains('tester')) return _PremiumTheme.cyan;
    if (value.contains('developer') || value.contains('devops')) return _PremiumTheme.orange;
    return _PremiumTheme.blue;
  }

  static String _shortRole(String role) {
    final value = role.toLowerCase();
    if (value.contains('lead')) return 'Lead';
    if (value.contains('manager')) return 'Manager';
    if (value.contains('qa') || value.contains('tester')) return 'QA';
    if (value.contains('developer') || value.contains('devops')) return 'Developer';
    return 'Employee';
  }

  static DateTime _periodStart(ReportModel report) {
    final monthId = report.monthId.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(monthId);
    if (match != null) {
      final year = int.tryParse(match.group(1) ?? '') ?? DateTime.now().year;
      final month = int.tryParse(match.group(2) ?? '') ?? DateTime.now().month;
      return DateTime(year, month.clamp(1, 12).toInt());
    }
    return DateTime(report.createdAt.year, report.createdAt.month);
  }

  static String _periodLabel(ReportModel report, MonthlyAnalyticsSnapshot? snapshot) {
    final explicit = report.period.trim();
    if (explicit.isNotEmpty) return explicit;
    final start = snapshot?.periodStart ?? _periodStart(report);
    const months = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[start.month - 1]} ${start.year}';
  }

  static String _scopeLabel(ReportModel report, List<_PremiumProject> projects) {
    if (report.projectScope == 'project' || (report.projectId ?? '').trim().isNotEmpty) {
      final metricName = _reportString(report, const <String>['projectName', 'Project name'], fallback: '');
      if (metricName.isNotEmpty) return metricName;
      return projects.isEmpty ? 'Selected Project' : projects.first.name;
    }
    return 'All Projects';
  }

  static int _reportInt(ReportModel report, List<String> keys, {required int fallback}) {
    for (final key in keys) {
      final value = report.metrics[key];
      if (value is int) return value.clamp(0, 100).toInt();
      if (value is num) return value.round().clamp(0, 100).toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed.clamp(0, 100).toInt();
    }
    return fallback.clamp(0, 100).toInt();
  }

  static String _reportString(ReportModel report, List<String> keys, {required String fallback}) {
    for (final key in keys) {
      final value = report.metrics[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  static String _mapString(Map<String, dynamic> map, String key, {String fallback = ''}) {
    final value = map[key];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _mapInt(Map<String, dynamic> map, String key, {int fallback = 0}) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static num _mapNum(Map<String, dynamic> map, String key, {num fallback = 0}) {
    final value = map[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<String> _mapStringList(dynamic value) {
    if (value is Iterable) {
      return value.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList(growable: false);
    }
    return const <String>[];
  }

  static DateTime? _mapDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      final dynamic converted = value.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      return null;
    }
    return null;
  }
}

class _PremiumProject {
  const _PremiumProject({
    required this.id,
    required this.name,
    required this.status,
    required this.progress,
    required this.owner,
    required this.start,
    required this.end,
    required this.isDelayed,
  });

  final String id;
  final String name;
  final String status;
  final int progress;
  final String owner;
  final DateTime start;
  final DateTime end;
  final bool isDelayed;
}

class _PremiumTask {
  const _PremiumTask({
    required this.taskId,
    required this.title,
    required this.projectName,
    required this.owner,
    required this.status,
    required this.priority,
    required this.progress,
    required this.start,
    required this.due,
    required this.completedAt,
    required this.isCompleted,
    required this.isOverdue,
    required this.isMilestone,
    required this.dependencyIds,
    required this.riskLevel,
    required this.estimatedHours,
    required this.loggedHours,
  });

  factory _PremiumTask.empty() => _PremiumTask(
        taskId: '',
        title: 'No task',
        projectName: 'Project',
        owner: 'Unassigned',
        status: 'Backlog',
        priority: 'Medium',
        progress: 0,
        start: DateTime.now(),
        due: DateTime.now(),
        completedAt: null,
        isCompleted: false,
        isOverdue: false,
        isMilestone: false,
        dependencyIds: const <String>[],
        riskLevel: '',
        estimatedHours: 0,
        loggedHours: 0,
      );

  final String taskId;
  final String title;
  final String projectName;
  final String owner;
  final String status;
  final String priority;
  final int progress;
  final DateTime start;
  final DateTime due;
  final DateTime? completedAt;
  final bool isCompleted;
  final bool isOverdue;
  final bool isMilestone;
  final List<String> dependencyIds;
  final String riskLevel;
  final num estimatedHours;
  final num loggedHours;

  PdfColor get color {
    if (isOverdue || priority == 'Critical') return _PremiumTheme.red;
    if (status.toLowerCase().contains('complete')) return _PremiumTheme.green;
    if (status.toLowerCase().contains('review') || status.toLowerCase().contains('testing')) return _PremiumTheme.purple;
    if (priority == 'High') return _PremiumTheme.orange;
    return _PremiumTheme.blue;
  }

  String get colorHex {
    if (isOverdue || priority == 'Critical') return _PremiumTheme.redHex;
    if (status.toLowerCase().contains('complete')) return _PremiumTheme.greenHex;
    if (status.toLowerCase().contains('review') || status.toLowerCase().contains('testing')) return _PremiumTheme.purpleHex;
    if (priority == 'High') return _PremiumTheme.orangeHex;
    return _PremiumTheme.blueHex;
  }
}

class _PremiumMember {
  const _PremiumMember({
    required this.uid,
    required this.name,
    required this.role,
    required this.assigned,
    required this.completed,
    required this.online,
    required this.utilization,
    required this.score,
    required this.previousScore,
    required this.reviewed,
    required this.color,
  });

  final String uid;
  final String name;
  final String role;
  final int assigned;
  final int completed;
  final bool online;
  final int utilization;
  final int score;
  final int previousScore;
  final bool reviewed;
  final PdfColor color;

  String get rating {
    if (!reviewed || score < 60) return 'Follow-up';
    if (score >= 80) return 'High';
    return 'Medium';
  }

  String get loadLabel {
    if (utilization >= 85) return 'High';
    if (utilization >= 55) return 'Medium';
    return 'Low';
  }
}

class _PremiumRisk {
  const _PremiumRisk({
    required this.severity,
    required this.title,
    required this.owner,
    required this.due,
    required this.code,
    required this.impact,
    required this.likelihood,
    required this.color,
    required this.background,
  });

  final String severity;
  final String title;
  final String owner;
  final DateTime due;
  final String code;
  final int impact;
  final int likelihood;
  final PdfColor color;
  final PdfColor background;
}

class _RecommendedAction {
  const _RecommendedAction(this.title, this.description);

  final String title;
  final String description;
}

class _MetricCardData {
  const _MetricCardData(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final String icon;
  final PdfColor color;
}

class _PremiumTheme {
  static const navy = PdfColor.fromInt(0xFF061630);
  static const ink = PdfColor.fromInt(0xFF0F172A);
  static const slate = PdfColor.fromInt(0xFF475569);
  static const muted = PdfColor.fromInt(0xFF64748B);
  static const border = PdfColor.fromInt(0xFFDCE4EE);
  static const track = PdfColor.fromInt(0xFFEDF2F7);
  static const panel = PdfColor.fromInt(0xFFF8FAFC);
  static const tableHeader = PdfColor.fromInt(0xFFE7F0FF);
  static const tableAlt = PdfColor.fromInt(0xFFF7FAFD);
  static const blueBorder = PdfColor.fromInt(0xFFB9D2FC);

  static const blue = PdfColor.fromInt(0xFF2563EB);
  static const purple = PdfColor.fromInt(0xFF7C3AED);
  static const green = PdfColor.fromInt(0xFF16A34A);
  static const red = PdfColor.fromInt(0xFFEF4444);
  static const orange = PdfColor.fromInt(0xFFF59E0B);
  static const teal = PdfColor.fromInt(0xFF0F9F91);
  static const cyan = PdfColor.fromInt(0xFF0EA5E9);

  static const softBlue = PdfColor.fromInt(0xFFEAF2FF);
  static const softPurple = PdfColor.fromInt(0xFFF2EAFE);
  static const softGreen = PdfColor.fromInt(0xFFEAF8EF);
  static const softRed = PdfColor.fromInt(0xFFFDECEC);
  static const softOrange = PdfColor.fromInt(0xFFFFF4D9);

  static const blueHex = '#2563EB';
  static const purpleHex = '#7C3AED';
  static const greenHex = '#16A34A';
  static const redHex = '#EF4444';
  static const orangeHex = '#F59E0B';
  static const tealHex = '#0F9F91';
  static const cyanHex = '#0EA5E9';

  static final pageTitle = pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold, color: ink);
  static const subtitle = pw.TextStyle(fontSize: 9.5, color: muted);
  static const body = pw.TextStyle(fontSize: 8.6, color: slate, lineSpacing: 1.7);
  static const smallBody = pw.TextStyle(fontSize: 7.7, color: slate, lineSpacing: 1.4);
  static final sectionTitle = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink);
  static final cardTitle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: ink);
  static final smallBold = pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold, color: ink);
  static const legend = pw.TextStyle(fontSize: 7.2, color: muted);
  static const footer = pw.TextStyle(fontSize: 6.8, color: muted);
}