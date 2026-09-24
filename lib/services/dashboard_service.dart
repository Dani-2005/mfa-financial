import 'api_client.dart';
import 'auth_service.dart';

/// Igual que antes en su interfaz pública, pero por dentro ya no habla
/// directo con MySQL: llama al servidor MAF API en el VPS.
class DashboardService {
  Future<Map<String, String>> _headers() async {
    final headers = await AuthService.instance.authHeaders();
    if (headers == null) throw StateError('No hay una sesión activa.');
    return headers;
  }

  Future<Map<String, dynamic>> fetchCapitalSummary() async {
    final response = await ApiClient.instance.get('/api/dashboard/capital-summary', headers: await _headers());
    if (!response.ok) throw StateError('No se pudo cargar el resumen de capital.');
    // Un JSON decodificado da List<dynamic>, no List<double>: el resto del
    // código hace `as List<double>` directo sobre este campo, así que hay
    // que convertirlo explícitamente aquí (una vez), no dejarlo como venga.
    return {
      ...response.data,
      'serie_mensual': (response.data['serie_mensual'] as List).map((v) => (v as num).toDouble()).toList(),
    };
  }

  Future<int> fetchPrestamosActivosCount() async {
    final response = await ApiClient.instance.get('/api/dashboard/prestamos-activos-count', headers: await _headers());
    if (!response.ok) throw StateError('No se pudo cargar el conteo de préstamos activos.');
    return response.data['n'] as int;
  }

  Future<Map<String, dynamic>> fetchProximasCuotas({int limite = 5}) async {
    final response = await ApiClient.instance.get(
      '/api/dashboard/proximas-cuotas?limite=$limite',
      headers: await _headers(),
    );
    if (!response.ok) throw StateError('No se pudieron cargar las próximas cuotas.');

    final proximas = (response.data['proximas'] as List).cast<Map<String, dynamic>>().map((cuota) {
      return {
        ...cuota,
        'fecha_vencimiento': DateTime.parse(cuota['fecha_vencimiento'] as String),
      };
    }).toList();

    return {
      'total_pendientes': response.data['total_pendientes'],
      'proximas': proximas,
    };
  }
}
