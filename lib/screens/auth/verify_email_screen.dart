import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/verification_service.dart';

/// Asks for the 6-digit code that was e-mailed after registration.
/// Pops with `true` when the e-mail is verified, so the caller can
/// continue to the login screen:
///
///   final ok = await Navigator.push<bool>(context, MaterialPageRoute(
///       builder: (_) => VerifyEmailScreen(email: email)));
///
/// Set [sendCodeOnOpen] when the user did NOT just register (for example
/// when login says "please verify"): a fresh code is e-mailed on open.
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final bool sendCodeOnOpen;

  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.sendCodeOnOpen = false,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const Color _navy = Color(0xFF1F3864);

  final VerificationService _service = VerificationService();
  final TextEditingController _codeController = TextEditingController();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _error;
  String? _info;
  int _cooldown = 60; // a code was just sent, so wait before asking again
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.sendCodeOnOpen) {
      _cooldown = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoSend());
    } else {
      _startCooldown(60); // a code was just sent at registration
    }
  }

  /// Asks the server for a fresh code as the screen opens.
  Future<void> _autoSend() async {
    setState(() => _isResending = true);
    final result = await _service.resend(email: widget.email);
    if (!mounted) return;
    setState(() => _isResending = false);
    if (result['success'] == true) {
      setState(() => _info = 'We sent a new code to ${widget.email}.');
      _startCooldown(60);
    } else if (result['retry_after'] is int) {
      // A code was sent a moment ago - use that one.
      setState(() => _info = 'A code was sent a moment ago. Check your e-mail.');
      _startCooldown(result['retry_after'] as int);
    } else {
      setState(() => _error = result['message'] as String? ?? 'Could not send a code');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Please enter the 6-digit code.');
      return;
    }
    setState(() {
      _isVerifying = true;
      _error = null;
      _info = null;
    });
    final result = await _service.verify(email: widget.email, code: code);
    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isVerifying = false;
        _error = result['message'] as String? ?? 'Verification failed';
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
      _info = null;
    });
    final result = await _service.resend(email: widget.email);
    if (!mounted) return;
    setState(() => _isResending = false);
    if (result['success'] == true) {
      _codeController.clear();
      setState(() => _info = 'A new code was sent. Older codes no longer work.');
      _startCooldown(60);
    } else {
      final wait = result['retry_after'] as int?;
      setState(() => _error = result['message'] as String? ?? 'Could not resend');
      if (wait != null) _startCooldown(wait);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Verify your e-mail'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_read_outlined,
                      size: 64, color: _navy),
                  const SizedBox(height: 16),
                  Text(
                    widget.sendCodeOnOpen
                        ? 'Enter the 6-digit code sent to\n${widget.email}'
                        : 'We sent a 6-digit code to\n${widget.email}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 28, letterSpacing: 8),
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '------',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _verify(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red)),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.green[700])),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: (_isVerifying || _isResending) ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verify',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: (_cooldown > 0 || _isResending || _isVerifying)
                        ? null
                        : _resend,
                    child: Text(_isResending
                        ? 'Sending...'
                        : (_cooldown > 0
                            ? 'Send a new code in ${_cooldown}s'
                            : 'Send a new code')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
