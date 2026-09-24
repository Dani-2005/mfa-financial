import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'session.dart';

/// Mensaje genérico para cualquier fallo de credenciales: nunca se distingue
/// si el usuario no existe o si la contraseña es incorrecta, para no dar
/// pistas a quien intente adivinar cuentas válidas.
const String _mensajeCredencialesInvalidas = 'Usuario o contraseña incorrectos.';

/// Mensaje único y deliberadamente genérico para cualquier motivo por el que
/// una sesión guardada deja de ser válida (expiró por inactividad, pasaron
/// más de 30 minutos con la app cerrada, o se inició sesión con la misma
/// cuenta en otro dispositivo). Se usa siempre el mismo texto para no
/// revelar cuál de esos casos ocurrió.
const String mensajeSesionFinalizada = 'Tu sesión anterior finalizó. Inicia sesión de nuevo.';

/// Resultado de validar/restaurar la sesión guardada en el dispositivo.
class SessionCheckResult {
  final AuthUser? user;

  /// true cuando había una sesión guardada localmente pero ya no es válida
  /// (para que la pantalla de login muestre [mensajeSesionFinalizada]).
  final bool sessionEnded;

  /// true cuando no se pudo confirmar nada porque no hay conexión al
  /// servidor: la sesión local no se destruye ni se marca como finalizada
  /// (se reintentará sola en cuanto vuelva la conexión), pero la pantalla de
  /// login puede avisar explícitamente que es un problema de red.
  final bool sinConexion;

  const SessionCheckResult({this.user, this.sessionEnded = false, this.sinConexion = false});
}

