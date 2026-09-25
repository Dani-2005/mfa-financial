import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'dashboard_service.dart';
import 'http_helpers.dart';

final _dashboardService = DashboardService();

Router buildDashboardRouter() {
  final router = Router();

  router.get('/capital-summary', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final resumen = await _dashboardService.fetchCapitalSummary();
    return jsonResponse(resumen);
  });

  router.get('/intereses-summary', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final resumen = await _dashboardService.fetchInteresesSummary();
    return jsonResponse(resumen);
  });

  router.get('/capital-por-anio', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final anioStr = request.url.queryParameters['anio'];
    final anio = int.tryParse(anioStr ?? '') ?? DateTime.now().year;
    final datos = await _dashboardService.fetchCapitalPorAnio(anio);
    return jsonResponse(datos);
  });

  router.get('/intereses-por-anio', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final anioStr = request.url.queryParameters['anio'];
    final anio = int.tryParse(anioStr ?? '') ?? DateTime.now().year;
    final datos = await _dashboardService.fetchInteresesPorAnio(anio);
    return jsonResponse(datos);
  });

  router.get('/prestamos-activos-count', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final n = await _dashboardService.fetchPrestamosActivosCount();
    return jsonResponse({'n': n});
  });

  router.get('/proximas-cuotas', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final limiteStr = request.url.queryParameters['limite'];
    final limite = limiteStr != null ? int.tryParse(limiteStr) ?? 5 : 5;
    final proximas = await _dashboardService.fetchProximasCuotas(limite: limite);
    return jsonResponse(proximas);
  });

  return router;
}
