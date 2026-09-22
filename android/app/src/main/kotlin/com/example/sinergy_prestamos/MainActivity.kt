package com.example.sinergy_prestamos

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (en vez de FlutterActivity) porque local_auth
// necesita un FragmentActivity para mostrar el diálogo de huella/rostro
// (androidx.biometric.BiometricPrompt).
class MainActivity : FlutterFragmentActivity()
