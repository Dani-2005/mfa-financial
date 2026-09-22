import 'dart:convert';
import 'database_service.dart';
import 'session.dart';

class AuditoriaService {
  /// Nombre completo del administrador que tiene la sesión activa en este
  /// momento. Si por alguna razón se llama sin sesión (no debería pasar en
  /// el flujo normal de la app, ya que todo queda detrás del login), queda
  /// registrado como 'Sistema' en vez de fallar.
  String get usuarioResponsable => Session.current?.nombreCompleto ?? 'Sistema';

  Future<List<Map<String, dynamic>>> fetchAll() async {
    final result = await DatabaseService.instance.query(
      'SELECT auditoriaSistema_id, tabla_afectada, registro_id, accion, '
      'datos_anteriores, datos_nuevos, fecha_accion, usuario_responsable '
      'FROM auditoria_sistema '
      'ORDER BY fecha_accion DESC, auditoriaSistema_id DESC',
    );

    return result.rows.map((row) {
      final fields = row.typedAssoc();
      final fecha = fields['fecha_accion'] as DateTime?;

      return {
        'id': fields['auditoriaSistema_id'],
        'tabla_afectada': fields['tabla_afectada'],
        'registro_id': fields['registro_id'],
        'accion': fields['accion'],
        'datos_anteriores': _prettyJson(fields['datos_anteriores']),
        'datos_nuevos': _prettyJson(fields['datos_nuevos']),
        'fecha_accion': fecha == null ? '' : _formatFecha(fecha),
        'usuario_responsable': fields['usuario_responsable'],
      };
    }).toList();
  }

  /// El driver de MySQL a veces ya entrega las columnas JSON decodificadas
  /// (Map/List) y a veces como texto crudo; aquí se normaliza a un string
  /// legible con indentación, sin importar cuál de los dos formatos llegó.
  String? _prettyJson(dynamic raw) {
    if (raw == null) return null;

    dynamic decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }

    try {
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return decoded.toString();
    }
  }

  String _formatFecha(DateTime fecha) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${fecha.year}-${two(fecha.month)}-${two(fecha.day)} ${two(fecha.hour)}:${two(fecha.minute)}:${two(fecha.second)}';
  }

  Future<void> log({
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
