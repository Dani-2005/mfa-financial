import 'package:mysql_client_plus/exception.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'cliente_service.dart';
import 'http_helpers.dart';

final _clienteService = ClienteService();

Router buildClienteRouter() {
  final router = Router();

  router.get('/', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final clientes = await _clienteService.fetchAll();
    return jsonResponse({'clientes': clientes});
  });

  router.post('/', (Request request) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final body = await bodyJson(request);
    try {
      await _clienteService.create(
        usuarioResponsable: user.nombreCompleto,
        documentoIdentidad: body['documentoIdentidad'] as String,
        tipoCliente: body['tipoCliente'] as String,
        nombreCliente: body['nombreCliente'] as String,
        representante: body['representante'] as String,
        correo: body['correo'] as String?,
        telefono: body['telefono'] as String?,
        direccion: body['direccion'] as String?,
      );
      return jsonResponse({'ok': true});
    } on MySQLServerException catch (e) {
      if (e.errorCode == 1062) {
        return errorResponse('duplicate_documento', status: 409);
      }
      return errorResponse('Error al guardar: ${e.message}', status: 500);
    }
  });

  router.put('/<id>', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final clienteId = int.tryParse(id);
    if (clienteId == null) return errorResponse('Id inválido.');
    final body = await bodyJson(request);
    try {
      await _clienteService.update(
        usuarioResponsable: user.nombreCompleto,
        clienteId: clienteId,
        registroIdAuditoria: body['registroIdAuditoria'] as String,
        documentoIdentidad: body['documentoIdentidad'] as String,
        tipoCliente: body['tipoCliente'] as String,
        nombreCliente: body['nombreCliente'] as String,
        representante: body['representante'] as String,
        correo: body['correo'] as String?,
        telefono: body['telefono'] as String?,
        direccion: body['direccion'] as String?,
        datosAnteriores: (body['datosAnteriores'] as Map).cast<String, dynamic>(),
      );
      return jsonResponse({'ok': true});
    } on MySQLServerException catch (e) {
      if (e.errorCode == 1062) {
        return errorResponse('duplicate_documento', status: 409);
      }
      return errorResponse('Error al guardar: ${e.message}', status: 500);
    }
  });

  router.post('/<id>/activo', (Request request, String id) async {
    final user = await usuarioAutenticado(request);
    if (user == null) return errorResponse('Sesión no válida.', status: 401);
    final clienteId = int.tryParse(id);
    if (clienteId == null) return errorResponse('Id inválido.');
    final body = await bodyJson(request);
    await _clienteService.setActivo(
      usuarioResponsable: user.nombreCompleto,
      clienteId: clienteId,
      documentoIdentidad: body['documentoIdentidad'] as String,
      activo: body['activo'] as bool,
    );
    return jsonResponse({'ok': true});
  });

  return router;
}
