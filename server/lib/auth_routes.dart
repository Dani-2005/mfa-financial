import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'auth_service.dart';
import 'http_helpers.dart';
import 'models.dart';

final _authService = AuthService();

Map<String, dynamic> _userJson(AuthUser user) => {
      'usuarioId': user.usuarioId,
      'nombreUsuario': user.nombreUsuario,
      'nombreCompleto': user.nombreCompleto,
    };

Map<String, dynamic> _loginResultJson(LoginResult r) => {
      ..._userJson(r.user),
      'token': r.token,
      'expiraEn': r.expiraEn.toIso8601String(),
    };

Router buildAuthRouter() {
  final router = Router();

  router.post('/login', (Request request) async {
    final body = await bodyJson(request);
    final usuario = body['usuario'] as String? ?? '';
    final password = body['password'] as String? ?? '';
    try {
      final result = await _authService.login(nombreUsuario: usuario, password: password);
      return jsonResponse(_loginResultJson(result));
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}', status: 401);
    }
  });

  router.get('/session', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    return jsonResponse(_userJson(user));
  });

  router.post('/logout', (Request request) async {
    final usuarioIdStr = request.headers['x-usuario-id'];
    final authHeader = request.headers['authorization'];
    if (usuarioIdStr == null || authHeader == null || !authHeader.startsWith('Bearer ')) {
      return jsonResponse({'ok': true});
    }
    final usuarioId = int.tryParse(usuarioIdStr);
    final token = authHeader.substring('Bearer '.length);
    if (usuarioId == null) return jsonResponse({'ok': true});

    final body = await bodyJson(request);
    final nombreUsuario = body['nombreUsuario'] as String? ?? 'desconocido';
    await _authService.logout(usuarioId: usuarioId, token: token, nombreUsuario: nombreUsuario);
    return jsonResponse({'ok': true});
  });

  router.post('/change-password', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final body = await bodyJson(request);
    final actual = body['actual'] as String? ?? '';
    final nueva = body['nueva'] as String? ?? '';
    try {
      await _authService.changePassword(user: user, actual: actual, nueva: nueva);
      return jsonResponse({'ok': true});
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.post('/remember/enable', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final r = await _authService.habilitarRecordarDispositivo(user);
    return jsonResponse({'token': r.token, 'expiraEn': r.expiraEn.toIso8601String()});
  });

  router.post('/remember/disable', (Request request) async {
    final body = await bodyJson(request);
    final usuarioId = body['usuarioId'] as int?;
    final token = body['token'] as String?;
    if (usuarioId == null || token == null) return jsonResponse({'ok': true});
    await _authService.olvidarDispositivo(usuarioId: usuarioId, token: token);
    return jsonResponse({'ok': true});
  });

  router.post('/remember/renew', (Request request) async {
    final body = await bodyJson(request);
    final usuarioId = body['usuarioId'] as int?;
    final recordarToken = body['recordarToken'] as String?;
    if (usuarioId == null || recordarToken == null) {
      return errorResponse('Faltan datos.', status: 401);
    }
    final result = await _authService.renovarSesionConBiometria(
      usuarioId: usuarioId,
      recordarToken: recordarToken,
    );
    if (result == null) return errorResponse('Credencial no válida.', status: 401);
    return jsonResponse({
      ..._loginResultJson(result.sesion),
      'recordarToken': result.nuevoRecordarToken,
    });
  });

  return router;
}
