import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/cliente_service.dart';
import '../services/pago_service.dart';
import '../services/prestamo_service.dart';
import '../services/recibo_pdf_service.dart';
import '../widgets/custom_dropdown.dart';
import '../widgets/pdf_actions_dialog.dart';

/// Datos para abrir "Registrar Pago" con la cuota ya elegida de antemano
/// (por ejemplo, al venir del botón "Registrar pago" del Dashboard).
class PagoPrefill {
  final int clienteId;
  final int prestamoId;
  final int cuotaId;

  const PagoPrefill({required this.clienteId, required this.prestamoId, required this.cuotaId});
}

class PaymentsScreen extends StatefulWidget {
  final PagoPrefill? prefill;

  /// Se llama justo después de abrir el diálogo con [prefill], para que
  /// quien lo dio (el Dashboard, vía main.dart) lo borre de su estado. Si no
  /// se borra, un evento que no tiene nada que ver con "Registrar pago" —
  /// como cruzar el punto donde la app cambia de diseño móvil a desktop al
  /// redimensionar la ventana, que recrea esta pantalla desde cero— vuelve
  /// a ver el mismo `prefill` ya usado y reabre el diálogo solo.
  final VoidCallback? onPrefillConsumed;

  const PaymentsScreen({super.key, this.prefill, this.onPrefillConsumed});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final PagoService _pagoService = PagoService();

  // Filtros de Fecha (por defecto, el mes/año actual)
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  int _currentPage = 1;
  final int _itemsPerPage = 5;

  List<Map<String, dynamic>> _allPayments = [];
  bool _isLoading = true;
  String? _loadError;

