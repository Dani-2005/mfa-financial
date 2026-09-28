import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/cliente_service.dart';
import '../services/loan_calculator.dart';
import '../services/plan_pagos_pdf_service.dart';
import '../services/prestamo_service.dart';
import '../widgets/custom_dropdown.dart';
import '../widgets/money_input_formatter.dart';
import '../widgets/pdf_actions_dialog.dart';

class LoansScreen extends StatefulWidget {
  /// Cambia cada vez que se entra a esta pestaña (ver main.dart): al
  /// cambiar, la lista se vuelve a pedir al servidor sin perder búsqueda ni
  /// filtros.
  final int refreshSignal;

  const LoansScreen({super.key, this.refreshSignal = 0});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  final PrestamoService _prestamoService = PrestamoService();
  final TextEditingController _searchController = TextEditingController();

  int _selectedFilter = 0; // 0: Todos, 1: Al día, 2: Pendientes
  int _currentPage = 1;
  static const int _itemsPerPage = 8;

  String _searchQuery = '';
  List<Map<String, dynamic>> _loans = [];
  bool _isLoading = true;
  String? _loadError;

  // ==========================================
  // FILTROS AVANZADOS (ícono de controles al lado de la búsqueda)
  // ==========================================
  List<Map<String, dynamic>> _estadosFiltro = [];
  bool _isLoadingEstadosFiltro = false;

  String? _filtroEstadoNombre;
  String? _filtroTipoTasa;
  DateTime? _filtroFechaDesde;
  DateTime? _filtroFechaHasta;
  double? _filtroMontoDesde;
  double? _filtroMontoHasta;

  bool get _hayFiltrosActivos =>
      _filtroEstadoNombre != null ||
      _filtroTipoTasa != null ||
      _filtroFechaDesde != null ||
      _filtroFechaHasta != null ||
      _filtroMontoDesde != null ||
      _filtroMontoHasta != null;

  @override
  void initState() {
    super.initState();
    _loadLoans();
    _loadEstadosFiltro();
  }

  Future<void> _loadEstadosFiltro() async {
    setState(() => _isLoadingEstadosFiltro = true);
    try {
      final estados = await _prestamoService.fetchEstados();
      if (!mounted) return;
      setState(() {
        _estadosFiltro = estados;
        _isLoadingEstadosFiltro = false;
      });
    } catch (_) {
      // El filtro por estado simplemente queda vacío si falla; no es
      // crítico para ver el listado, así que no se muestra ningún error.
      if (!mounted) return;
      setState(() => _isLoadingEstadosFiltro = false);
    }
  }

