import 'package:mysql_client_plus/exception.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'http_helpers.dart';
import 'loan_calculator.dart';
import 'prestamo_service.dart';

final _prestamoService = PrestamoService();

Router buildPrestamoRouter() {
  final router = Router();

  router.get('/', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamos = await _prestamoService.fetchAll();
    return jsonResponse({'prestamos': prestamos});
  });

  router.get('/next-codigo', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final codigo = await _prestamoService.generateNextCodigo();
    return jsonResponse({'codigo': codigo});
  });

  router.post('/', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final body = await bodyJson(request);
    try {
      final movimientos = ((body['movimientosPlanificados'] as List?) ?? const [])
          .map((m) => MovimientoCapitalPlanificado(
                periodoDesde: m['periodoDesde'] as int,
                esInyeccion: m['esInyeccion'] as bool,
                monto: (m['monto'] as num).toDouble(),
              ))
          .toList();

      await _prestamoService.create(
        usuarioResponsable: user.nombreCompleto,
        codigoReferencia: body['codigoReferencia'] as String,
        clienteId: body['clienteId'] as int,
        tipoTasa: body['tipoTasa'] as String,
        tipoCalculo: body['tipoCalculo'] as String,
        capitalInicial: (body['capitalInicial'] as num).toDouble(),
        tasaInteresMensual: (body['tasaInteresMensual'] as num).toDouble(),
        mesCambioTasa: body['mesCambioTasa'] as int?,
        nuevaTasaInteres: (body['nuevaTasaInteres'] as num?)?.toDouble(),
        mesCambioCapitalizacion: body['mesCambioCapitalizacion'] as int?,
        frecuenciaPago: body['frecuenciaPago'] as String,
        fechaInicio: DateTime.parse(body['fechaInicio'] as String),
        numeroCuotas: body['numeroCuotas'] as int,
        movimientosPlanificados: movimientos,
      );
      return jsonResponse({'ok': true});
    } on MySQLServerException catch (e) {
      if (e.errorCode == 1062) return errorResponse('duplicate_codigo', status: 409);
      return errorResponse('Error al guardar: ${e.message}', status: 500);
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.get('/<id>/editar', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    try {
      final datos = await _prestamoService.fetchParaEditar(prestamoId);
      return jsonResponse(datos);
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.put('/<id>', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    final body = await bodyJson(request);
    try {
      await _prestamoService.editar(
        usuarioResponsable: user.nombreCompleto,
        prestamoId: prestamoId,
        clienteId: body['clienteId'] as int,
        tipoTasa: body['tipoTasa'] as String,
        tipoCalculo: body['tipoCalculo'] as String,
        capitalInicial: (body['capitalInicial'] as num).toDouble(),
        tasaInteresMensual: (body['tasaInteresMensual'] as num).toDouble(),
        mesCambioTasa: body['mesCambioTasa'] as int?,
        nuevaTasaInteres: (body['nuevaTasaInteres'] as num?)?.toDouble(),
        mesCambioCapitalizacion: body['mesCambioCapitalizacion'] as int?,
        frecuenciaPago: body['frecuenciaPago'] as String,
        fechaInicio: DateTime.parse(body['fechaInicio'] as String),
        numeroCuotas: body['numeroCuotas'] as int,
      );
      return jsonResponse({'ok': true});
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.get('/<id>/detalle', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    try {
      final detalle = await _prestamoService.fetchDetalle(prestamoId);
      return jsonResponse(detalle);
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}', status: 404);
    }
  });

  router.get('/<id>/cuotas', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    final cuotas = await _prestamoService.fetchCuotas(prestamoId);
    return jsonResponse({'cuotas': cuotas});
  });

  router.get('/<id>/movimientos-capital', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    final movimientos = await _prestamoService.fetchMovimientosCapital(prestamoId);
    return jsonResponse({'movimientos': movimientos});
  });

  router.get('/<id>/cuotas-elegibles-inyeccion', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    final elegibles = await _prestamoService.fetchCuotasElegiblesParaInyeccion(prestamoId);
    return jsonResponse({'elegibles': elegibles});
  });

  router.post('/<id>/inyeccion-capital', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    final body = await bodyJson(request);
    try {
      final nuevoBalance = await _prestamoService.registrarInyeccionCapital(
        usuarioResponsable: user.nombreCompleto,
        prestamoId: prestamoId,
        periodoDesde: body['periodoDesde'] as int,
        monto: (body['monto'] as num).toDouble(),
        descripcionConcepto: body['descripcionConcepto'] as String?,
        fechaTransaccion: DateTime.parse(body['fechaTransaccion'] as String),
      );
      return jsonResponse({'nuevoBalance': nuevoBalance});
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.get('/<id>/saldo-actual', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    try {
      final saldo = await _prestamoService.fetchSaldoActual(prestamoId);
      return jsonResponse(saldo);
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.get('/<id>/ancla-abono', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    try {
      final ancla = await _prestamoService.fetchAnclaAbono(prestamoId);
      return jsonResponse(ancla);
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.post('/<id>/abono-capital', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    final body = await bodyJson(request);
    try {
      final codigoRecibo = await _prestamoService.registrarAbonoCapital(
        usuarioResponsable: user.nombreCompleto,
        prestamoId: prestamoId,
        monto: (body['monto'] as num).toDouble(),
        descripcionConcepto: body['descripcionConcepto'] as String,
        metodoPago: body['metodoPago'] as String?,
        referencia: body['referencia'] as String?,
        fechaEmision: DateTime.parse(body['fechaEmision'] as String),
      );
      return jsonResponse({'codigoRecibo': codigoRecibo});
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.post('/<id>/liquidacion-total', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    final body = await bodyJson(request);
    try {
      final codigoRecibo = await _prestamoService.registrarLiquidacionTotal(
        usuarioResponsable: user.nombreCompleto,
        prestamoId: prestamoId,
        descripcionConcepto: body['descripcionConcepto'] as String,
        metodoPago: body['metodoPago'] as String?,
        referencia: body['referencia'] as String?,
        fechaEmision: DateTime.parse(body['fechaEmision'] as String),
      );
      return jsonResponse({'codigoRecibo': codigoRecibo});
    } on ArgumentError catch (e) {
      return errorResponse('${e.message}');
    }
  });

  router.get('/cliente/<clienteId>/activos', (Request request, String clienteId) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final id = int.tryParse(clienteId);
    if (id == null) return errorResponse('Id inválido.');
    final prestamos = await _prestamoService.fetchActivosPorCliente(id);
    return jsonResponse({'prestamos': prestamos});
  });

  router.get('/<id>/cuotas-pendientes', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final prestamoId = int.tryParse(id);
    if (prestamoId == null) return errorResponse('Id inválido.');
    final cuotas = await _prestamoService.fetchCuotasPendientes(prestamoId);
    return jsonResponse({'cuotas': cuotas});
  });

  return router;
}
