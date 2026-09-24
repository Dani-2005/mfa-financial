import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auditoria_service.dart';
import 'auth_middleware.dart';
import 'http_helpers.dart';

final _auditoriaService = AuditoriaService();

Router buildAuditoriaRouter() {
  final router = Router();

  router.get('/', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final registros = await _auditoriaService.fetchAll();
    return jsonResponse({'registros': registros});
  });

  return router;
}
