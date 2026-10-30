import 'dart:typed_data';
import '../config/app_config.dart';
import 'api_client.dart';
import 'package:dio/dio.dart';

/// Profile extras (SRDS FR-07): photo and Urdu voice dialect.
///   GET    /api/auth/profile/extra
///   PUT    /api/auth/profile/dialect   {urdu_dialect: Standard|Punjabi}
///   POST   /api/auth/profile/photo     (multipart field "photo")
///   GET    /api/auth/profile/photo     (image bytes)
///   DELETE /api/auth/profile/photo
class ProfileService {
  final Dio _dio = ApiClient.create();

  static String get baseUrl => '${AppConfig.apiHost}/api/auth/profile';

  Options _auth(String token, {ResponseType? type}) => Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: type,
      );

  /// {'success': true, 'urdu_dialect': String, 'has_photo': bool}
  Future<Map<String, dynamic>> getExtras(String token) async {
    try {
      final response = await _dio.get('$baseUrl/extra', options: _auth(token));
      if (response.statusCode == 200 && response.data is Map) {
        return {
          'success': true,
          'urdu_dialect': response.data['urdu_dialect'] ?? 'Standard',
          'has_photo': response.data['has_photo'] == true,
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  Future<Map<String, dynamic>> setDialect(String token, String dialect) async {
    try {
      final response = await _dio.put(
        '$baseUrl/dialect',
        data: {'urdu_dialect': dialect},
        options: _auth(token),
      );
      if (response.statusCode == 200) return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required String token,
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final form = FormData.fromMap({
        'photo': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _dio.post(
        '$baseUrl/photo',
        data: form,
        options: _auth(token),
      );
      if (response.statusCode == 201) return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// The photo bytes, or null if there is none / it cannot be loaded.
  Future<Uint8List?> getPhoto(String token) async {
    try {
      final response = await _dio.get<List<int>>(
        '$baseUrl/photo',
        options: _auth(token, type: ResponseType.bytes),
      );
      if (response.statusCode == 200 && response.data != null) {
        return Uint8List.fromList(response.data!);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> deletePhoto(String token) async {
    try {
      final response = await _dio.delete('$baseUrl/photo', options: _auth(token));
      if (response.statusCode == 200) return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  String _errorMessage(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Session expired, please log in again';
    }
    if (e.response?.statusCode == 413) return 'Photo must be 2 MB or smaller';
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'Cannot connect to server';
  }
}
