import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/auditoria_service.dart';
import '../services/cliente_service.dart';
import '../services/graficas_service.dart';
import '../services/reporte_pdf_service.dart';
import '../services/reporte_service.dart';
import '../widgets/custom_dropdown.dart';
import '../widgets/mini_charts.dart';
import '../widgets/pdf_actions_dialog.dart';

class AuditAndReportsScreen extends StatefulWidget {
  const AuditAndReportsScreen({super.key});

  @override
  State<AuditAndReportsScreen> createState() => _AuditAndReportsScreenState();
}

class _AuditAndReportsScreenState extends State<AuditAndReportsScreen> {
  // Control de vista interna (0: Bitácora, 1: Generar Reportes, 2: Gráficas)
  int _selectedSection = 0;

  // ==========================================
  // ESTADOS PARA LA PESTAÑA DE GRÁFICAS
  // ==========================================
  final GraficasService _graficasService = GraficasService();
  bool _chartsLoaded = false;
  bool _isLoadingCharts = false;
  String? _chartsError;
  Map<String, dynamic> _capitalNuevo = const {};
  Map<String, dynamic> _ingresosPorMes = const {};
  Map<String, int> _distribucionEstados = const {};
  Map<String, int> _cuotasPorVencimiento = const {};

  // Filtros para la bitácora
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedActionFilter = 'TODAS';

  // ==========================================
  // ESTADOS PARA REPORTES PERSONALIZADOS
  // ==========================================
  String _selectedReportModule = 'Clientes';
  
  // Filtro específico para préstamos y pagos por cliente
  String _selectedReportClient = 'TODOS';
  List<String> _availableClients = const ['TODOS'];
  String? _clientesFiltroError;
  // Resuelve la etiqueta mostrada en el filtro ("documento - nombre") de
  // vuelta al cliente_id real, para poder filtrar la consulta del reporte.
  final Map<String, int> _clienteIdPorEtiqueta = {};
  final ClienteService _clienteService = ClienteService();
  final ReporteService _reporteService = ReporteService();

  // Campos disponibles y su selección por cada módulo/página
  final Map<String, Map<String, bool>> _reportModuleFields = {
    'Clientes': {
      'Cédula / ID': true,
      'Nombre Completo': true,
      'Teléfono': true,
      'Dirección': false,
      'Estatus Activo': true,
    },
    'Préstamos': {
      'Código Préstamo': true,
      'Cédula Cliente': true,
      'Monto Aprobado': true,
      'Plazo': true,
      'Estatus': true,
    },
    'Pagos': {
      'Número Recibo': true,
      'Cédula Cliente': true,
      'Préstamo': true,
      'Monto Pagado': true,
      'Descripción': true,
      'Referencia / Método': true,
      'Fecha': true,
    },
    'Auditoría': {
      'ID Log': true,
      'Tabla Afectada': true,
      'Acción': true,
      'Registro ID': true,
      'Usuario Responsable': true,
      'Fecha Acción': true,
      'Snapshots JSON': false,
    },
  };

  final AuditoriaService _auditoriaService = AuditoriaService();
  List<Map<String, dynamic>> _auditLogs = [];
  bool _isLoadingLogs = true;
  String? _loadLogsError;

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
    _loadClientesParaFiltro();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClientesParaFiltro() async {
    setState(() => _clientesFiltroError = null);
    try {
      final clientes = await _clienteService.fetchAll();
      if (!mounted) return;
      setState(() {
        _clienteIdPorEtiqueta.clear();
        for (final c in clientes) {
          final etiqueta = '${c['documento_identidad']} - ${c['nombre_cliente']}';
          _clienteIdPorEtiqueta[etiqueta] = c['cliente_id'] as int;
        }
        _availableClients = ['TODOS', ..._clienteIdPorEtiqueta.keys];
      });
    } catch (e) {
      // Si falla, el filtro se queda solo con "TODOS"; no bloquea el resto de
      // la pantalla, pero se avisa para que no parezca que no hay clientes.
      if (!mounted) return;
      setState(() {
        _clientesFiltroError = e is NoConnectionException ? e.message : 'No se pudo cargar el filtro de clientes.';
      });
    }
  }