/// Igual que antes en su interfaz pública (mismos métodos, mismos nombres),
/// pero por dentro ya no habla directo con MySQL: llama al servidor MAF API
/// en el VPS (ver `ApiClient`), que es quien valida credenciales, aplica el
/// bloqueo por intentos fallidos, y controla la sesión única por cuenta.
/// Esta pantalla y el resto de la app no necesitaron ningún cambio gracias
/// a que la interfaz de esta clase se mantuvo idéntica.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Debe coincidir con la duración que usa el servidor para la sesión
  /// (ver `server/lib/auth_service.dart`); se usa aquí solo para decidir
  /// localmente si ya pasó demasiado tiempo con la app en segundo plano
  /// antes de intentar validar contra el servidor.
  static const Duration duracionSesion = Duration(minutes: 30);

  static const String _keyToken = 'session_token';
  static const String _keyUsuarioId = 'session_usuario_id';
  static const String _keyExpiraEn = 'session_expira_en';
  static const String _keyBackgroundedAt = 'session_backgrounded_at';

  static const String _keyRecordarToken = 'recordar_token';
  static const String _keyRecordarUsuarioId = 'recordar_usuario_id';
  static const String _keyRecordarNombre = 'recordar_nombre_completo';

  // En macOS el Llavero "data protection" (el default del plugin) exige el
  // entitlement keychain-access-groups, que a su vez exige firmar con un
  // certificado de desarrollo; sin él, guardar el token falla. El Llavero
  // clásico no necesita nada de eso. MacOsOptions solo se aplica en macOS.
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<void> _guardarLocal({required String token, required int usuarioId, required DateTime expiraEn}) async {
    await _secureStorage.write(key: _keyToken, value: token);
    await _secureStorage.write(key: _keyUsuarioId, value: usuarioId.toString());
    await _secureStorage.write(key: _keyExpiraEn, value: expiraEn.toIso8601String());
    await _secureStorage.delete(key: _keyBackgroundedAt);
  }

  /// Como [_guardarLocal], pero para justo después de que el servidor ya
  /// creó la sesión: si el almacenamiento seguro falla (p. ej. el Llavero de
  /// macOS rechaza la escritura), se cierra esa sesión en el servidor antes
  /// de propagar el error. Si no, la sesión quedaría activa del lado del
  /// servidor sin que este dispositivo tenga el token, y la regla de sesión
  /// única bloquearía cualquier reintento hasta que expire sola.
  Future<void> _guardarLocalOLiberar({required String token, required int usuarioId, required DateTime expiraEn}) async {
    try {
      await _guardarLocal(token: token, usuarioId: usuarioId, expiraEn: expiraEn);
    } catch (_) {
      await _cerrarSesionServidor(usuarioId, token);
      try {
        await _limpiarLocal();
      } catch (_) {}
      throw ArgumentError('No se pudo guardar la sesión en este dispositivo. Intenta de nuevo.');
    }
  }

  Future<void> _limpiarLocal() async {
    await _secureStorage.delete(key: _keyToken);
    await _secureStorage.delete(key: _keyUsuarioId);
    await _secureStorage.delete(key: _keyExpiraEn);
    await _secureStorage.delete(key: _keyBackgroundedAt);
  }

  Map<String, String> _authHeaders(int usuarioId, String token) => {
        'X-Usuario-Id': usuarioId.toString(),
        'Authorization': 'Bearer $token',
      };

  /// Headers de autenticación para que otros servicios (Clientes, Préstamos,
  /// etc.) llamen al servidor API con la sesión actual, sin duplicar el
  /// acceso al almacenamiento seguro donde vive el token. Devuelve `null` si
  /// no hay sesión activa.
  Future<Map<String, String>?> authHeaders() async {
    final user = Session.current;
    final token = await _secureStorage.read(key: _keyToken);
    if (user == null || token == null) return null;
    return _authHeaders(user.usuarioId, token);
  }

  /// Marca el momento en que la app pasó a segundo plano/se cerró, para
  /// poder calcular al reabrir si pasaron más de [duracionSesion] minutos.
  Future<void> marcarSegundoPlano() async {
    if (Session.current == null) return;
    await _secureStorage.write(key: _keyBackgroundedAt, value: DateTime.now().toIso8601String());
  }

  /// Restaura la sesión al reabrir la app a partir del token guardado
  /// cifrado en el dispositivo (`flutter_secure_storage`); la contraseña
  /// real nunca se guarda ahí, y el token tampoco se guarda nunca en texto
  /// plano del lado del servidor (solo su hash), igual que antes — lo
  /// único que cambió es que la validación contra la sesión activa ahora
  /// la hace el servidor API en vez de esta app consultando MySQL directo.
  Future<SessionCheckResult> restoreSession() async {
    final tokenLocal = await _secureStorage.read(key: _keyToken);
    final usuarioIdStr = await _secureStorage.read(key: _keyUsuarioId);
    final expiraEnStr = await _secureStorage.read(key: _keyExpiraEn);

    if (tokenLocal == null || usuarioIdStr == null || expiraEnStr == null) {
      Session.current = null;
      return const SessionCheckResult();
    }

    final usuarioId = int.tryParse(usuarioIdStr);
    final expiraEnLocal = DateTime.tryParse(expiraEnStr);
    if (usuarioId == null || expiraEnLocal == null) {
      await _limpiarLocal();
      Session.current = null;
      return const SessionCheckResult(sessionEnded: true);
    }

    final ahora = DateTime.now();

    // 30 minutos después de haberse ido a segundo plano/cerrado la app.
    final backgroundedAtStr = await _secureStorage.read(key: _keyBackgroundedAt);
    if (backgroundedAtStr != null) {
      final backgroundedAt = DateTime.tryParse(backgroundedAtStr);
      if (backgroundedAt == null || ahora.difference(backgroundedAt) > duracionSesion) {
        await _cerrarSesionServidor(usuarioId, tokenLocal);
        await _limpiarLocal();
        Session.current = null;
        return const SessionCheckResult(sessionEnded: true);
      }
    }

    // 30 minutos de inactividad ya reflejados en la expiración local.
    if (ahora.isAfter(expiraEnLocal)) {
      await _cerrarSesionServidor(usuarioId, tokenLocal);
      await _limpiarLocal();
      Session.current = null;
      return const SessionCheckResult(sessionEnded: true);
    }

    ApiResponse response;
    try {
      response = await ApiClient.instance.get('/api/auth/session', headers: _authHeaders(usuarioId, tokenLocal));
    } on NoConnectionException {
      // Sin conexión al servidor: no se destruye la sesión local por esto
      // solo (sería muy molesto sin internet momentáneamente), se deja tal
      // cual para reintentar la próxima vez.
      Session.current = null;
      return const SessionCheckResult(sinConexion: true);
    } catch (_) {
      Session.current = null;
      return const SessionCheckResult();
    }

    if (!response.ok) {
      await _limpiarLocal();
      Session.current = null;
      return const SessionCheckResult(sessionEnded: true);
    }

    final nuevaExpiracion = ahora.add(duracionSesion);
    await _secureStorage.write(key: _keyExpiraEn, value: nuevaExpiracion.toIso8601String());
    await _secureStorage.delete(key: _keyBackgroundedAt);

    final user = AuthUser(
      usuarioId: response.data['usuarioId'] as int,
      nombreUsuario: response.data['nombreUsuario'] as String,
      nombreCompleto: response.data['nombreCompleto'] as String,
    );
    Session.current = user;
    return SessionCheckResult(user: user);
  }

  Future<void> _cerrarSesionServidor(int usuarioId, String token) async {
    try {
      await ApiClient.instance.post(
        '/api/auth/logout',
        headers: _authHeaders(usuarioId, token),
        body: {'nombreUsuario': ''},
      );
    } catch (_) {
      // Si no hay conexión, no pasa nada: la sesión local ya se va a
      // limpiar de todos modos, y el servidor la expirará sola.
    }
  }

  /// Autentica con usuario/contraseña. Lanza [ArgumentError] con un mensaje
  /// seguro para mostrar directamente en la UI si falla por cualquier
  /// motivo (usuario inexistente, contraseña incorrecta, cuenta bloqueada
  /// o desactivada) — el servidor decide cuál mensaje exacto mandar.
  Future<AuthUser> login({required String nombreUsuario, required String password}) async {
    if (nombreUsuario.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('Ingresa tu usuario y contraseña.');
    }

    final response = await ApiClient.instance.post(
      '/api/auth/login',
      body: {'usuario': nombreUsuario, 'password': password},
    );

    if (!response.ok) {
      throw ArgumentError(response.data['error'] as String? ?? _mensajeCredencialesInvalidas);
    }

    final token = response.data['token'] as String;
    final usuarioId = response.data['usuarioId'] as int;
    final expiraEn = DateTime.parse(response.data['expiraEn'] as String);
    await _guardarLocalOLiberar(token: token, usuarioId: usuarioId, expiraEn: expiraEn);

    final user = AuthUser(
      usuarioId: usuarioId,
      nombreUsuario: response.data['nombreUsuario'] as String,
      nombreCompleto: response.data['nombreCompleto'] as String,
    );
    Session.current = user;
    return user;
  }

  Future<void> logout() async {
    final user = Session.current;
    final tokenLocal = await _secureStorage.read(key: _keyToken);
    if (user != null && tokenLocal != null) {
      try {
        await ApiClient.instance.post(
          '/api/auth/logout',
          headers: _authHeaders(user.usuarioId, tokenLocal),
          body: {'nombreUsuario': user.nombreUsuario},
        );
      } catch (_) {}
    }
    Session.current = null;
    await _limpiarLocal();
  }

  /// true si este dispositivo tiene guardada una credencial de "recordar"
  /// para desbloqueo biométrico (no confirma que siga siendo válida en el
  /// servidor; eso se valida recién al intentar [renovarSesionConBiometria]).
  Future<bool> tieneDispositivoRecordado() async {
    final token = await _secureStorage.read(key: _keyRecordarToken);
    return token != null;
  }

  /// Nombre completo guardado junto con la credencial de "recordar", para
  /// poder mostrar algo como "Continuar como Miguel Flores" antes de pedir
  /// la biometría, sin necesitar ninguna llamada al servidor todavía.
  Future<String?> nombreRecordado() => _secureStorage.read(key: _keyRecordarNombre);

  /// Activa el desbloqueo biométrico en este dispositivo para la sesión
  /// actual. Requiere que ya haya una sesión activa (se llama justo después
  /// de un login normal exitoso).
  Future<void> habilitarRecordarDispositivo() async {
    final user = Session.current;
    final tokenLocal = await _secureStorage.read(key: _keyToken);
    if (user == null || tokenLocal == null) {
      throw StateError('No hay una sesión activa.');
    }

    final response = await ApiClient.instance.post(
      '/api/auth/remember/enable',
      headers: _authHeaders(user.usuarioId, tokenLocal),
    );
    if (!response.ok) {
      throw StateError('No se pudo activar el desbloqueo biométrico.');
    }

    await _secureStorage.write(key: _keyRecordarToken, value: response.data['token'] as String);
    await _secureStorage.write(key: _keyRecordarUsuarioId, value: user.usuarioId.toString());
    await _secureStorage.write(key: _keyRecordarNombre, value: user.nombreCompleto);
  }

  /// Olvida este dispositivo: borra la credencial de "recordar" tanto local
  /// como del lado del servidor.
  Future<void> olvidarDispositivo() async {
    final token = await _secureStorage.read(key: _keyRecordarToken);
    final usuarioIdStr = await _secureStorage.read(key: _keyRecordarUsuarioId);
    final usuarioId = usuarioIdStr == null ? null : int.tryParse(usuarioIdStr);

    if (token != null && usuarioId != null) {
      try {
        await ApiClient.instance.post(
          '/api/auth/remember/disable',
          body: {'usuarioId': usuarioId, 'token': token},
        );
      } catch (_) {}
    }

    await _secureStorage.delete(key: _keyRecordarToken);
    await _secureStorage.delete(key: _keyRecordarUsuarioId);
    await _secureStorage.delete(key: _keyRecordarNombre);
  }

  /// Usa la credencial de "recordar" (ya confirmada por biometría del lado
  /// del sistema operativo, ver `BiometricService`) para generar una sesión
  /// nueva y legítima sin pedir usuario/contraseña. Devuelve `null` si no
  /// hay credencial guardada o si ya no es válida — en ese caso también la
  /// borra localmente.
  Future<AuthUser?> renovarSesionConBiometria() async {
    final tokenRecordado = await _secureStorage.read(key: _keyRecordarToken);
    final usuarioIdStr = await _secureStorage.read(key: _keyRecordarUsuarioId);
    if (tokenRecordado == null || usuarioIdStr == null) return null;

    final usuarioId = int.tryParse(usuarioIdStr);
    if (usuarioId == null) {
      await olvidarDispositivo();
      return null;
    }

    ApiResponse response;
    try {
      response = await ApiClient.instance.post(
        '/api/auth/remember/renew',
        body: {'usuarioId': usuarioId, 'recordarToken': tokenRecordado},
      );
    } catch (_) {
      return null;
    }

    if (!response.ok) {
      await olvidarDispositivo();
      return null;
    }

    final nuevoToken = response.data['token'] as String;
    final expiraEn = DateTime.parse(response.data['expiraEn'] as String);
    await _guardarLocalOLiberar(token: nuevoToken, usuarioId: usuarioId, expiraEn: expiraEn);

    // El token de "recordar" rota en cada uso: hay que guardar el nuevo o
    // el próximo desbloqueo biométrico ya no funcionaría.
    final nuevoRecordarToken = response.data['recordarToken'] as String;
    await _secureStorage.write(key: _keyRecordarToken, value: nuevoRecordarToken);

    final user = AuthUser(
      usuarioId: usuarioId,
      nombreUsuario: response.data['nombreUsuario'] as String,
      nombreCompleto: response.data['nombreCompleto'] as String,
    );
    Session.current = user;
    return user;
  }

  /// Desliza la expiración de la sesión activa otros 30 minutos (se llama
  /// periódicamente mientras hay actividad reciente en la app).
  Future<SessionCheckResult> refrescarActividad() => restoreSession();

  /// Cambia la contraseña del usuario logueado.
  Future<void> changePassword({required String actual, required String nueva}) async {
    final user = Session.current;
    final tokenLocal = await _secureStorage.read(key: _keyToken);
    if (user == null || tokenLocal == null) {
      throw StateError('No hay una sesión activa.');
    }

    final response = await ApiClient.instance.post(
      '/api/auth/change-password',
      headers: _authHeaders(user.usuarioId, tokenLocal),
      body: {'actual': actual, 'nueva': nueva},
    );

    if (!response.ok) {
      throw ArgumentError(response.data['error'] as String? ?? 'No se pudo cambiar la contraseña.');
    }

    // Cambiar la contraseña invalida cualquier desbloqueo biométrico ya
    // activado (el servidor ya borró la credencial); se limpia también
    // localmente por si este era el dispositivo recordado.
    await _secureStorage.delete(key: _keyRecordarToken);
    await _secureStorage.delete(key: _keyRecordarUsuarioId);
    await _secureStorage.delete(key: _keyRecordarNombre);
  }
}

