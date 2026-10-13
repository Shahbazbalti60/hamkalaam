import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';

/// Password reset in two steps, on one screen:
///   1. enter your e-mail  -> server e-mails a 6-digit code
///   2. enter the code + a new password -> password is changed
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() => _error = 'Please enter a valid e-mail address.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await Provider.of<AuthService>(context, listen: false)
        .forgotPassword(email);

    if (!mounted) return;
    setState(() => _busy = false);

    if (result['success'] == true) {
      setState(() => _codeSent = true);
    } else {
      setState(() => _error = result['message'] ?? 'Could not send the code.');
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final password = _passwordController.text;

    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your e-mail.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await Provider.of<AuthService>(context, listen: false)
        .resetPassword(
      email: _emailController.text.trim(),
      code: code,
      newPassword: password,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. You can now log in.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      setState(() => _error = result['message'] ?? 'Could not reset password.');
    }
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F3864),
        foregroundColor: Colors.white,
        title: const Text('Forgot Password',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_reset,
                    size: 64, color: Color(0xFF1F3864)),
                const SizedBox(height: 16),
                Text(
                  _codeSent ? 'Enter your reset code' : 'Reset your password',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F3864)),
                ),
                const SizedBox(height: 8),
                Text(
                  _codeSent
                      ? 'We sent a 6-digit code to ${_emailController.text.trim()}. '
                          'It is valid for 15 minutes.'
                      : 'Enter the e-mail you registered with and we will send you a 6-digit code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (!_codeSent) ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_busy,
                    decoration: _decoration('Email', Icons.email_outlined),
                    onSubmitted: (_) => _sendCode(),
                  ),
                ] else ...[
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !_busy,
                    decoration:
                        _decoration('6-digit code', Icons.pin_outlined)
                            .copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _hidePassword,
                    enabled: !_busy,
                    decoration: _decoration(
                      'New password',
                      Icons.lock_outline,
                      suffix: IconButton(
                        icon: Icon(_hidePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmController,
                    obscureText: _hidePassword,
                    enabled: !_busy,
                    decoration: _decoration(
                        'Confirm new password', Icons.lock_outline),
                    onSubmitted: (_) => _resetPassword(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red[700], fontSize: 13)),
                ],
                const SizedBox(height: 22),
                ElevatedButton(
                  onPressed: _busy ? null : (_codeSent ? _resetPassword : _sendCode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F3864),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _codeSent ? 'Reset password' : 'Send code',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _sendCode,
                    child: const Text('Resend code'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _error = null;
                            }),
                    child: const Text('Use a different e-mail'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
