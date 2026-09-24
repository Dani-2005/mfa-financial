import 'package:flutter/material.dart';
import 'screens/change_password_dialog.dart';
import 'screens/dashboard_screen.dart'; // Asegúrate de importar tu dashboard
import 'screens/login_screen.dart';
import 'screens/loans_screen.dart';     // Asegúrate de importar tu pantalla de préstamos
import 'screens/payments_screen.dart'; // O 'screens/payments_screen.dart' dependiendo de dónde guardaste el archivo
import 'screens/clients_screen.dart'; // Asegúrate de importar tu pantalla de clientes
import 'screens/audit_reports_screen.dart'; // Asegúrate de importar tu pantalla de auditoría
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/session.dart';
import 'widgets/session_activity_guard.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MAF Financial',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey,
          primary: Colors.black,
          secondary: Colors.grey.shade800,
        ),
        fontFamily: 'Roboto',
      ),
      home: const AuthGate(),
    );
  }
}

/// Decide qué mostrar primero: mientras se revisa si ya había una sesión
/// guardada (cifrada en el dispositivo) se ve un splash con el logo; luego
/// pasa a [LoginScreen] o directo a [MainNavigationScreen] según corresponda.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checkingSession = true;
  bool _authenticated = false;

  /// Aviso deliberadamente genérico que se muestra una sola vez en el login
  /// cuando la sesión se cerró sola (inactividad, más de 30 minutos con la
  /// app cerrada, o inicio de sesión con la misma cuenta en otro
  /// dispositivo) — nunca revela cuál de esos motivos fue.
  String? _sessionNotice;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final result = await AuthService.instance.restoreSession();
    if (!mounted) return;
    setState(() {
      _authenticated = result.user != null;
      _sessionNotice = result.sinConexion
          ? const NoConnectionException().message
          : (result.sessionEnded ? mensajeSesionFinalizada : null);
      _checkingSession = false;
    });
  }

  void _onLoginSuccess() => setState(() {
        _authenticated = true;
        _sessionNotice = null;
      });

  void _onLogout() => setState(() {
        _authenticated = false;
        _sessionNotice = null;
      });

  /// El cierre de sesión se forzó solo (no fue un logout manual): se vuelve
  /// al login mostrando el aviso genérico.
  void _onSessionEnded() => setState(() {
        _authenticated = false;
        _sessionNotice = mensajeSesionFinalizada;
      });

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (!_authenticated) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess, sessionNotice: _sessionNotice);
    }
    return SessionActivityGuard(
      onSessionEnded: _onSessionEnded,
      child: MainNavigationScreen(onLogout: _onLogout),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const MainNavigationScreen({super.key, required this.onLogout});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _NavItemData {
  final IconData iconOutlined;
  final IconData iconFilled;
  final String label;

  const _NavItemData({
    required this.iconOutlined,
    required this.iconFilled,
    required this.label,
  });
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // El IndexedStack mantiene cada pantalla viva en segundo plano (para no
  // perder su estado al cambiar de pestaña), así que el Dashboard no vuelve
  // a consultar la base de datos solo por navegar hacia él. Esta llave
  // fuerza que se recree (y por lo tanto vuelva a cargar sus datos) cada
  // vez que se entra a esa pestaña desde otra distinta.
  int _dashboardRefreshKey = 0;

  // Igual que arriba, pero para forzar que Pagos se recree con una cuota ya
  // pre-elegida cuando se llega desde el botón "Registrar pago" del
  // Dashboard (si no se recreara, al ya estar montada no reabriría el
  // diálogo con los nuevos datos).
  int _paymentsPrefillKey = 0;
  PagoPrefill? _pendingPagoPrefill;

  List<Widget> get _screens => [
        DashboardScreen(
          key: ValueKey('dashboard_$_dashboardRefreshKey'),
          onRegistrarPago: _goToRegistrarPago,
        ),
        const LoansScreen(),
        PaymentsScreen(
          key: ValueKey('payments_$_paymentsPrefillKey'),
          prefill: _pendingPagoPrefill,
          onPrefillConsumed: () {
            if (mounted) setState(() => _pendingPagoPrefill = null);
          },
        ),
        const ClientsScreen(),
        const AuditAndReportsScreen(),
      ];

  void _goToRegistrarPago(PagoPrefill prefill) {
    setState(() {
      _pendingPagoPrefill = prefill;
      _paymentsPrefillKey++;
      _currentIndex = 2; // Pestaña de Pagos
    });
  }

  static const List<_NavItemData> _navItems = [
    _NavItemData(iconOutlined: Icons.dashboard_outlined, iconFilled: Icons.dashboard, label: 'Dashboard'),
    _NavItemData(iconOutlined: Icons.attach_money_outlined, iconFilled: Icons.attach_money, label: 'Préstamos'),
    _NavItemData(iconOutlined: Icons.receipt_long_outlined, iconFilled: Icons.receipt_long, label: 'Pagos'),
    _NavItemData(iconOutlined: Icons.people_outline, iconFilled: Icons.people, label: 'Clientes'),
    _NavItemData(iconOutlined: Icons.shield_outlined, iconFilled: Icons.shield, label: 'Auditoría'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth >= 800;

        final Widget body = IndexedStack(
          index: _currentIndex,
          children: _screens,
        );

        if (isDesktop) {
          // --- DISEÑO DESKTOP ---
          return Scaffold(
            key: const ValueKey('scaffold-desktop'),
            backgroundColor: const Color(0xFFF5F5F5),
            body: Stack(
              children: [
                Positioned.fill(
                  child: body,
                ),

                // 1. Ponemos left: 0 y right: 0 para que toque los bordes
                Positioned(
                  top: 90,
                  left: 0,
                  right: 0,
                  child: _buildDesktopNavBar(),
                ),
              ],
            ),
          );
        }

        // --- DISEÑO MÓVIL ---
        return Scaffold(
          key: const ValueKey('scaffold-mobile'),
          body: body,
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border(top: BorderSide(color: Colors.grey.shade800, width: 1)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (int i = 0; i < _navItems.length; i++)
                      Expanded(child: _buildNavItem(i, _navItems[i], isDesktop: false)),
                    Expanded(child: _buildAccountMenu(isDesktop: false)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- BARRA DE NAVEGACIÓN DESKTOP ---
  Widget _buildDesktopNavBar() {
    return Container(
      // Añadimos padding horizontal interno para que los iconos no se peguen a los bordes
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 0, 0, 0), 
        // 2. Quitamos el borde redondeado para que sea una barra recta
        borderRadius: BorderRadius.zero, 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15), 
            blurRadius: 8, 
            offset: const Offset(0, 4)
          )
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _navItems.length; i++) ...[
              if (i > 0) const SizedBox(width: 24),
              _buildNavItem(i, _navItems[i], isDesktop: true),
            ],
            const SizedBox(width: 24),
            Container(width: 1, height: 24, color: Colors.grey.shade800),
            const SizedBox(width: 12),
            _buildAccountMenu(isDesktop: true),
          ],
        ),
      ),
    );
  }

  // --- MENÚ DE CUENTA: CAMBIAR CONTRASEÑA / CERRAR SESIÓN ---
  Widget _buildAccountMenu({required bool isDesktop}) {
    final nombre = Session.current?.nombreCompleto ?? '';

    return PopupMenuButton<String>(
      tooltip: nombre.isEmpty ? 'Cuenta' : 'Cuenta: $nombre',
      color: Colors.white,
      icon: Icon(
        Icons.account_circle_outlined,
        color: isDesktop ? Colors.grey.shade500 : Colors.grey.shade600,
        size: isDesktop ? 22 : 24,
      ),
      onSelected: (value) async {
        if (value == 'password') {
          showChangePasswordDialog(context);
          return;
        }
        if (value == 'logout') {
          final tieneDispositivoRecordado = await AuthService.instance.tieneDispositivoRecordado();
          if (!mounted) return;
          bool olvidarDispositivo = false;

          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setDialogState) => AlertDialog(
                title: const Text('Cerrar Sesión', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                content: SizedBox(
                  width: 320,
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('¿Seguro que deseas cerrar tu sesión?'),
                    if (tieneDispositivoRecordado) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => setDialogState(() => olvidarDispositivo = !olvidarDispositivo),
                        child: Row(
                          children: [
                            Checkbox(
                              value: olvidarDispositivo,
                              onChanged: (v) => setDialogState(() => olvidarDispositivo = v ?? false),
                            ),
                            const Expanded(
                              child: Text(
                                'También olvidar este dispositivo (deja de pedir solo la huella/Face ID la próxima vez)',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade800)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
          if (confirmed == true) {
            await AuthService.instance.logout();
            if (olvidarDispositivo) {
              await AuthService.instance.olvidarDispositivo();
            }
            widget.onLogout();
          }
        }
      },
      itemBuilder: (context) => [
        if (nombre.isNotEmpty) ...[
          PopupMenuItem<String>(
            enabled: false,
            child: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem<String>(
          value: 'password',
          child: Row(
            children: [
              Icon(Icons.password, size: 18, color: Colors.black87),
              SizedBox(width: 10),
              Text('Cambiar Contraseña'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Text('Cerrar Sesión', style: TextStyle(color: Colors.red.shade700)),
            ],
          ),
        ),
      ],
    );
  }

  // --- ITEM DE NAVEGACIÓN REUTILIZABLE ---
  Widget _buildNavItem(int index, _NavItemData item, {required bool isDesktop}) {
    final iconOutlined = item.iconOutlined;
    final iconFilled = item.iconFilled;
    final label = item.label;
    bool isActive = _currentIndex == index;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (index == 0 && _currentIndex != 0) {
            _dashboardRefreshKey++;
          }
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: isDesktop 
          // Estilo horizontal para Desktop
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: isActive 
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15), 
                      borderRadius: BorderRadius.circular(12)
                    ) 
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive ? iconFilled : iconOutlined, 
                    color: isActive ? Colors.white : Colors.grey.shade500,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label, 
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey.shade500,
                      fontSize: 13, 
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            )
          // Estilo vertical clásico para Móvil
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: isActive 
                      ? BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8)
                        ) 
                      : null,
                  child: Icon(
                    isActive ? iconFilled : iconOutlined, 
                    color: isActive ? Colors.white : Colors.grey.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  // Margen mínimo garantizado fuera del FittedBox: si no se
                  // reserva aparte, el texto escalado puede llenar toda la
                  // franja sin dejar espacio y termina tocando al vecino.
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.grey.shade600,
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}