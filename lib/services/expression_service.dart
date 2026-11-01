import '../config/app_config.dart';
import 'api_client.dart';
import 'package:dio/dio.dart';

/// Admin: face-expression training samples (SRDS FR-20 / FR-21).
///   POST   /api/admin/expression-samples          {label, rec_id, vectors}
///   GET    /api/admin/expression-samples/summary
///   DELETE /api/admin/expression-samples/<label>
class ExpressionService {
  final Dio _dio = ApiClient.create();

  static String get baseUrl => '${AppConfig.apiHost}/api/admin/expression-samples';

  Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  /// {'success': true, 'counts': {label: n}, 'recordings': {label: n}}
  Future<Map<String, dynamic>> getSummary(String token) async {
    try {
      final r = await _dio.get('$baseUrl/summary', options: _auth(token));
      if (r.statusCode == 200 && r.data is Map) return _countsFrom(r.data);
    } on DioException catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  Future<Map<String, dynamic>> upload({
    required String token,
    required String label,
    required String recId,
    required List<List<double>> vectors,
  }) async {
    try {
      final r = await _dio.post(
        baseUrl,
        data: {'label': label, 'rec_id': recId, 'vectors': vectors},
        options: _auth(token),
      );
      if (r.statusCode == 201 && r.data is Map) return _countsFrom(r.data);
    } on DioException catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  Future<Map<String, dynamic>> deleteClass(String token, String label) async {
    try {
      final r = await _dio.delete('$baseUrl/$label', options: _auth(token));
      if (r.statusCode == 200 && r.data is Map) return _countsFrom(r.data);
    } on DioException catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  Map<String, dynamic> _countsFrom(dynamic data) {
    Map<String, int> toInts(dynamic m) => m is Map
        ? m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
        : <String, int>{};
    return {
      'success': true,
      'counts': toInts(data['counts']),
      'recordings': toInts(data['recordings']),
    };
  }

  String _msg(DioException e) {
    if (e.response?.statusCode == 401) return 'Session expired, please log in again';
    if (e.response?.statusCode == 403) return 'Admin access required';
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'Cannot connect to server';
  }
}
