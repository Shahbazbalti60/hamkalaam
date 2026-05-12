import 'package:flutter/material.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  // Dummy data — will be replaced with real API data later
  final List<Map<String, dynamic>> _sessions = [
    {
      'id': 1,
      'date': '11 May 2026',
      'time': '10:30 AM',
      'sentences': [
        {'urdu': 'کیا آپ مجھے پانی دے سکتے ہیں؟', 'words': 'Water, Give, Me', 'expression': 'Question'},
        {'urdu': 'مجھے ڈاکٹر سے ملنا ہے', 'words': 'Doctor, Meet, Need', 'expression': 'Neutral'},
      ],
    },
    {
      'id': 2,
      'date': '10 May 2026',
      'time': '3:45 PM',
      'sentences': [
        {'urdu': 'شکریہ آپ کا', 'words': 'Thank You', 'expression': 'Happy'},
        {'urdu': 'مجھے مدد چاہیے', 'words': 'Help, Need', 'expression': 'Neutral'},
        {'urdu': 'کیا یہ ٹھیک ہے؟', 'words': 'This, Okay', 'expression': 'Question'},
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F3864),
        foregroundColor: Colors.white,
        title: const Text('Session History',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _sessions.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                return _SessionCard(session: _sessions[index]);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No Sessions Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F3864),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start signing to see your session history here.',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  const _SessionCard({required this.session});

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sentences = widget.session['sentences'] as List;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Session header
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F3864).withOpacity(0.04),
                borderRadius: _expanded
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      )
                    : BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F3864).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.chat_bubble_outline,
                        color: Color(0xFF1F3864), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.session['date'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F3864),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.session['time']}  ·  ${sentences.length} sentence${sentences.length > 1 ? 's' : ''}',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xFF1F3864),
                  ),
                ],
              ),
            ),
          ),

          // Sentences list
          if (_expanded)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: sentences.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final sentence = sentences[index];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Urdu sentence
                      Text(
                        sentence['urdu'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F3864),
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 8),
                      // Word sequence
                      Row(
                        children: [
                          Icon(Icons.sign_language,
                              size: 14, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              sentence['words'],
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Expression badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _getExpressionColor(sentence['expression'])
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sentence['expression'],
                          style: TextStyle(
                            fontSize: 11,
                            color: _getExpressionColor(
                                sentence['expression']),
                            fontWeight: FontWeight.w500,
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
  }

  Color _getExpressionColor(String expression) {
    switch (expression) {
      case 'Question':
        return Colors.blue;
      case 'Happy':
        return Colors.green;
      case 'Sad':
        return Colors.indigo;
      case 'Negation':
        return Colors.red;
      case 'Affirmation':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
}