  final List<String> _months = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];

  @override
  void initState() {
    super.initState();
    _loadPayments();

    final prefill = widget.prefill;
    if (prefill != null) {
      // El diálogo necesita un context ya insertado en el árbol (usa
      // Overlay/Navigator), así que se espera al primer frame construido.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onPrefillConsumed?.call();
        _showNewPaymentModal(context, prefill: prefill);
      });
    }
  }

  Future<void> _loadPayments() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final payments = await _pagoService.fetchAll();
      if (!mounted) return;
      setState(() {
        _allPayments = payments;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is NoConnectionException ? e.message : 'No se pudo cargar el historial de pagos.';
        _isLoading = false;
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
              Text('CONTABILIDAD Y CAJA', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2), overflow: TextOverflow.ellipsis),
              Text('Historial de Pagos', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset('assets/logooficial.jpeg', fit: BoxFit.contain),
              ),
            ),
            const SizedBox(width: 12),
            const Text('MAF Financial', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1)),
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset('assets/logooficial.jpeg', fit: BoxFit.contain),
              ),
            ),
            const SizedBox(width: 12),
            const Text('MAF Financial', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1)),
          ],
        ),
        const SizedBox(height: 20),
        const Text('CONTABILIDAD Y CAJA', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const Text('Historial de Pagos', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // --- DISEÑO PARA MÓVIL ---
  Widget _buildMobileContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: _buildPaymentsCoreContent(),
    );
  }

  // --- DISEÑO PARA ESCRITORIO ---
  Widget _buildDesktopContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: _buildPaymentsCoreContent(),
    );
  }

  // --- NÚCLEO DE PAGOS ---
  Widget _buildPaymentsCoreContent() {
    Widget listSection;

    if (_isLoading) {
      listSection = const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    } else if (_loadError != null) {
      listSection = Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade800, fontSize: 12)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadPayments,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      final filteredPayments = _allPayments.where((p) {
        return p['anio'] == _selectedYear && p['mes'] == _selectedMonth;
      }).toList();

      int totalPages = (filteredPayments.length / _itemsPerPage).ceil();
      if (totalPages == 0) totalPages = 1;
      if (_currentPage > totalPages) _currentPage = totalPages;

      int startIndex = (_currentPage - 1) * _itemsPerPage;
      int endIndex = startIndex + _itemsPerPage;
      if (endIndex > filteredPayments.length) {
        endIndex = filteredPayments.length;
      }

      final paginatedList = filteredPayments.isEmpty
          ? <Map<String, dynamic>>[]
          : filteredPayments.sublist(startIndex, endIndex);

      listSection = paginatedList.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                ...paginatedList.map((payment) => _buildPaymentCard(payment)),
                const SizedBox(height: 16),
                _buildPagination(totalPages, filteredPayments.length),
              ],
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopActionsBar(),
        const SizedBox(height: 16),
        _buildFilterBar(),
        const SizedBox(height: 20),
        listSection,
      ],
    );
  }

  Widget _buildTopActionsBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Período: ${_months[_selectedMonth - 1]} $_selectedYear', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Respaldo financiero y contable', style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => _showNewPaymentModal(context),
          icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.white),
          label: const Text('Registrar Pago', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: CustomDropdown<int>(
              initialValue: _selectedMonth,
              decoration: InputDecoration(
                labelText: 'Mes',
                prefixIcon: const Icon(Icons.calendar_month, color: Colors.black, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: List.generate(12, (index) => index + 1)
                  .map((m) => CustomDropdownItem(value: m, label: _months[m - 1]))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selectedMonth = val!;
                  _currentPage = 1;
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CustomDropdown<int>(
              initialValue: _selectedYear,
              decoration: InputDecoration(
                labelText: 'Año',
                prefixIcon: const Icon(Icons.date_range, color: Colors.black, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [2024, 2025, 2026, 2027]
                  .map((y) => CustomDropdownItem(value: y, label: '$y'))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selectedYear = val!;
                  _currentPage = 1;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    bool isActive = payment['activo'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? Colors.grey.shade200 : Colors.red.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.receipt_long, color: Colors.black, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payment['codigo_recibo'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(payment['cliente'], style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  // Botón para exportar/imprimir PDF del recibo individual
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 20),
                    tooltip: 'Descargar o Imprimir PDF',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    onPressed: () => _showPdfOptionsModal(context, payment),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.teal.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isActive ? 'VÁLIDO' : 'ANULADO',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isActive ? Colors.teal : Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monto Pagado', style: TextStyle(color: Colors.grey.shade800, fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(payment['monto'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Fecha de Emisión', style: TextStyle(color: Colors.grey.shade800, fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(payment['fecha_emision'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${payment['tipoMovimiento'] == 'Cuota_Ordinaria' ? 'Cuota' : 'Movimiento'}: ${payment['cuota']}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text('Concepto: ${payment['concepto']}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Método: ${payment['metodo']}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade800, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Ref: ${payment['referencia']}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade800, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.receipt_outlined, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          const Text('No hay pagos registrados para este mes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 4),
          Text('Selecciona otro período o registra un nuevo comprobante.', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
        ],
      ),
    );
  }

  Widget _buildPagination(int totalPages, int totalItems) {
    return Column(
      children: [
        Text('Página $_currentPage de $totalPages ($totalItems registros en total)', style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPageButton(
              icon: Icons.chevron_left,
              onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
            ),
            const SizedBox(width: 12),
            Text('Página $_currentPage', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(width: 12),
            _buildPageButton(
              icon: Icons.chevron_right,
              onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPageButton({required IconData icon, required VoidCallback? onPressed}) {
    bool isEnabled = onPressed != null;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isEnabled ? Colors.white : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: isEnabled ? Colors.grey.shade800 : Colors.grey.shade500),
        onPressed: onPressed,
      ),
    );
  }

 // --- MODAL DE OPCIONES PDF / IMPRESIÓN ---
  Future<Uint8List> _generarPdfRecibo(String codigoRecibo) async {
    final detalle = await _pagoService.fetchReciboDetalle(codigoRecibo);
    return ReciboPdfService.generar(detalle);
  }

  void _showPdfOptionsModal(BuildContext context, Map<String, dynamic> payment) {
    showPdfActionsDialog(
      context,
      titulo: 'Recibo ${payment['codigo_recibo']}',
      nombreArchivo: 'recibo_${payment['codigo_recibo']}.pdf',
      generarPdf: () => _generarPdfRecibo(payment['codigo_recibo'] as String),
      infoContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cliente: ${payment['cliente']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Monto: ${payment['monto']} (${payment['cuota']})', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
        ],
      ),
    );
  }

  // --- MODAL CON TAMAÑO FIJO Y TEXTAREA SCROLLEABLE PARA EL CONCEPTO ---
  void _showNewPaymentModal(BuildContext context, {PagoPrefill? prefill}) {
    showDialog(
      context: context,
      builder: (dialogContext) => _NewPaymentDialog(
        pagoService: _pagoService,
        prefill: prefill,
        onSaved: () {
          _currentPage = 1;
          _loadPayments();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pago registrado con éxito')),
          );
        },
      ),
    );
  }
}

/// Diálogo de "Registrar Nuevo Pago": cascada Cliente -> Préstamo -> Cuota
/// pendiente, con monto y concepto sugeridos automáticamente (editables) al
/// elegir la cuota.
class _NewPaymentDialog extends StatefulWidget {
  final PagoService pagoService;
  final VoidCallback onSaved;
  final PagoPrefill? prefill;

  const _NewPaymentDialog({required this.pagoService, required this.onSaved, this.prefill});

  @override
  State<_NewPaymentDialog> createState() => _NewPaymentDialogState();
}

class _NewPaymentDialogState extends State<_NewPaymentDialog> {
  final ClienteService _clienteService = ClienteService();
  final PrestamoService _prestamoService = PrestamoService();

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _refController = TextEditingController();
  final TextEditingController _conceptController = TextEditingController();

  List<Map<String, dynamic>> _clientes = [];
  bool _isLoadingClientes = true;
  String? _clientesLoadError;

  int? _selectedClienteId;
  List<Map<String, dynamic>> _prestamos = [];
  bool _isLoadingPrestamos = false;
  String? _prestamosLoadError;

  int? _selectedPrestamoId;
  List<Map<String, dynamic>> _cuotas = [];
  bool _isLoadingCuotas = false;
  String? _cuotasLoadError;

  int? _selectedCuotaId;
  String _selectedMethod = 'Transferencia Bancaria';

  /// Se incrementa en cada paso del prellenado externo (p. ej. al abrir el
  /// diálogo desde una cuota del Dashboard: cliente -> préstamo -> cuota),
  /// para forzar que el dropdown correspondiente se reconstruya con el
  /// nuevo valor. El FormField de un CustomDropdown solo usa su
  /// `initialValue` la primera vez que se crea; sin este empujón en la key,
  /// el campo seguía mostrándose vacío aunque el estado interno
  /// (`_selectedClienteId`/`_selectedPrestamoId`/`_selectedCuotaId`) ya
  /// tuviera el valor correcto asignado.
  int _prefillTick = 0;

  /// Tipo de movimiento que se está registrando: define qué campos se
  /// muestran y a qué método del servicio se llama al guardar.
  String _tipoMovimiento = 'Cuota_Ordinaria';

  /// Cuota Ordinaria y Pago Parcial son los dos tipos que pagan contra una
  /// cuota puntual (usan el selector de cuota); Abono a Capital y
  /// Liquidación Total pagan contra el préstamo directamente.
  bool get _esTipoPorCuota => _tipoMovimiento == 'Cuota_Ordinaria' || _tipoMovimiento == 'Pago_Parcial';
  Map<String, dynamic>? _saldoInfo;
  bool _isLoadingSaldo = false;
  String? _saldoError;

  bool _isSaving = false;

  /// Aviso de validación/error mostrado dentro del propio diálogo. No se usa
  /// SnackBar aquí porque se ancla al Scaffold de la pantalla de atrás y
  /// queda tapado por este diálogo modal — no se llega a ver completo.
  String? _errorMessage;
  Timer? _errorTimer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadClientes().then((_) => _applyPrefillIfAny());
  }

  /// Si el diálogo se abrió desde el Dashboard con una cuota ya elegida,
  /// encadena la misma cascada Cliente -> Préstamo -> Cuota que seguiría un
  /// usuario manualmente, para reusar toda la lógica y validaciones ya
  /// existentes (montos sugeridos, concepto por defecto, etc.).
  Future<void> _applyPrefillIfAny() async {
    final prefill = widget.prefill;
    if (prefill == null || !mounted) return;
    setState(() => _prefillTick++);
    await _onClienteChanged(prefill.clienteId);
    if (!mounted) return;
    setState(() => _prefillTick++);
    await _onPrestamoChanged(prefill.prestamoId);
    if (!mounted) return;
    setState(() => _prefillTick++);
    _onCuotaChanged(prefill.cuotaId);
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _scrollController.dispose();
    _amountController.dispose();
    _refController.dispose();
    _conceptController.dispose();
    super.dispose();
  }

  Future<void> _loadClientes() async {
    setState(() {
      _isLoadingClientes = true;
      _clientesLoadError = null;
    });
    try {
      final clientes = await _clienteService.fetchAll();
      if (!mounted) return;
      setState(() {
        _clientes = clientes.where((c) => c['activo'] == true).toList();
        _isLoadingClientes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingClientes = false;
        _clientesLoadError = e is NoConnectionException ? e.message : 'No se pudieron cargar los clientes.';
      });
    }
  }

  Future<void> _onClienteChanged(int? clienteId) async {
    setState(() {
      _selectedClienteId = clienteId;
      _selectedPrestamoId = null;
      _selectedCuotaId = null;
      _prestamos = [];
      _cuotas = [];
      _amountController.clear();
      _conceptController.clear();
      _isLoadingPrestamos = clienteId != null;
      _prestamosLoadError = null;
    });
    if (clienteId == null) return;
    try {
      final prestamos = await _prestamoService.fetchActivosPorCliente(clienteId);
      if (!mounted) return;
      setState(() {
        _prestamos = prestamos;
        _isLoadingPrestamos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPrestamos = false;
        _prestamosLoadError = e is NoConnectionException ? e.message : 'No se pudieron cargar los préstamos.';
      });
    }
  }

  Future<void> _onPrestamoChanged(int? prestamoId) async {
    setState(() {
      _selectedPrestamoId = prestamoId;
      _selectedCuotaId = null;
      _cuotas = [];
      _saldoInfo = null;
      _saldoError = null;
      _amountController.clear();
      _conceptController.clear();
      _isLoadingCuotas = prestamoId != null && _esTipoPorCuota;
      _isLoadingSaldo = prestamoId != null && !_esTipoPorCuota;
      _cuotasLoadError = null;
    });
    if (prestamoId == null) return;

    if (_esTipoPorCuota) {
      try {
        final cuotas = await _prestamoService.fetchCuotasPendientes(prestamoId);
        if (!mounted) return;
        setState(() {
          _cuotas = cuotas;
          _isLoadingCuotas = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoadingCuotas = false;
          _cuotasLoadError = e is NoConnectionException ? e.message : 'No se pudieron cargar las cuotas.';
        });
      }
      return;
    }

    // Abono a Capital o Liquidación Total: no se elige cuota, se consulta
    // el saldo actual del préstamo para anclar el monto y el concepto.
    // Cada tipo se ancla distinto: el abono usa el periodo vigente (próxima
    // cuota pendiente, o la cuota de hoy si todo capitaliza sin fases);
    // la liquidación siempre usa el saldo final acumulado del préstamo.
    try {
      final saldo = _tipoMovimiento == 'Liquidacion_Total'
          ? await _prestamoService.fetchSaldoActual(prestamoId)
          : await _prestamoService.fetchAnclaAbono(prestamoId);
      final prestamo = _prestamos.firstWhere((p) => p['prestamo_id'] == prestamoId);
      final saldoActual = saldo['saldoActual'] as double;
      if (!mounted) return;
      setState(() {
        _saldoInfo = saldo;
        _isLoadingSaldo = false;
        if (_tipoMovimiento == 'Liquidacion_Total') {
          _amountController.text = saldoActual.toStringAsFixed(2);
          _conceptController.text = 'Liquidación total del préstamo #${prestamo['codigo_referencia']}. '
              'Paga el saldo total de \$${saldoActual.toStringAsFixed(2)} y finaliza el préstamo.';
        } else {
          _conceptController.text = 'Abono a capital del préstamo #${prestamo['codigo_referencia']}.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSaldo = false;
        _saldoError = e is ArgumentError
            ? '${e.message}'
            : (e is NoConnectionException ? e.message : 'No se pudo obtener el saldo actual del préstamo.');
      });
    }
  }

  void _onTipoChanged(String tipo) {
    setState(() {
      _tipoMovimiento = tipo;
      _selectedCuotaId = null;
      _cuotas = [];
      _saldoInfo = null;
      _saldoError = null;
      _amountController.clear();
      _conceptController.clear();
    });
    if (_selectedPrestamoId != null) {
      _onPrestamoChanged(_selectedPrestamoId);
    }
  }

  void _onCuotaChanged(int? cuotaId) {
    setState(() {
      _selectedCuotaId = cuotaId;
      if (cuotaId == null) return;

      final cuota = _cuotas.firstWhere((c) => c['cuota_id'] == cuotaId);
      final prestamo = _prestamos.firstWhere((p) => p['prestamo_id'] == _selectedPrestamoId);
      final montoRestante = cuota['montoSugerido'] as double;

      if (_tipoMovimiento == 'Pago_Parcial') {
        // No se pre-llena: el usuario debe decidir cuánto abona de lo que
        // falta, así que solo se sugiere el concepto y se deja el monto en
        // blanco para que no confirme por error el monto completo.
        _amountController.clear();
        _conceptController.text = 'Pago parcial de la cuota ${cuota['numeroPeriodo']} de ${cuota['numeroCuotas']} '
            'del préstamo #${prestamo['codigo_referencia']} (falta \$${montoRestante.toStringAsFixed(2)}).';
      } else {
        _amountController.text = montoRestante.toStringAsFixed(2);
        _conceptController.text = 'Pago de la cuota ${cuota['numeroPeriodo']} de ${cuota['numeroCuotas']} '
            'del préstamo #${prestamo['codigo_referencia']}.';
      }
    });
  }

  void _snack(String message) {
    _errorTimer?.cancel();
    setState(() => _errorMessage = message);
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _errorMessage = null);
    });
    // El aviso se muestra arriba del todo del formulario: si el usuario
    // estaba desplazado hacia abajo (llenando los últimos campos), hay que
    // subir la vista para que lo vea sin tener que hacer scroll manual.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<void> _save() async {
    if (_selectedClienteId == null || _selectedPrestamoId == null) {
      _snack('Selecciona el cliente y el préstamo');
      return;
    }
    if (_esTipoPorCuota && _selectedCuotaId == null) {
      _snack('Selecciona la cuota a pagar');
      return;
    }

    double? monto;
    if (_tipoMovimiento != 'Liquidacion_Total') {
      monto = double.tryParse(_amountController.text);
      if (monto == null || monto <= 0) {
        _snack('Ingresa un monto válido');
        return;
      }
    }

    if (_conceptController.text.trim().isEmpty) {
      _snack('Ingresa el concepto del pago');
      return;
    }

    _errorTimer?.cancel();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final referencia = _refController.text.trim().isEmpty ? null : _refController.text.trim();
      final concepto = _conceptController.text.trim();

      switch (_tipoMovimiento) {
        case 'Abono_Capital':
          await _prestamoService.registrarAbonoCapital(
            prestamoId: _selectedPrestamoId!,
            monto: monto!,
            descripcionConcepto: concepto,
            metodoPago: _selectedMethod,
            referencia: referencia,
            fechaEmision: DateTime.now(),
          );
          break;
        case 'Liquidacion_Total':
          await _prestamoService.registrarLiquidacionTotal(
            prestamoId: _selectedPrestamoId!,
            descripcionConcepto: concepto,
            metodoPago: _selectedMethod,
            referencia: referencia,
            fechaEmision: DateTime.now(),
          );
          break;
        case 'Pago_Parcial':
          await widget.pagoService.registrarPagoParcial(
            cuotaId: _selectedCuotaId!,
            monto: monto!,
            descripcionConcepto: concepto,
            metodoPago: _selectedMethod,
            referencia: referencia,
            fechaEmision: DateTime.now(),
          );
          break;
        default:
          await widget.pagoService.registrarPago(
            cuotaId: _selectedCuotaId!,
            monto: monto!,
            descripcionConcepto: concepto,
            metodoPago: _selectedMethod,
            referencia: referencia,
            fechaEmision: DateTime.now(),
          );
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } on ArgumentError catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      _snack('${e.message}');
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      _snack(e is NoConnectionException ? e.message : 'No se pudo registrar el movimiento. Intenta de nuevo.');
    }
  }

  Widget _tipoChip(String value, String label, IconData icon) {
    final selected = _tipoMovimiento == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
      ),
      avatar: Icon(icon, size: 16, color: selected ? Colors.white : Colors.black87),
      selected: selected,
      onSelected: (_) => _onTipoChanged(value),
      selectedColor: Colors.black,
      backgroundColor: Colors.grey.shade100,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? Colors.black : Colors.grey.shade300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar Nuevo Pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      content: SizedBox(
        width: 450,
        height: 560,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _errorMessage == null
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TweenAnimationBuilder<double>(
                            key: ValueKey(_errorMessage),
                            duration: const Duration(milliseconds: 200),
                            tween: Tween(begin: 0, end: 1),
                            builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
              ),
              Text(
                '¿Qué tipo de movimiento vas a registrar?',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tipoChip('Cuota_Ordinaria', 'Cuota Ordinaria', Icons.receipt_long),
                  _tipoChip('Pago_Parcial', 'Pago Parcial', Icons.hourglass_bottom),
                  _tipoChip('Abono_Capital', 'Abono a Capital', Icons.trending_down),
                  _tipoChip('Liquidacion_Total', 'Liquidación Total', Icons.flag_circle_outlined),
                ],
              ),
              const SizedBox(height: 14),

              // Selector de Cliente
              CustomDropdown<int>(
                key: ValueKey('cliente_${_clientes.length}_${_isLoadingClientes}_$_prefillTick'),
                initialValue: _selectedClienteId,
                enabled: !_isLoadingClientes && _clientesLoadError == null,
                decoration: InputDecoration(
                  labelText: _isLoadingClientes ? 'Cargando clientes...' : 'Cliente',
                  prefixIcon: const Icon(Icons.person, color: Colors.black),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _clientes
                    .map((c) => CustomDropdownItem<int>(
                          value: c['cliente_id'] as int,
                          label: '${c['nombre_cliente']} (${c['documento_identidad']})',
                        ))
                    .toList(),
                onChanged: _onClienteChanged,
              ),
              if (_clientesLoadError != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(_clientesLoadError!, style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                    ),
                    TextButton(onPressed: _loadClientes, child: const Text('Reintentar', style: TextStyle(fontSize: 12))),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Selector de Préstamo (solo si el cliente tiene varios, pero
              // siempre se muestra para elegir explícitamente cuál es)
              CustomDropdown<int>(
                key: ValueKey('prestamo_${_selectedClienteId}_$_prefillTick'),
                initialValue: _selectedPrestamoId,
                enabled: _selectedClienteId != null && !_isLoadingPrestamos && _prestamosLoadError == null,
                decoration: InputDecoration(
                  labelText: _isLoadingPrestamos ? 'Cargando préstamos...' : 'Préstamo',
                  prefixIcon: const Icon(Icons.request_page_outlined, color: Colors.black),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _prestamos
                    .map((p) => CustomDropdownItem<int>(
                          value: p['prestamo_id'] as int,
                          label: '#${p['codigo_referencia']} (${p['loanType']})',
                        ))
                    .toList(),
                onChanged: _onPrestamoChanged,
              ),
              if (_prestamosLoadError != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(_prestamosLoadError!, style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                    ),
                    TextButton(
                      onPressed: () => _onClienteChanged(_selectedClienteId),
                      child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ] else if (_selectedClienteId != null && !_isLoadingPrestamos && _prestamos.isEmpty) ...[
                const SizedBox(height: 6),
                Text('Este cliente no tiene préstamos activos.', style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
              ],
              const SizedBox(height: 12),

              if (_esTipoPorCuota) ...[
                // Selector de Cuota Pendiente/Parcial: se desactiva si el
                // préstamo no tiene ninguna cuota pendiente o parcial (nada
                // que cobrar), en vez de dejarlo abierto mostrando un menú
                // vacío.
                CustomDropdown<int>(
                  key: ValueKey('cuota_${_selectedPrestamoId}_${_tipoMovimiento}_$_prefillTick'),
                  initialValue: _selectedCuotaId,
                  enabled: _selectedPrestamoId != null && !_isLoadingCuotas && _cuotas.isNotEmpty && _cuotasLoadError == null,
                  decoration: InputDecoration(
                    labelText: _isLoadingCuotas
                        ? 'Cargando cuotas...'
                        : _cuotasLoadError != null
                            ? 'No se pudo cargar'
                            : (_selectedPrestamoId != null && _cuotas.isEmpty)
                                ? 'Sin cuotas pendientes'
                                : 'Cuota Pendiente',
                    prefixIcon: const Icon(Icons.list_alt, color: Colors.black),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _cuotas
                      .map((c) => CustomDropdownItem<int>(
                            value: c['cuota_id'] as int,
                            label: 'Cuota ${c['numeroPeriodo']} de ${c['numeroCuotas']} — Vence ${c['fechaVencimiento']}'
                                '${c['estado'] == 'Parcial' ? ' (Parcial, falta \$${(c['montoSugerido'] as double).toStringAsFixed(2)})' : ''}',
                          ))
                      .toList(),
                  onChanged: _onCuotaChanged,
                ),
                if (_cuotasLoadError != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_cuotasLoadError!, style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                      ),
                      TextButton(
                        onPressed: () => _onPrestamoChanged(_selectedPrestamoId),
                        child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ] else if (_selectedPrestamoId != null && !_isLoadingCuotas && _cuotas.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Este préstamo no tiene cuotas pendientes por cobrar.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                  ),
                ],
                if (_tipoMovimiento == 'Pago_Parcial' && _selectedCuotaId != null) ...[
                  const SizedBox(height: 6),
                  Builder(builder: (_) {
                    final cuota = _cuotas.firstWhere((c) => c['cuota_id'] == _selectedCuotaId);
                    final restante = cuota['montoSugerido'] as double;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        'Falta \$${restante.toStringAsFixed(2)} de esta cuota. Ingresa un monto menor a ese '
                        'para dejarla en "Parcial"; si vas a cubrir todo lo que falta, usa "Cuota Ordinaria".',
                        style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
              ] else if (_selectedPrestamoId != null) ...[
                // Saldo actual del préstamo (Abono a Capital / Liquidación Total)
                if (_isLoadingSaldo)
                  Text('Consultando saldo actual...', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))
                else if (_saldoError != null)
                  Text(_saldoError!, style: TextStyle(fontSize: 12, color: Colors.red.shade700))
                else if (_saldoInfo != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      _tipoMovimiento == 'Liquidacion_Total'
                          ? 'Saldo total adeudado: \$${(_saldoInfo!['saldoActual'] as double).toStringAsFixed(2)}'
                          : 'Saldo actual: \$${(_saldoInfo!['saldoActual'] as double).toStringAsFixed(2)}'
                              '${_saldoInfo!['periodoInicial'] != null ? ' — se aplicará a partir de la cuota ${_saldoInfo!['periodoInicial']}' : ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                const SizedBox(height: 12),
              ],

              // Monto: en Abono a Capital y Pago Parcial es editable (el
              // usuario decide cuánto abona); en Cuota Ordinaria y
              // Liquidación Total es de solo lectura porque siempre exigen
              // el monto exacto (el total de la cuota, o el saldo completo).
              TextField(
                controller: _amountController,
                readOnly: _tipoMovimiento == 'Liquidacion_Total' || _tipoMovimiento == 'Cuota_Ordinaria',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  labelText: _tipoMovimiento == 'Abono_Capital'
                      ? 'Monto a Abonar (\$)'
                      : _tipoMovimiento == 'Pago_Parcial'
                          ? 'Monto Parcial a Pagar (\$)'
                          : 'Monto Total Pagado (\$)',
                  prefixIcon: const Icon(Icons.attach_money, color: Colors.black),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: _tipoMovimiento == 'Liquidacion_Total' || _tipoMovimiento == 'Cuota_Ordinaria',
                  fillColor: Colors.grey.shade100,
                ),
              ),
              const SizedBox(height: 12),

              // Método de Pago
              CustomDropdown<String>(
                initialValue: _selectedMethod,
                decoration: InputDecoration(
                  labelText: 'Método de Pago',
                  prefixIcon: const Icon(Icons.payment, color: Colors.black),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: ['Transferencia Bancaria', 'Pago Móvil', 'Efectivo USD', 'Depósito', 'Zelle', 'Binance / USDT', 'PayPal']
                    .map((m) => CustomDropdownItem(value: m, label: m))
                    .toList(),
                onChanged: (val) => setState(() => _selectedMethod = val!),
              ),
              const SizedBox(height: 12),

              // Referencia
              TextField(
                controller: _refController,
                decoration: InputDecoration(
                  labelText: 'Número de Referencia (opcional)',
                  prefixIcon: const Icon(Icons.confirmation_number_outlined, color: Colors.black),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),

              // Concepto: se sugiere un texto por defecto al elegir la
              // cuota, pero queda libre para editarlo.
              SizedBox(
                height: 95,
                child: TextField(
                  controller: _conceptController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    labelText: 'Descripción del Concepto',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade800)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Guardar Pago', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}