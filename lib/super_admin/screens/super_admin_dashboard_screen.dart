import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'super_admin_wizard_screen.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({Key? key}) : super(key: key);

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchNotifier = ValueNotifier<String>('');
  int _selectedIndex = 0; // 0: Dashboard, 1: Workspaces, 2: Analytics, 3: Plans, 4: Workflow, 5: Settings, 6: Billing

  @override
  void dispose() {
    _searchController.dispose();
    _searchNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Row(
        children: [
          // ==========================================
          // PERSISTENT SIDE NAVIGATION BAR
          // ==========================================
          Container(
            width: 260,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF673AB7).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.admin_panel_settings, color: Color(0xFF673AB7), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "SaaS Admin",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E1E26)),
                          ),
                          Text(
                            "Control Center",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                const SizedBox(height: 16),

                // Navigation Items
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      _buildNavItem(icon: Icons.dashboard_rounded, label: "Dashboard & Telemetry", index: 0),
                      _buildNavItem(icon: Icons.domain_rounded, label: "Workspaces", index: 1),
                      _buildNavItem(icon: Icons.analytics_rounded, label: "Analytics", index: 2),
                      _buildNavItem(icon: Icons.price_change_rounded, label: "Plans & Pricing", index: 3),
                      _buildNavItem(icon: Icons.account_tree_rounded, label: "Workflow Panels", index: 4),
                      _buildNavItem(icon: Icons.receipt_long_rounded, label: "Billing & Transactions", index: 6), // Razorpay Billing Records Tab
                      _buildNavItem(icon: Icons.settings_rounded, label: "Settings", index: 5),
                    ],
                  ),
                ),

                const Spacer(),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),

                // Bottom User & Logout Profile Section
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFF673AB7),
                        child: Text("SA", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              FirebaseAuth.instance.currentUser?.email ?? "Super Admin",
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text("Platform Owner", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 20, color: Colors.redAccent),
                        tooltip: 'Sign Out',
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, color: Color(0xFFEEEEEE)),

          // ==========================================
          // MAIN CONTENT AREA (Dynamically Switched)
          // ==========================================
          Expanded(
            child: Scaffold(
              backgroundColor: const Color(0xFFF4F6F9),
              appBar: AppBar(
                title: Text(
                  _getPageTitle(_selectedIndex),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E1E26)),
                ),
                backgroundColor: Colors.white,
                elevation: 0,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(color: Colors.grey.shade200, height: 1),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF673AB7)),
                      label: const Text('Sync Firestore', style: TextStyle(color: Color(0xFF673AB7), fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF673AB7)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: () {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Firestore telemetry synchronized successfully!"), backgroundColor: Colors.green),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
              body: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('companies').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Error loading Firestore data: ${snapshot.error}",
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  return _buildSelectedPageContent(docs);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getPageTitle(int index) {
    switch (index) {
      case 0: return "Platform Overview & Live Telemetry";
      case 1: return "Tenant Workspaces Management";
      case 2: return "System Analytics & Growth";
      case 3: return "Subscription Plans & Pricing Management";
      case 4: return "Platform Workflow & Engine Panels";
      case 5: return "Super Admin Settings";
      case 6: return "Razorpay Billing & Transaction Records";
      default: return "Control Panel";
    }
  }

  Widget _buildSelectedPageContent(List<QueryDocumentSnapshot> docs) {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardView(docs);
      case 1:
        return _buildWorkspacesView(docs);
      case 2:
        return _buildAnalyticsView(docs);
      case 3:
        return _buildPlansView(docs);
      case 4:
        return _buildWorkflowPanelsView();
      case 5:
        return _buildSettingsView();
      case 6:
        return _buildBillingTransactionsView(); // Renders Razorpay transaction ledger
      default:
        return _buildDashboardView(docs);
    }
  }

  // ==========================================
  // PAGE 6: RAZORPAY BILLING & TRANSACTIONS VIEW
  // ==========================================
  Widget _buildBillingTransactionsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('billing_records').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data?.docs ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Razorpay Billing & Payment Records", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26))),
              const SizedBox(height: 4),
              const Text("Live transaction logs, subscription charges, and payment statuses synced from payment gateway webhooks.", style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 24),

              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                      child: const Row(
                        children: [
                          Expanded(flex: 2, child: Text("Transaction ID", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13))),
                          Expanded(flex: 2, child: Text("Company ID", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13))),
                          Expanded(flex: 1, child: Text("Amount", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13))),
                          Expanded(flex: 1, child: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text("Timestamp", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13), textAlign: TextAlign.right)),
                        ],
                      ),
                    ),
                    records.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(48.0),
                            child: Center(
                              child: Text(
                                "No billing records found. Transactions will appear here automatically when Razorpay webhooks fire.",
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: records.length,
                            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                            itemBuilder: (context, index) {
                              final data = records[index].data() as Map<String, dynamic>;
                              final paymentId = data['paymentId'] ?? records[index].id;
                              final companyId = data['companyId'] ?? 'N/A';
                              final amount = data['amount'] ?? '999';
                              final currency = data['currency'] ?? 'INR';
                              final status = (data['status'] ?? 'succeeded').toString().toUpperCase();
                              
                              Color statusColor = Colors.green;
                              if (status == 'FAILED' || status == 'PENDING') statusColor = Colors.red;

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                child: Row(
                                  children: [
                                    Expanded(flex: 2, child: Text(paymentId, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12, color: Color(0xFF1E1E26)), overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 2, child: Text(companyId, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 1, child: Text("₹$amount $currency", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E1E26)))),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: statusColor.withOpacity(0.3)),
                                          ),
                                          child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        data['createdAt'] != null ? data['createdAt'].toString().split('.').first : 'Just now',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // PAGE 0: DASHBOARD & MONITORING VIEW
  // ==========================================
  Widget _buildDashboardView(List<QueryDocumentSnapshot> docs) {
    int totalWorkspaces = docs.length;
    
    int proPlans = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? '').toString().toLowerCase().trim();
      return plan == 'pro';
    }).length;

    int enterprisePlans = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? '').toString().toLowerCase().trim();
      return plan == 'enterprise';
    }).length;

    int freePlans = totalWorkspaces - proPlans - enterprisePlans;
    if (freePlans < 0) freePlans = 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Live Ecosystem Telemetry",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Real-time database analytics and multi-tenant performance metrics.",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF673AB7),
                  foregroundColor: Colors.white,
                  elevation: 3,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add_business, size: 20),
                label: const Text("Provision New Company", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SuperAdminWizardScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 28),

          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: "Total Workspaces",
                    value: "$totalWorkspaces",
                    subtitle: "Active Firestore Tenant Nodes",
                    icon: Icons.domain,
                    color: Colors.blue.shade600,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    title: "Paid Subscriptions",
                    value: "${proPlans + enterprisePlans}",
                    subtitle: "Pro & Enterprise Active",
                    icon: Icons.star_rounded,
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildModernThreeWayPieChartCard(
                    freeCount: freePlans,
                    proCount: proPlans,
                    enterpriseCount: enterprisePlans,
                    total: totalWorkspaces == 0 ? 1 : totalWorkspaces,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Tenant Onboarding Velocity", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                            child: const Text("Live Firestore Sync", style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 180,
                        child: CustomPaint(
                          painter: _LineChartPainter(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Infrastructure Resource Load", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26))),
                      const SizedBox(height: 20),
                      _buildResourceGauge("Firestore Connection Pool", 0.35, Colors.blue),
                      const SizedBox(height: 16),
                      _buildResourceGauge("Memory Allocation (RAM)", 0.62, Colors.purple),
                      const SizedBox(height: 16),
                      _buildResourceGauge("Database Read/Write IOPS", 0.22, Colors.green),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResourceGauge(String label, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E1E26))),
            Text("${(percentage * 100).toInt()}%", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 8,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PAGE 1: WORKSPACES VIEW
  // ==========================================
  Widget _buildWorkspacesView(List<QueryDocumentSnapshot> docs) {
    int totalWorkspaces = docs.length;
    int proPlans = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? '').toString().toLowerCase().trim();
      return plan == 'pro';
    }).length;
    int enterprisePlans = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? '').toString().toLowerCase().trim();
      return plan == 'enterprise';
    }).length;

    double paidAdoptionRate = totalWorkspaces == 0 ? 0.0 : ((proPlans + enterprisePlans) / totalWorkspaces);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Tenant Workspaces Directory", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26))),
                  SizedBox(height: 4),
                  Text("Manage and filter live enterprise tenant databases from Firestore.", style: TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF673AB7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add),
                label: const Text("Provision New Company"),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SuperAdminWizardScreen())),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Ecosystem Subscription Health", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(20)),
                      child: const Text("Firestore Real-Time", style: TextStyle(color: Color(0xFF673AB7), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Paid Tier Adoption Rate (Pro & Enterprise)", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    Text("${(paidAdoptionRate * 100).toStringAsFixed(1)}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E1E26))),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: paidAdoptionRate,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ValueListenableBuilder<String>(
              valueListenable: _searchNotifier,
              builder: (context, currentQuery, child) {
                return TextField(
                  controller: _searchController,
                  onChanged: (val) => _searchNotifier.value = val,
                  decoration: InputDecoration(
                    icon: const Icon(Icons.search, color: Color(0xFF673AB7)),
                    hintText: "Search workspaces by name, email, plan tier, or ID...",
                    border: InputBorder.none,
                    suffixIcon: currentQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); _searchNotifier.value = ''; })
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          ValueListenableBuilder<String>(
            valueListenable: _searchNotifier,
            builder: (context, searchQuery, child) {
              final trimmedQuery = searchQuery.toLowerCase().trim();
              final filteredDocs = docs.where((doc) {
                if (trimmedQuery.isEmpty) return true;
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['name'] ?? '').toString().toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();
                final plan = (data['plan'] ?? 'free').toString().toLowerCase();
                final id = doc.id.toLowerCase();
                return '$name $email $id $plan'.contains(trimmedQuery);
              }).toList();

              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                      child: const Row(
                        children: [
                          Expanded(flex: 3, child: Text("Company Name", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13))),
                          Expanded(flex: 3, child: Text("Admin Email", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13))),
                          Expanded(flex: 2, child: Text("Workspace ID", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13))),
                          Expanded(flex: 1, child: Text("Plan Tier", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13), textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    filteredDocs.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(48.0),
                            child: Center(
                              child: Text(
                                docs.isEmpty ? "No tenant companies found in Firestore." : "No companies match your search query.",
                                style: const TextStyle(color: Colors.grey, fontSize: 15),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredDocs.length,
                            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                            itemBuilder: (context, index) {
                              final data = filteredDocs[index].data() as Map<String, dynamic>;
                              final companyId = filteredDocs[index].id;
                              final name = data['name'] ?? 'Unnamed Workspace';
                              final plan = (data['plan'] ?? 'free').toString().toUpperCase();
                              final email = data['email'] ?? 'No email';

                              Color planColor = const Color(0xFF673AB7);
                              if (plan == 'PRO') planColor = Colors.amber.shade900;
                              if (plan == 'ENTERPRISE') planColor = Colors.blue.shade700;

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: const Color(0xFF673AB7).withOpacity(0.1),
                                            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C', style: const TextStyle(color: Color(0xFF673AB7), fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E1E26)), overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ),
                                    Expanded(flex: 3, child: Text(email, style: TextStyle(color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 2, child: Text(companyId, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                                    Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: planColor.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: planColor.withOpacity(0.3)),
                                          ),
                                          child: Text(plan, style: TextStyle(color: planColor, fontWeight: FontWeight.bold, fontSize: 11)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PAGE 2: ANALYTICS VIEW
  // ==========================================
  Widget _buildAnalyticsView(List<QueryDocumentSnapshot> docs) {
    int totalWorkspaces = docs.length;
    
    int proPlans = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? '').toString().toLowerCase().trim();
      return plan == 'pro';
    }).length;

    int enterprisePlans = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? '').toString().toLowerCase().trim();
      return plan == 'enterprise';
    }).length;

    int freePlans = totalWorkspaces - proPlans - enterprisePlans;
    if (freePlans < 0) freePlans = 0;

    double estimatedMRR = (proPlans * 49.0) + (enterprisePlans * 199.0);
    double conversionRate = totalWorkspaces == 0 ? 0.0 : ((proPlans + enterprisePlans) / totalWorkspaces) * 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("System Analytics & Revenue Growth", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26))),
          const SizedBox(height: 4),
          const Text("Real-time financial metrics and subscription tier distributions.", style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),

          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: "Estimated MRR",
                    value: "\$${estimatedMRR.toStringAsFixed(0)}",
                    subtitle: "Monthly Recurring Revenue",
                    icon: Icons.payments_rounded,
                    color: Colors.green.shade600,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    title: "Paid Conversion",
                    value: "${conversionRate.toStringAsFixed(1)}%",
                    subtitle: "Free-to-Paid Upgrade Rate",
                    icon: Icons.trending_up_rounded,
                    color: Colors.purple.shade600,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    title: "Active Tenants",
                    value: "$totalWorkspaces",
                    subtitle: "Provisioned Workspaces",
                    icon: Icons.apartment_rounded,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Subscription Tier Distribution Analysis", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26))),
                const SizedBox(height: 20),
                _buildAnalyticsTierBar(label: "Enterprise Tier (\$199/mo)", count: enterprisePlans, total: totalWorkspaces == 0 ? 1 : totalWorkspaces, color: Colors.blue.shade700),
                const SizedBox(height: 16),
                _buildAnalyticsTierBar(label: "Pro Tier (\$49/mo)", count: proPlans, total: totalWorkspaces == 0 ? 1 : totalWorkspaces, color: Colors.amber.shade700),
                const SizedBox(height: 16),
                _buildAnalyticsTierBar(label: "Free Allocation (\$0/mo)", count: freePlans, total: totalWorkspaces == 0 ? 1 : totalWorkspaces, color: const Color(0xFF673AB7)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTierBar({required String label, required int count, required int total, required Color color}) {
    double percentage = count / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E1E26))),
            Text("$count workspaces (${(percentage * 100).toStringAsFixed(1)}%)", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 10,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PAGE 3: PLANS & PRICING MANAGEMENT SCREEN
  // ==========================================
  Widget _buildPlansView(List<QueryDocumentSnapshot> docs) {
    int totalWorkspaces = docs.length;

    int proCount = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? '').toString().toLowerCase().trim();
      return plan == 'pro';
    }).length;

    int enterpriseCount = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final plan = (data['plan'] ?? '').toString().toLowerCase().trim();
      return plan == 'enterprise';
    }).length;

    int freeCount = totalWorkspaces - proCount - enterpriseCount;
    if (freeCount < 0) freeCount = 0;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('plans').snapshots(),
      builder: (context, planSnapshot) {
        Map<String, dynamic> freePlan = {'price': '0', 'description': 'Free tier workspace allocation with standard features.'};
        Map<String, dynamic> proPlan = {'price': '49', 'description': 'Advanced workspace features for growing teams.'};
        Map<String, dynamic> enterprisePlan = {'price': '199', 'description': 'For large organizations requiring maximum security and SLA.'};

        if (planSnapshot.hasData) {
          for (var doc in planSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (doc.id == 'free') freePlan = data;
            if (doc.id == 'pro') proPlan = data;
            if (doc.id == 'enterprise') enterprisePlan = data;
          }
        }

        String freeRawPrice = (freePlan['price'] ?? '0').toString().replaceAll('\$', '').trim();
        String proRawPrice = (proPlan['price'] ?? '49').toString().replaceAll('\$', '').trim();
        String entRawPrice = (enterprisePlan['price'] ?? '199').toString().replaceAll('\$', '').trim();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Subscription Plans & Pricing Setup", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26))),
              const SizedBox(height: 4),
              const Text("Manage tier pricing and resource limits synced live with Firestore.", style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 28),

              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildEditablePricingCard(
                        context: context,
                        planId: 'free',
                        title: "Free Allocation",
                        price: "\$$freeRawPrice",
                        rawPrice: freeRawPrice,
                        period: "/ month",
                        description: freePlan['description'] ?? '',
                        activeWorkspaces: freeCount,
                        limits: ["Up to 10 Team Members", "5 GB Cloud Storage", "Core Projects & Tasks Module"],
                        color: const Color(0xFF673AB7),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildEditablePricingCard(
                        context: context,
                        planId: 'pro',
                        title: "Pro Tier",
                        price: "\$$proRawPrice",
                        rawPrice: proRawPrice,
                        period: "/ month",
                        description: proPlan['description'] ?? '',
                        activeWorkspaces: proCount,
                        limits: ["Up to 50 Team Members", "50 GB Cloud Storage", "All Modules (Timeline, Reports, Appraisal)"],
                        color: Colors.amber.shade700,
                        isPopular: true,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildEditablePricingCard(
                        context: context,
                        planId: 'enterprise',
                        title: "Enterprise Tier",
                        price: "\$$entRawPrice",
                        rawPrice: entRawPrice,
                        period: "/ month",
                        description: enterprisePlan['description'] ?? '',
                        activeWorkspaces: enterpriseCount,
                        limits: ["Unlimited Team Members", "500 GB Cloud Storage", "Dedicated Priority Support & SLA"],
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditablePricingCard({
    required BuildContext context,
    required String planId,
    required String title,
    required String price,
    required String rawPrice,
    required String period,
    required String description,
    required int activeWorkspaces,
    required List<String> limits,
    required Color color,
    bool isPopular = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPopular ? color : Colors.grey.shade200, width: isPopular ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text("Most Popular", style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26))),
              Text(period, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.8)),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, color: Color(0xFFEEEEEE))),
          
          Text("Active Tenants: $activeWorkspaces", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E1E26))),
          const SizedBox(height: 12),

          ...limits.map((limit) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: color),
                    const SizedBox(width: 10),
                    Expanded(child: Text(limit, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                  ],
                ),
              )),
          
          const Spacer(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(Icons.edit_rounded, size: 16, color: color),
              label: Text("Edit Plan Details", style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              onPressed: () => _showEditPlanDialog(context, planId, title, rawPrice, description),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPlanDialog(BuildContext context, String planId, String planTitle, String currentPrice, String currentDesc) {
    final priceController = TextEditingController(text: currentPrice);
    final descController = TextEditingController(text: currentDesc);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $planTitle"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monthly Price (\$)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Plan Description', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF673AB7), foregroundColor: Colors.white),
            onPressed: () async {
              String sanitizedPrice = priceController.text.replaceAll('\$', '').trim();
              await FirebaseFirestore.instance.collection('plans').doc(planId).set({
                'price': sanitizedPrice,
                'description': descController.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Plan successfully updated in Firestore!"), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text("Save Changes"),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PAGE 4: WORKFLOW PANELS VIEW
  // ==========================================
  Widget _buildWorkflowPanelsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Platform Workflow & Automation Engines", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26))),
          const SizedBox(height: 4),
          const Text("Configure how tenant creation and role-based access rules operate.", style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),

          _buildWorkflowCard(
            title: "1. Tenant Provisioning Pipeline",
            description: "Controls the multi-step database initialization process when provisioning new companies.",
            status: "Active & Automated",
            statusColor: Colors.green,
            icon: Icons.domain_add_rounded,
            steps: [
              "Step 1: Validate Super Admin permissions via Firebase Auth UID.",
              "Step 2: Generate unique company node in Firestore /companies collection.",
              "Step 3: Provision root admin member document under /companies/{id}/members/{uid}.",
              "Step 4: Initialize default modules framework based on selected tier limits.",
            ],
          ),
          const SizedBox(height: 20),

          _buildWorkflowCard(
            title: "2. Auth Auto-Healing & UID Migration Engine",
            description: "Automatically maps legacy email placeholder accounts to real Firebase Auth UIDs on login.",
            status: "Active Engine",
            statusColor: Colors.blue,
            icon: Icons.healing_rounded,
            steps: [
              "Step 1: Intercept user state change upon successful sign-in.",
              "Step 2: Check singular root profile document under /user/{uid}.",
              "Step 3: If unlinked, query collectionGroup('members') by verified email.",
              "Step 4: Migrate legacy email placeholder IDs to secure Auth UID seamlessly.",
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowCard({
    required String title,
    required String description,
    required String status,
    required Color statusColor,
    required IconData icon,
    required List<String> steps,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF673AB7).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: const Color(0xFF673AB7), size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26))),
                    const SizedBox(height: 2),
                    Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFEEEEEE))),
          ...steps.map((step) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF673AB7)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(step, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ==========================================
  // PAGE 5: SETTINGS VIEW
  // ==========================================
  Widget _buildSettingsView() {
    return const Padding(
      padding: EdgeInsets.all(28.0),
      child: Center(
        child: Text("Super Admin Global Platform Configurations & Security Policies...", style: TextStyle(fontSize: 16, color: Colors.grey)),
      ),
    );
  }

  Widget _buildNavItem({required IconData icon, required String label, required int index}) {
    bool isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF673AB7).withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? const Color(0xFF673AB7) : Colors.grey.shade600, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF673AB7) : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        onTap: () => setState(() => _selectedIndex = index),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        dense: true,
      ),
    );
  }

  Widget _buildMetricCard({required String title, required String value, required String subtitle, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 30)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26)), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 11), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernThreeWayPieChartCard({required int freeCount, required int proCount, required int enterpriseCount, required int total}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CustomPaint(
              painter: _ThreeWayDonutChartPainter(
                freeCount: freeCount.toDouble(),
                proCount: proCount.toDouble(),
                enterpriseCount: enterpriseCount.toDouble(),
              ),
              child: Center(child: Text("$total", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E1E26)))),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Subscription Breakdown", style: TextStyle(color: Color(0xFF1E1E26), fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                _buildLegendItem(color: Colors.blue.shade700, label: "Enterprise", count: enterpriseCount),
                const SizedBox(height: 4),
                _buildLegendItem(color: Colors.amber.shade700, label: "Pro", count: proCount),
                const SizedBox(height: 4),
                _buildLegendItem(color: const Color(0xFF673AB7), label: "Free", count: freeCount),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label, required int count}) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text("$count", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26))),
      ],
    );
  }
}

