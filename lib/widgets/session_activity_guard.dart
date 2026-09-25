import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Envuelve la app ya autenticada para hacer cumplir el cierre de sesión
/// automático: 30 minutos sin ninguna interacción (mouse/touch) mientras la
/// app está abierta, o 30 minutos transcurridos desde que la app pasó a
/// segundo plano/se cerró. También revalida periódicamente contra el
/// servidor para detectar si esta sesión ya no es válida (expiró, se cerró
/// desde el servidor o la cuenta se desactivó), y en ese caso también
/// fuerza el cierre de sesión. Otras sesiones de la misma cuenta en otros
/// dispositivos no la afectan. Cerrar la app en escritorio (X o Cmd+Q) también
/// cierra la sesión, ver [_SessionActivityGuardState.didRequestAppExit].
///
/// Cualquiera de estos motivos dispara [onSessionEnded], que quien lo use
/// (normalmente el `AuthGate`) debe traducir en volver a la pantalla de
/// login mostrando [mensajeSesionFinalizada] sin distinguir cuál fue la
/// causa exacta.
class SessionActivityGuard extends StatefulWidget {
  final Widget child;
  final VoidCallback onSessionEnded;

  const SessionActivityGuard({
    super.key,
    required this.child,
    required this.onSessionEnded,
  });

  @override
  State<SessionActivityGuard> createState() => _SessionActivityGuardState();
}

class _SessionActivityGuardState extends State<SessionActivityGuard> with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  Timer? _keepAliveTimer;
  bool _ended = false;

  static const Duration _revalidacionPeriodica = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetInactivityTimer();
    _keepAliveTimer = Timer.periodic(_revalidacionPeriodica, (_) => _checkStillValid());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _keepAliveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        AuthService.instance.marcarSegundoPlano();
        break;
      case AppLifecycleState.resumed:
        _resetInactivityTimer();
        _checkStillValid();
        break;
    }
  }

  /// Se llama en escritorio (macOS/Windows) cuando el usuario cierra la
  /// ventana con la X o sale con Cmd+Q: se cierra la sesión en el servidor
  /// antes de salir, para que la cuenta no quede "activa" y bloquee el
  /// login desde otro dispositivo hasta que expire sola. El timeout evita
  /// que la ventana tarde en cerrarse si no hay conexión; en ese caso la
  /// sesión expira en el servidor a los 30 minutos igual que antes.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!_ended) {
      _ended = true;
      try {
        await AuthService.instance.logout().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    return AppExitResponse.exit;
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(AuthService.duracionSesion, _onInactivityTimeout);
  }

  Future<void> _onInactivityTimeout() async {
    if (_ended || !mounted) return;
    await AuthService.instance.logout();
    _finish();
  }

  Future<void> _checkStillValid() async {
    if (_ended) return;
    final result = await AuthService.instance.refrescarActividad();
    if (result.sessionEnded) {
      _finish();
    }
  }

  void _finish() {
    if (_ended || !mounted) return;
    _ended = true;
    _inactivityTimer?.cancel();
    _keepAliveTimer?.cancel();
    widget.onSessionEnded();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      onPointerHover: (_) => _resetInactivityTimer(),
      onPointerSignal: (_) => _resetInactivityTimer(),
      child: widget.child,
    );
  }
}
