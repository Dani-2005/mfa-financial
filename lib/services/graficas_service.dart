import 'api_client.dart';
import 'auth_service.dart';
import 'dashboard_service.dart';

/// Arma los datos agregados para la pestaña de "Gráficas" de Auditoría.
/// Reutiliza donde puede la misma lógica ya usada en otras pantallas
/// (capital nuevo por mes del Dashboard, umbrales de vencimiento) para que
/// los números coincidan entre pantallas. Por dentro ya no habla directo
/// con MySQL: llama al servidor MAF API en el VPS.
class GraficasService {
  final DashboardService _dashboardService = DashboardService();

  static const _mesesAbrev = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  Future<Map<String, String>> _headers() async {
    final headers = await AuthService.instance.authHeaders();
    if (headers == null) throw StateError('No hay una sesión activa.');
    return headers;
  }

  /// Capital nuevo colocado en cada uno de los últimos 6 meses (mismo dato
  /// que la mini-gráfica del Dashboard), con las etiquetas de mes ya
  /// resueltas para el eje X.
  Future<Map<String, dynamic>> fetchCapitalNuevoPorMes() async {
    final resumen = await _dashboardService.fetchCapitalSummary();
    final valores = (resumen['serie_mensual'] as List).cast<double>();
    final ahora = DateTime.now();
    final etiquetas = List.generate(valores.length, (i) {
      final offset = valores.length - 1 - i;
      final mes = DateTime(ahora.year, ahora.month - offset, 1);
      return _mesesAbrev[mes.month - 1];
    });
    return {'etiquetas': etiquetas, 'valores': valores};
  }

  /// Total cobrado (recibos_pagos) en cada uno de los últimos 6 meses,
  /// separado por tipo de movimiento, para una barra agrupada.
  Future<Map<String, dynamic>> fetchIngresosPorMes() async {
    final response = await ApiClient.instance.get('/api/graficas/ingresos-por-mes', headers: await _headers());
    if (!response.ok) throw StateError('No se pudieron cargar los ingresos por mes.');
    return {
      'etiquetas': (response.data['etiquetas'] as List).cast<String>(),
      'cuotaOrdinaria': (response.data['cuotaOrdinaria'] as List).map((v) => (v as num).toDouble()).toList(),
      'abonoCapital': (response.data['abonoCapital'] as List).map((v) => (v as num).toDouble()).toList(),
      'liquidacionTotal': (response.data['liquidacionTotal'] as List).map((v) => (v as num).toDouble()).toList(),
    };
  }

  /// Cuántos préstamos activos hay en cada estado de salud (mismas
  /// categorías que ya usan las pestañas de la pantalla de Préstamos: Al
  /// día, Pendiente, En Mora; más los ya Pagados).
  Future<Map<String, int>> fetchDistribucionEstados() async {
    final response = await ApiClient.instance.get('/api/graficas/distribucion-estados', headers: await _headers());
    if (!response.ok) throw StateError('No se pudo cargar la distribución de estados.');
    return response.data.map((key, value) => MapEntry(key, value as int));
  }

  /// Cuotas pendientes de préstamos activos, agrupadas por qué tan cerca
  /// está su fecha de vencimiento: ya vencidas, próximas a vencer (7 días)
  /// o todavía lejos ("al día").
  Future<Map<String, int>> fetchCuotasPorVencimiento() async {
    final response = await ApiClient.instance.get('/api/graficas/cuotas-por-vencimiento', headers: await _headers());
    if (!response.ok) throw StateError('No se pudieron cargar las cuotas por vencimiento.');
    return response.data.map((key, value) => MapEntry(key, value as int));
  }
}
