import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auditoria_service.dart';
import 'database_service.dart';
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

  const SessionCheckResult({this.user, this.sessionEnded = false});
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const int _maxIntentosFallidos = 5;
  static const Duration _duracionBloqueo = Duration(minutes: 15);

  /// Tiempo de inactividad (o de app cerrada) tras el cual la sesión se
  /// considera terminada. Es deslizante: cualquier actividad detectada la
  /// extiende de nuevo, tanto en el dispositivo como en el servidor.
  static const Duration duracionSesion = Duration(minutes: 30);

  /// Vigencia del "recordar este dispositivo" para desbloqueo biométrico:
  /// mucho más larga que la sesión activa (también deslizante, se renueva
  /// en cada desbloqueo exitoso), porque no reemplaza el control de
  /// inactividad/cierre — solo evita tener que volver a escribir la
  /// contraseña, y cada desbloqueo con huella/Face ID sigue generando una
  /// sesión nueva y legítima sujeta a las mismas reglas de siempre.
  static const Duration duracionRecordarDispositivo = Duration(days: 30);

  static const String _keyToken = 'session_token';
  static const String _keyUsuarioId = 'session_usuario_id';
  static const String _keyExpiraEn = 'session_expira_en';
  static const String _keyBackgroundedAt = 'session_backgrounded_at';

  static const String _keyRecordarToken = 'recordar_token';
  static const String _keyRecordarUsuarioId = 'recordar_usuario_id';
  static const String _keyRecordarNombre = 'recordar_nombre_completo';

  final AuditoriaService _auditoria = AuditoriaService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Genera un token de sesión aleatorio y criptográficamente seguro (32
  /// bytes). Solo vive cifrado en el dispositivo; en la base de datos jamás
  /// se guarda el token en sí, solo su hash.
  String _generarToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

  Future<void> _guardarLocal({required String token, required int usuarioId, required DateTime expiraEn}) async {
    await _secureStorage.write(key: _keyToken, value: token);
    await _secureStorage.write(key: _keyUsuarioId, value: usuarioId.toString());
    await _secureStorage.write(key: _keyExpiraEn, value: expiraEn.toIso8601String());
    await _secureStorage.delete(key: _keyBackgroundedAt);
  }

  Future<void> _limpiarLocal() async {
    await _secureStorage.delete(key: _keyToken);
    await _secureStorage.delete(key: _keyUsuarioId);
    await _secureStorage.delete(key: _keyExpiraEn);
    await _secureStorage.delete(key: _keyBackgroundedAt);
  }

  /// Borra el token del lado del servidor (solo si sigue siendo el nuestro,
  /// para no borrar por accidente una sesión más nueva de otro dispositivo).
  Future<void> _destruirTokenServidor(int usuarioId, String tokenHash) async {
    await DatabaseService.instance.query(
      'DELETE FROM sesiones WHERE usuario_id = :id AND token_hash = :hash',
      {'id': usuarioId, 'hash': tokenHash},
    );
  }

  /// Marca el momento en que la app pasó a segundo plano/se cerró, para
  /// poder calcular al reabrir si pasaron más de [duracionSesion] minutos.
  Future<void> marcarSegundoPlano() async {
    if (Session.current == null) return;
    await _secureStorage.write(key: _keyBackgroundedAt, value: DateTime.now().toIso8601String());
  }

  /// Restaura la sesión al reabrir la app a partir del token guardado
  /// cifrado en el dispositivo (`flutter_secure_storage`); la contraseña
  /// real nunca se guarda ahí, solo queda como hash bcrypt en la base de
  /// datos. Ese token es la única credencial de sesión y por eso jamás se
  /// envía ni se guarda en texto plano del lado del servidor (solo su
  /// hash SHA-256), igual que una contraseña.
  ///
  /// Valida el token guardado localmente contra la única sesión activa
  /// permitida por cuenta en la base de datos: si expiró, si pasaron más de 30 minutos
  /// desde que se cerró la app, o si se inició sesión con la misma cuenta
  /// en otro dispositivo (lo que reemplaza el token anterior), la sesión
  /// local se destruye y no se puede continuar sin volver a autenticarse.
  ///
  /// Este mismo método se usa tanto al abrir la app como para revalidar
  /// periódicamente una sesión ya en curso (ver `SessionActivityGuard`).
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
    final hashLocal = _hashToken(tokenLocal);

    // 30 minutos después de haberse ido a segundo plano/cerrado la app.
    final backgroundedAtStr = await _secureStorage.read(key: _keyBackgroundedAt);
    if (backgroundedAtStr != null) {
      final backgroundedAt = DateTime.tryParse(backgroundedAtStr);
      if (backgroundedAt == null || ahora.difference(backgroundedAt) > duracionSesion) {
        await _destruirTokenServidor(usuarioId, hashLocal);
        await _limpiarLocal();
        Session.current = null;
        return const SessionCheckResult(sessionEnded: true);
      }
    }

    // 30 minutos de inactividad ya reflejados en la expiración local.
    if (ahora.isAfter(expiraEnLocal)) {
      await _destruirTokenServidor(usuarioId, hashLocal);
      await _limpiarLocal();
      Session.current = null;
      return const SessionCheckResult(sessionEnded: true);
    }

    final result = await DatabaseService.instance.query(
      'SELECT s.token_hash, s.expira_en, u.usuario_id, u.nombre_usuario, u.nombre_completo, u.activo '
      'FROM sesiones s JOIN usuarios u ON u.usuario_id = s.usuario_id '
      'WHERE s.usuario_id = :id',
      {'id': usuarioId},
    );

    if (result.rows.isEmpty) {
      // Ya no existe del lado del servidor: se cerró sesión desde otro
      // lugar o fue purgada por expiración.
      await _limpiarLocal();
      Session.current = null;
      return const SessionCheckResult(sessionEnded: true);
    }

    final f = result.rows.first.typedAssoc();
    final tokenHashServidor = f['token_hash'] as String;
    final expiraEnServidor = f['expira_en'] as DateTime;
    final activo = f['activo'] as bool;

    if (!activo || tokenHashServidor != hashLocal || ahora.isAfter(expiraEnServidor)) {
      // Cuenta desactivada, sesión reemplazada por otro inicio de sesión, o
      // expiró del lado del servidor: en cualquier caso, la sesión local ya
      // no es válida y no se revela cuál de los tres motivos fue.
      await _limpiarLocal();
      Session.current = null;
      return const SessionCheckResult(sessionEnded: true);
    }

    // Sesión válida: se desliza la expiración 30 minutos más, tanto en el
    // servidor como localmente.
    final nuevaExpiracion = ahora.add(duracionSesion);
    await DatabaseService.instance.query(
      'UPDATE sesiones SET expira_en = :exp WHERE usuario_id = :id AND token_hash = :hash',
      {'exp': _formatDateTime(nuevaExpiracion), 'id': usuarioId, 'hash': hashLocal},
    );
    await _secureStorage.write(key: _keyExpiraEn, value: nuevaExpiracion.toIso8601String());
    await _secureStorage.delete(key: _keyBackgroundedAt);

    final user = AuthUser(
      usuarioId: f['usuario_id'] as int,
      nombreUsuario: f['nombre_usuario'] as String,
      nombreCompleto: f['nombre_completo'] as String,
    );
    Session.current = user;
    return SessionCheckResult(user: user);
  }

  /// Autentica con usuario/contraseña. Lanza [ArgumentError] con un mensaje
  /// seguro para mostrar directamente en la UI si falla por cualquier
  /// motivo (usuario inexistente, contraseña incorrecta, cuenta bloqueada
  /// o desactivada). El bloqueo tras varios intentos fallidos (más abajo)
  /// funciona como límite de intentos (rate limiting) para el login.
  Future<AuthUser> login({required String nombreUsuario, required String password}) async {
    final usuario = nombreUsuario.trim().toLowerCase();
    if (usuario.isEmpty || password.isEmpty) {
      throw ArgumentError('Ingresa tu usuario y contraseña.');
    }

    final result = await DatabaseService.instance.query(
      'SELECT usuario_id, nombre_usuario, nombre_completo, password_hash, intentos_fallidos, '
      'bloqueado_hasta, activo FROM usuarios WHERE nombre_usuario = :usuario',
      {'usuario': usuario},
    );

    if (result.rows.isEmpty) {
      // Se calcula un hash de todos modos para que el tiempo de respuesta
      // sea parecido al de un usuario que sí existe (mitiga enumeración por
      // temporización).
      BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));
      throw ArgumentError(_mensajeCredencialesInvalidas);
    }

    final f = result.rows.first.typedAssoc();
    final usuarioId = f['usuario_id'] as int;
    final activo = f['activo'] as bool;
    final bloqueadoHasta = f['bloqueado_hasta'] as DateTime?;
    final intentosFallidos = f['intentos_fallidos'] as int;
    final hash = f['password_hash'] as String;

    if (!activo) {
      throw ArgumentError(_mensajeCredencialesInvalidas);
    }

    if (bloqueadoHasta != null && bloqueadoHasta.isAfter(DateTime.now())) {
      final minutos = bloqueadoHasta.difference(DateTime.now()).inMinutes + 1;
      throw ArgumentError(
        'Cuenta bloqueada temporalmente por demasiados intentos fallidos. '
        'Intenta de nuevo en $minutos minuto${minutos == 1 ? '' : 's'}.',
      );
    }

    if (!BCrypt.checkpw(password, hash)) {
      final nuevosIntentos = intentosFallidos + 1;
      final seBloquea = nuevosIntentos >= _maxIntentosFallidos;

      await DatabaseService.instance.query(
        'UPDATE usuarios SET intentos_fallidos = :intentos, bloqueado_hasta = :bloqueo WHERE usuario_id = :id',
        {
          'intentos': seBloquea ? 0 : nuevosIntentos,
          'bloqueo': seBloquea ? _formatDateTime(DateTime.now().add(_duracionBloqueo)) : null,
          'id': usuarioId,
        },
      );
      await _auditoria.log(
        tablaAfectada: 'usuarios',
        registroId: usuario,
        accion: 'UPDATE',
        datosNuevos: {
          'evento': seBloquea ? 'cuenta bloqueada por intentos fallidos' : 'intento de login fallido',
          'intentos_fallidos': seBloquea ? 0 : nuevosIntentos,
        },
      );

      if (seBloquea) {
        throw ArgumentError(
          'Cuenta bloqueada temporalmente por demasiados intentos fallidos. Intenta de nuevo en 15 minutos.',
        );
      }
      throw ArgumentError(_mensajeCredencialesInvalidas);
    }

    await DatabaseService.instance.query(
      'UPDATE usuarios SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_login = NOW() '
      'WHERE usuario_id = :id',
      {'id': usuarioId},
    );

    // Nuevo token de sesión: al reemplazar (UPSERT) cualquier fila anterior
    // de este usuario en `sesiones`, cualquier sesión que estuviera abierta
    // en otro dispositivo con esta misma cuenta queda invalidada de
    // inmediato (solo una sesión activa por cuenta).
    final token = _generarToken();
    final tokenHash = _hashToken(token);
    final expiraEn = DateTime.now().add(duracionSesion);
    await DatabaseService.instance.query(
      'INSERT INTO sesiones (usuario_id, token_hash, expira_en) VALUES (:id, :hash, :exp) '
      'ON DUPLICATE KEY UPDATE token_hash = :hash, expira_en = :exp, creado_en = CURRENT_TIMESTAMP',
      {'id': usuarioId, 'hash': tokenHash, 'exp': _formatDateTime(expiraEn)},
    );
    await _guardarLocal(token: token, usuarioId: usuarioId, expiraEn: expiraEn);

    final user = AuthUser(
      usuarioId: usuarioId,
      nombreUsuario: f['nombre_usuario'] as String,
      nombreCompleto: f['nombre_completo'] as String,
    );
    Session.current = user;

    await _auditoria.log(
      tablaAfectada: 'usuarios',
      registroId: usuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'login exitoso'},
    );

    return user;
  }

  Future<void> logout() async {
    final user = Session.current;
    if (user != null) {
      final tokenLocal = await _secureStorage.read(key: _keyToken);
      if (tokenLocal != null) {
        await _destruirTokenServidor(user.usuarioId, _hashToken(tokenLocal));
      }
      await _auditoria.log(
        tablaAfectada: 'usuarios',
        registroId: user.nombreUsuario,
        accion: 'UPDATE',
        datosNuevos: {'evento': 'logout'},
      );
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
  /// la biometría, sin necesitar ninguna consulta a la base todavía.
  Future<String?> nombreRecordado() => _secureStorage.read(key: _keyRecordarNombre);

  /// Activa el desbloqueo biométrico en este dispositivo para la sesión
  /// actual: genera una credencial nueva y de larga duración (30 días,
  /// deslizante), reemplazando (UPSERT) cualquier credencial anterior de
  /// esta misma cuenta — igual que con la sesión, solo un dispositivo
  /// recordado a la vez por cuenta. Requiere que ya haya una sesión activa
  /// (se llama justo después de un login normal exitoso).
  Future<void> habilitarRecordarDispositivo() async {
    final user = Session.current;
    if (user == null) {
      throw StateError('No hay una sesión activa.');
    }

    final token = _generarToken();
    final tokenHash = _hashToken(token);
    final expiraEn = DateTime.now().add(duracionRecordarDispositivo);

    await DatabaseService.instance.query(
      'INSERT INTO recordar_dispositivo (usuario_id, token_hash, expira_en) VALUES (:id, :hash, :exp) '
      'ON DUPLICATE KEY UPDATE token_hash = :hash, expira_en = :exp, creado_en = CURRENT_TIMESTAMP',
      {'id': user.usuarioId, 'hash': tokenHash, 'exp': _formatDateTime(expiraEn)},
    );

    await _secureStorage.write(key: _keyRecordarToken, value: token);
    await _secureStorage.write(key: _keyRecordarUsuarioId, value: user.usuarioId.toString());
    await _secureStorage.write(key: _keyRecordarNombre, value: user.nombreCompleto);

    await _auditoria.log(
      tablaAfectada: 'usuarios',
      registroId: user.nombreUsuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'desbloqueo biométrico activado en un dispositivo'},
    );
  }

  /// Olvida este dispositivo: borra la credencial de "recordar" tanto local
  /// como del lado del servidor (solo si sigue siendo la misma, para no
  /// afectar por accidente una más nueva de otro dispositivo). Se puede
  /// llamar con o sin sesión activa (p. ej. desde el propio login, o al
  /// cerrar sesión con la opción de "olvidar este dispositivo").
  Future<void> olvidarDispositivo() async {
    final token = await _secureStorage.read(key: _keyRecordarToken);
    final usuarioIdStr = await _secureStorage.read(key: _keyRecordarUsuarioId);
    final usuarioId = usuarioIdStr == null ? null : int.tryParse(usuarioIdStr);

    if (token != null && usuarioId != null) {
      await DatabaseService.instance.query(
        'DELETE FROM recordar_dispositivo WHERE usuario_id = :id AND token_hash = :hash',
        {'id': usuarioId, 'hash': _hashToken(token)},
      );
    }

    await _secureStorage.delete(key: _keyRecordarToken);
    await _secureStorage.delete(key: _keyRecordarUsuarioId);
    await _secureStorage.delete(key: _keyRecordarNombre);
  }

  /// Usa la credencial de "recordar" (ya confirmada por biometría del lado
  /// del sistema operativo, ver `BiometricService`) para generar una sesión
  /// nueva y legítima sin pedir usuario/contraseña — exactamente el mismo
  /// token de sesión, con la misma expiración deslizante de 30 minutos y el
  /// mismo control de una sola sesión activa que un login normal. Nunca
  /// evita el bloqueo por intentos fallidos ni una cuenta desactivada.
  ///
  /// Devuelve `null` si no hay credencial guardada o si ya no es válida
  /// (expiró, la reemplazó otro dispositivo, o la cuenta está bloqueada o
  /// desactivada) — en ese caso también la borra localmente, para que la
  /// pantalla de login vuelva a mostrar el formulario normal en vez de
  /// insistir con la biometría.
  Future<AuthUser?> renovarSesionConBiometria() async {
    final tokenRecordado = await _secureStorage.read(key: _keyRecordarToken);
    final usuarioIdStr = await _secureStorage.read(key: _keyRecordarUsuarioId);
    if (tokenRecordado == null || usuarioIdStr == null) return null;

    final usuarioId = int.tryParse(usuarioIdStr);
    if (usuarioId == null) {
      await olvidarDispositivo();
      return null;
    }

    final hashRecordado = _hashToken(tokenRecordado);
    final result = await DatabaseService.instance.query(
      'SELECT r.token_hash, r.expira_en, u.usuario_id, u.nombre_usuario, u.nombre_completo, '
      'u.activo, u.bloqueado_hasta '
      'FROM recordar_dispositivo r JOIN usuarios u ON u.usuario_id = r.usuario_id '
      'WHERE r.usuario_id = :id',
      {'id': usuarioId},
    );

    if (result.rows.isEmpty) {
      await olvidarDispositivo();
      return null;
    }

    final f = result.rows.first.typedAssoc();
    final ahora = DateTime.now();
    final activo = f['activo'] as bool;
    final bloqueadoHasta = f['bloqueado_hasta'] as DateTime?;
    final expiraEn = f['expira_en'] as DateTime;
    final valido = f['token_hash'] == hashRecordado &&
        activo &&
        (bloqueadoHasta == null || bloqueadoHasta.isBefore(ahora)) &&
        expiraEn.isAfter(ahora);

    if (!valido) {
      await olvidarDispositivo();
      return null;
    }

    // Válida: se renueva por otros 30 días (deslizante) y se emite una
    // sesión nueva, con el mismo mecanismo (y las mismas garantías) que
    // un login con usuario/contraseña.
    final nuevoToken = _generarToken();
    final nuevoHash = _hashToken(nuevoToken);
    final nuevaExpiracionRecordar = ahora.add(duracionRecordarDispositivo);
    await DatabaseService.instance.query(
      'UPDATE recordar_dispositivo SET token_hash = :hash, expira_en = :exp WHERE usuario_id = :id',
      {'hash': nuevoHash, 'exp': _formatDateTime(nuevaExpiracionRecordar), 'id': usuarioId},
    );
    await _secureStorage.write(key: _keyRecordarToken, value: nuevoToken);

    final sesionToken = _generarToken();
    final sesionHash = _hashToken(sesionToken);
    final sesionExpiraEn = ahora.add(duracionSesion);
    await DatabaseService.instance.query(
      'INSERT INTO sesiones (usuario_id, token_hash, expira_en) VALUES (:id, :hash, :exp) '
      'ON DUPLICATE KEY UPDATE token_hash = :hash, expira_en = :exp, creado_en = CURRENT_TIMESTAMP',
      {'id': usuarioId, 'hash': sesionHash, 'exp': _formatDateTime(sesionExpiraEn)},
    );
    await _guardarLocal(token: sesionToken, usuarioId: usuarioId, expiraEn: sesionExpiraEn);

    final user = AuthUser(
      usuarioId: f['usuario_id'] as int,
      nombreUsuario: f['nombre_usuario'] as String,
      nombreCompleto: f['nombre_completo'] as String,
    );
    Session.current = user;

    await _auditoria.log(
      tablaAfectada: 'usuarios',
      registroId: user.nombreUsuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'login exitoso mediante biometría'},
    );

    return user;
  }

  /// Desliza la expiración de la sesión activa otros 30 minutos (se llama
  /// periódicamente mientras hay actividad reciente en la app). Si la
  /// sesión ya no es la vigente en el servidor (p. ej. porque se inició
  /// sesión en otro dispositivo), no la reactiva: devuelve el resultado de
  /// [restoreSession] para que quien llame pueda forzar el cierre de
  /// sesión con el aviso genérico correspondiente.
  Future<SessionCheckResult> refrescarActividad() => restoreSession();

  /// Cambia la contraseña del usuario logueado. Exige la contraseña actual
  /// correcta y una nueva contraseña que cumpla el mínimo de seguridad.
  Future<void> changePassword({required String actual, required String nueva}) async {
    final user = Session.current;
    if (user == null) {
      throw StateError('No hay una sesión activa.');
    }

    if (nueva.length < 8) {
      throw ArgumentError('La nueva contraseña debe tener al menos 8 caracteres.');
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(nueva) || !RegExp(r'[0-9]').hasMatch(nueva)) {
      throw ArgumentError('La nueva contraseña debe combinar letras y números.');
    }

    final result = await DatabaseService.instance.query(
      'SELECT password_hash FROM usuarios WHERE usuario_id = :id',
      {'id': user.usuarioId},
    );
    final hashActual = result.rows.first.typedAssoc()['password_hash'] as String;

    if (!BCrypt.checkpw(actual, hashActual)) {
      throw ArgumentError('La contraseña actual no es correcta.');
    }
    if (BCrypt.checkpw(nueva, hashActual)) {
      throw ArgumentError('La nueva contraseña debe ser diferente a la actual.');
    }

    final nuevoHash = BCrypt.hashpw(nueva, BCrypt.gensalt(logRounds: 12));
    await DatabaseService.instance.query(
      'UPDATE usuarios SET password_hash = :hash WHERE usuario_id = :id',
      {'hash': nuevoHash, 'id': user.usuarioId},
    );

    // Cambiar la contraseña invalida cualquier desbloqueo biométrico ya
    // activado (en este dispositivo o en cualquier otro): si el cambio fue
    // por una sospecha de seguridad, no debe quedar un atajo biométrico
    // basado en la confianza anterior.
    await DatabaseService.instance.query(
      'DELETE FROM recordar_dispositivo WHERE usuario_id = :id',
      {'id': user.usuarioId},
    );
    await _secureStorage.delete(key: _keyRecordarToken);
    await _secureStorage.delete(key: _keyRecordarUsuarioId);
    await _secureStorage.delete(key: _keyRecordarNombre);

    await _auditoria.log(
      tablaAfectada: 'usuarios',
      registroId: user.nombreUsuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'contraseña actualizada por el propio usuario'},
    );
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
