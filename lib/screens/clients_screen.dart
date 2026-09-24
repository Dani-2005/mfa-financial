import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/cliente_service.dart';
import '../widgets/custom_dropdown.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ClienteService _clienteService = ClienteService();
  String _searchQuery = '';
  int _currentPage = 1;
  final int _itemsPerPage = 5;

  List<Map<String, dynamic>> _allClients = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final clients = await _clienteService.fetchAll();
      if (!mounted) return;
      setState(() {
        _allClients = clients;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is NoConnectionException ? e.message : 'No se pudo cargar la lista de clientes.';
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
              Text('DIRECTORIO Y PERFILES', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2), overflow: TextOverflow.ellipsis),
              Text('Gestión de Clientes', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
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
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset('assets/logooficial.jpeg', fit: BoxFit.contain, errorBuilder: (c, o, s) => const Icon(Icons.business, color: Colors.white)),
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
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset('assets/logooficial.jpeg', fit: BoxFit.contain, errorBuilder: (c, o, s) => const Icon(Icons.business, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            const Text('MAF Financial', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1)),
          ],
        ),
        const SizedBox(height: 20),
        const Text('DIRECTORIO Y PERFILES', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const Text('Gestión de Clientes', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMobileContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: _buildClientsCoreContent(),
    );
  }

  Widget _buildDesktopContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: _buildClientsCoreContent(),
    );
  }

  Widget _buildClientsCoreContent() {
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
              onPressed: _loadClients,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      final filteredClients = _allClients.where((client) {
        final query = _searchQuery.toLowerCase();
        final name = client['nombre_cliente'].toString().toLowerCase();
        final doc = client['documento_identidad'].toString().toLowerCase();
        return name.contains(query) || doc.contains(query);
      }).toList();

      int totalPages = (filteredClients.length / _itemsPerPage).ceil();
      if (totalPages == 0) totalPages = 1;
      if (_currentPage > totalPages) _currentPage = totalPages;

      int startIndex = (_currentPage - 1) * _itemsPerPage;
      int endIndex = startIndex + _itemsPerPage;
      if (endIndex > filteredClients.length) {
        endIndex = filteredClients.length;
      }

      final paginatedList = filteredClients.isEmpty
          ? <Map<String, dynamic>>[]
          : filteredClients.sublist(startIndex, endIndex);

      listSection = paginatedList.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                ...paginatedList.map((client) => _buildClientCard(client)),
                const SizedBox(height: 16),
                _buildPagination(totalPages, filteredClients.length),
              ],
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopActionsBar(),
        const SizedBox(height: 16),
        _buildSearchBar(),
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
              const Text('Base de Datos de Titulares', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Personas Naturales y Jurídicas', style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => _showNewClientModal(context),
          icon: const Icon(Icons.person_add_alt_1, size: 16, color: Colors.white),
          label: const Text('Nuevo Cliente', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: _searchController,
        maxLength: 50,
        decoration: InputDecoration(
          counterText: '',
          hintText: 'Buscar por nombre o documento...',
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          prefixIcon: const Icon(Icons.search, color: Colors.black, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
            _currentPage = 1;
          });
        },
      ),
    );
  }

  // Tarjeta de cliente envuelta en InkWell para navegar a la pantalla de detalles
  Widget _buildClientCard(Map<String, dynamic> client) {
    bool isActive = client['activo'];
    bool isJuridico = client['tipo_cliente'] == 'JURIDICO';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? Colors.grey.shade200 : Colors.red.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            // Navegación hacia la pantalla de detalles del cliente
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ClientDetailScreen(client: client),
              ),
            );
            // Al volver, recargamos por si se activó/desactivó el cliente.
            _loadClients();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(isJuridico ? Icons.business : Icons.person, color: Colors.black, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  client['nombre_cliente'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Doc: ${client['documento_identidad']}',
                                  style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: isJuridico ? Colors.indigo.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            client['tipo_cliente'],
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isJuridico ? Colors.indigo : Colors.blue.shade700),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.teal.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isActive ? 'ACTIVO' : 'INACTIVO',
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isJuridico) ...[
                        Text(
                          'Representante: ${client['representante']}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Correo: ${client['correo'] ?? "No registrado"}',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Tel: ${client['telefono'] ?? "N/A"}', 
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dirección: ${client['direccion'] ?? "Sin dirección registrada"}', 
                        style: const TextStyle(fontSize: 10, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.person_search_outlined, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          const Text('No se encontraron clientes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 4),
          Text('Intenta con otro término de búsqueda o registra uno nuevo.', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
        ],
      ),
    );
  }

  Widget _buildPagination(int totalPages, int totalItems) {
    return Column(
      children: [
        Text('Página $_currentPage de $totalPages ($totalItems registros)', style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w500)),
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

  void _showNewClientModal(BuildContext context) {
    String selectedTipoCliente = 'NATURAL';
    String selectedPrefijo = 'V';

    final TextEditingController docController = TextEditingController();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController repController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController addressController = TextEditingController();
    final ScrollController scrollController = ScrollController();

    bool isSaving = false;
    String? emailError;
    // Aviso general (campos faltantes, error del servidor): se muestra
    // dentro del propio diálogo, no con SnackBar, porque un SnackBar se
    // ancla al Scaffold de atrás y queda tapado por este diálogo modal.
    String? errorMessage;
    Timer? errorTimer;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void setError(String message) {
            errorTimer?.cancel();
            setModalState(() => errorMessage = message);
            errorTimer = Timer(const Duration(seconds: 4), () {
              if (context.mounted) setModalState(() => errorMessage = null);
            });
            // El aviso se muestra arriba del todo del formulario: si el
            // usuario estaba desplazado hacia abajo, hay que subir la vista
            // para que lo vea sin tener que hacer scroll manual.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!scrollController.hasClients) return;
              scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
            });
          }

          return AlertDialog(
            title: const Text('Registrar Nuevo Cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: SizedBox(
              width: 450,
              height: 530,
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
                                            errorMessage!,
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
                    Text('Complete los datos respetando los límites de la base de datos:', style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
                    const SizedBox(height: 14),
                    CustomDropdown<String>(
                      initialValue: selectedTipoCliente,
                      decoration: InputDecoration(
                        labelText: 'Tipo de Cliente',
                        prefixIcon: const Icon(Icons.category, color: Colors.black),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        CustomDropdownItem(value: 'NATURAL', label: 'Natural (Persona)'),
                        CustomDropdownItem(value: 'JURIDICO', label: 'Jurídico (Empresa)'),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          selectedTipoCliente = val!;
                          if (selectedTipoCliente == 'JURIDICO') {
                            selectedPrefijo = 'J';
                          } else if (selectedPrefijo == 'J') {
                            selectedPrefijo = 'V';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: CustomDropdown<String>(
                            key: ValueKey('prefijo_$selectedTipoCliente'),
                            initialValue: selectedPrefijo,
                            enabled: selectedTipoCliente == 'NATURAL',
                            decoration: InputDecoration(
                              labelText: 'Tipo',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                            items: selectedTipoCliente == 'JURIDICO'
                                ? const [CustomDropdownItem(value: 'J', label: 'J')]
                                : const [
                                    CustomDropdownItem(value: 'V', label: 'V'),
                                    CustomDropdownItem(value: 'E', label: 'E'),
                                    CustomDropdownItem(value: 'P', label: 'P'),
                                  ],
                            onChanged: (val) {
                              setModalState(() => selectedPrefijo = val!);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: docController,
                            maxLength: 19,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Documento de Identidad',
                              prefixIcon: const Icon(Icons.badge, color: Colors.black),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      maxLength: 150,
                      decoration: InputDecoration(
                        labelText: 'Nombre Completo o Razón Social',
                        prefixIcon: const Icon(Icons.person, color: Colors.black),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        counterText: '',
                      ),
                    ),
                    if (selectedTipoCliente == 'JURIDICO') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: repController,
                        maxLength: 150,
                        decoration: InputDecoration(
                          labelText: 'Representante Legal (o N/A)',
                          prefixIcon: const Icon(Icons.supervisor_account, color: Colors.black),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          counterText: '',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      maxLength: 100,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        if (emailError != null) {
                          setModalState(() => emailError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Correo Electrónico',
                        prefixIcon: const Icon(Icons.email, color: Colors.black),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        counterText: '',
                        errorText: emailError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      maxLength: 20,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Número de Teléfono',
                        prefixIcon: const Icon(Icons.phone, color: Colors.black),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 95,
                      child: TextField(
                        controller: addressController,
                        maxLength: 255,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          labelText: 'Dirección Física / Domicilio Fiscal',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.all(12),
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade800)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                onPressed: isSaving
                    ? null
                    : () async {
                        final camposFaltantes = docController.text.trim().isEmpty ||
                            nameController.text.trim().isEmpty ||
                            emailController.text.trim().isEmpty ||
                            phoneController.text.trim().isEmpty ||
                            addressController.text.trim().isEmpty ||
                            (selectedTipoCliente == 'JURIDICO' && repController.text.trim().isEmpty);
                        if (camposFaltantes) {
                          setError('Todos los campos son obligatorios.');
                          return;
                        }

                        if (phoneController.text.trim().length < 5) {
                          setError('El teléfono debe tener al menos 5 caracteres.');
                          return;
                        }

                        final email = emailController.text.trim();
                        final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                        if (!emailRegex.hasMatch(email)) {
                          setModalState(() {
                            emailError = 'Ingresa un correo válido (ej: nombre@dominio.com)';
                          });
                          return;
                        }

                        errorTimer?.cancel();
                        setModalState(() {
                          isSaving = true;
                          errorMessage = null;
                        });

                        try {
                          await _clienteService.create(
                            documentoIdentidad: '$selectedPrefijo${docController.text.trim()}',
                            tipoCliente: selectedTipoCliente,
                            nombreCliente: nameController.text.trim(),
                            representante: selectedTipoCliente == 'JURIDICO' ? repController.text.trim() : 'N/A',
                            correo: email,
                            telefono: phoneController.text.trim(),
                            direccion: addressController.text.trim(),
                          );

                          if (!context.mounted) return;
                          Navigator.pop(context);

                          await _loadClients();
                          if (!mounted) return;
                          setState(() => _currentPage = 1);

                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text('Cliente ${nameController.text} registrado con éxito')),
                          );
                        } on ClienteDuplicadoException {
                          setModalState(() => isSaving = false);
                          setError('Ya existe un cliente con ese documento de identidad');
                        } catch (e) {
                          setModalState(() => isSaving = false);
                          setError(e is NoConnectionException ? e.message : 'No se pudo guardar el cliente. Intenta de nuevo.');
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar Cliente', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==========================================
// PANTALLA DE DETALLES DEL CLIENTE
// ==========================================
class ClientDetailScreen extends StatefulWidget {
  final Map<String, dynamic> client;

  const ClientDetailScreen({super.key, required this.client});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  final ClienteService _clienteService = ClienteService();
  late Map<String, dynamic> client;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    client = widget.client;
  }

  Future<void> _toggleActivo() async {
    final bool isActive = client['activo'] ?? true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isActive ? 'Desactivar Cliente' : 'Activar Cliente'),
        content: SizedBox(
          width: 320,
          child: Text(
            isActive
                ? '¿Seguro que deseas desactivar a ${client['nombre_cliente']}?'
                : '¿Deseas reactivar a ${client['nombre_cliente']}?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade800)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Colors.red.shade700 : Colors.teal.shade700,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isActive ? 'Desactivar' : 'Activar', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isToggling = true);

    try {
      await _clienteService.setActivo(
        clienteId: client['cliente_id'] as int,
        documentoIdentidad: client['documento_identidad'] as String,
        activo: !isActive,
      );

      if (!mounted) return;
      setState(() {
        client = {...client, 'activo': !isActive};
        _isToggling = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isActive ? 'Cliente desactivado' : 'Cliente activado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isToggling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is NoConnectionException ? e.message : 'No se pudo actualizar el estado del cliente. Intenta de nuevo.',
          ),
        ),
      );
    }
  }

  void _showEditClientModal() {
    final originalDocumento = client['documento_identidad'] as String;
    final datosAnteriores = {
      'documento_identidad': client['documento_identidad'],
      'tipo_cliente': client['tipo_cliente'],
      'nombre_cliente': client['nombre_cliente'],
      'representante': client['representante'],
      'correo': client['correo'],
      'telefono': client['telefono'],
      'direccion': client['direccion'],
    };

    String selectedTipoCliente = client['tipo_cliente'] as String;

    // El documento ya pudo haberse guardado con un prefijo (V/E/P/J); si no
    // tiene ninguno reconocible (datos de antes de este selector), se asume
    // uno por defecto según el tipo de cliente y se deja el valor tal cual
    // como los dígitos a editar.
    final documentoActual = client['documento_identidad'] as String? ?? '';
    const prefijosValidos = {'V', 'E', 'P', 'J'};
    final primerCaracter = documentoActual.isNotEmpty ? documentoActual[0].toUpperCase() : '';
    String selectedPrefijo;
    String digitosIniciales;
    if (prefijosValidos.contains(primerCaracter)) {
      selectedPrefijo = primerCaracter;
      digitosIniciales = documentoActual.substring(1);
    } else {
      selectedPrefijo = selectedTipoCliente == 'JURIDICO' ? 'J' : 'V';
      digitosIniciales = documentoActual;
    }

    final docController = TextEditingController(text: digitosIniciales);
    final nameController = TextEditingController(text: client['nombre_cliente'] as String?);
    final repController = TextEditingController(text: client['representante'] as String?);
    final emailController = TextEditingController(text: client['correo'] as String?);
    final phoneController = TextEditingController(text: client['telefono'] as String?);
    final addressController = TextEditingController(text: client['direccion'] as String?);
    final scrollController = ScrollController();

    bool isSaving = false;
    String? emailError;
    // Igual que en el modal de Nuevo Cliente: aviso general dentro del
    // diálogo, no SnackBar (queda tapado por el diálogo modal).
    String? errorMessage;
    Timer? errorTimer;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          void setError(String message) {
            errorTimer?.cancel();
            setModalState(() => errorMessage = message);
            errorTimer = Timer(const Duration(seconds: 4), () {
              if (dialogContext.mounted) setModalState(() => errorMessage = null);
            });
            // El aviso se muestra arriba del todo del formulario: si el
            // usuario estaba desplazado hacia abajo, hay que subir la vista
            // para que lo vea sin tener que hacer scroll manual.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!scrollController.hasClients) return;
              scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
            });
          }

          return AlertDialog(
            title: const Text('Editar Cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: SizedBox(
              width: 450,
              height: 530,
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
                                            errorMessage!,
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
                    CustomDropdown<String>(
                      initialValue: selectedTipoCliente,
                      decoration: InputDecoration(
                        labelText: 'Tipo de Cliente',
                        prefixIcon: const Icon(Icons.category, color: Colors.black),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        CustomDropdownItem(value: 'NATURAL', label: 'Natural (Persona)'),
                        CustomDropdownItem(value: 'JURIDICO', label: 'Jurídico (Empresa)'),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          selectedTipoCliente = val!;
                          if (selectedTipoCliente == 'JURIDICO') {
                            selectedPrefijo = 'J';
                          } else if (selectedPrefijo == 'J') {
                            selectedPrefijo = 'V';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: CustomDropdown<String>(
                            key: ValueKey('prefijo_$selectedTipoCliente'),
                            initialValue: selectedPrefijo,
                            enabled: selectedTipoCliente == 'NATURAL',
                            decoration: InputDecoration(
                              labelText: 'Tipo',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                            items: selectedTipoCliente == 'JURIDICO'
                                ? const [CustomDropdownItem(value: 'J', label: 'J')]
                                : const [
                                    CustomDropdownItem(value: 'V', label: 'V'),
                                    CustomDropdownItem(value: 'E', label: 'E'),
                                    CustomDropdownItem(value: 'P', label: 'P'),
                                  ],
                            onChanged: (val) {
                              setModalState(() => selectedPrefijo = val!);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: docController,
                            maxLength: 19,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Documento de Identidad',
                              prefixIcon: const Icon(Icons.badge, color: Colors.black),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      maxLength: 150,
                      decoration: InputDecoration(
                        labelText: 'Nombre Completo o Razón Social',
                        prefixIcon: const Icon(Icons.person, color: Colors.black),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        counterText: '',
                      ),
                    ),
                    if (selectedTipoCliente == 'JURIDICO') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: repController,
                        maxLength: 150,
                        decoration: InputDecoration(
                          labelText: 'Representante Legal (o N/A)',
                          prefixIcon: const Icon(Icons.supervisor_account, color: Colors.black),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          counterText: '',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      maxLength: 100,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        if (emailError != null) {
                          setModalState(() => emailError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Correo Electrónico',
                        prefixIcon: const Icon(Icons.email, color: Colors.black),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        counterText: '',
                        errorText: emailError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      maxLength: 20,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Número de Teléfono',
                        prefixIcon: const Icon(Icons.phone, color: Colors.black),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 95,
                      child: TextField(
                        controller: addressController,
                        maxLength: 255,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          labelText: 'Dirección Física / Domicilio Fiscal',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.all(12),
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade800)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (docController.text.isEmpty || nameController.text.isEmpty) {
                          setError('Por favor complete al menos el Documento y el Nombre');
                          return;
                        }

                        final email = emailController.text.trim();
                        final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                        if (email.isNotEmpty && !emailRegex.hasMatch(email)) {
                          setModalState(() {
                            emailError = 'Ingresa un correo válido (ej: nombre@dominio.com)';
                          });
                          return;
                        }

                        errorTimer?.cancel();
                        setModalState(() {
                          isSaving = true;
                          errorMessage = null;
                        });

                        final newDocumento = '$selectedPrefijo${docController.text.trim()}';
                        final newTipo = selectedTipoCliente;
                        final newNombre = nameController.text.trim();
                        final newRepresentante = repController.text.trim().isEmpty ? 'N/A' : repController.text.trim();
                        final newCorreo = email.isEmpty ? null : email;
                        final newTelefono = phoneController.text.trim().isEmpty ? null : phoneController.text.trim();
                        final newDireccion = addressController.text.trim().isEmpty ? null : addressController.text.trim();

                        try {
                          await _clienteService.update(
                            clienteId: client['cliente_id'] as int,
                            registroIdAuditoria: originalDocumento,
                            documentoIdentidad: newDocumento,
                            tipoCliente: newTipo,
                            nombreCliente: newNombre,
                            representante: newRepresentante,
                            correo: newCorreo,
                            telefono: newTelefono,
                            direccion: newDireccion,
                            datosAnteriores: datosAnteriores,
                          );

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);

                          if (!mounted) return;
                          setState(() {
                            client = {
                              ...client,
                              'documento_identidad': newDocumento,
                              'tipo_cliente': newTipo,
                              'nombre_cliente': newNombre,
                              'representante': newRepresentante,
                              'correo': newCorreo,
                              'telefono': newTelefono,
                              'direccion': newDireccion,
                            };
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cliente actualizado con éxito')),
                          );
                        } on ClienteDuplicadoException {
                          setModalState(() => isSaving = false);
                          setError('Ya existe un cliente con ese documento de identidad');
                        } catch (e) {
                          setModalState(() => isSaving = false);
                          setError(e is NoConnectionException ? e.message : 'No se pudo actualizar el cliente. Intenta de nuevo.');
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar Cambios', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isActive = client['activo'] ?? true;
    bool isJuridico = client['tipo_cliente'] == 'JURIDICO';
    int prestamosActivos = client['prestamos_activos'] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Expediente del Cliente',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tarjeta superior de Resumen / Estado
              Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(isJuridico ? Icons.business : Icons.person, color: Colors.black, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client['nombre_cliente'] ?? 'Sin nombre',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          client['documento_identidad'] ?? 'Sin documento',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.teal.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isActive ? 'ACTIVO' : 'INACTIVO',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? Colors.teal : Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showEditClientModal,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isToggling ? null : _toggleActivo,
                        icon: _isToggling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(isActive ? Icons.block : Icons.check_circle_outline, color: Colors.white, size: 18),
                        label: Text(
                          isActive ? 'Desactivar' : 'Activar',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isActive ? Colors.red.shade700 : Colors.teal.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Tarjeta destacada: Préstamos Activos
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet, color: Colors.white70, size: 24),
                        const SizedBox(width: 12),
                        const Flexible(
                          child: Text(
                            'Préstamos Activos',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$prestamosActivos',
                      style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sección de Datos Detallados
            const Text(
              'Información General',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(Icons.category, 'Tipo de Cliente', client['tipo_cliente'] ?? 'N/A'),
                  if (isJuridico) ...[
                    const Divider(height: 20),
                    _buildDetailRow(Icons.supervisor_account, 'Representante Legal', client['representante'] ?? 'N/A'),
                  ],
                  const Divider(height: 20),
                  _buildDetailRow(Icons.email, 'Correo Electrónico', client['correo'] ?? 'No registrado'),
                  const Divider(height: 20),
                  _buildDetailRow(Icons.phone, 'Teléfono', client['telefono'] ?? 'No registrado'),
                  const Divider(height: 20),
                  _buildDetailRow(Icons.location_on, 'Dirección Física', client['direccion'] ?? 'Sin dirección registrada'),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}