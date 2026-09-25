import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'http_helpers.dart';
import 'reporte_service.dart';

final _reporteService = ReporteService();

Router buildReporteRouter() {
  final router = Router();

  router.get('/', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final modulo = request.url.queryParameters['modulo'];
    if (modulo == null) return errorResponse('Falta el parámetro modulo.');
    final clienteIdStr = request.url.queryParameters['clienteId'];
    final clienteId = clienteIdStr != null ? int.tryParse(clienteIdStr) : null;
    final tipoAccion = request.url.queryParameters['tipoAccion'];
    final fechaDesdeStr = request.url.queryParameters['fechaDesde'];
    final fechaHastaStr = request.url.queryParameters['fechaHasta'];
    final filas = await _reporteService.fetchDatos(
      modulo: modulo,
      clienteId: clienteId,
      tipoAccion: tipoAccion,
      fechaDesde: fechaDesdeStr != null ? DateTime.tryParse(fechaDesdeStr) : null,
      fechaHasta: fechaHastaStr != null ? DateTime.tryParse(fechaHastaStr) : null,
    );
    return jsonResponse({'filas': filas});
  });

  return router;
}
