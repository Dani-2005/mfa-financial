import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/dashboard_service.dart';
import '../widgets/mini_charts.dart' show abreviarMonto;
import 'payments_screen.dart' show PagoPrefill;

class DashboardScreen extends StatefulWidget {
  final void Function(PagoPrefill prefill)? onRegistrarPago;

  const DashboardScreen({super.key, this.onRegistrarPago});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();

  double? _totalCapital;
  double? _porcentajeCambio;
  List<double> _serieMensual = [];
  bool? _capitalNuevoCreciendo;
  double? _totalIntereses;
  double? _porcentajeCambioIntereses;
  List<double> _serieInteresesMensual = [];
  bool? _interesesCreciendo;
  int? _prestamosActivos;
  List<Map<String, dynamic>> _proximasCuotas = [];
  int _totalCuotasPendientes = 0;

  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _dashboardService.fetchCapitalSummary(),
        _dashboardService.fetchInteresesSummary(),
        _dashboardService.fetchPrestamosActivosCount(),
        _dashboardService.fetchProximasCuotas(),
      ]);
      final capitalSummary = results[0] as Map<String, dynamic>;
      final interesesSummary = results[1] as Map<String, dynamic>;
      final prestamosActivos = results[2] as int;
      final proximasCuotas = results[3] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _totalCapital = capitalSummary['total_actual'] as double;
        _porcentajeCambio = capitalSummary['porcentaje_cambio'] as double?;
        _serieMensual = capitalSummary['serie_mensual'] as List<double>;
        _capitalNuevoCreciendo = capitalSummary['capital_nuevo_creciendo'] as bool?;
        _totalIntereses = interesesSummary['total_actual'] as double;
        _porcentajeCambioIntereses = interesesSummary['porcentaje_cambio'] as double?;
        _serieInteresesMensual = interesesSummary['serie_mensual'] as List<double>;
        _interesesCreciendo = interesesSummary['intereses_creciendo'] as bool?;
        _prestamosActivos = prestamosActivos;
        _proximasCuotas = (proximasCuotas['proximas'] as List).cast<Map<String, dynamic>>();
        _totalCuotasPendientes = proximasCuotas['total_pendientes'] as int;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is NoConnectionException ? e.message : 'No se pudieron cargar los datos del panel.';
        _isLoading = false;
      });
    }
  }

  String _formatCurrency(double value) {
    final isNegative = value < 0;
    final parts = value.abs().toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];

    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
      buffer.write(intPart[i]);
    }

    return '${isNegative ? '-' : ''}\$${buffer.toString()},$decPart';
  }

  @override
  Widget build(BuildContext context) {
    // 1. ELIMINAMOS el Scaffold y el SafeArea. Usamos un Container directo.
    return Container(
      width: double.infinity,  // <-- ESTO OBLIGA A TOMAR TODA LA PANTALLA
      height: double.infinity,
      color: const Color(0xFFF5F5F5), // Gris muy claro para el fondo
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth >= 800;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra fija superior
              _buildHeader(context, isDesktop),
              
              // Contenido con scroll
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: isDesktop ? 80 : 20), 
                      isDesktop ? _buildDesktopContent() : _buildMobileContent(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- CABECERA ---
  Widget _buildHeader(BuildContext context, bool isDesktop) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity, 
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 0, 0, 0),
        // 3. Solo aplicamos la curva si es móvil
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(isDesktop ? 0 : 32),
        ),
      ),
      padding: EdgeInsets.only(
        // Añadimos el topPadding solo en móvil para que el texto no quede debajo de la hora
        top: (isDesktop ? 20 : 30) + (isDesktop ? 0 : topPadding), 
        left: isDesktop ? 40 : 16,
        right: isDesktop ? 40 : 16,
        bottom: isDesktop ? 30 : 40,
      ),
      child: isDesktop
          ? _buildDesktopHeaderContent() 
          : _buildMobileHeaderContent(),
    );
  }

  // Contenido del header horizontal y compacto (Desktop)
  Widget _buildDesktopHeaderContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Lado Izquierdo: Textos
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('VISIÓN GENERAL', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2), overflow: TextOverflow.ellipsis),
              Text('Panel Principal', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Lado Derecho: Logo y Nombre de Empresa
        Row(
          children: [
            Container(
              width: 74,
              height: 50,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 0, 0, 0),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))
                ]
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/logooficial.jpeg', 
                  fit: BoxFit.contain, 
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'MAF Financial', 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1),
            ),
          ],
        ),
      ],
    );
  }

  // Contenido del header vertical y tradicional (Móvil)
  Widget _buildMobileHeaderContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 59,
              height: 40,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 0, 0, 0),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))
                ]
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/logooficial.jpeg', 
                  fit: BoxFit.contain, 
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'MAF Financial', 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('VISIÓN GENERAL', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const Text('Panel Principal', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // --- DISEÑO PARA MÓVIL ---
  Widget _buildMobileContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          _buildTotalCapitalCard(),
          const SizedBox(height: 12),
          _buildInteresesCard(),
          const SizedBox(height: 12),
          _buildActiveLoansCard(),
          const SizedBox(height: 24),
          _buildAlertsSection(),
        ],
      ),
    );
  }

  // --- DISEÑO PARA WINDOWS/ESCRITORIO ---
  Widget _buildDesktopContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _buildTotalCapitalCard(),
                const SizedBox(height: 16),
                _buildInteresesCard(),
                const SizedBox(height: 16),
                _buildActiveLoansCard(),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 2,
            child: _buildAlertsSection(),
          ),
        ],
      ),
    );
  }

  // --- COMPONENTES ---
  Widget _buildTotalCapitalCard() {
    return _buildMetricCard(
      titulo: 'CAPITAL TOTAL PRESTADO',
      total: _totalCapital,
      porcentajeCambio: _porcentajeCambio,
      serieMensual: _serieMensual,
      creciendo: _capitalNuevoCreciendo,
      leyendaGrafica: 'Capital nuevo · 6 meses',
      textoSinDatos: 'Nuevo este período',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MetricYearDetailScreen(
            titulo: 'Capital Nuevo Colocado',
            leyendaMes: 'Capital colocado',
            fetchPorAnio: _dashboardService.fetchCapitalPorAnio,
            formatMoney: _formatCurrency,
          ),
        ),
      ),
    );
  }

  Widget _buildInteresesCard() {
    return _buildMetricCard(
      titulo: 'INTERESES TOTALES COBRADOS',
      total: _totalIntereses,
      porcentajeCambio: _porcentajeCambioIntereses,
      serieMensual: _serieInteresesMensual,
      creciendo: _interesesCreciendo,
      leyendaGrafica: 'Intereses cobrados · 6 meses',
      textoSinDatos: 'Cobrado este período',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MetricYearDetailScreen(
            titulo: 'Intereses Cobrados',
            leyendaMes: 'Intereses cobrados',
            fetchPorAnio: _dashboardService.fetchInteresesPorAnio,
            formatMoney: _formatCurrency,
          ),
        ),
      ),
    );
  }

  /// Tarjeta genérica de métrica con gráfico de barras mensual: la usan
  /// tanto el capital total prestado como los intereses totales cobrados,
  /// que comparten exactamente la misma forma de dato (total acumulado +
  /// variación vs. mes pasado + serie de los últimos 6 meses).
  Widget _buildMetricCard({
    required String titulo,
    required double? total,
    required double? porcentajeCambio,
    required List<double> serieMensual,
    required bool? creciendo,
    required String leyendaGrafica,
    required String textoSinDatos,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: _isLoading ? null : _loadDashboardData,
                icon: Icon(Icons.refresh, size: 16, color: Colors.grey.shade600),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Actualizar',
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              ),
            )
          else if (_loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_loadError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            )
          else
            LayoutBuilder(
              builder: (context, rowConstraints) {
                // El gráfico prefiere su ancho natural (hasta 170) pegado a la
                // derecha; en pantallas muy angostas se reduce como proporción
                // del ancho disponible para nunca desbordar, en vez de competir
                // en partes iguales con el texto (lo que dejaría un hueco vacío
                // a su derecha en vez de quedar pegado al borde).
                final chartMaxWidth = (rowConstraints.maxWidth * 0.42).clamp(130.0, 190.0);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatCurrency(total ?? 0),
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black),
                                maxLines: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildVariacionLabel(
                            total: total,
                            porcentajeCambio: porcentajeCambio,
                            textoSinDatos: textoSinDatos,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: chartMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CapitalBarChart(
                            values: serieMensual,
                            isGrowing: creciendo ?? true,
                            formatMoney: _formatCurrency,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            leyendaGrafica,
                            style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildVariacionLabel({
    required double? total,
    required double? porcentajeCambio,
    required String textoSinDatos,
  }) {
    if (porcentajeCambio == null) {
      return Text(
        total != null && total > 0 ? textoSinDatos : 'Sin datos del mes pasado',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
      );
    }

    final esPositivo = porcentajeCambio >= 0;
    final signo = esPositivo ? '+' : '';

    return Row(
      children: [
        Icon(
          esPositivo ? Icons.trending_up : Icons.trending_down,
          size: 14,
          color: esPositivo ? Colors.teal.shade700 : Colors.red.shade700,
        ),
        const SizedBox(width: 4),
        Text(
          '$signo${porcentajeCambio.toStringAsFixed(1)}%',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: esPositivo ? Colors.teal.shade700 : Colors.red.shade700,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'vs. mes pasado',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveLoansCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL PRÉSTAMOS ACTIVOS', style: TextStyle(color: Colors.grey.shade800, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
              _isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      ),
                    )
                  : Text(
                      '${_prestamosActivos ?? 0}',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'PRÓXIMAS CUOTAS POR COBRAR',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '$_totalCuotasPendientes Pendiente${_totalCuotasPendientes == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            )
          ],
        ),
        const SizedBox(height: 12),
        if (_proximasCuotas.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              'No hay cuotas próximas por cobrar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          )
        else
          for (int i = 0; i < _proximasCuotas.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _buildAlertCard(_proximasCuotas[i]),
          ],
      ],
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> cuota) {
    final name = cuota['nombre_cliente'] as String;
    final codigo = cuota['codigo_referencia'] as String;
    final amount = _formatCurrency(cuota['monto'] as double);
    final fechaVencimiento = cuota['fecha_vencimiento_display'] as String;
    final isUrgent = cuota['is_urgent'] as bool;
    final clienteId = cuota['cliente_id'] as int;
    final prestamoId = cuota['prestamo_id'] as int;
    final cuotaId = cuota['cuota_id'] as int;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isUrgent ? Colors.grey.shade500 : Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: isUrgent ? Colors.grey.shade300 : Colors.grey.shade100,
                foregroundColor: Colors.black,
                child: const Icon(Icons.person_outline, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text('Préstamo #$codigo', style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text('Vence: $fechaVencimiento', style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                child: const Text('PENDIENTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: widget.onRegistrarPago == null
                    ? null
                    : () => widget.onRegistrarPago!(
                          PagoPrefill(clienteId: clienteId, prestamoId: prestamoId, cuotaId: cuotaId),
                        ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFAAAAAA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Registrar pago', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              )
            ],
          )
        ],
      ),
    );
  }
}

/// Gráfico de barras del capital nuevo colocado en los últimos meses, una
/// barra por mes con su abreviatura debajo. Verde si la tendencia viene
/// creciendo, rojo si viene cayendo. Reemplaza al sparkline anterior (una
/// línea sin etiquetas ni valores) porque a los usuarios les costaba
/// interpretarlo: las barras muestran la magnitud de cada mes de forma
/// directa, y tocar una barra muestra su monto exacto en un tooltip.
class _CapitalBarChart extends StatelessWidget {
  final List<double> values;
  final bool isGrowing;
  final String Function(double) formatMoney;
  // Si no se dan, se calculan como "los últimos N meses hasta hoy" (uso
  // original, en la tarjeta del dashboard). La pantalla de detalle por año
  // sí las da explícitas (Ene..Dic de un año que puede no ser el actual).
  final List<String>? labels;
  final double height;

  const _CapitalBarChart({
    required this.values,
    required this.isGrowing,
    required this.formatMoney,
    this.labels,
    this.height = 100,
  });

  static const _mesesAbrev = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  List<String> _etiquetas() {
    if (labels != null) return labels!;
    final ahora = DateTime.now();
    return List.generate(values.length, (i) {
      final offset = values.length - 1 - i;
      final mes = DateTime(ahora.year, ahora.month - offset, 1);
      return _mesesAbrev[mes.month - 1];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(height: height);
    }

    final color = isGrowing ? Colors.teal.shade600 : Colors.red.shade600;
    final etiquetas = _etiquetas();
    final maxValor = values.reduce((a, b) => a > b ? a : b);
    final maxEje = maxValor <= 0 ? 1.0 : maxValor * 1.25;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxEje,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxEje / 2,
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tooltipMargin: 6,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                formatMoney(rod.toY),
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: maxEje / 2,
                getTitlesWidget: (value, meta) => Text(
                  abreviarMonto(value),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: 7, color: Colors.grey.shade700),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 16,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= etiquetas.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      etiquetas[i],
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(fontSize: 8, color: Colors.grey.shade700),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(values.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: color,
                  width: 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Detalle de una métrica del dashboard (capital colocado o intereses
/// cobrados) mes a mes, para un año elegido con un selector — a diferencia
/// de la tarjeta chica, que siempre muestra los últimos 6 meses corridos
/// sin importar el año. Se abre al tocar la tarjeta correspondiente.
class _MetricYearDetailScreen extends StatefulWidget {
  final String titulo;
  final String leyendaMes;
  final Future<Map<String, dynamic>> Function(int anio) fetchPorAnio;
  final String Function(double) formatMoney;

  const _MetricYearDetailScreen({
    required this.titulo,
    required this.leyendaMes,
    required this.fetchPorAnio,
    required this.formatMoney,
  });

  @override
  State<_MetricYearDetailScreen> createState() => _MetricYearDetailScreenState();
}

class _MetricYearDetailScreenState extends State<_MetricYearDetailScreen> {
  static const _mesesNombre = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];
  static const _mesesAbrev = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  int _anioSeleccionado = DateTime.now().year;
  List<int> _aniosDisponibles = [DateTime.now().year];
  List<double> _meses = List.filled(12, 0);
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar(_anioSeleccionado);
  }

  Future<void> _cargar(int anio) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final datos = await widget.fetchPorAnio(anio);
      if (!mounted) return;
      final anios = datos['anios_disponibles'] as List<int>;
      setState(() {
        _meses = datos['meses'] as List<double>;
        // El año elegido siempre queda como opción, aunque no tenga datos
        // todavía (ej. el año actual recién empezando).
        _aniosDisponibles = {...anios, anio}.toList()..sort();
        _anioSeleccionado = anio;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is NoConnectionException ? e.message : 'No se pudo cargar el detalle.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _meses.fold<double>(0, (sum, v) => sum + v);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(widget.titulo, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Año', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                        DropdownButton<int>(
                          value: _anioSeleccionado,
                          underline: const SizedBox(),
                          items: _aniosDisponibles
                              .map((a) => DropdownMenuItem(value: a, child: Text('$a', style: const TextStyle(fontSize: 14))))
                              .toList(),
                          onChanged: _isLoading ? null : (a) {
                            if (a != null && a != _anioSeleccionado) _cargar(a);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator(color: Colors.black)),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade800, fontSize: 12)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => _cargar(_anioSeleccionado),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                            child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL $_anioSeleccionado',
                            style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.formatMoney(total),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black),
                          ),
                          const SizedBox(height: 20),
                          _CapitalBarChart(
                            values: _meses,
                            isGrowing: true,
                            formatMoney: widget.formatMoney,
                            labels: _mesesAbrev,
                            height: 220,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < 12; i++) ...[
                            if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_mesesNombre[i], style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                  Text(
                                    widget.formatMoney(_meses[i]),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _meses[i] > 0 ? Colors.black : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}