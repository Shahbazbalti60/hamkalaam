import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../config/app_config.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  /// The single AuthService created by Provider. ApiClient uses this to
  /// ask for a fresh token when a request comes back 401 (expired).
  static AuthService? instance;

  // Plain Dio (no auto-retry) for login/register/logout/renew/password.
  final Dio _plainDio = Dio();
  // Dio with automatic "renew token and retry once" for logged-in calls.
  late final Dio _authedDio = ApiClient.create();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Change AppConfig.apiHost in lib/config/app_config.dart to switch
  // between web (127.0.0.1) and phone (LAN IP) testing.
  static String get baseUrl => '${AppConfig.apiHost}/api/auth';

  String? _accessToken;
  String? _userRole;
  String? _userName;
  String? _userEmail;
  bool _isLoading = false;

  Timer? _renewTimer;
  Future<bool>? _renewInFlight;

  String? get accessToken => _accessToken;
  String? get userRole => _userRole;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _accessToken != null;
  bool get isAdmin => _userRole == 'Admin';

  AuthService() {
    instance = this;
    _loadToken();
  }

  @override
  void dispose() {
    _renewTimer?.cancel();
    if (identical(instance, this)) instance = null;
    super.dispose();
  }

  Future<void> _loadToken() async {
    try {
      final stored = await _storage.read(key: 'access_token');
      if (stored != null) {
        if (JwtDecoder.isExpired(stored)) {
          // Too old to renew — throw it away so the app goes to login
          // instead of failing on every request.
          await _storage.delete(key: 'access_token');
        } else {
          _accessToken = stored;
          _extractUserInfo(stored);
          _startRenewTimer();
          notifyListeners();
        }
      }
    } catch (e) {
      _accessToken = null;
    }
  }

  void _extractUserInfo(String token) {
    try {
      Map<String, dynamic> decoded = JwtDecoder.decode(token);
      _userRole = decoded['role'] ?? 'User';
      _userName = decoded['name'] ?? 'User';
      _userEmail = decoded['email'] ?? '';
    } catch (e) {
      _userRole = 'User';
    }
  }

  // ───────────────────────── token renewal ─────────────────────────

  /// Checks once a minute; when the token has under 10 minutes left,
  /// quietly swaps it for a fresh one. Keeps the session alive for as
  /// long as the app is open.
  void _startRenewTimer() {
    _renewTimer?.cancel();
    _renewTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final token = _accessToken;
      if (token == null) return;
      try {
        if (JwtDecoder.getRemainingTime(token) < const Duration(minutes: 10)) {
          await renewToken();
        }
      } catch (_) {}
    });
  }

  /// Exchanges the current (still valid) token for a new one.
  /// Safe to call from several places at once — they share one request.
  Future<bool> renewToken() {
    if (_accessToken == null) return Future.value(false);
    return _renewInFlight ??= _doRenew().whenComplete(() => _renewInFlight = null);
  }

  Future<bool> _doRenew() async {
    try {
      final response = await _plainDio.post(
        '$baseUrl/renew',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      final newToken = response.data['access_token'] as String?;
      if (response.statusCode == 200 && newToken != null) {
        _accessToken = newToken;
        await _storage.write(key: 'access_token', value: newToken);
        _extractUserInfo(newToken);
        notifyListeners();
        return true;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        // Token is really dead (expired / account disabled) — stop trying.
        _renewTimer?.cancel();
      }
    } catch (_) {}
    return false;
  }

  // ───────────────────────── login / register ─────────────────────────

  Future<Map<String, dynamic>> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _plainDio.post(
        '$baseUrl/login',
        data: {'email': email, 'password': password},
      );

      if (response.statusCode == 200) {
        _accessToken = response.data['access_token'];
        await _storage.write(key: 'access_token', value: _accessToken);
        _extractUserInfo(_accessToken!);
        _startRenewTimer();
        _isLoading = false;
        notifyListeners();
        return {'success': true, 'role': _userRole};
      }
    } on DioException catch (e) {
      _isLoading = false;
      notifyListeners();
      if (e.response?.statusCode == 401) {
        return {'success': false, 'message': 'Invalid email or password'};
      } else if (e.response?.statusCode == 403) {
        final data = e.response?.data;
        return {
          'success': false,
          'message': 'Please verify your email first',
          if (data is Map && data['verification_required'] == true)
            'verification_required': true,
          if (data is Map && data['email'] != null)
            'email': data['email'].toString(),
        };
      }
      return {'success': false, 'message': 'Cannot connect to server'};
    }

    _isLoading = false;
    notifyListeners();
    return {'success': false, 'message': 'Something went wrong'};
  }

  Future<Map<String, dynamic>> register(
      String name, String email, String password, String role) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _plainDio.post(
        '$baseUrl/register',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'role': role,
        },
      );

      _isLoading = false;
      notifyListeners();

      if (response.statusCode == 201) {
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
      if (e.response?.statusCode == 400) {
        return {
          'success': false,
          'message': e.response?.data['message'] ?? 'Registration failed'
        };
      }
      return {'success': false, 'message': 'Cannot connect to server'};
    }

    _isLoading = false;
    notifyListeners();
    return {'success': false, 'message': 'Something went wrong'};
  }

  Future<void> logout() async {
    _renewTimer?.cancel();
    try {
      if (_accessToken != null) {
        await _plainDio.post(
          '$baseUrl/logout',
          options: Options(
            headers: {'Authorization': 'Bearer $_accessToken'},
          ),
        );
      }
    } catch (e) {
      // Even if logout API fails, clear local tokens
    }

    _accessToken = null;
    _userRole = null;
    _userName = null;
    _userEmail = null;
    await _storage.delete(key: 'access_token');
    notifyListeners();
  }

  // ───────────────────────── password reset ─────────────────────────

  /// Step 1: asks the server to e-mail a 6-digit code.
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await _plainDio.post(
        '$baseUrl/password/forgot',
        data: {'email': email},
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        return {'success': false, 'message': data['error'].toString()};
      }
      return {'success': false, 'message': 'Cannot connect to server'};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// Step 2: checks the code and sets the new password.
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await _plainDio.post(
        '$baseUrl/password/reset',
        data: {'email': email, 'code': code, 'new_password': newPassword},
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['details'] is Map) {
        // Validation problem (e.g. password too short) — show the first reason.
        final details = data['details'] as Map;
        final first = details.values.first;
        final text = first is List && first.isNotEmpty ? first.first : first;
        return {'success': false, 'message': text.toString()};
      }
      if (data is Map && data['error'] != null) {
        return {'success': false, 'message': data['error'].toString()};
      }
      return {'success': false, 'message': 'Cannot connect to server'};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  // ───────────────────────── profile ─────────────────────────

  Future<Map<String, dynamic>> updateProfile(String name) async {
    try {
      final response = await _authedDio.put(
        '$baseUrl/profile',
        data: {'name': name},
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
        ),
      );
      if (response.statusCode == 200) {
        _userName = name;
        notifyListeners();
        return {'success': true};
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return {
          'success': false,
          'message': 'Session expired, please log in again'
        };
      }
      return {'success': false, 'message': 'Cannot connect to server'};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }
}