  /// Carga perezosa: solo se piden los datos de las gráficas la primera
  /// vez que el usuario entra a esa pestaña, no de entrada con la pantalla.
  Future<void> _loadChartsIfNeeded() async {
    if (_chartsLoaded || _isLoadingCharts) return;
    setState(() {
      _isLoadingCharts = true;
      _chartsError = null;
    });
    try {
      final resultados = await Future.wait([
        _graficasService.fetchCapitalNuevoPorMes(),
        _graficasService.fetchIngresosPorMes(),
        _graficasService.fetchDistribucionEstados(),
        _graficasService.fetchCuotasPorVencimiento(),
      ]);
      if (!mounted) return;
      setState(() {
        _capitalNuevo = resultados[0];
        _ingresosPorMes = resultados[1];
        _distribucionEstados = resultados[2] as Map<String, int>;
        _cuotasPorVencimiento = resultados[3] as Map<String, int>;
        _chartsLoaded = true;
        _isLoadingCharts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chartsError = e is NoConnectionException ? e.message : 'No se pudieron cargar las gráficas.';
        _isLoadingCharts = false;
      });
    }
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _isLoadingLogs = true;
      _loadLogsError = null;
    });
    try {
      final logs = await _auditoriaService.fetchAll();
      if (!mounted) return;
      setState(() {
        _auditLogs = logs;
        _isLoadingLogs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadLogsError = e is NoConnectionException ? e.message : 'No se pudo cargar la bitácora de auditoría.';
        _isLoadingLogs = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,  
      height: double.infinity,
      color: const Color(0xFFF5F5F5), 
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth >= 800;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, 
            children: [
              _buildHeader(context, isDesktop),
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

  // ==========================================
  // HEADER
  // ==========================================
  Widget _buildHeader(BuildContext context, bool isDesktop) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity, 
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 0, 0, 0),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(isDesktop ? 0 : 32),
        ),
      ),
      padding: EdgeInsets.only(
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

  Widget _buildDesktopHeaderContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GESTIÓN', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2), overflow: TextOverflow.ellipsis),
              Text('Auditoría y Reportes', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 12),
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
        const Text('GESTIÓN', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const Text('Auditoría y Reportes', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ==========================================
  // SELECTOR DE VISTA
  // ==========================================
  static const _sectionLabels = ['Bitácora de Auditoría', 'Generar Reportes', 'Gráficas'];
  static const _sectionLabelsCortas = ['Bitácora', 'Reportes', 'Gráficas'];

  void _onSectionTap(int index) {
    setState(() => _selectedSection = index);
    if (index == 2) _loadChartsIfNeeded();
  }

  Widget _buildSectionSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: List.generate(_sectionLabels.length, (index) {
          final selected = _selectedSection == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => _onSectionTap(index),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final style = TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    );
                    final full = _sectionLabels[index];
                    // Mismo tamaño de letra siempre: si la etiqueta completa
                    // no entra en esta pestaña (letra grande, pantalla
                    // angosta), se usa una versión corta en vez de achicar
                    // la fuente o cortarla con puntos suspensivos.
                    final painter = TextPainter(
                      text: TextSpan(text: full, style: style),
                      textScaler: MediaQuery.textScalerOf(context),
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                    )..layout();
                    final cabeCompleta = painter.width <= constraints.maxWidth;
                    return Text(
                      cabeCompleta ? full : _sectionLabelsCortas[index],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    );
                  },
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActiveSectionView() {
    switch (_selectedSection) {
      case 1:
        return _buildReportsView();
      case 2:
        return _buildChartsView();
      default:
        return _buildAuditLogsView();
    }
  }

  Widget _buildMobileContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          _buildSectionSelector(),
          const SizedBox(height: 16),
          _buildActiveSectionView(),
        ],
      ),
    );
  }

  Widget _buildDesktopContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 480, child: _buildSectionSelector()),
            ],
          ),
          const SizedBox(height: 20),
          _buildActiveSectionView(),
        ],
      ),
    );
  }

  // ==========================================
  // VISTA 1: BITÁCORA DE AUDITORÍA
  // ==========================================
  Widget _buildAuditLogsView() {
    final filteredLogs = _auditLogs.where((log) {
      final query = _searchQuery.toLowerCase();
      final table = log['tabla_afectada'].toLowerCase();
      final user = log['usuario_responsable'].toLowerCase();
      final regId = log['registro_id'].toLowerCase();
      
      bool matchesSearch = table.contains(query) || user.contains(query) || regId.contains(query);
      bool matchesAction = _selectedActionFilter == 'TODAS' || log['accion'] == _selectedActionFilter;

      return matchesSearch && matchesAction;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const hintStyle = TextStyle(fontSize: 12);
                    const hintFull = 'Buscar tabla, usuario o ID...';
                    // Mismo tamaño de letra siempre: si el hint completo no
                    // entra (letra grande, pantalla angosta), se usa una
                    // versión corta en vez de dejar que se corte solo.
                    final painter = TextPainter(
                      text: const TextSpan(text: hintFull, style: hintStyle),
                      textScaler: MediaQuery.textScalerOf(context),
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      // Deja espacio para el ícono de búsqueda y el padding.
                    )..layout(maxWidth: double.infinity);
                    final espacioDisponible = constraints.maxWidth - 14 - 20 - 8 - 14;
                    final cabeCompleto = painter.width <= espacioDisponible;
                    return TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: cabeCompleto ? hintFull : 'Buscar...',
                        hintMaxLines: 1,
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        prefixIcon: const Icon(Icons.search, size: 20, color: Colors.black),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedActionFilter,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold),
                    items: const [
                      DropdownMenuItem(value: 'TODAS', child: Text('Acción: Todas')),
                      DropdownMenuItem(value: 'INSERT', child: Text('INSERT')),
                      DropdownMenuItem(value: 'UPDATE', child: Text('UPDATE')),
                      DropdownMenuItem(value: 'DELETE', child: Text('DELETE')),
                      DropdownMenuItem(value: 'DESACTIVAR', child: Text('DESACTIVAR')),
                    ],
                    onChanged: (val) => setState(() => _selectedActionFilter = val!),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: IconButton(
                onPressed: _isLoadingLogs ? null : _loadAuditLogs,
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh, size: 20, color: Colors.black),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoadingLogs)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator(color: Colors.black)),
          )
        else if (_loadLogsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                const SizedBox(height: 12),
                Text(_loadLogsError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade800, fontSize: 12)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loadAuditLogs,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                  child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          )
        else if (filteredLogs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40.0),
            child: Center(child: Text('No se encontraron registros de auditoría', style: TextStyle(color: Colors.grey.shade800))),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredLogs.length,
            itemBuilder: (context, index) {
              final log = filteredLogs[index];
              return _buildLogCard(log);
            },
          ),
      ],
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    String accion = log['accion'];
    Color actionColor = Colors.blue;
    if (accion == 'INSERT') actionColor = Colors.teal;
    if (accion == 'UPDATE') actionColor = Colors.orange.shade800;
    if (accion == 'DELETE') actionColor = Colors.red;
    if (accion == 'DESACTIVAR') actionColor = Colors.purple;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    accion,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: actionColor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tabla: ${log['tabla_afectada']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  log['fecha_accion'],
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: Color(0xFFF1F5F9)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Registro ID: ${log['registro_id']}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Usuario: ${log['usuario_responsable']}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showAuditDetailsModal(context, log),
                icon: const Icon(Icons.code, size: 14),
                label: const Text('Ver Snapshots (JSON)', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAuditDetailsModal(BuildContext context, Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalle de Auditoría #${log['id']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Datos Anteriores (JSON):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.redAccent)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text(log['datos_anteriores'] ?? 'NULL (Sin datos previos)', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ),
                const SizedBox(height: 14),
                const Text('Datos Nuevos (JSON):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text(log['datos_nuevos'] ?? 'NULL (Registro eliminado)', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VISTA 2: GENERAR REPORTES PERSONALIZADOS
  // ==========================================
  Widget _buildReportsView() {
    final currentFields = _reportModuleFields[_selectedReportModule] ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Centro de Generación de Reportes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 4),
        Text(
          'Seleccione el módulo, filtre por cliente específico (si aplica) y personalice los campos del documento.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 16),

        // 1. Selector de Módulo / Página a reportar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Seleccione la Página / Módulo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              CustomDropdown<String>(
                initialValue: _selectedReportModule,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                items: _reportModuleFields.keys.map((String moduleName) {
                  return CustomDropdownItem<String>(value: moduleName, label: moduleName);
                }).toList(),
                onChanged: (String? newModule) {
                  if (newModule != null) {
                    setState(() {
                      _selectedReportModule = newModule;
                    });
                  }
                },
              ),
            ],
          ),
        ),

        // ==========================================
        // FILTRO CONDICIONAL: PRÉSTAMOS O PAGOS POR CLIENTE
        // ==========================================
        if (_selectedReportModule == 'Préstamos' || _selectedReportModule == 'Pagos') ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtro Opcional: Seleccionar Cliente Específico para $_selectedReportModule',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Text(
                  'Deje en "TODOS" para incluir el registro general completo.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 10),
                CustomDropdown<String>(
                  initialValue: _selectedReportClient,
                  enabled: _clientesFiltroError == null,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _availableClients.map((String client) {
                    return CustomDropdownItem<String>(value: client, label: client);
                  }).toList(),
                  onChanged: (String? val) {
                    if (val != null) setState(() => _selectedReportClient = val);
                  },
                ),
                if (_clientesFiltroError != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_clientesFiltroError!, style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                      ),
                      TextButton(
                        onPressed: _loadClientesParaFiltro,
                        child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // 2. Selector de Campos Dinámicos dentro del módulo
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '2. Campos a incluir en el reporte de "$_selectedReportModule"',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        currentFields.updateAll((key, value) => true);
                      });
                    },
                    child: const Text('Marcar Todos', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFF1F5F9)),
              const SizedBox(height: 6),
              
              ...currentFields.keys.map((String fieldKey) {
                bool isChecked = currentFields[fieldKey] ?? false;
                return CheckboxListTile(
                  title: Text(fieldKey, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  value: isChecked,
                  activeColor: Colors.black,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (bool? value) {
                    setState(() {
                      _reportModuleFields[_selectedReportModule]![fieldKey] = value ?? false;
                    });
                  },
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==========================================
        // BOTÓN DE ACCIÓN CON ANCHO ADAPTABLE (Desktop vs Mobile)
        // ==========================================
        LayoutBuilder(
          builder: (context, constraints) {
            bool isDesktopButton = constraints.maxWidth >= 600;

            Widget generateButton = ElevatedButton.icon(
              onPressed: () => _generarReporte(context, _selectedReportModule),
              icon: const Icon(Icons.picture_as_pdf, size: 16, color: Colors.white),
              label: const Text('Generar y Exportar Reporte Personalizado', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );

            return isDesktopButton
                ? Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 380,
                      child: generateButton,
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: generateButton,
                  );
          },
        ),
      ],
    );
  }

  void _generarReporte(BuildContext context, String reportType) {
    final selectedFieldsMap = _reportModuleFields[reportType] ?? {};
    final activeFields = selectedFieldsMap.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (activeFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar al menos un campo para generar el reporte.')),
      );
      return;
    }

    final aplicaFiltroCliente =
        (reportType == 'Préstamos' || reportType == 'Pagos') && _selectedReportClient != 'TODOS';
    final clienteId = aplicaFiltroCliente ? _clienteIdPorEtiqueta[_selectedReportClient] : null;

    final nombreArchivo =
        'reporte_${reportType.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';

    showPdfActionsDialog(
      context,
      titulo: 'Reporte de $reportType',
      nombreArchivo: nombreArchivo,
      generarPdf: () async {
        final filas = await _reporteService.fetchDatos(modulo: reportType, clienteId: clienteId);
        return ReportePdfService.generar(
          modulo: reportType,
          columnas: activeFields,
          filas: filas,
          filtroCliente: aplicaFiltroCliente ? _selectedReportClient : null,
        );
      },
      infoContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Módulo: $reportType', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Campos: ${activeFields.join(", ")}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
          if (aplicaFiltroCliente) ...[
            const SizedBox(height: 4),
            Text('Cliente: $_selectedReportClient', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // VISTA 3: GRÁFICAS
  // ==========================================
  static const Map<String, Color> _coloresEstados = {
    'AL DÍA': Colors.teal,
    'PENDIENTE': Color(0xFF00838F), // cyan.shade800
    'EN MORA': Color(0xFFD32F2F), // red.shade700
    'PAGADO': Color(0xFF455A64), // blueGrey.shade700
  };

  static const Map<String, Color> _coloresCuotasVencimiento = {
    'Vencidas': Color(0xFFD32F2F),
    'Próximas (7 días)': Color(0xFFEF6C00), // orange.shade800
    'Al día': Colors.teal,
  };

  static const Map<String, Color> _coloresIngresos = {
    'Cuota Ordinaria': Colors.black,
    'Abono a Capital': Colors.teal,
    'Liquidación Total': Color(0xFF455A64),
  };

  Widget _buildChartsView() {
    if (_isLoadingCharts) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }
    if (_chartsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(_chartsError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade800, fontSize: 12)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                _chartsLoaded = false;
                _loadChartsIfNeeded();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
    if (!_chartsLoaded) return const SizedBox();

    final tarjetas = <_TarjetaGrafica>[
      _TarjetaGrafica(
        titulo: 'Capital Nuevo por Mes',
        subtitulo: 'Cuánto se prestó cada uno de los últimos 6 meses',
        builder: (h) => buildBarraCategorica(
          etiquetas: (_capitalNuevo['etiquetas'] as List).cast<String>(),
          valores: (_capitalNuevo['valores'] as List).cast<double>(),
          height: h,
        ),
      ),
      _TarjetaGrafica(
        titulo: 'Ingresos Cobrados por Mes',
        subtitulo: 'Cuota Ordinaria, Abono a Capital y Liquidación Total',
        leyenda: _coloresIngresos,
        builder: (h) => buildBarraAgrupada(
          etiquetas: (_ingresosPorMes['etiquetas'] as List).cast<String>(),
          series: {
            'Cuota Ordinaria': (_ingresosPorMes['cuotaOrdinaria'] as List).cast<double>(),
            'Abono a Capital': (_ingresosPorMes['abonoCapital'] as List).cast<double>(),
            'Liquidación Total': (_ingresosPorMes['liquidacionTotal'] as List).cast<double>(),
          },
          colores: _coloresIngresos,
          height: h,
        ),
      ),
      _TarjetaGrafica(
        titulo: 'Distribución de la Cartera',
        subtitulo: 'Préstamos por estado de salud',
        leyenda: _coloresEstados,
        builder: (h) => buildDona(datos: _distribucionEstados, colores: _coloresEstados, height: h),
      ),
      _TarjetaGrafica(
        titulo: 'Cuotas por Vencimiento',
        subtitulo: 'Cuotas pendientes de préstamos activos',
        leyenda: _coloresCuotasVencimiento,
        builder: (h) => buildBarraCategorica(
          etiquetas: _cuotasPorVencimiento.keys.toList(),
          valores: _cuotasPorVencimiento.values.map((v) => v.toDouble()).toList(),
          coloresPorBarra: _cuotasPorVencimiento.keys.map((k) => _coloresCuotasVencimiento[k]!).toList(),
          esMoneda: false,
          height: h,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final esAncho = constraints.maxWidth >= 700;
        final anchoTarjeta = esAncho ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: tarjetas.map((t) => SizedBox(width: anchoTarjeta, child: _buildChartCard(t))).toList(),
        );
      },
    );
  }

  Widget _buildChartCard(_TarjetaGrafica tarjeta) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _ChartFocusScreen(tarjeta: tarjeta)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(tarjeta.titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Icon(Icons.open_in_full, size: 16, color: Colors.grey.shade500),
              ],
            ),
            const SizedBox(height: 2),
            Text(tarjeta.subtitulo, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            const SizedBox(height: 14),
            tarjeta.builder(160),
            if (tarjeta.leyenda != null) ...[
              const SizedBox(height: 10),
              buildLeyenda(tarjeta.leyenda!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Datos de una tarjeta de gráfica: se reutilizan tanto en la tarjeta chica
/// del listado como en la pantalla de enfoque, para no duplicar la lógica
/// de construcción de cada gráfica.
class _TarjetaGrafica {
  final String titulo;
  final String subtitulo;
  final Widget Function(double height) builder;
  final Map<String, Color>? leyenda;

  const _TarjetaGrafica({
    required this.titulo,
    required this.subtitulo,
    required this.builder,
    this.leyenda,
  });
}

/// Pantalla de "enfoque": la misma gráfica de la tarjeta, más grande y con
/// su leyenda, ocupando toda la pantalla.
class _ChartFocusScreen extends StatelessWidget {
  final _TarjetaGrafica tarjeta;

  const _ChartFocusScreen({required this.tarjeta});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(tarjeta.titulo, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tarjeta.subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  const SizedBox(height: 20),
                  tarjeta.builder(340),
                  if (tarjeta.leyenda != null) ...[
                    const SizedBox(height: 18),
                    buildLeyenda(tarjeta.leyenda!),
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