import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'http_helpers.dart';
import 'pago_service.dart';

final _pagoService = PagoService();

Router buildPagoRouter() {
  final router = Router();

  router.get('/', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final pagos = await _pagoService.fetchAll();
    return jsonResponse({'pagos': pagos});
  });

  router.get('/recibo/<codigo>', (Request request, String codigo) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    try {
      final detalle = await _pagoService.fetchReciboDetalle(codigo);
      return jsonResponse(detalle);
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}', status: 404);
    }
  });

  router.post('/cuota/<cuotaId>/pago', (Request request, String cuotaId) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final id = int.tryParse(cuotaId);
    if (id == null) return errorResponse('Id inválido.');
    final body = await bodyJson(request);
    try {
      await _pagoService.registrarPago(
        usuarioResponsable: user.nombreCompleto,
        cuotaId: id,
        monto: (body['monto'] as num).toDouble(),
        descripcionConcepto: body['descripcionConcepto'] as String,
        metodoPago: body['metodoPago'] as String?,
        referencia: body['referencia'] as String?,
        fechaEmision: DateTime.parse(body['fechaEmision'] as String),
      );
      return jsonResponse({'ok': true});
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.post('/cuota/<cuotaId>/pago-parcial', (Request request, String cuotaId) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final id = int.tryParse(cuotaId);
    if (id == null) return errorResponse('Id inválido.');
    final body = await bodyJson(request);
    try {
      await _pagoService.registrarPagoParcial(
        usuarioResponsable: user.nombreCompleto,
        cuotaId: id,
        monto: (body['monto'] as num).toDouble(),
        descripcionConcepto: body['descripcionConcepto'] as String,
        metodoPago: body['metodoPago'] as String?,
        referencia: body['referencia'] as String?,
        fechaEmision: DateTime.parse(body['fechaEmision'] as String),
      );
      return jsonResponse({'ok': true});
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  return router;
}
