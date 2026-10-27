import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/dataset_service.dart';
import '../auth/login_screen.dart';
import '../admin/admin_user_management_screen.dart';
import '../admin/admin_dataset_screen.dart';
import '../admin/admin_model_screen.dart';
import '../admin/admin_stats_screen.dart';
import 'profile_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final DatasetService _datasetService = DatasetService();

  bool _isLoadingStats = true;
  int _totalWords = 0;
  int _totalSamples = 0;
  int _underSampled = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null) {
      setState(() => _isLoadingStats = false);
      return;
    }

    final result = await _datasetService.getStatistics(token);

    if (!mounted) return;

    if (result['success'] == true) {
      final stats = result['stats'] as Map<String, dynamic>;
      setState(() {
        _totalWords = (stats['total_words'] as num?)?.toInt() ?? 0;
        _totalSamples = (stats['total_samples'] as num?)?.toInt() ?? 0;
        _underSampled = (stats['words_under_target'] as num?)?.toInt() ?? 0;
        _isLoadingStats = false;
      });
    } else {
      setState(() => _isLoadingStats = false);
    }
  }

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
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Admin welcome card — informational only. Profile is
              // reached via the dedicated "My Profile" action card
              // below, not by tapping this card (avoids two paths to
              // the same destination).
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

              // Dataset stats row — real data from /api/dataset/statistics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dataset Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F3864))),
                  if (_isLoadingStats)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(child: _StatCard(label: 'Total Words', value: '$_totalWords', icon: Icons.text_fields, color: Colors.blue)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Total Samples', value: '$_totalSamples', icon: Icons.video_library_outlined, color: Colors.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Under-sampled', value: '$_underSampled', icon: Icons.warning_amber_outlined, color: Colors.orange)),
                ],
              ),

              const SizedBox(height: 24),

              const Text('Admin Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F3864))),
              const SizedBox(height: 14),

              _AdminActionCard(
                icon: Icons.video_camera_back_outlined,
                title: 'Dataset Management',
                subtitle: 'Capture PSL gesture videos, add words, manage samples',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminDatasetScreen()),
                  );
                  // Refresh stats in case words were added/deleted
                  // while the person was on that screen.
                  _loadStats();
                },
              ),

              const SizedBox(height: 12),

              _AdminActionCard(
                icon: Icons.people_outline,
                title: 'User Management',
                subtitle: 'View registered users, manage roles and accounts',
                onTap: () {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AdminUserManagementScreen()));
                },
              ),

              const SizedBox(height: 12),

              _AdminActionCard(
                icon: Icons.person_outline,
                title: 'My Profile',
                subtitle: 'Manage your account and preferences',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
              ),

              const SizedBox(height: 12),

              _AdminActionCard(
                icon: Icons.model_training,
                title: 'Model Management',
                subtitle: 'See the recognition model, its test results, and reload it',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminModelScreen()),
                  );
                },
              ),

              const SizedBox(height: 12),

              _AdminActionCard(
                icon: Icons.analytics_outlined,
                title: 'System Statistics',
                subtitle: 'View usage, daily activity, popular words, and system health',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminStatsScreen()),
                  );
                },
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
                        'Recognition currently uses a model trained on the public SignSpeak PSL dataset. Samples recorded here are kept to improve the model on your own camera and signers.',
                        style: TextStyle(color: Colors.amber[900], fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
  final VoidCallback onTap;

  const _AdminActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

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
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}