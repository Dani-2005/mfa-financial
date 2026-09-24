/// Usuario administrador autenticado. A diferencia de la app (donde vive un
/// `Session.current` global, correcto ahí porque solo hay un usuario a la
/// vez en el dispositivo), en el servidor este valor SIEMPRE se resuelve
/// por petición HTTP a partir del token recibido y se pasa explícitamente
/// como parámetro — nunca como una variable global — porque el servidor
/// atiende peticiones de distintos usuarios en paralelo, y un global
/// mutable se mezclaría entre peticiones concurrentes.
class AuthUser {
  final int usuarioId;
  final String nombreUsuario;
  final String nombreCompleto;

  const AuthUser({
    required this.usuarioId,
    required this.nombreUsuario,
    required this.nombreCompleto,
  });
}
