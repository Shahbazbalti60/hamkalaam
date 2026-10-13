import 'package:dio/dio.dart';
import 'auth_service.dart';

/// Creates a Dio instance for talking to the Flask backend.
///
/// If a request that carried a login token comes back 401 (token
/// expired), this silently asks [AuthService] for a fresh token and
/// repeats the SAME request once with the new token — so the person
/// never sees "Token has expired" in the middle of using the app.
///
/// Login / register / logout / password calls are never retried.
class ApiClient {
  static Dio create() {
    final dio = Dio();

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, ErrorInterceptorHandler handler) async {
          final req = e.requestOptions;
          final path = req.path;

          final hadToken = req.headers.containsKey('Authorization');
          final isAuthFlow = path.endsWith('/renew') ||
              path.endsWith('/logout') ||
              path.endsWith('/login') ||
              path.endsWith('/register');
          final alreadyRetried = req.extra['retried'] == true;

          if (e.response?.statusCode == 401 &&
              hadToken &&
              !isAuthFlow &&
              !alreadyRetried) {
            final auth = AuthService.instance;
            final renewed = auth != null && await auth.renewToken();

            if (renewed) {
              req.headers['Authorization'] = 'Bearer ${auth.accessToken}';
              req.extra['retried'] = true;

              // A FormData (file upload) can only be sent once, so
              // give the retry a fresh copy of it.
              if (req.data is FormData) {
                req.data = (req.data as FormData).clone();
              }

              try {
                final response = await dio.fetch(req);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                return handler.next(retryError);
              }
            }
          }

          handler.next(e);
        },
      ),
    );

    return dio;
  }
}
