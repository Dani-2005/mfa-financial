import 'dart:convert';
import 'auditoria_descripcion.dart';
import 'database_service.dart';
import 'http_helpers.dart';

/// Igual que el `AuditoriaService` de la app, pero `usuarioResponsable` se
/// recibe explícito en cada llamada en vez de leerse de un global — ver la
/// nota en `models.dart` sobre por qué el servidor no puede usar ese patrón.
class AuditoriaService {
  Future<List<Map<String, dynamic>>> fetchAll() async {
    final result = await DatabaseService.instance.query(
      'SELECT auditoriaSistema_id, tabla_afectada, registro_id, accion, '
      'datos_anteriores, datos_nuevos, fecha_accion, usuario_responsable '
      'FROM auditoria_sistema '
      'ORDER BY fecha_accion DESC, auditoriaSistema_id DESC',
    );

    return result.rows.map((row) {
      final f = row.typedAssoc();
      final fila = jsonSafeRow(f);
      fila['descripcion'] = descripcionAuditoria(
        tabla: f['tabla_afectada'] as String,
        accion: f['accion'] as String,
        registroId: f['registro_id'] as String,
        usuario: (f['usuario_responsable'] as String?) ?? 'N/A',
        nuevos: auditoriaAsMap(f['datos_nuevos']),
      );
      return fila;
    }).toList();
  }

  Future<void> log({
    required String usuarioResponsable,
    required String tablaAfectada,
    required String registroId,
    required String accion,
    Map<String, dynamic>? datosAnteriores,
    Map<String, dynamic>? datosNuevos,
  }) async {
    await DatabaseService.instance.query(
      'INSERT INTO auditoria_sistema '
      '(tabla_afectada, registro_id, accion, datos_anteriores, datos_nuevos, usuario_responsable) '
      'VALUES (:tabla, :registroId, :accion, :anteriores, :nuevos, :usuario)',
      {
        'tabla': tablaAfectada,
        'registroId': registroId,
        'accion': accion,
        'anteriores': datosAnteriores == null ? null : jsonEncode(datosAnteriores),
        'nuevos': datosNuevos == null ? null : jsonEncode(datosNuevos),
        'usuario': usuarioResponsable,
      },
    );
  }
}
