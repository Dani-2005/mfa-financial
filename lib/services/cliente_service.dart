import 'api_client.dart';
import 'auth_service.dart';

/// Se lanza cuando el servidor rechaza un alta/edición de cliente porque ya
/// existe otro cliente con el mismo documento de identidad (columna única).
class ClienteDuplicadoException implements Exception {}

/// Igual que antes en su interfaz pública, pero por dentro ya no habla
/// directo con MySQL: llama al servidor MAF API en el VPS.
class ClienteService {
  Future<Map<String, String>> _headers() async {
    final headers = await AuthService.instance.authHeaders();
    if (headers == null) throw StateError('No hay una sesión activa.');
    return headers;
  }

  Future<List<Map<String, dynamic>>> fetchAll() async {
    final response = await ApiClient.instance.get('/api/clientes/', headers: await _headers());
    if (!response.ok) throw StateError('No se pudieron cargar los clientes.');
    final lista = response.data['clientes'] as List;
    return lista.cast<Map<String, dynamic>>();
  }

  Future<void> create({
    required String documentoIdentidad,
    required String tipoCliente,
    required String nombreCliente,
    required String representante,
    String? correo,
    String? telefono,
    String? direccion,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/clientes/',
      headers: await _headers(),
      body: {
        'documentoIdentidad': documentoIdentidad,
        'tipoCliente': tipoCliente,
        'nombreCliente': nombreCliente,
        'representante': representante,
        'correo': correo,
        'telefono': telefono,
        'direccion': direccion,
      },
    );
    if (!response.ok) {
      if (response.data['error'] == 'duplicate_documento') throw ClienteDuplicadoException();
      throw StateError('No se pudo guardar el cliente.');
    }
  }

  Future<void> update({
    required int clienteId,
    required String registroIdAuditoria,
    required String documentoIdentidad,
    required String tipoCliente,
    required String nombreCliente,
    required String representante,
    String? correo,
    String? telefono,
    String? direccion,
    required Map<String, dynamic> datosAnteriores,
  }) async {
    final response = await ApiClient.instance.put(
      '/api/clientes/$clienteId',
      headers: await _headers(),
      body: {
        'registroIdAuditoria': registroIdAuditoria,
        'documentoIdentidad': documentoIdentidad,
        'tipoCliente': tipoCliente,
        'nombreCliente': nombreCliente,
        'representante': representante,
        'correo': correo,
        'telefono': telefono,
        'direccion': direccion,
        'datosAnteriores': datosAnteriores,
      },
    );
    if (!response.ok) {
      if (response.data['error'] == 'duplicate_documento') throw ClienteDuplicadoException();
      throw StateError('No se pudo actualizar el cliente.');
    }
  }

  Future<void> setActivo({
    required int clienteId,
    required String documentoIdentidad,
    required bool activo,
  }) async {
    final response = await ApiClient.instance.post(
      '/api/clientes/$clienteId/activo',
      headers: await _headers(),
      body: {'documentoIdentidad': documentoIdentidad, 'activo': activo},
    );
    if (!response.ok) throw StateError('No se pudo cambiar el estado del cliente.');
  }
}
