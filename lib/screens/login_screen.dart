import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';

/// Pantalla de inicio de sesión. Layout único (tarjeta centrada de ancho
/// máximo) que se adapta solo con el ancho disponible: en desktop queda
/// como una tarjeta fija sobre el fondo negro, en móvil (Android/iOS) la
/// misma tarjeta ocupa el ancho de la pantalla con márgenes, con scroll
/// para no chocar con el teclado.
class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  /// Aviso genérico opcional (p. ej. sesión cerrada por inactividad, por
  /// más de 30 minutos con la app cerrada, o por inicio de sesión en otro
  /// dispositivo) que se muestra una sola vez al llegar a esta pantalla.
  final String? sessionNotice;

  const LoginScreen({super.key, required this.onLoginSuccess, this.sessionNotice});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usuarioController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _errorTimer;
  late String? _noticeMessage = widget.sessionNotice;
  final ScrollController _scrollController = ScrollController();

  bool _biometricDisponible = false;
  bool _isBiometricLoading = false;
  bool _esFaceId = false;

  @override
  void initState() {
    super.initState();
    _initBiometricState();
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _scrollController.dispose();
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Revisa, sin bloquear la pantalla, si este dispositivo tiene un
  /// desbloqueo biométrico activo y si el sensor sigue disponible ahora
  /// (pudo desactivarse desde la última vez). Si ambas cosas son ciertas,
  /// se ofrece el atajo; si no, la pantalla se ve exactamente como antes.
  Future<void> _initBiometricState() async {
    final recordado = await AuthService.instance.tieneDispositivoRecordado();
    bool disponible = false;
    bool esFaceId = false;
    if (recordado) {
      disponible = await BiometricService.instance.isAvailable();
      if (disponible) {
        esFaceId = await BiometricService.instance.esFaceId();
      }
    }
    if (!mounted) return;
    setState(() {
      _biometricDisponible = disponible;
      _esFaceId = esFaceId;
    });
  }

  Future<void> _intentarBiometria() async {
    setState(() => _isBiometricLoading = true);
    final confirmado = await BiometricService.instance.authenticate(
      'Confirma tu identidad para entrar a MAF Financial',
    );
    if (!confirmado) {
      if (!mounted) return;
      setState(() => _isBiometricLoading = false);
      return; // cancelado o falló el sensor: se queda en esta pantalla, sin mensaje de error.
    }

    try {
      final user = await AuthService.instance.renovarSesionConBiometria();
      if (!mounted) return;
      if (user != null) {
        widget.onLoginSuccess();
        return;
      }
      // La credencial ya no era válida (expiró, la reemplazó otro
      // dispositivo, o la cuenta quedó bloqueada/desactivada): cae al
      // formulario normal en vez de insistir con la biometría.
      setState(() {
        _isBiometricLoading = false;
        _biometricDisponible = false;
      });
      _showError('No se pudo continuar con biometría. Inicia sesión con tu contraseña.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBiometricLoading = false);
      _showError('No se pudo continuar con biometría. Inicia sesión con tu contraseña.');
    }
  }

  /// Tras un login normal exitoso, si el sensor está disponible y esta
  /// cuenta todavía no tiene el desbloqueo biométrico activado en este
  /// dispositivo, se ofrece activarlo. No bloquea el login si se cancela o
  /// si algo falla al activarlo.
  Future<void> _ofrecerActivarBiometriaSiAplica() async {
    final yaRecordado = await AuthService.instance.tieneDispositivoRecordado();
    if (yaRecordado) return;

    final disponible = await BiometricService.instance.isAvailable();
    if (!disponible || !mounted) return;

    final activar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activar huella / Face ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const SizedBox(
          width: 320,
          child: Text(
            '¿Quieres usar tu huella o Face ID para entrar más rápido en este dispositivo la próxima vez?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Ahora no', style: TextStyle(color: Colors.grey.shade800)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Activar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (activar != true || !mounted) return;

    final confirmado = await BiometricService.instance.authenticate(
      'Confirma tu huella o Face ID para activarlo en MAF Financial',
    );
    if (!confirmado) return;

    try {
      await AuthService.instance.habilitarRecordarDispositivo();
    } catch (_) {
      // No se pudo activar el atajo; el login normal ya tuvo éxito, así
      // que no se le muestra ningún error por esto al usuario.
    }
  }

  void _showError(String message) {
    _errorTimer?.cancel();
    setState(() => _errorMessage = message);
    _errorTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _errorMessage = null);
    });
    // El aviso se muestra dentro de la tarjeta, arriba de los campos: si el
    // teclado empujó la vista hacia abajo, hay que subirla para que se vea.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    _errorTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      await AuthService.instance.login(
        nombreUsuario: _usuarioController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      await _ofrecerActivarBiometriaSiAplica();
      if (!mounted) return;
      widget.onLoginSuccess();
    } on ArgumentError catch (e) {
      setState(() => _isLoading = false);
      _showError('${e.message}');
    } on NoConnectionException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.message);
    } catch (_) {
      setState(() => _isLoading = false);
      _showError('No se pudo iniciar sesión. Intenta de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBrandHeader(),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12)),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Iniciar Sesión',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Acceso exclusivo para administradores.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 20),
                          _buildNoticeBanner(),
                          _buildErrorBanner(),
                          TextFormField(
                            controller: _usuarioController,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.none,
                            autofillHints: const [AutofillHints.username],
                            decoration: _fieldDecoration('Usuario', Icons.person_outline),
                            validator: (value) => (value == null || value.trim().isEmpty) ? 'Ingresa tu usuario' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.none,
                            keyboardType: TextInputType.visiblePassword,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: _fieldDecoration('Contraseña', Icons.lock_outline).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: Colors.grey.shade700,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (value) => (value == null || value.isEmpty) ? 'Ingresa tu contraseña' : null,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Text(
                                            'Ingresar',
                                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                ),
                              ),
                              if (_biometricDisponible) ...[
                                const SizedBox(width: 12),
                                _buildBiometricButton(),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Cuadro cuadrado junto al botón "Ingresar": ícono de huella o de rostro
  /// según lo que este dispositivo tenga enrolado, para entrar sin escribir
  /// usuario/contraseña.
  Widget _buildBiometricButton() {
    return SizedBox(
      width: 48,
      height: 48,
      child: OutlinedButton(
        onPressed: _isBiometricLoading ? null : _intentarBiometria,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          padding: EdgeInsets.zero,
          side: const BorderSide(color: Colors.black, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isBiometricLoading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : Icon(_esFaceId ? Icons.face : Icons.fingerprint, size: 24),
      ),
    );
  }

  Widget _buildNoticeBanner() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _noticeMessage == null
          ? const SizedBox(width: double.infinity)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.grey.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _noticeMessage!,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildErrorBanner() {
    return AnimatedSize(
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
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          width: 107,
          height: 72,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade800),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/logooficial.jpeg', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'MAF Financial',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        const SizedBox(height: 2),
        Text(
          'GESTIÓN DE PRÉSTAMOS',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade800, fontSize: 13),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
