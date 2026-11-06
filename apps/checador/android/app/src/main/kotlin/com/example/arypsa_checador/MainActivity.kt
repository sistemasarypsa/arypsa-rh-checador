package com.example.arypsa_checador

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity (no FlutterActivity): lo exige local_auth para
// mostrar el diálogo de huella del sistema.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LectorZkPlugin.registrar(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
