import 'auditoria_service.dart';
import 'database_service.dart';

class ClienteService {
  final AuditoriaService _auditoria = AuditoriaService();

  Future<List<Map<String, dynamic>>> fetchAll() async {
    final result = await DatabaseService.instance.query(
      'SELECT c.*, '
      '(SELECT COUNT(*) FROM prestamos p WHERE p.cliente_id = c.cliente_id '
      "AND p.activo = TRUE AND p.estado NOT IN ('Pagado', 'Anulado')) AS prestamos_activos "
      'FROM clientes c '
      'ORDER BY c.created_at DESC',
    );

    return result.rows.map((row) => row.typedAssoc()).toList();
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
    await DatabaseService.instance.query(
      'INSERT INTO clientes '
      '(documento_identidad, tipo_cliente, nombre_cliente, representante, correo, telefono, direccion) '
      'VALUES (:documento, :tipo, :nombre, :representante, :correo, :telefono, :direccion)',
      {
        'documento': documentoIdentidad,
        'tipo': tipoCliente,
        'nombre': nombreCliente,
        'representante': representante,
        'correo': correo,
        'telefono': telefono,
        'direccion': direccion,
      },
    );

    await _auditoria.log(
      tablaAfectada: 'clientes',
      registroId: documentoIdentidad,
      accion: 'INSERT',
      datosNuevos: {
        'documento_identidad': documentoIdentidad,
        'tipo_cliente': tipoCliente,
        'nombre_cliente': nombreCliente,
        'representante': representante,
        'correo': correo,
        'telefono': telefono,
        'direccion': direccion,
      },
    );
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
    await DatabaseService.instance.query(
      'UPDATE clientes SET '
      'documento_identidad = :documento, tipo_cliente = :tipo, nombre_cliente = :nombre, '
      'representante = :representante, correo = :correo, telefono = :telefono, direccion = :direccion '
      'WHERE cliente_id = :id',
      {
        'documento': documentoIdentidad,
        'tipo': tipoCliente,
        'nombre': nombreCliente,
        'representante': representante,
        'correo': correo,
        'telefono': telefono,
        'direccion': direccion,
        'id': clienteId,
      },
    );

    await _auditoria.log(
      tablaAfectada: 'clientes',
      registroId: registroIdAuditoria,
      accion: 'UPDATE',
      datosAnteriores: datosAnteriores,
      datosNuevos: {
        'documento_identidad': documentoIdentidad,
        'tipo_cliente': tipoCliente,
        'nombre_cliente': nombreCliente,
        'representante': representante,
        'correo': correo,
        'telefono': telefono,
        'direccion': direccion,
      },
    );
  }

  Future<void> setActivo({
    required int clienteId,
    required String documentoIdentidad,
    required bool activo,
  }) async {
    await DatabaseService.instance.query(
      'UPDATE clientes SET activo = :activo WHERE cliente_id = :id',
      {'activo': activo, 'id': clienteId},
    );

    await _auditoria.log(
      tablaAfectada: 'clientes',
      registroId: documentoIdentidad,
      accion: activo ? 'UPDATE' : 'DESACTIVAR',
      datosAnteriores: {'activo': !activo},
      datosNuevos: {'activo': activo},
    );
  }
}
