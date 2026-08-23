import 'package:flutter/material.dart';

class AdminDatasetScreen extends StatefulWidget {
  const AdminDatasetScreen({super.key});

  @override
  State<AdminDatasetScreen> createState() => _AdminDatasetScreenState();
}

class _AdminDatasetScreenState extends State<AdminDatasetScreen> {
  final List<Map<String, dynamic>> _words = [
    {'id': 1, 'word': 'ہیلو', 'gloss': 'Hello', 'domain': 'Greetings', 'samples': 52},
    {'id': 2, 'word': 'شکریہ', 'gloss': 'Thank You', 'domain': 'Greetings', 'samples': 48},
    {'id': 3, 'word': 'پانی', 'gloss': 'Water', 'domain': 'Daily Needs', 'samples': 30},
    {'id': 4, 'word': 'مدد', 'gloss': 'Help', 'domain': 'Daily Needs', 'samples': 0},
    {'id': 5, 'word': 'ڈاکٹر', 'gloss': 'Doctor', 'domain': 'Healthcare', 'samples': 15},
    {'id': 6, 'word': 'اسکول', 'gloss': 'School', 'domain': 'Education', 'samples': 0},
    {'id': 7, 'word': 'کھانا', 'gloss': 'Food', 'domain': 'Daily Needs', 'samples': 22},
    {'id': 8, 'word': 'گھر', 'gloss': 'Home', 'domain': 'Daily Needs', 'samples': 50},
  ];

  String _filterDomain = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> get _filteredWords {
    return _words.where((w) {
      final matchesSearch = w['word'].contains(_searchQuery) ||
          w['gloss'].toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesDomain = _filterDomain == 'All' || w['domain'] == _filterDomain;
      return matchesSearch && matchesDomain;
    }).toList();
  }

  void _showAddWordDialog() {
    final wordController = TextEditingController();
    final glossController = TextEditingController();
    String selectedDomain = 'Greetings';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New PSL Word',
              style: TextStyle(color: Color(0xFF1F3864), fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordController,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'Urdu Word',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.text_fields),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: glossController,
                decoration: const InputDecoration(
                  labelText: 'English Gloss',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.translate),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedDomain,
                decoration: const InputDecoration(
                  labelText: 'Domain',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: ['Greetings', 'Healthcare', 'Education', 'Daily Needs', 'Numbers', 'Other']
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (val) => setDialogState(() => selectedDomain = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F3864)),
              onPressed: () {
                if (wordController.text.isNotEmpty && glossController.text.isNotEmpty) {
                  setState(() {
                    _words.add({
                      'id': _words.length + 1,
                      'word': wordController.text,
                      'gloss': glossController.text,
                      'domain': selectedDomain,
                      'samples': 0,
                    });
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Word added!'), backgroundColor: Colors.green),
                  );
                }
              },
              child: const Text('Add Word', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteWord(Map<String, dynamic> word) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Word'),
        content: Text('Delete "${word['gloss']}" (${word['word']})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() => _words.removeWhere((w) => w['id'] == word['id']));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"${word['gloss']}" deleted'), backgroundColor: Colors.red),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showWordDetails(Map<String, dynamic> word) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(word['word'], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1F3864))),
                      Text(word['gloss'], style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                  child: Text(word['domain'], style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Sample Progress', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F3864))),
                Text('${word['samples']}/50',
                    style: TextStyle(color: word['samples'] >= 50 ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (word['samples'] as int) / 50,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(word['samples'] >= 50 ? Colors.green : Colors.orange),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Video capture — coming when camera is integrated!'), backgroundColor: Color(0xFF1F3864)),
                  );
                },
                icon: const Icon(Icons.videocam),
                label: const Text('Capture Sample Video'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); _deleteWord(word); },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Delete Word', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalWords = _words.length;
    final totalSamples = _words.fold<int>(0, (sum, w) => sum + (w['samples'] as int));
    final underSampled = _words.where((w) => w['samples'] < 50).length;
    final completed = _words.where((w) => w['samples'] >= 50).length;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F3864),
        foregroundColor: Colors.white,
        title: const Text('Dataset Management', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddWordDialog,
        backgroundColor: const Color(0xFF1F3864),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Word', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1F3864).withOpacity(0.04),
            child: Row(
              children: [
                Expanded(child: _StatCard(title: 'Words', value: '$totalWords', color: Colors.blue, icon: Icons.text_fields)),
                const SizedBox(width: 8),
                Expanded(child: _StatCard(title: 'Samples', value: '$totalSamples', color: Colors.green, icon: Icons.video_library_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _StatCard(title: 'Done', value: '$completed', color: Colors.teal, icon: Icons.check_circle_outline)),
                const SizedBox(width: 8),
                Expanded(child: _StatCard(title: 'Needed', value: '$underSampled', color: Colors.orange, icon: Icons.warning_amber_outlined)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Overall Dataset Progress', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F3864))),
                    Text('$completed / $totalWords words complete', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: totalWords > 0 ? completed / totalWords : 0,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1F3864)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search words...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterDomain,
                      items: ['All', 'Greetings', 'Healthcare', 'Education', 'Daily Needs', 'Numbers', 'Other']
                          .map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                      onChanged: (val) => setState(() => _filterDomain = val!),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _filteredWords.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search_off, size: 60, color: Colors.grey[300]), const SizedBox(height: 12), Text('No words found', style: TextStyle(color: Colors.grey[400]))]))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: _filteredWords.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final word = _filteredWords[index];
                      final isComplete = word['samples'] >= 50;
                      final progress = (word['samples'] as int) / 50.0;
                      return GestureDetector(
                        onTap: () => _showWordDetails(word),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isComplete ? Colors.green[200]! : word['samples'] == 0 ? Colors.red[100]! : Colors.orange[200]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: isComplete ? Colors.green[50] : word['samples'] == 0 ? Colors.red[50] : Colors.orange[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isComplete ? Icons.check_circle : word['samples'] == 0 ? Icons.radio_button_unchecked : Icons.timelapse,
                                  color: isComplete ? Colors.green : word['samples'] == 0 ? Colors.red : Colors.orange,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text(word['word'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F3864))),
                                      const SizedBox(width: 6),
                                      Text('(${word['gloss']})', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                    ]),
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
                                        child: Text(word['domain'], style: TextStyle(color: Colors.blue[700], fontSize: 10)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${word['samples']}/50 samples',
                                          style: TextStyle(fontSize: 11, color: isComplete ? Colors.green[700] : Colors.orange[700], fontWeight: FontWeight.w500)),
                                    ]),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: progress.clamp(0.0, 1.0),
                                        minHeight: 4,
                                        backgroundColor: Colors.grey[200],
                                        valueColor: AlwaysStoppedAnimation<Color>(isComplete ? Colors.green : Colors.orange),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({required this.title, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 10)),
        ],
      ),
    );
  }
}