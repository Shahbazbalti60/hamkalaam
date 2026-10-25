import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/dataset_service.dart';

/// Lists every recorded sample of ONE word, so the admin can remove
/// bad takes (poor lighting, wrong sign, blur) - SRDS FR-11.
class SampleListScreen extends StatefulWidget {
  final int wordId;
  final String urduWord;
  final String gloss;

  const SampleListScreen({
    super.key,
    required this.wordId,
    required this.urduWord,
    required this.gloss,
  });

  @override
  State<SampleListScreen> createState() => _SampleListScreenState();
}

class _SampleListScreenState extends State<SampleListScreen> {
  static const Color _navy = Color(0xFF1F3864);
  final DatasetService _service = DatasetService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _samples = [];
  bool _changed = false; // tells the previous screen to refresh counts

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _token =>
      Provider.of<AuthService>(context, listen: false).accessToken;

  Future<void> _load() async {
    final token = _token;
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
    final result = await _service.getSamples(token: token, wordId: widget.wordId);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _samples = List<Map<String, dynamic>>.from(
            (result['samples'] as List).map((e) => Map<String, dynamic>.from(e)));
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = result['message'] ?? 'Could not load samples';
      });
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> sample, int number) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete sample $number?'),
        content: const Text('The video file and its record will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final token = _token;
    if (token == null) return;

    final result =
        await _service.deleteSample(token: token, sampleId: sample['id'] as int);
    if (!mounted) return;
    if (result['success'] == true) {
      _changed = true;
      setState(() => _samples.removeWhere((s) => s['id'] == sample['id']));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sample deleted'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Could not delete'),
            backgroundColor: Colors.red),
      );
    }
  }

  String _when(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final min = d.minute.toString().padLeft(2, '0');
      final ap = d.hour >= 12 ? 'PM' : 'AM';
      return '${d.day} ${months[d.month - 1]}, $h12:$min $ap';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: Text('${widget.urduWord}  (${widget.gloss})'),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
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
    if (_samples.isEmpty) {
      return const Center(child: Text('No samples recorded for this word yet.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _samples.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = _samples[i];
          final dur = (s['duration_seconds'] as num?)?.toDouble();
          final light = (s['lighting_level'] as num?)?.toDouble();
          final lowLight = light != null && light < 80;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _navy.withValues(alpha: 0.1),
              child: Text('${i + 1}', style: const TextStyle(color: _navy)),
            ),
            title: Text(
              [
                if (dur != null) '${dur.toStringAsFixed(1)} s',
                if (light != null) 'light ${light.round()}',
              ].join('   ·   '),
            ),
            subtitle: Text(
              _when(s['captured_at'] as String?),
              style: TextStyle(color: lowLight ? Colors.orange[800] : null),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete this sample',
              onPressed: () => _confirmDelete(s, i + 1),
            ),
          );
        },
      ),
    );
  }
}
