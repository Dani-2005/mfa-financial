import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'graficas_service.dart';
import 'http_helpers.dart';

final _graficasService = GraficasService();

Router buildGraficasRouter() {
  final router = Router();

  router.get('/ingresos-por-mes', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final datos = await _graficasService.fetchIngresosPorMes();
    return jsonResponse(datos);
  });

  router.get('/distribucion-estados', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final datos = await _graficasService.fetchDistribucionEstados();
    return jsonResponse(datos);
  });

  router.get('/cuotas-por-vencimiento', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final datos = await _graficasService.fetchCuotasPorVencimiento();
    return jsonResponse(datos);
  });

  return router;
}