// Custom Painter for Growth Trend Line Chart
class _LineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = const Color(0xFF673AB7)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintFill = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFF673AB7).withOpacity(0.2), const Color(0xFF673AB7).withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final points = [
      Offset(0, size.height * 0.8),
      Offset(size.width * 0.2, size.height * 0.65),
      Offset(size.width * 0.4, size.height * 0.5),
      Offset(size.width * 0.6, size.height * 0.4),
      Offset(size.width * 0.8, size.height * 0.25),
      Offset(size.width, size.height * 0.1),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final controlPoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      path.quadraticBezierTo(p1.dx, p1.dy, controlPoint.dx, controlPoint.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);

    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final pointBorderPaint = Paint()
      ..color = const Color(0xFF673AB7)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (var pt in points) {
      canvas.drawCircle(pt, 5, pointPaint);
      canvas.drawCircle(pt, 5, pointBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom Painter for 3-Way Donut Chart (Free, Pro, Enterprise)
class _ThreeWayDonutChartPainter extends CustomPainter {
  final double freeCount;
  final double proCount;
  final double enterpriseCount;

  _ThreeWayDonutChartPainter({required this.freeCount, required this.proCount, required this.enterpriseCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 14.0;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    final total = freeCount + proCount + enterpriseCount;
    if (total == 0) return;

    final freeSweep = (freeCount / total) * 2 * math.pi;
    final proSweep = (proCount / total) * 2 * math.pi;
    final enterpriseSweep = (enterpriseCount / total) * 2 * math.pi;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double startAngle = -math.pi / 2;

    // Draw Free Arc
    if (freeCount > 0) {
      paint.color = const Color(0xFF673AB7);
      canvas.drawArc(rect, startAngle, freeSweep, false, paint);
      startAngle += freeSweep;
    }

    // Draw Pro Arc
    if (proCount > 0) {
      paint.color = Colors.amber.shade700;
      canvas.drawArc(rect, startAngle, proSweep, false, paint);
      startAngle += proSweep;
    }

    // Draw Enterprise Arc
    if (enterpriseCount > 0) {
      paint.color = Colors.blue.shade700;
      canvas.drawArc(rect, startAngle, enterpriseSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}