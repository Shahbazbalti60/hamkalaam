import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/webview_page.dart';

/// Small phone test: opens the front camera inside a WebView and shows how
/// many hands / faces the detector sees. Not part of the final app flow.
class WebViewTestScreen extends StatefulWidget {
  const WebViewTestScreen({super.key});

  @override
  State<WebViewTestScreen> createState() => _WebViewTestScreenState();
}

class _WebViewTestScreenState extends State<WebViewTestScreen> {
  WebViewController? _controller;
  String _status = 'Asking for camera permission...';
  int _hands = 0;
  bool _face = false;
  int _segments = 0;
  int _ticks = 0;
  String _console = '';

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
        var granted = true;
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cams.first);
      final cc = CameraController(front, ResolutionPreset.low, enableAudio: false);
      await cc.initialize();
      await cc.dispose();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    if (!granted) {
      setState(() => _status = 'Camera permission was refused.');
      return;
    }
    final c = WebViewController(
      onPermissionRequest: (request) => request.grant(),
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Hamkalaam', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          // Only a failure of the page itself matters; a missing icon or
          // similar small file is ignored.
          if (e.isForMainFrame == true && mounted) {
            setState(() => _status = 'Page error: ${e.description}');
          }
        },
      ))
      ..setOnConsoleMessage((m) {
        if (m.level == JavaScriptLogLevel.error && mounted) {
          setState(() => _console = m.message);
        }
      })
      ..loadHtmlString(kWebViewPageHtml, baseUrl: 'https://hamkalaam.app/');
    setState(() {
      _controller = c;
      _status = 'Loading detector (needs internet)...';
    });
  }

  void _onMessage(JavaScriptMessage m) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(m.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    switch (msg['type']) {
      case 'log':
        setState(() => _status = '${msg['message']}');
        break;
      case 'ready':
        setState(() => _status = 'Detector ready. Starting camera...');
        _controller?.runJavaScript('hkStart()');
        break;
      case 'started':
        setState(() => _status = 'Camera running. Show your hand and face.');
        _controller?.runJavaScript('hkContinuous(true)');
        break;
      case 'error':
        setState(() => _status = 'ERROR (${msg['where']}): ${msg['message']}');
        break;
      case 'tick':
        final hand = msg['hand'] as Map<String, dynamic>? ?? {};
        final face = msg['face'] as Map<String, dynamic>? ?? {};
        setState(() {
          _ticks++;
          _hands = (hand['handCount'] as num?)?.toInt() ?? 0;
          _face = face['detected'] == true;
        });
        break;
      case 'segment':
        setState(() => _segments++);
        break;
    }
  }

  @override
  void dispose() {
    _controller?.runJavaScript('hkStop()');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F3864),
        foregroundColor: Colors.white,
        title: const Text('Camera test (WebView)'),
      ),
      body: Column(
        children: [
          Expanded(
            child: c == null
                ? Center(child: Text(_status))
                : WebViewWidget(controller: c),
          ),
          Container(
            width: double.infinity,
            color: Colors.grey[900],
            padding: const EdgeInsets.all(12),
            child: Text(
              '$_status\nhands: $_hands   face: ${_face ? "yes" : "no"}   '
              'words cut: $_segments   updates: $_ticks'
              '${_console.isEmpty ? "" : "\nconsole: $_console"}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
