import 'dart:convert';
import 'api_client.dart';
import 'auth_service.dart';

/// Solo lectura: el servidor MAF API en el VPS ya audita por su cuenta las
/// acciones de todos los servicios (todos migrados a la API), así que esta
/// clase ya no necesita escribir nada — solo consultar el historial.
class AuditoriaService {
  Future<List<Map<String, dynamic>>> fetchAll() async {
    final headers = await AuthService.instance.authHeaders();
    if (headers == null) throw StateError('No hay una sesión activa.');

    final response = await ApiClient.instance.get('/api/auditoria/', headers: headers);
    if (!response.ok) throw StateError('No se pudo cargar la auditoría.');

    final registros = (response.data['registros'] as List).cast<Map<String, dynamic>>();

    return registros.map((fields) {
      final fechaStr = fields['fecha_accion'] as String?;
      final fecha = fechaStr == null || fechaStr.isEmpty ? null : DateTime.parse(fechaStr);

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
}
