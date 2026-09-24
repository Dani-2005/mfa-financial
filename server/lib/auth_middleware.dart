import 'package:shelf/shelf.dart';

import 'auth_service.dart';
import 'models.dart';

final _authService = AuthService();

/// Saca usuarioId + token de los headers `X-Usuario-Id` y
/// `Authorization: Bearer <token>`, y los valida contra la sesión activa
/// (deslizándola otros 30 minutos si sigue siendo válida). Devuelve `null`
/// si faltan los headers o si la sesión ya no es válida. Compartido por
/// todos los módulos de rutas que requieren un usuario autenticado.
Future<AuthUser?> usuarioAutenticado(Request request) async {
  final usuarioIdStr = request.headers['x-usuario-id'];
  final authHeader = request.headers['authorization'];
  if (usuarioIdStr == null || authHeader == null || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  final usuarioId = int.tryParse(usuarioIdStr);
  if (usuarioId == null) return null;
  final token = authHeader.substring('Bearer '.length);
  return _authService.validarYDeslizarSesion(usuarioId: usuarioId, token: token);
}
