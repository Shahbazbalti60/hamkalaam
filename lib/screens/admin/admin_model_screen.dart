import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/psl_words_ur.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';

/// Admin "Model Management": what the recogniser is, where it comes
/// from, measured accuracy, and a button to load the model files again.
class AdminModelScreen extends StatefulWidget {
  const AdminModelScreen({super.key});

  @override
  State<AdminModelScreen> createState() => _AdminModelScreenState();
}

class _AdminModelScreenState extends State<AdminModelScreen> {
  static const Color _navy = Color(0xFF1F3864);
  final AdminService _service = AdminService();

  bool _loading = true;
  bool _reloading = false;
  String? _error;
  Map<String, dynamic>? _data;

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
    final result = await _service.getModelStatus(token);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _data = result['data'] as Map<String, dynamic>;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = result['message'] as String? ?? 'Could not load model status';
      });
    }
  }

  Future<void> _reload() async {
    final token = _token;
    if (token == null) return;
    setState(() => _reloading = true);
    final result = await _service.reloadModel(token);
    if (!mounted) return;
    setState(() => _reloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['success'] == true
            ? 'Model reloaded (${result['word_count']} words).'
            : (result['message'] as String? ?? 'Reload failed')),
        backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      ),
    );
    _load();
  }

  String _when(String? iso) {
    if (iso == null) return '-';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final min = d.minute.toString().padLeft(2, '0');
      return '${d.day} ${months[d.month - 1]} ${d.year}, $h12:$min ${d.hour >= 12 ? 'PM' : 'AM'}';
    } catch (_) {
      return '-';
    }
  }

  /// Turns results.json into display rows (one level of nesting).
  List<MapEntry<String, String>> _resultRows(dynamic results) {
    final rows = <MapEntry<String, String>>[];
    String fmt(dynamic v) {
      if (v is double && v >= 0 && v <= 1) {
        return '${(v * 100).toStringAsFixed(1)} %';
      }
      return v.toString();
    }

    void walk(String prefix, dynamic node, int depth) {
      if (rows.length >= 24) return;
      if (node is Map && depth < 2) {
        node.forEach((k, v) => walk(prefix.isEmpty ? '$k' : '$prefix.$k', v, depth + 1));
      } else if (node is num || node is String || node is bool) {
        rows.add(MapEntry(prefix, fmt(node)));
      }
    }

    walk('', results, 0);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Model Management',
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
    final loaded = d['loaded'] == true;
    final file = d['model_file'] is Map
        ? Map<String, dynamic>.from(d['model_file'])
        : null;
    final words = (d['words'] as List? ?? []).map((e) => e.toString()).toList();
    final resultRows = _resultRows(d['results']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    loaded ? Icons.check_circle : Icons.hourglass_empty,
                    color: loaded ? Colors.green : Colors.orange[800],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      loaded
                          ? 'Model is loaded and ready'
                          : 'Model not loaded yet (it loads on first use)',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _row('Type', 'LSTM word recogniser (3 layers)'),
              _row('Vocabulary', '${d['word_count']} PSL words'),
              _row('Input', '${d['sequence_length']} frames x hand landmarks'),
              if (d['parameters'] != null)
                _row('Parameters', '${d['parameters']}'),
              _row('Model file',
                  file == null ? 'NOT FOUND' : '${file['name']}  (${file['size_mb']} MB)'),
              _row('File updated', _when(file?['modified_at'] as String?)),
              _row('TensorFlow installed',
                  d['tensorflow_installed'] == true ? 'Yes' : 'No'),
              _row('Needs hand in at least',
                  '${((d['min_hands_ratio'] as num? ?? 0) * 100).toStringAsFixed(0)} % of frames'),
              _row('"Uncertain" below',
                  '${((d['confident_threshold'] as num? ?? 0) * 100).toStringAsFixed(0)} % confidence'),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _reloading ? null : _reload,
                  icon: _reloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_reloading ? 'Loading model...' : 'Reload model from disk'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Use this after copying a newly trained model file into the server. The running model is kept if the new one fails to load.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          )),
          const SizedBox(height: 20),
          _title('Training source'),
          _card(const Text(
            'Trained on the public "Dynamic Word Level Pakistan Sign Language Dataset" (SignSpeak team, COMSATS Abbottabad, Apache-2.0). Samples recorded in this app are kept for future improvement of the model.',
            style: TextStyle(height: 1.5),
          )),
          const SizedBox(height: 20),
          _title('Measured test results'),
          _card(resultRows.isEmpty
              ? const Text(
                  'No results file found. Copy results.json from the training notebook into app/ai/model/ on the server to show the accuracy numbers here.',
                  style: TextStyle(color: Colors.grey, height: 1.5),
                )
              : Column(
                  children: [
                    for (final r in resultRows) _row(r.key, r.value),
                  ],
                )),
          const SizedBox(height: 20),
          _title('Vocabulary (${words.length})'),
          _card(words.isEmpty
              ? const Text('labels.json not found.',
                  style: TextStyle(color: Colors.grey))
              : Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final w in words)
                      Chip(
                        label: Text('${pslUrdu[w] ?? w}  $w',
                            style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                )),
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

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                flex: 4,
                child: Text(label,
                    style: const TextStyle(color: Colors.grey, fontSize: 13))),
            Expanded(
                flex: 6,
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