  @override
  void didUpdateWidget(covariant LoansScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal == oldWidget.refreshSignal) return;
    // Se pide después de mostrar la pestaña, para que el cambio de
    // pestaña sea inmediato y la recarga no compita con ese frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadLoans(silencioso: true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// [silencioso]: recarga al volver a la pestaña. Mantiene la lista actual
  /// en pantalla mientras llegan los datos nuevos (sin spinner), y si falla
  /// se queda con los datos que ya tenía en vez de mostrar el error.
  Future<void> _loadLoans({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final loans = await _prestamoService.fetchAll();
      if (!mounted) return;
      setState(() {
        _loans = loans;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || silencioso) return;
      setState(() {
        _loadError = e is NoConnectionException ? e.message : 'No se pudo cargar la lista de préstamos.';
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
              _buildHeader(context, isDesktop),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: isDesktop ? 80 : 20),
                      isDesktop
                          ? _buildDesktopContent()
                          : _buildMobileContent(),
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
              Text(
                'GESTIÓN',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Préstamos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
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
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
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
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                height: 1,
              ),
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
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
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
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'GESTIÓN',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const Text(
          'Préstamos',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          _buildTopActions(isDesktop: false),
          const SizedBox(height: 14),
          _buildSearchBar(),
          const SizedBox(height: 14),
          _buildFilterTabs(),
          const SizedBox(height: 16),
          _buildLoansListContent(),
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
          _buildTopActions(isDesktop: true),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(flex: 3, child: _buildSearchBar()),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: _buildFilterTabs()),
            ],
          ),
          const SizedBox(height: 20),
          _buildLoansListContent(),
        ],
      ),
    );
  }

  Widget _buildLoansListContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadLoans,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              child: const Text(
                'Reintentar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    final query = _searchQuery.toLowerCase();
    final filtered = _loans.where((loan) {
      final matchesSearch =
          query.isEmpty ||
          (loan['name'] as String).toLowerCase().contains(query) ||
          (loan['code'] as String).toLowerCase().contains(query) ||
          ((loan['nombrePrestamo'] as String?) ?? '').toLowerCase().contains(query) ||
          ((loan['estadoNombre'] as String?) ?? '').toLowerCase().contains(query);

      final status = loan['status'] as String;
      bool matchesTab;
      switch (_selectedFilter) {
        case 1:
          matchesTab = status == 'AL DÍA';
          break;
        case 2:
          matchesTab = status == 'PENDIENTE' || status == 'EN MORA';
          break;
        case 3:
          matchesTab = status == 'PAGADO';
          break;
        default:
          matchesTab = status != 'PAGADO';
      }

      final matchesEstado = _filtroEstadoNombre == null || loan['estadoNombre'] == _filtroEstadoNombre;
      final matchesTipoTasa = _filtroTipoTasa == null || loan['tipoTasa'] == _filtroTipoTasa;

      var matchesFecha = true;
      if (_filtroFechaDesde != null || _filtroFechaHasta != null) {
        final fecha = DateTime.tryParse((loan['fechaInicioRaw'] as String?) ?? '');
        if (fecha == null) {
          matchesFecha = false;
        } else {
          if (_filtroFechaDesde != null && fecha.isBefore(_filtroFechaDesde!)) matchesFecha = false;
          if (_filtroFechaHasta != null &&
              fecha.isAfter(_filtroFechaHasta!.add(const Duration(hours: 23, minutes: 59, seconds: 59)))) {
            matchesFecha = false;
          }
        }
      }

      var matchesMonto = true;
      if (_filtroMontoDesde != null || _filtroMontoHasta != null) {
        final monto = (loan['capitalInicialMonto'] as num?)?.toDouble();
        if (monto == null) {
          matchesMonto = false;
        } else {
          if (_filtroMontoDesde != null && monto < _filtroMontoDesde!) matchesMonto = false;
          if (_filtroMontoHasta != null && monto > _filtroMontoHasta!) matchesMonto = false;
        }
      }

      return matchesSearch && matchesTab && matchesEstado && matchesTipoTasa && matchesFecha && matchesMonto;
    }).toList();

    // Agrupados por estado (alfabético, "Sin estado" al final); dentro de
    // cada estado se conserva el orden que trae el servidor (más recientes
    // primero). Se ordena antes de paginar para que cada grupo quede junto.
    final ordenOriginal = {for (var i = 0; i < filtered.length; i++) filtered[i]: i};
    filtered.sort((a, b) {
      final ea = a['estadoNombre'] as String?;
      final eb = b['estadoNombre'] as String?;
      if (ea != eb) {
        if (ea == null) return 1;
        if (eb == null) return -1;
        final cmp = _sinAcentos(ea).compareTo(_sinAcentos(eb));
        if (cmp != 0) return cmp;
      }
      return ordenOriginal[a]!.compareTo(ordenOriginal[b]!);
    });
    final conteoPorEstado = <String?, int>{};
    for (final loan in filtered) {
      final estado = loan['estadoNombre'] as String?;
      conteoPorEstado[estado] = (conteoPorEstado[estado] ?? 0) + 1;
    }

    int totalPages = (filtered.length / _itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;
    if (_currentPage > totalPages) _currentPage = totalPages;

    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, filtered.length);
    final paginated = filtered.isEmpty
        ? <Map<String, dynamic>>[]
        : filtered.sublist(startIndex, endIndex);

    if (paginated.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(40.0),
        child: Center(
          child: Text(
            'No se encontraron préstamos',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paginated.length; i++) ...[
          if (i == 0 || paginated[i]['estadoNombre'] != paginated[i - 1]['estadoNombre'])
            _buildEstadoHeader(
              paginated[i]['estadoNombre'] as String?,
              conteoPorEstado[paginated[i]['estadoNombre']] ?? 0,
              primero: i == 0,
            ),
          _buildLoanCard(context, paginated[i]),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        _buildPagination(totalPages, filtered.length),
      ],
    );
  }

  static String _sinAcentos(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  /// Encabezado de grupo en el listado, p. ej. "Lara (5)". El conteo es del
  /// grupo completo (con los filtros aplicados), no solo de la página actual.
  Widget _buildEstadoHeader(String? estado, int cantidad, {required bool primero}) {
    return Padding(
      padding: EdgeInsets.only(top: primero ? 0 : 12, bottom: 10, left: 4),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, size: 18, color: Colors.grey.shade800),
          const SizedBox(width: 6),
          Text(
            '${estado ?? 'Sin estado'} ($cantidad)',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'EN MORA':
        return Colors.red.shade700;
      case 'PENDIENTE':
        return Colors.cyan.shade800;
      case 'PAGADO':
        return Colors.blueGrey.shade700;
      default:
        return Colors.teal;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'EN MORA':
        return Colors.red.shade50;
      case 'PENDIENTE':
        return Colors.cyan.shade50;
      case 'PAGADO':
        return Colors.blueGrey.shade50;
      default:
        return Colors.teal.shade50;
    }
  }

  /// En computadora el botón "Nuevo Préstamo" va más grande (más fácil de
  /// encontrar y de pulsar con el mouse); en celular se mantiene compacto.
  Widget _buildTopActions({required bool isDesktop}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const style = TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color.fromARGB(255, 0, 0, 0),
                  );
                  const full = 'Listado de Préstamos';
                  // Mismo tamaño de letra siempre: si el título completo no
                  // entra en una línea (letra grande de accesibilidad,
                  // pantalla angosta), se usa una versión corta en vez de
                  // achicar la fuente o cortarla con puntos suspensivos.
                  final painter = TextPainter(
                    text: const TextSpan(text: full, style: style),
                    textScaler: MediaQuery.textScalerOf(context),
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                  )..layout();
                  final cabeCompleto = painter.width <= constraints.maxWidth;
                  return Text(
                    cabeCompleto ? full : 'Listado',
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFAAAAAA),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${_loans.length} préstamo${_loans.length == 1 ? '' : 's'} registrado${_loans.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: IconButton(
                onPressed: _isLoading ? null : _loadLoans,
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh, size: 20, color: Colors.black),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NewLoanFormScreen(),
                  ),
                );
                _loadLoans();
              },
              icon: Icon(
                Icons.add_circle_outline,
                size: isDesktop ? 22 : 18,
                color: Colors.white,
              ),
              label: Text(
                'Nuevo Préstamo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isDesktop ? 15 : 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 0, 0, 0),
                padding: isDesktop
                    ? const EdgeInsets.symmetric(horizontal: 24, vertical: 18)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isDesktop ? 26 : 20),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por cliente, código, nombre o estado...',
          hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
          suffixIcon: IconButton(
            onPressed: _showFiltrosDialog,
            tooltip: 'Filtros avanzados',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.tune, color: _hayFiltrosActivos ? Colors.black : Colors.grey.shade600, size: 18),
                if (_hayFiltrosActivos)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
            _currentPage = 1;
          });
        },
      ),
    );
  }

  /// Diálogo de filtros avanzados (Estado, Tipo de Tasa, rango de fecha de
  /// inicio y rango de monto), abierto desde el ícono de controles de la
  /// barra de búsqueda. Los cambios se editan en variables locales al
  /// diálogo (vía [StatefulBuilder]) y solo se aplican a la lista real al
  /// tocar "Aplicar Filtros" — así no se refiltra la lista de fondo con
  /// cada toque mientras el usuario todavía está eligiendo.
  Future<void> _showFiltrosDialog() async {
    String tempEstado = _filtroEstadoNombre ?? 'TODOS';
    String tempTipoTasa = _filtroTipoTasa ?? 'TODOS';
    DateTime? tempFechaDesde = _filtroFechaDesde;
    DateTime? tempFechaHasta = _filtroFechaHasta;
    final montoDesdeCtrl = TextEditingController(
      text: _filtroMontoDesde != null ? MoneyInputFormatter.format(_filtroMontoDesde!) : '',
    );
    final montoHastaCtrl = TextEditingController(
      text: _filtroMontoHasta != null ? MoneyInputFormatter.format(_filtroMontoHasta!) : '',
    );

    await showDialog(
      context: context,
      builder: (dialogContext) {
        final isDesktop = MediaQuery.sizeOf(dialogContext).width >= 800;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickFecha({required bool esDesde}) async {
              final actual = esDesde ? tempFechaDesde : tempFechaHasta;
              final picked = await showDatePicker(
                context: context,
                initialDate: actual ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked == null) return;
              setDialogState(() {
                if (esDesde) {
                  tempFechaDesde = picked;
                } else {
                  tempFechaHasta = picked;
                }
              });
            }

            Widget fechaField(String label, DateTime? value, VoidCallback onTap) {
              return InkWell(
                onTap: onTap,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: label,
                    prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.black),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  child: Text(
                    value == null
                        ? '(sin definir)'
                        : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
                    style: TextStyle(fontSize: 13, color: value == null ? Colors.grey.shade600 : Colors.black87),
                  ),
                ),
              );
            }

            Widget montoField(String label, TextEditingController controller) {
              return TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoneyInputFormatter()],
                decoration: InputDecoration(
                  labelText: label,
                  prefixIcon: const Icon(Icons.attach_money, size: 18, color: Colors.black),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              );
            }

            final campoEstado = CustomDropdown<String>(
              key: ValueKey('filtro_estado_${_estadosFiltro.length}'),
              initialValue: tempEstado,
              enabled: !_isLoadingEstadosFiltro,
              decoration: InputDecoration(
                labelText: 'Estado',
                prefixIcon: const Icon(Icons.map_outlined, color: Colors.black),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const CustomDropdownItem(value: 'TODOS', label: 'Todos los estados'),
                ..._estadosFiltro.map((e) => CustomDropdownItem<String>(value: e['nombre'] as String, label: e['nombre'] as String)),
              ],
              onChanged: (val) => setDialogState(() => tempEstado = val ?? 'TODOS'),
            );

            final campoTipoTasa = CustomDropdown<String>(
              initialValue: tempTipoTasa,
              decoration: InputDecoration(
                labelText: 'Tipo de Tasa',
                prefixIcon: const Icon(Icons.percent, color: Colors.black),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                CustomDropdownItem(value: 'TODOS', label: 'Todas'),
                CustomDropdownItem(value: 'Fija', label: 'Fija'),
                CustomDropdownItem(value: 'Variable', label: 'Variable'),
              ],
              onChanged: (val) => setDialogState(() => tempTipoTasa = val ?? 'TODOS'),
            );

            final campoFechas = isDesktop
                ? Row(
                    children: [
                      Expanded(child: fechaField('Fecha inicio desde', tempFechaDesde, () => pickFecha(esDesde: true))),
                      const SizedBox(width: 10),
                      Expanded(child: fechaField('Fecha inicio hasta', tempFechaHasta, () => pickFecha(esDesde: false))),
                    ],
                  )
                : Column(
                    children: [
                      fechaField('Fecha inicio desde', tempFechaDesde, () => pickFecha(esDesde: true)),
                      const SizedBox(height: 12),
                      fechaField('Fecha inicio hasta', tempFechaHasta, () => pickFecha(esDesde: false)),
                    ],
                  );

            final campoMontos = isDesktop
                ? Row(
                    children: [
                      Expanded(child: montoField('Monto desde', montoDesdeCtrl)),
                      const SizedBox(width: 10),
                      Expanded(child: montoField('Monto hasta', montoHastaCtrl)),
                    ],
                  )
                : Column(
                    children: [
                      montoField('Monto desde', montoDesdeCtrl),
                      const SizedBox(height: 12),
                      montoField('Monto hasta', montoHastaCtrl),
                    ],
                  );

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 80 : 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Filtros Avanzados',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close, color: Colors.black54),
                              tooltip: 'Cerrar',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // En escritorio, Estado y Tipo de Tasa comparten fila
                        // (hay espacio de sobra); en móvil van apilados para
                        // no comprimirlos.
                        isDesktop
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: campoEstado),
                                  const SizedBox(width: 10),
                                  Expanded(child: campoTipoTasa),
                                ],
                              )
                            : Column(
                                children: [
                                  campoEstado,
                                  const SizedBox(height: 12),
                                  campoTipoTasa,
                                ],
                              ),
                        const SizedBox(height: 12),
                        campoFechas,
                        const SizedBox(height: 12),
                        campoMontos,
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _filtroEstadoNombre = null;
                                  _filtroTipoTasa = null;
                                  _filtroFechaDesde = null;
                                  _filtroFechaHasta = null;
                                  _filtroMontoDesde = null;
                                  _filtroMontoHasta = null;
                                  _currentPage = 1;
                                });
                                Navigator.pop(dialogContext);
                              },
                              child: Text('Limpiar filtros', style: TextStyle(color: Colors.grey.shade800)),
                            ),
                            const Spacer(),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                              onPressed: () {
                                setState(() {
                                  _filtroEstadoNombre = tempEstado == 'TODOS' ? null : tempEstado;
                                  _filtroTipoTasa = tempTipoTasa == 'TODOS' ? null : tempTipoTasa;
                                  _filtroFechaDesde = tempFechaDesde;
                                  _filtroFechaHasta = tempFechaHasta;
                                  _filtroMontoDesde = MoneyInputFormatter.parse(montoDesdeCtrl.text);
                                  _filtroMontoHasta = MoneyInputFormatter.parse(montoHastaCtrl.text);
                                  _currentPage = 1;
                                });
                                Navigator.pop(dialogContext);
                              },
                              child: const Text('Aplicar Filtros', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    montoDesdeCtrl.dispose();
    montoHastaCtrl.dispose();
  }

  Widget _buildFilterTabs() {
    final alDia = _loans.where((l) => l['status'] == 'AL DÍA').length;
    final pendientes = _loans
        .where((l) => l['status'] == 'PENDIENTE' || l['status'] == 'EN MORA')
        .length;
    final pagados = _loans.where((l) => l['status'] == 'PAGADO').length;
    final todos = _loans.length - pagados;

    // Wrap en vez de Row: si los 4 botones no caben en una sola línea (letra
    // grande, pantalla angosta), el que no entra baja a una segunda línea
    // en vez de achicar el texto (eso hacía que unos botones se vieran con
    // letra más chica que otros).
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildFilterTab('Todos', todos, 0),
        _buildFilterTab('Al día', alDia, 1),
        _buildFilterTab('Pendientes', pendientes, 2),
        _buildFilterTab('Pagados', pagados, 3),
      ],
    );
  }

  Widget _buildFilterTab(String label, int count, int index) {
    bool isSelected = _selectedFilter == index;
    return GestureDetector(
        onTap: () => setState(() {
          _selectedFilter = index;
          _currentPage = 1;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color.fromARGB(255, 0, 0, 0)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color.fromARGB(255, 0, 0, 0)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFAAAAAA)
                      : Colors.grey.shade500,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$label $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade800,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildLoanCard(BuildContext context, Map<String, dynamic> loan) {
    final name = loan['name'] as String;
    final code = loan['code'] as String;
    final nombrePrestamo = loan['nombrePrestamo'] as String?;
    final type = loan['frecuencia'] as String;
    final totalAmount = loan['totalAmount'] as String;
    final remainingAmount = loan['remainingAmount'] as String;
    final progressText = loan['progressText'] as String;
    final progressValue = loan['progressValue'] as double;
    final status = loan['status'] as String;
    final statusColor = _statusColor(status);
    final statusBg = _statusBg(status);
    final dueDate = loan['dueDate'] as String;
    final letraVence = loan['letraVence'] as String?;
    final letraVencida = loan['letraVencida'] == true;
    final initials = loan['initials'] as String;
    final isCompany = loan['isCompany'] as bool;
    final isUrgent = loan['isUrgent'] as bool;
    final isOverdue = loan['isOverdue'] as bool;

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => LoanDetailScreen(loan: loan)),
        );
        _loadLoans();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOverdue
                ? Colors.red.shade200
                : (isUrgent ? Colors.cyan.shade200 : Colors.grey.shade200),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isCompany
                        ? const Color(0xFFAAAAAA).withValues(alpha: 0.2)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: isCompany
                      ? const Icon(
                          Icons.business,
                          color: Color.fromARGB(255, 0, 0, 0),
                          size: 20,
                        )
                      : Text(
                          initials,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontSize: 13,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color.fromARGB(255, 0, 0, 0),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nombrePrestamo != null && nombrePrestamo.isNotEmpty
                            ? '$code · $nombrePrestamo • $type'
                            : '$code • $type',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monto Total',
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          totalAmount,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Saldo Restante',
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          remainingAmount,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    progressText.startsWith('Capitalizando')
                        ? progressText
                        : 'Progreso: $progressText',
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(progressValue * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressValue,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isOverdue
                      ? Colors.red.shade700
                      : const Color.fromARGB(255, 0, 0, 0),
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Wrap: en pantallas angostas el aviso de la letra baja a
                // la línea siguiente en vez de desbordarse.
                Expanded(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOverdue
                                ? Icons.error_outline
                                : Icons.calendar_today_outlined,
                            size: 14,
                            color: isOverdue ? Colors.red.shade700 : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dueDate,
                            style: TextStyle(
                              color: isOverdue
                                  ? Colors.red.shade700
                                  : Colors.grey.shade800,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (letraVence != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.event_note_outlined,
                              size: 14,
                              color: letraVencida ? Colors.red.shade700 : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              letraVencida
                                  ? 'La letra venció el $letraVence'
                                  : 'La letra vence el $letraVence',
                              style: TextStyle(
                                color: letraVencida
                                    ? Colors.red.shade700
                                    : Colors.grey.shade800,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagination(int totalPages, int totalItems) {
    return Column(
      children: [
        Text(
          'Página $_currentPage de $totalPages ($totalItems préstamos)',
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPageButton(
              icon: Icons.chevron_left,
              onPressed: _currentPage > 1
                  ? () => setState(() => _currentPage--)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              'Página $_currentPage',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(width: 12),
            _buildPageButton(
              icon: Icons.chevron_right,
              onPressed: _currentPage < totalPages
                  ? () => setState(() => _currentPage++)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPageButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
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
        icon: Icon(
          icon,
          size: 18,
          color: isEnabled ? Colors.grey.shade800 : Colors.grey.shade500,
        ),
        onPressed: onPressed,
      ),
    );
  }
}

// ==========================================
// PANTALLA DE DETALLE DEL PRÉSTAMO
// ==========================================
class LoanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> loan;

  const LoanDetailScreen({super.key, required this.loan});

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  final PrestamoService _prestamoService = PrestamoService();

  /// Copia local editable de los datos del préstamo mostrados en la
  /// tarjeta superior: `widget.loan` es la instantánea con la que se abrió
  /// esta pantalla (viene del listado), y tras una Inyección de Capital se
  /// actualiza aquí el "Saldo Actual" sin necesidad de recargar la lista.
  late Map<String, dynamic> _loan;

  List<Map<String, dynamic>> _cuotas = [];
  bool _isLoadingCuotas = true;
  String? _loadError;

  List<Map<String, dynamic>> _movimientosCapital = [];
  bool _isLoadingMovimientos = true;

  @override
  void initState() {
    super.initState();
    _loan = Map<String, dynamic>.from(widget.loan);
    _loadCuotas();
    _loadMovimientosCapital();
  }

  Future<void> _loadCuotas() async {
    setState(() {
      _isLoadingCuotas = true;
      _loadError = null;
    });
    try {
      final cuotas = await _prestamoService.fetchCuotas(
        widget.loan['prestamo_id'] as int,
      );
      if (!mounted) return;
      setState(() {
        _cuotas = cuotas;
        _isLoadingCuotas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is NoConnectionException ? e.message : 'No se pudo cargar la tabla de cuotas.';
        _isLoadingCuotas = false;
      });
    }
  }

  Future<void> _loadMovimientosCapital() async {
    try {
      final movimientos = await _prestamoService.fetchMovimientosCapital(
        widget.loan['prestamo_id'] as int,
      );
      if (!mounted) return;
      setState(() {
        _movimientosCapital = movimientos;
        _isLoadingMovimientos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMovimientos = false);
    }
  }

  String _formatMoneyPreview(double value) {
    final isNegative = value < 0;
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
      buffer.write(intPart[i]);
    }
    return '${isNegative ? '-' : ''}\$${buffer.toString()},${parts[1]}';
  }

  /// Genera el PDF del plan de pagos completo de este préstamo: encabezado
  /// con los datos del préstamo, la tabla de cuotas y los movimientos de
  /// capital. Reutiliza `_cuotas`/`_movimientosCapital` ya cargados en la
  /// pantalla; solo pide al servidor los datos que le faltan (cliente,
  /// cambio de tasa, operación por fases).
  Future<Uint8List> _generarPdfPlanPagos() async {
    final detalle = await _prestamoService.fetchDetalle(widget.loan['prestamo_id'] as int);
    return PlanPagosPdfService.generar(
      detalle: detalle,
      cuotas: _cuotas,
      movimientos: _movimientosCapital,
    );
  }

  void _showPlanPagosPdfModal() {
    showPdfActionsDialog(
      context,
      titulo: 'Plan de Pagos — Préstamo #${_loan['code']}',
      nombreArchivo: 'plan_pagos_${_loan['code']}.pdf',
      generarPdf: _generarPdfPlanPagos,
      infoContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cliente: ${_loan['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            'Incluye la tabla de cuotas completa, con los movimientos de capital resaltados '
            'justo arriba de la cuota donde se aplican.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  /// Abre el formulario de "Registrar Préstamo" pero prellenado con los
  /// datos actuales de este préstamo, en modo edición. Si se guarda algo,
  /// refresca tanto la tabla de cuotas como la tarjeta de resumen de arriba
  /// (recapital/tasa/plazo pueden haber cambiado).
  Future<void> _openEditarPrestamo() async {
    final prestamoId = widget.loan['prestamo_id'] as int;
    try {
      final datos = await _prestamoService.fetchParaEditar(prestamoId);
      if (!mounted) return;
      final guardado = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => NewLoanFormScreen(existingLoan: datos, prestamoId: prestamoId),
        ),
      );
      if (guardado == true) {
        _loadCuotas();
        _loadMovimientosCapital();
        _refreshResumenPrestamo();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is NoConnectionException ? e.message : 'No se pudo cargar el préstamo para editar.',
          ),
        ),
      );
    }
  }

  /// Vuelve a traer este préstamo desde el listado general para refrescar
  /// la tarjeta de resumen (código, tipo, capital, tasa, fecha, etc.) con
  /// el mismo formato de texto que ya usa esa tarjeta, tras una edición.
  Future<void> _refreshResumenPrestamo() async {
    try {
      final prestamoId = widget.loan['prestamo_id'] as int;
      final todos = await _prestamoService.fetchAll();
      final actualizado = todos.firstWhere(
        (p) => p['prestamo_id'] == prestamoId,
        orElse: () => _loan,
      );
      if (!mounted) return;
      setState(() => _loan = Map<String, dynamic>.from(actualizado));
    } catch (_) {
      // Si falla, la tarjeta se queda con los datos anteriores; no es
      // crítico porque la tabla de cuotas (la que sí se recarga) ya
      // refleja los términos nuevos.
    }
  }

  /// Abre el diálogo de "Inyectar Capital": el prestamista elige a partir
  /// de cuál cuota (entre las que todavía no se han cobrado/cerrado) se
  /// aplica el aumento de capital, y desde ahí se recalcula todo el resto
  /// del cronograma con [PrestamoService.registrarInyeccionCapital].
  Future<void> _showInyectarCapitalModal() async {
    final prestamoId = widget.loan['prestamo_id'] as int;

    List<Map<String, dynamic>> elegibles;
    try {
      elegibles = await _prestamoService.fetchCuotasElegiblesParaInyeccion(
        prestamoId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is NoConnectionException ? e.message : 'No se pudieron cargar las cuotas disponibles. Intenta de nuevo.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    if (elegibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este préstamo no tiene ninguna cuota disponible para inyectar capital en este momento.',
          ),
        ),
      );
      return;
    }

    int selectedPeriodo = elegibles.first['numeroPeriodo'] as int;
    final montoController = TextEditingController();
    final motivoController = TextEditingController();
    final scrollController = ScrollController();
    bool isSaving = false;
    String? errorMessage;
    Timer? errorTimer;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          void setError(String message) {
            errorTimer?.cancel();
            setModalState(() => errorMessage = message);
            errorTimer = Timer(const Duration(seconds: 4), () {
              if (dialogContext.mounted) {
                setModalState(() => errorMessage = null);
              }
            });
            // El aviso se muestra arriba del todo del formulario: si el
            // usuario estaba desplazado hacia abajo, hay que subir la vista
            // para que lo vea sin tener que hacer scroll manual.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!scrollController.hasClients) return;
              scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            });
          }

          final anclaSeleccionada = elegibles.firstWhere(
            (c) => c['numeroPeriodo'] == selectedPeriodo,
          );

          return AlertDialog(
            title: const Text(
              'Inyectar Capital',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: errorMessage == null
                          ? const SizedBox(width: double.infinity)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TweenAnimationBuilder<double>(
                                  key: ValueKey(errorMessage),
                                  duration: const Duration(milliseconds: 200),
                                  tween: Tween(begin: 0, end: 1),
                                  builder: (_, opacity, child) =>
                                      Opacity(opacity: opacity, child: child),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          size: 18,
                                          color: Colors.red.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            errorMessage!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
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
                      'El préstamo puede recibir capital adicional en cualquier momento. Elige a partir de qué '
                      'cuota se aplica: desde ahí se recalculan intereses y saldos según la configuración del préstamo.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    CustomDropdown<int>(
                      initialValue: selectedPeriodo,
                      decoration: InputDecoration(
                        labelText: 'A partir de la cuota',
                        prefixIcon: const Icon(
                          Icons.event_repeat,
                          color: Colors.black,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: elegibles
                          .map(
                            (c) => CustomDropdownItem(
                              value: c['numeroPeriodo'] as int,
                              label:
                                  'Cuota ${c['numeroPeriodo']} · vence ${c['fechaVencimiento']}',
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setModalState(() => selectedPeriodo = val!),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Saldo vigente en ese punto: ${_formatMoneyPreview(anclaSeleccionada['saldoActual'] as double)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: montoController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [MoneyInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Monto a Inyectar (\$)',
                        prefixIcon: const Icon(
                          Icons.attach_money,
                          color: Colors.black,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: motivoController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Motivo (opcional)',
                        prefixIcon: const Icon(
                          Icons.notes,
                          color: Colors.black,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey.shade800),
                ),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final monto = MoneyInputFormatter.parse(
                          montoController.text.trim(),
                        );
                        if (monto == null || monto <= 0) {
                          setError('Ingresa un monto válido mayor a 0.');
                          return;
                        }
                        errorTimer?.cancel();
                        setModalState(() {
                          isSaving = true;
                          errorMessage = null;
                        });
                        try {
                          final nuevoBalance = await _prestamoService
                              .registrarInyeccionCapital(
                                prestamoId: prestamoId,
                                periodoDesde: selectedPeriodo,
                                monto: monto,
                                descripcionConcepto:
                                    motivoController.text.trim().isEmpty
                                    ? null
                                    : motivoController.text.trim(),
                                fechaTransaccion: DateTime.now(),
                              );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (!mounted) return;
                          setState(
                            () => _loan['remainingAmount'] =
                                _formatMoneyPreview(nuevoBalance),
                          );
                          await _loadCuotas();
                          await _loadMovimientosCapital();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Capital inyectado correctamente. El cronograma se recalculó.',
                              ),
                            ),
                          );
                        } on ArgumentError catch (e) {
                          setModalState(() => isSaving = false);
                          setError('${e.message}');
                        } catch (e) {
                          setModalState(() => isSaving = false);
                          setError(
                            e is NoConnectionException ? e.message : 'No se pudo registrar la inyección de capital. Intenta de nuevo.',
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Inyectar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );

    errorTimer?.cancel();
    montoController.dispose();
    motivoController.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'EN MORA':
        return Colors.red.shade700;
      case 'PENDIENTE':
        return Colors.cyan.shade800;
      case 'PAGADO':
        return Colors.blueGrey.shade700;
      default:
        return Colors.teal;
    }
  }

  /// Detecta si la tasa aplicada cambia entre dos cuotas consecutivas,
  /// comparando directamente el cronograma ya calculado (fuente de verdad),
  /// en vez de volver a consultar prestamos.mes_cambio_tasa por separado.
  Map<String, dynamic>? get _cambioDeTasa {
    for (int i = 1; i < _cuotas.length; i++) {
      if (_cuotas[i]['tasa'] != _cuotas[i - 1]['tasa']) {
        return {
          'periodo': _cuotas[i]['periodo'],
          'tasaAnterior': _cuotas[i - 1]['tasa'],
          'tasaNueva': _cuotas[i]['tasa'],
        };
      }
    }
    return null;
  }

  /// Detecta si la operación es por fases (deja de capitalizar en algún
  /// punto), comparando el campo "capitalizado" entre cuotas consecutivas.
  Map<String, dynamic>? get _cambioDeCapitalizacion {
    for (int i = 1; i < _cuotas.length; i++) {
      if (_cuotas[i]['capitalizado'] != _cuotas[i - 1]['capitalizado'] &&
          _cuotas[i]['capitalizado'] == 'No') {
        return {'periodo': _cuotas[i]['periodo']};
      }
    }
    return null;
  }

  Color _estadoCuotaColor(String estado) {
    switch (estado) {
      case 'Pagado':
        return Colors.teal;
      case 'Parcial':
        return Colors.amber.shade800;
      case 'Vencido':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;
    final name = loan['name'] as String;
    final code = loan['code'] as String;
    final nombrePrestamo = loan['nombrePrestamo'] as String?;
    final loanType = loan['loanType'] as String;
    final type = loan['frecuencia'] as String;
    final totalAmount = loan['totalAmount'] as String;
    final remainingAmount = loan['remainingAmount'] as String;
    final status = loan['status'] as String;
    final statusColor = _statusColor(status);
    final interestRate = loan['interestRate'] as String;
    final startDate = loan['startDate'] as String;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Detalle de Préstamo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. INFORMACIÓN DEL PRÉSTAMO (Registrada al crear)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 10),

                    // Grid de datos
                    Wrap(
                      spacing: 20,
                      runSpacing: 12,
                      children: [
                        _infoItem('Código', code, Icons.qr_code),
                        if (nombrePrestamo != null && nombrePrestamo.isNotEmpty)
                          _infoItem('Nombre del Préstamo', nombrePrestamo, Icons.label_outline),
                        _infoItem(
                          'Tipo de Préstamo',
                          loanType,
                          Icons.category_outlined,
                        ),
                        _infoItem('Frecuencia', type, Icons.schedule),
                        _infoItem(
                          'Capital Inicial',
                          totalAmount,
                          Icons.attach_money,
                        ),
                        _infoItem(
                          'Saldo Actual',
                          remainingAmount,
                          Icons.account_balance_wallet_outlined,
                        ),
                        _infoItem(
                          'Tasa de Interés',
                          '$interestRate inicial',
                          Icons.percent,
                        ),
                        _infoItem(
                          'Fecha de Inicio',
                          startDate,
                          Icons.calendar_today,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 10),
                    const Text(
                      'Cambio de Tasa de Interés',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingCuotas)
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey.shade500,
                        ),
                      )
                    else if (_cambioDeTasa == null)
                      Text(
                        'Sin cambios de tasa programados (tasa fija durante todo el préstamo).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            Icons.sync_alt,
                            size: 14,
                            color: Colors.orange.shade800,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'La tasa cambia de ${_cambioDeTasa!['tasaAnterior']} a ${_cambioDeTasa!['tasaNueva']} '
                              'a partir de la cuota ${_cambioDeTasa!['periodo']}.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 14),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 10),
                    const Text(
                      'Operación por Fases',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingCuotas)
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey.shade500,
                        ),
                      )
                    else if (_cambioDeCapitalizacion == null)
                      Text(
                        'No es una operación por fases (mecánica de cálculo constante durante todo el préstamo).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            Icons.timeline,
                            size: 14,
                            color: Colors.deepPurple.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Deja de capitalizar y pasa a pago líquido (renta fija) a partir de la cuota '
                              '${_cambioDeCapitalizacion!['periodo']}.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 14),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 10),
                    const Text(
                      'Movimientos de Capital',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingMovimientos)
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey.shade500,
                        ),
                      )
                    else if (_movimientosCapital.isEmpty)
                      Text(
                        'Sin inyecciones ni retiros de capital registrados.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final m in _movimientosCapital)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    m['esInyeccion'] as bool
                                        ? Icons.trending_up
                                        : Icons.trending_down,
                                    size: 14,
                                    color: m['esInyeccion'] as bool
                                        ? Colors.teal.shade700
                                        : Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${m['tipo']} de ${m['monto']}'
                                      '${m['periodo'] != null ? ' a partir de la cuota ${m['periodo']}.' : ' (${m['fecha']})'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (status != 'PAGADO')
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width >= 800 ? 300 : null,
                        child: OutlinedButton.icon(
                          onPressed: _isLoadingCuotas
                              ? null
                              : _showInyectarCapitalModal,
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text(
                            'Inyectar Capital',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: Colors.black),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width >= 800 ? 300 : null,
                      child: OutlinedButton.icon(
                        onPressed: _isLoadingCuotas ? null : _showPlanPagosPdfModal,
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text(
                          'Plan de Pagos (PDF)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (status != 'PAGADO')
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width >= 800 ? 300 : null,
                        child: OutlinedButton.icon(
                          onPressed: _isLoadingCuotas ? null : _openEditarPrestamo,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text(
                            'Editar Préstamo',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: Colors.black),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. TABLA DE CUOTAS (PLAN DE PAGOS) - CENTRADA
              const Text(
                'Tabla de Cuotas (Plan de Pagos)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Desglosa los periodos de cobro, intereses generados y capital amortizado.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
              ),
              if (_cuotas.any((c) => c['capitalizado'] == 'Sí')) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Las cuotas con Capitalizado = "Sí" salen como "Pagado" aunque el cliente no las pagó: '
                          'el interés se reinvierte automáticamente en el saldo en vez de cobrarse.',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              if (_isLoadingCuotas)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  ),
                )
              else if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 40,
                        color: Colors.red.shade400,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _loadError!,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _loadCuotas,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                        ),
                        child: const Text(
                          'Reintentar',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_cuotas.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'Este préstamo no tiene cuotas generadas.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xFFF8FAFC),
                        ),
                        columns: const [
                          DataColumn(
                            label: Text(
                              'N° Periodo',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Vencimiento',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Saldo Inicio',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Tasa (%)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Interés',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Amortización',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Cap. Capitalizado',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Saldo Fin',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Estado',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        rows: _cuotas.map(_buildQuotaRow).toList(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoItem(String label, String value, IconData icon) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  DataRow _buildQuotaRow(Map<String, dynamic> cuota) {
    final estado = cuota['estado'] as String;
    final estadoColor = _estadoCuotaColor(estado);

    return DataRow(
      cells: [
        DataCell(
          Text(
            'Cuota ${cuota['periodo']}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        DataCell(
          Text(
            cuota['fecha'] as String,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
        ),
        DataCell(
          Text(
            cuota['saldoInicio'] as String,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        DataCell(
          Text(cuota['tasa'] as String, style: const TextStyle(fontSize: 12)),
        ),
        DataCell(
          Text(
            cuota['interes'] as String,
            style: const TextStyle(fontSize: 12, color: Colors.redAccent),
          ),
        ),
        DataCell(
          Text(
            cuota['amortizacion'] as String,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        DataCell(
          Text(
            cuota['capitalizado'] as String,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
          ),
        ),
        DataCell(
          Text(
            cuota['saldoFin'] as String,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: estadoColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              estado,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: estadoColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NewLoanFormScreen extends StatefulWidget {
  /// Cuando se pasan ambos, la pantalla arranca en modo edición: prellena
  /// el formulario con [existingLoan] (tal cual lo devuelve
  /// `PrestamoService.fetchParaEditar`) y al guardar llama a
  /// `PrestamoService.editar` sobre [prestamoId] en vez de crear uno nuevo.
  final Map<String, dynamic>? existingLoan;
  final int? prestamoId;

  const NewLoanFormScreen({super.key, this.existingLoan, this.prestamoId});

  @override
  State<NewLoanFormScreen> createState() => _NewLoanFormScreenState();
}

class _MovimientoPlanEntry {
  String tipo = 'Inyeccion';
  final TextEditingController montoController = TextEditingController();
  final TextEditingController periodoController = TextEditingController();

  void dispose() {
    montoController.dispose();
    periodoController.dispose();
  }
}

class _NewLoanFormScreenState extends State<NewLoanFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final ClienteService _clienteService = ClienteService();
  final PrestamoService _prestamoService = PrestamoService();

  final TextEditingController _codeController = TextEditingController(
    text: 'Generando código...',
  );
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _interestController = TextEditingController();
  final TextEditingController _newInterestController = TextEditingController();
  final TextEditingController _numeroCuotasController = TextEditingController();

  String? _codigoGenerado;
  String _selectedFrequency = 'Mensual';
  DateTime _startDate = DateTime.now();

  // Vencimiento de la letra de cambio del préstamo (opcional).
  DateTime? _vencimientoLetra;

  final TextEditingController _mesCambioController = TextEditingController();
  String _selectedTipoTasa = 'Fija';
  String _selectedTipoCalculo = 'Simple';

  bool _esOperacionPorFases = false;
  final TextEditingController _cuotaTransicionCapController =
      TextEditingController();

  List<Map<String, dynamic>> _clientes = [];
  int? _selectedClienteId;
  bool _isLoadingClientes = true;
  String? _clientesLoadError;

  List<Map<String, dynamic>> _estados = [];
  int? _selectedEstadoId;
  bool _isLoadingEstados = true;
  String? _estadosLoadError;

  final List<_MovimientoPlanEntry> _movimientos = [];

  bool _isSaving = false;

  void _addMovimiento() {
    setState(() => _movimientos.add(_MovimientoPlanEntry()));
  }

  void _removeMovimiento(int index) {
    setState(() {
      _movimientos[index].dispose();
      _movimientos.removeAt(index);
    });
  }

  bool get _isEditMode => widget.existingLoan != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _prefillDesdeExistente(widget.existingLoan!);
    } else {
      _loadCodigoReferencia();
    }
    _loadClientes();
    _loadEstados();
  }

  void _prefillDesdeExistente(Map<String, dynamic> e) {
    _codigoGenerado = e['codigoReferencia'] as String;
    _codeController.text = _codigoGenerado!;
    _nombreController.text = (e['nombrePrestamo'] as String?) ?? '';
    _selectedClienteId = e['clienteId'] as int;
    _selectedEstadoId = e['estadoId'] as int?;
    _selectedTipoTasa = e['tipoTasa'] as String;
    _selectedTipoCalculo = e['tipoCalculo'] as String;
    _amountController.text = MoneyInputFormatter.format(e['capitalInicial'] as double);
    _interestController.text = '${e['tasaInteresMensual']}';
    _numeroCuotasController.text = '${e['numeroCuotas']}';
    _selectedFrequency = e['frecuenciaPago'] as String;
    _startDate = DateTime.parse(e['fechaInicio'] as String);
    _vencimientoLetra = DateTime.tryParse((e['fechaVencimientoLetra'] as String?) ?? '');
    if (e['mesCambioTasa'] != null) {
      _mesCambioController.text = '${e['mesCambioTasa']}';
    }
    if (e['nuevaTasaInteres'] != null) {
      _newInterestController.text = '${e['nuevaTasaInteres']}';
    }
    if (e['mesCambioCapitalizacion'] != null) {
      _esOperacionPorFases = true;
      _cuotaTransicionCapController.text = '${e['mesCambioCapitalizacion']}';
    }
  }

  Future<void> _loadCodigoReferencia() async {
    try {
      final codigo = await _prestamoService.generateNextCodigo();
      if (!mounted) return;
      setState(() {
        _codigoGenerado = codigo;
        _codeController.text = codigo;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _codeController.text = 'Error al generar código');
    }
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
        // En modo edición se conserva el cliente actual del préstamo aunque
        // ya esté inactivo, para que el dropdown no se quede sin una opción
        // que coincida con el valor ya seleccionado.
        _clientes = clientes
            .where((c) => c['activo'] == true || (_isEditMode && c['cliente_id'] == _selectedClienteId))
            .toList();
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

  Future<void> _loadEstados() async {
    setState(() {
      _isLoadingEstados = true;
      _estadosLoadError = null;
    });
    try {
      final estados = await _prestamoService.fetchEstados();
      if (!mounted) return;
      setState(() {
        _estados = estados;
        _isLoadingEstados = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingEstados = false;
        _estadosLoadError = e is NoConnectionException ? e.message : 'No se pudieron cargar los estados.';
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nombreController.dispose();
    _amountController.dispose();
    _interestController.dispose();
    _newInterestController.dispose();
    _numeroCuotasController.dispose();
    _mesCambioController.dispose();
    _cuotaTransicionCapController.dispose();
    for (final m in _movimientos) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  /// Selector de fecha para la letra de cambio. Devuelve null si se cancela.
  Future<DateTime?> _pickFechaLetra(BuildContext context, DateTime? actual) {
    return showDatePicker(
      context: context,
      initialDate: actual ?? _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
  }

  static String _fechaTexto(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Campo de fecha de la letra: muestra la fecha elegida o "Sin fecha", y
  /// una X para borrarla (la letra es opcional).
  Widget _buildFechaLetraField({
    required String label,
    required DateTime? valor,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await _pickFechaLetra(context, valor);
        if (picked != null) setState(() => onChanged(picked));
      },
      child: InputDecorator(
        decoration: _inputDecoration(label, Icons.event_note_outlined).copyWith(
          suffixIcon: valor == null
              ? null
              : IconButton(
                  tooltip: 'Quitar fecha',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => onChanged(null)),
                ),
        ),
        child: Text(
          valor == null ? 'Sin fecha' : _fechaTexto(valor),
          style: TextStyle(
            fontSize: 13,
            color: valor == null ? Colors.grey.shade600 : Colors.black87,
          ),
        ),
      ),
    );
  }

  Future<void> _saveLoan() async {
    if (!_formKey.currentState!.validate()) return;


    if (_selectedClienteId == null || _selectedEstadoId == null || _codigoGenerado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos requeridos')),
      );
      return;
    }

    final bool esVariable = _selectedTipoTasa == 'Variable';

    setState(() => _isSaving = true);

    try {
      if (_isEditMode) {
        await _prestamoService.editar(
          prestamoId: widget.prestamoId!,
          nombrePrestamo: _nombreController.text.trim().isEmpty ? null : _nombreController.text.trim(),
          clienteId: _selectedClienteId!,
          estadoId: _selectedEstadoId!,
          tipoTasa: _selectedTipoTasa,
          tipoCalculo: _selectedTipoCalculo,
          capitalInicial: MoneyInputFormatter.parse(_amountController.text)!,
          tasaInteresMensual: double.parse(_interestController.text),
          mesCambioTasa: esVariable ? int.parse(_mesCambioController.text) : null,
          nuevaTasaInteres: esVariable
              ? double.parse(_newInterestController.text)
              : null,
          mesCambioCapitalizacion: _esOperacionPorFases
              ? int.parse(_cuotaTransicionCapController.text)
              : null,
          frecuenciaPago: _selectedFrequency,
          fechaInicio: _startDate,
          numeroCuotas: int.parse(_numeroCuotasController.text),
          fechaVencimientoLetra: _vencimientoLetra,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Préstamo $_codigoGenerado actualizado exitosamente')),
        );
        Navigator.pop(context, true);
        return;
      }

      final movimientosPlanificados = _movimientos
          .map(
            (m) => MovimientoCapitalPlanificado(
              periodoDesde: int.parse(m.periodoController.text),
              esInyeccion: m.tipo == 'Inyeccion',
              monto: MoneyInputFormatter.parse(m.montoController.text)!,
            ),
          )
          .toList();

      await _prestamoService.create(
        codigoReferencia: _codigoGenerado!,
        nombrePrestamo: _nombreController.text.trim().isEmpty ? null : _nombreController.text.trim(),
        clienteId: _selectedClienteId!,
        estadoId: _selectedEstadoId!,
        tipoTasa: _selectedTipoTasa,
        tipoCalculo: _selectedTipoCalculo,
        capitalInicial: MoneyInputFormatter.parse(_amountController.text)!,
        tasaInteresMensual: double.parse(_interestController.text),
        mesCambioTasa: esVariable ? int.parse(_mesCambioController.text) : null,
        nuevaTasaInteres: esVariable
            ? double.parse(_newInterestController.text)
            : null,
        mesCambioCapitalizacion: _esOperacionPorFases
            ? int.parse(_cuotaTransicionCapController.text)
            : null,
        frecuenciaPago: _selectedFrequency,
        fechaInicio: _startDate,
        numeroCuotas: int.parse(_numeroCuotasController.text),
        fechaVencimientoLetra: _vencimientoLetra,
        movimientosPlanificados: movimientosPlanificados,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Préstamo $_codigoGenerado registrado exitosamente'),
        ),
      );
      Navigator.pop(context);
    } on PrestamoCodigoDuplicadoException {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El código de referencia ya existe, intenta de nuevo')),
      );
    } on ArgumentError catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Revisa los datos del préstamo: ${e.message}')),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is NoConnectionException ? e.message : 'No se pudo registrar el préstamo. Intenta de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          _isEditMode ? 'Editar Préstamo' : 'Registrar Nuevo Préstamo',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Información del Contrato',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  if (_isEditMode && widget.existingLoan!['tieneActividad'] == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Este préstamo ya tiene pagos o movimientos registrados. Al guardar, el plan de '
                              'cuotas se recalcula con los términos nuevos: las cuotas ya cobradas siguen '
                              'marcadas como pagadas, pero su desglose de interés/capital puede cambiar. '
                              'No se altera ningún recibo ya emitido.',
                              style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _codeController,
                    readOnly: true,
                    decoration: _inputDecoration(
                      'Código de Referencia (AAAAMMSSSSSSSS)',
                      Icons.qr_code,
                    ),
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _nombreController,
                    decoration: _inputDecoration(
                      'Nombre del Préstamo (opcional)',
                      Icons.label_outline,
                    ),
                  ),
                  const SizedBox(height: 14),

                  CustomDropdown<int>(
                    key: ValueKey(
                      'cliente_${_clientes.length}_$_isLoadingClientes',
                    ),
                    initialValue: _selectedClienteId,
                    enabled: !_isLoadingClientes && _clientesLoadError == null,
                    decoration: _inputDecoration(
                      _isLoadingClientes ? 'Cargando clientes...' : 'Cliente',
                      Icons.person_outline,
                    ),
                    items: _clientes
                        .map(
                          (c) => CustomDropdownItem<int>(
                            value: c['cliente_id'] as int,
                            label:
                                '${c['nombre_cliente']} (${c['documento_identidad']})',
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedClienteId = value;
                      });
                    },
                    validator: (value) =>
                        value == null ? 'Selecciona un cliente' : null,
                  ),
                  if (_clientesLoadError != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _clientesLoadError!,
                            style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                          ),
                        ),
                        TextButton(
                          onPressed: _loadClientes,
                          child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),

                  CustomDropdown<int>(
                    key: ValueKey(
                      'estado_${_estados.length}_$_isLoadingEstados',
                    ),
                    initialValue: _selectedEstadoId,
                    enabled: !_isLoadingEstados && _estadosLoadError == null,
                    decoration: _inputDecoration(
                      _isLoadingEstados ? 'Cargando estados...' : 'Estado',
                      Icons.location_on_outlined,
                    ),
                    items: _estados
                        .map(
                          (e) => CustomDropdownItem<int>(
                            value: e['estado_id'] as int,
                            label: e['nombre'] as String,
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedEstadoId = value;
                      });
                    },
                    validator: (value) =>
                        value == null ? 'Selecciona un estado' : null,
                  ),
                  if (_estadosLoadError != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _estadosLoadError!,
                            style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                          ),
                        ),
                        TextButton(
                          onPressed: _loadEstados,
                          child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),

                  CustomDropdown<String>(
                    initialValue: _selectedTipoTasa,
                    decoration: _inputDecoration(
                      'Comportamiento de la Tasa',
                      Icons.show_chart,
                    ),
                    items: const [
                      CustomDropdownItem(
                        value: 'Fija',
                        label: 'Fija (no cambia nunca)',
                      ),
                      CustomDropdownItem(
                        value: 'Variable',
                        label: 'Variable (cambia en un mes definido)',
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedTipoTasa = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 14),

                  CustomDropdown<String>(
                    key: ValueKey('tipoCalculo_$_esOperacionPorFases'),
                    initialValue: _selectedTipoCalculo,
                    enabled: !_esOperacionPorFases,
                    decoration: _inputDecoration(
                      _esOperacionPorFases
                          ? 'Mecánica de Cálculo (fija en Compuesto por fases)'
                          : 'Mecánica de Cálculo',
                      Icons.functions,
                    ),
                    items: const [
                      CustomDropdownItem(
                        value: 'Simple',
                        label: 'Simple (el interés se paga cada periodo)',
                      ),
                      CustomDropdownItem(
                        value: 'Compuesto',
                        label: 'Compuesto (el interés se capitaliza al saldo)',
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedTipoCalculo = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [MoneyInputFormatter()],
                    decoration: _inputDecoration(
                      'Capital Inicial (\$)',
                      Icons.attach_money,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingrese el monto inicial';
                      }
                      if (MoneyInputFormatter.parse(value) == null) {
                        return 'Ingrese un número válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _interestController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: _inputDecoration(
                      'Tasa de Interés Inicial (%) - Ej: 5.0',
                      Icons.percent,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingrese la tasa de interés';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _numeroCuotasController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _inputDecoration(
                      'Número de Cuotas (Plazo)',
                      Icons.event_repeat,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingrese el número de cuotas';
                      }
                      final n = int.tryParse(value);
                      if (n == null || n <= 0) {
                        return 'Ingrese un número mayor a 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  CustomDropdown<String>(
                    initialValue: _selectedFrequency,
                    decoration: _inputDecoration(
                      'Frecuencia de Pago',
                      Icons.schedule,
                    ),
                    items:
                        ['Diario', 'Semanal', 'Quincenal', 'Mensual', 'Anual']
                            .map(
                              (freq) =>
                                  CustomDropdownItem(value: freq, label: freq),
                            )
                            .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedFrequency = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 14),

                  InkWell(
                    onTap: () => _selectStartDate(context),
                    child: InputDecorator(
                      decoration: _inputDecoration(
                        'Fecha de Inicio',
                        Icons.calendar_today_outlined,
                      ),
                      child: Text(
                        '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  _buildFechaLetraField(
                    label: 'Vencimiento de la Letra (opcional)',
                    valor: _vencimientoLetra,
                    onChanged: (v) => _vencimientoLetra = v,
                  ),
                  const SizedBox(height: 16),

                  if (_selectedTipoTasa == 'Variable') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Configuración de Cambio de Tasa',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Obligatorio porque elegiste tasa "Variable".',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _mesCambioController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: _inputDecoration(
                              'A partir de qué cuota cambia',
                              Icons.event_repeat,
                            ),
                            validator: (value) {
                              if (_selectedTipoTasa != 'Variable') return null;
                              if (value == null || value.isEmpty) {
                                return 'Ingrese la cuota donde cambia la tasa';
                              }
                              final mes = int.tryParse(value);
                              if (mes == null || mes < 1) {
                                return 'Ingrese un número válido';
                              }
                              final totalCuotas = int.tryParse(
                                _numeroCuotasController.text,
                              );
                              if (totalCuotas != null && mes > totalCuotas) {
                                return 'Debe ser ≤ al número de cuotas ($totalCuotas)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _newInterestController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: _inputDecoration(
                              'Nueva Tasa de Interés (%)',
                              Icons.trending_up,
                            ),
                            validator: (value) {
                              if (_selectedTipoTasa != 'Variable') return null;
                              if (value == null || value.isEmpty) {
                                return 'Ingrese la nueva tasa';
                              }
                              if (double.tryParse(value) == null) {
                                return 'Ingrese un número válido';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        '¿Es una operación estructurada por fases?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        'Ej: acumulación/reinversión que luego pasa a renta fija con pagos líquidos.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      value: _esOperacionPorFases,
                      activeThumbColor: Colors.black,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (bool value) {
                        setState(() {
                          _esOperacionPorFases = value;
                          if (value) _selectedTipoCalculo = 'Compuesto';
                        });
                      },
                    ),
                  ),

                  if (_esOperacionPorFases) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Configuración de Fases del Contrato',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fase 1 (Acumulación): el interés se capitaliza y no hay pago líquido. '
                            'Fase 2 (Renta Fija): el saldo se congela en lo acumulado y el interés pasa a ser el pago exigible.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _cuotaTransicionCapController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: _inputDecoration(
                              'A partir de qué cuota deja de capitalizar',
                              Icons.timeline,
                            ),
                            validator: (value) {
                              if (!_esOperacionPorFases) return null;
                              if (value == null || value.isEmpty) {
                                return 'Ingrese la cuota de transición';
                              }
                              final cuota = int.tryParse(value);
                              if (cuota == null || cuota < 1) {
                                return 'Ingrese un número válido';
                              }
                              final totalCuotas = int.tryParse(
                                _numeroCuotasController.text,
                              );
                              if (totalCuotas != null && cuota > totalCuotas) {
                                return 'Debe ser ≤ al número de cuotas ($totalCuotas)';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (!_isEditMode) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          'Movimientos de Capital Planificados (opcional)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addMovimiento,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text(
                          'Agregar',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  if (_movimientos.isEmpty)
                    Text(
                      'Si ya sabes que vas a inyectar capital en una cuota futura, agrégalo aquí para que se calcule desde ahora.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  for (int i = 0; i < _movimientos.length; i++) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InputDecorator(
                                  decoration: _inputDecoration(
                                    'Tipo',
                                    Icons.trending_up,
                                  ),
                                  child: const Text(
                                    'Inyección de Capital',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _removeMovimiento(i),
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _movimientos[i].montoController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [MoneyInputFormatter()],
                            decoration: _inputDecoration(
                              'Monto (\$)',
                              Icons.attach_money,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Ingrese el monto';
                              }
                              final monto = MoneyInputFormatter.parse(value);
                              if (monto == null || monto <= 0) {
                                return 'Ingrese un monto mayor a 0';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _movimientos[i].periodoController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: _inputDecoration(
                              'A partir de qué cuota',
                              Icons.event_repeat,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Ingrese la cuota';
                              }
                              final periodo = int.tryParse(value);
                              if (periodo == null || periodo < 1) {
                                return 'Ingrese un número válido';
                              }
                              final totalCuotas = int.tryParse(
                                _numeroCuotasController.text,
                              );
                              if (totalCuotas != null &&
                                  periodo > totalCuotas) {
                                return 'Debe ser ≤ al número de cuotas ($totalCuotas)';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  ],

                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveLoan,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEditMode ? 'Guardar Cambios' : 'Guardar Préstamo',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade800, fontSize: 12),
      prefixIcon: Icon(icon, color: Colors.black, size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
