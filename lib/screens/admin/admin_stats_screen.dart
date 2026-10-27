import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/psl_words_ur.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';

/// Admin "System Statistics": users, activity, popular words, health.
class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  static const Color _navy = Color(0xFF1F3864);
  final AdminService _service = AdminService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Not logged in';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _service.getSystemStats(token);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _data = result['data'] as Map<String, dynamic>;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = result['message'] as String? ?? 'Could not load statistics';
      });
    }
  }

  int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('System Statistics',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final d = _data!;
    final users = Map<String, dynamic>.from(d['users'] ?? {});
    final dataset = Map<String, dynamic>.from(d['dataset'] ?? {});
    final health = Map<String, dynamic>.from(d['health'] ?? {});
    final perDay = (d['sentences_per_day'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final topWords = (d['top_words'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _title('Overview'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _tile('Users', '${_int(users['total'])}', Icons.people_outline, Colors.blue),
              _tile('Active users', '${_int(users['active'])}', Icons.check_circle_outline, Colors.green),
              _tile('Admins', '${_int(users['admins'])}', Icons.admin_panel_settings_outlined, Colors.purple),
              _tile('Sessions', '${_int(d['sessions_total'])}', Icons.history, Colors.orange),
              _tile('Sentences', '${_int(d['sentences_total'])}', Icons.chat_bubble_outline, Colors.teal),
              _tile('Dataset words', '${_int(dataset['words'])}', Icons.text_fields, Colors.indigo),
              _tile('Dataset samples', '${_int(dataset['samples'])}', Icons.video_library_outlined, Colors.brown),
            ],
          ),
          const SizedBox(height: 24),
          _title('Sentences, last 7 days'),
          _card(_buildBars(perDay)),
          const SizedBox(height: 24),
          _title('Most used words'),
          _card(topWords.isEmpty
              ? const Text('No sentences yet.',
                  style: TextStyle(color: Colors.grey))
              : Column(
                  children: [
                    for (final w in topWords)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${pslUrdu[w['word']] ?? w['word']}   (${w['word']})',
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            Text('${_int(w['count'])}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, color: _navy)),
                          ],
                        ),
                      ),
                  ],
                )),
          const SizedBox(height: 24),
          _title('System health'),
          _card(Column(
            children: [
              _health('Database', health['database'] == true),
              _health('Recognition model loaded', health['model_loaded'] == true,
                  offText: 'Not loaded yet (loads on first use)'),
              _health('Voice (ElevenLabs) configured',
                  health['voice_configured'] == true,
                  offText: 'API key missing'),
              _health('E-mail sending configured',
                  health['email_configured'] == true,
                  offText: 'Dev mode (codes print in the server terminal)'),
              _health('E-mail verification required',
                  health['email_verification_required'] == true,
                  offText: 'Off'),
            ],
          )),
          const SizedBox(height: 12),
          const Text(
            'Recognition accuracy is not tracked live. See Model Management for the measured test results.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: _navy)),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: child,
      );

  Widget _tile(String label, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _health(String label, bool ok, {String? offText}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.remove_circle_outline,
              color: ok ? Colors.green : Colors.orange[800], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok || offText == null ? label : '$label: $offText',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBars(List<Map<String, dynamic>> perDay) {
    if (perDay.isEmpty) {
      return const Text('No data.', style: TextStyle(color: Colors.grey));
    }
    final maxCount =
        perDay.map((e) => _int(e['count'])).fold<int>(0, (a, b) => a > b ? a : b);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in perDay)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${_int(e['count'])}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    height: maxCount == 0
                        ? 2
                        : 2 + 80.0 * _int(e['count']) / maxCount,
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    names[DateTime.parse(e['date'] as String).weekday - 1],
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
