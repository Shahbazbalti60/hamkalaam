import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AuthService extends ChangeNotifier {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String baseUrl = 'http://127.0.0.1:5000/api';

  String? _accessToken;
  String? _userRole;
  String? _userName;
  String? _userEmail;
  bool _isLoading = false;

  String? get accessToken => _accessToken;
  String? get userRole => _userRole;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _accessToken != null;
  bool get isAdmin => _userRole == 'Admin';

  AuthService() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      _accessToken = await _storage.read(key: 'access_token');
      if (_accessToken != null) {
        _extractUserInfo(_accessToken!);
        notifyListeners();
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

  Future<Map<String, dynamic>> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    // ── TEMPORARY FAKE LOGIN FOR DEVELOPMENT ──
    await Future.delayed(const Duration(milliseconds: 800));

    if (email == 'test@test.com' && password == 'test1234') {
      _accessToken = 'fake_user_token';
      _userRole = 'User';
      _userName = 'Shahbaz Hussain';
      _userEmail = 'test@test.com';
      _isLoading = false;
      notifyListeners();
      return {'success': true, 'role': 'User'};
    }

    if (email == 'admin@test.com' && password == 'admin1234') {
      _accessToken = 'fake_admin_token';
      _userRole = 'Admin';
      _userName = 'Admin User';
      _userEmail = 'admin@test.com';
      _isLoading = false;
      notifyListeners();
      return {'success': true, 'role': 'Admin'};
    }
    // ── END FAKE LOGIN ──

    // Real Flask API call (uncomment when backend is ready)
    // try {
    //   final response = await _dio.post(
    //     '$baseUrl/auth/login/',
    //     data: {'email': email, 'password': password},
    //   );
    //   if (response.statusCode == 200) {
    //     _accessToken = response.data['access_token'];
    //     await _storage.write(key: 'access_token', value: _accessToken);
    //     _extractUserInfo(_accessToken!);
    //     _isLoading = false;
    //     notifyListeners();
    //     return {'success': true, 'role': _userRole};
    //   }
    // } on DioException catch (e) {
    //   _isLoading = false;
    //   notifyListeners();
    //   if (e.response?.statusCode == 401) {
    //     return {'success': false, 'message': 'Invalid email or password'};
    //   } else if (e.response?.statusCode == 403) {
    //     return {'success': false, 'message': 'Please verify your email first'};
    //   }
    //   return {'success': false, 'message': 'Cannot connect to server'};
    // }

    _isLoading = false;
    notifyListeners();
    return {'success': false, 'message': 'Invalid email or password'};
  }

  Future<Map<String, dynamic>> register(
      String name, String email, String password, String role) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _dio.post(
        '$baseUrl/auth/register/',
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
        return {'success': true};
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
    _accessToken = null;
    _userRole = null;
    _userName = null;
    _userEmail = null;
    await _storage.delete(key: 'access_token');
    notifyListeners();
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await _dio.post(
        '$baseUrl/auth/password-reset/',
        data: {'email': email},
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
    } on DioException {
      return {'success': false, 'message': 'Cannot connect to server'};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }
}