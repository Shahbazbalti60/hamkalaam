r"""Connects the e-mail verification screen to the register and login flow.

Run ONCE from E:\Projects\hamkalaam:   python wire_verification.py

It edits 3 files (auth_service.dart, register_screen.dart, login_screen.dart).
Nothing is written unless EVERY replacement matches exactly, and each
edited file is first copied to <name>.bak (delete the .bak files after testing).
"""
import os
import shutil
import sys

BASE = os.path.join("lib")
AUTH_SERVICE = os.path.join(BASE, "services", "auth_service.dart")
REGISTER = os.path.join(BASE, "screens", "auth", "register_screen.dart")
LOGIN = os.path.join(BASE, "screens", "auth", "login_screen.dart")

EDITS = {
    AUTH_SERVICE: [
        # login: pass the "verification_required" flag from the server on
        (r"""      } else if (e.response?.statusCode == 403) {
        return {'success': false, 'message': 'Please verify your email first'};
      }""",
         r"""      } else if (e.response?.statusCode == 403) {
        final data = e.response?.data;
        return {
          'success': false,
          'message': 'Please verify your email first',
          if (data is Map && data['verification_required'] == true)
            'verification_required': true,
          if (data is Map && data['email'] != null)
            'email': data['email'].toString(),
        };
      }"""),
        # register: pass the flag on success
        (r"""      if (response.statusCode == 201) {
        return {'success': true};
      }
    } on DioException catch (e) {
      _isLoading = false;
      notifyListeners();
      if (e.response?.statusCode == 400) {""",
         r"""      if (response.statusCode == 201) {
        final data = response.data;
        return {
          'success': true,
          'verification_required':
              data is Map && data['verification_required'] == true,
          'email': data is Map ? data['email']?.toString() : null,
        };
      }
    } on DioException catch (e) {
      _isLoading = false;
      notifyListeners();
      if (e.response?.statusCode == 400) {"""),
    ],
    REGISTER: [
        (r"""import 'login_screen.dart';
""", r"""import 'login_screen.dart';
import 'verify_email_screen.dart';
"""),
        (r"""  bool _registered = false;
""", r"""  bool _registered = false;
  bool _verified = false;
  bool _needsVerification = false;
"""),
        (r"""    if (result['success']) {
      setState(() => _registered = true);
    } else {""",
         r"""    if (result['success']) {
      if (result['verification_required'] == true) {
        // E-mail verification is switched on: ask for the 6-digit code.
        final verified = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(
              email: (result['email'] as String?) ?? _emailController.text.trim(),
            ),
          ),
        );
        if (!mounted) return;
        setState(() {
          _registered = true;
          _needsVerification = true;
          _verified = verified == true;
        });
      } else {
        setState(() => _registered = true);
      }
    } else {"""),
        (r"""                const Text(
                  'Check Your Email!',
                  style: TextStyle(""",
         r"""                Text(
                  _verified
                      ? 'Email Verified!'
                      : (_needsVerification ? 'Almost There!' : 'Account Created!'),
                  style: const TextStyle("""),
        (r"""                  'We sent a verification link to\n${_emailController.text.trim()}\n\nClick the link to activate your account.',""",
         r"""                  _verified
                      ? '${_emailController.text.trim()}\n\nis verified. You can now sign in.'
                      : (_needsVerification
                          ? 'Your account is created, but ${_emailController.text.trim()} is not verified yet.\n\nSign in and we will ask for the code again.'
                          : 'Your account has been created.\n\nYou can now sign in.'),"""),
    ],
    LOGIN: [
        (r"""import 'forgot_password_screen.dart';
""", r"""import 'forgot_password_screen.dart';
import 'verify_email_screen.dart';
"""),
        (r"""    } else {
      setState(() => _errorMessage = result['message']);
    }
  }""",
         r"""    } else if (result['verification_required'] == true) {
      // Correct password, but the e-mail is not verified yet.
      final email =
          (result['email'] as String?) ?? _emailController.text.trim();
      final verified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(email: email, sendCodeOnOpen: true),
        ),
      );
      if (!mounted) return;
      if (verified == true) {
        await _login(); // verified now: sign in with the typed password
      } else {
        setState(() => _errorMessage = 'Please verify your email to continue.');
      }
    } else {
      setState(() => _errorMessage = result['message']);
    }
  }"""),
    ],
}


def main():
    new_texts = {}
    for path, edits in EDITS.items():
        if not os.path.isfile(path):
            sys.exit(f"File not found: {path}\nRun this from E:\\Projects\\hamkalaam")
        with open(path, "r", encoding="utf-8", newline="") as f:
            raw = f.read()
        crlf = "\r\n" in raw
        text = raw.replace("\r\n", "\n")
        if "verify_email_screen.dart" in text or "verification_required" in text:
            print(f"{path}: already wired, skipping.")
            continue
        for i, (old, new) in enumerate(edits, 1):
            n = text.count(old)
            if n != 1:
                sys.exit(
                    f"STOPPED - nothing was changed.\n{path}: edit {i} matched {n} times "
                    f"(expected 1). Send me this file and I will adjust the patch.")
            text = text.replace(old, new, 1)
        new_texts[path] = text.replace("\n", "\r\n") if crlf else text

    for path, text in new_texts.items():
        shutil.copy(path, path + ".bak")
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        print(f"patched {path}  (backup: {path}.bak)")
    print("Done." if new_texts else "Nothing to do.")


if __name__ == "__main__":
    main()
