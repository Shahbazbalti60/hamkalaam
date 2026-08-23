import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import '../admin/admin_user_management_screen.dart';
import '../admin/admin_dataset_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F3864),
        foregroundColor: Colors.white,
        title: const Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.logout();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Admin welcome card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F3864), Color(0xFF2E5090)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1F3864).withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Administrator', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                            Text(
                              authService.userName ?? 'Admin',
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Manage the HamKalaam dataset, users, and system settings.',
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Dataset stats row
            const Text('Dataset Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F3864))),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(child: _StatCard(label: 'Total Words', value: '0', icon: Icons.text_fields, color: Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(label: 'Total Samples', value: '0', icon: Icons.video_library_outlined, color: Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(label: 'Under-sampled', value: '0', icon: Icons.warning_amber_outlined, color: Colors.orange)),
              ],
            ),

            const SizedBox(height: 24),

            const Text('Admin Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F3864))),
            const SizedBox(height: 14),

            _AdminActionCard(
              icon: Icons.video_camera_back_outlined,
              title: 'Dataset Management',
              subtitle: 'Capture PSL gesture videos, add words, manage samples',
              tag: 'Active',
              tagColor: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminDatasetScreen()),
                );
              },
            ),

            const SizedBox(height: 12),

            _AdminActionCard(
              icon: Icons.people_outline,
              title: 'User Management',
              subtitle: 'View registered users, manage roles and accounts',
              tag: 'Active',
              tagColor: Colors.green,
              onTap: () {
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminUserManagementScreen()));
              },
            ),

            const SizedBox(height: 12),

            _AdminActionCard(
              icon: Icons.model_training,
              title: 'Model Management',
              subtitle: 'Monitor AI model status and trigger retraining',
              tag: 'Coming Soon',
              tagColor: Colors.orange,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Model Management — available after dataset collection.')),
                );
              },
            ),

            const SizedBox(height: 12),

            _AdminActionCard(
              icon: Icons.analytics_outlined,
              title: 'System Statistics',
              subtitle: 'View recognition accuracy, session logs, and system health',
              tag: 'Coming Soon',
              tagColor: Colors.orange,
              onTap: () {},
            ),

            const SizedBox(height: 24),

            // Info banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber[800], size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Dataset collection is the current priority. Capture at least 50 samples per word for all 100 target words before model training begins.',
                      style: TextStyle(color: Colors.amber[900], fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _AdminActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final Color tagColor;
  final VoidCallback onTap;

  const _AdminActionCard({required this.icon, required this.title, required this.subtitle, required this.tag, required this.tagColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1F3864).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF1F3864), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1F3864))),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tagColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(tag, style: TextStyle(fontSize: 11, color: tagColor, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}