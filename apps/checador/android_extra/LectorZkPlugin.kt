package com.arypsa.checador

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Puente con el lector de huella ZKTeco por USB (SLK20R / ZK9500 / Live20R).
 *
 * Contrato del canal "arypsa/lector_zk": ver lib/lector/lector_zk.dart.
 *
 * ESTADO: esqueleto. Mientras el SDK del fabricante no esté en android/app/libs,
 * "disponible" responde false y la app trabaja en MODO PRUEBA (lector
 * simulado). Para integrarlo:
 *
 *   1. Pedir a ZKTeco / al distribuidor el "ZKFinger SDK for Android"
 *      (zkandroidcore.jar, zkandroidfpsensor.jar y las .so por ABI).
 *   2. Copiar los .jar a android/app/libs y las .so a android/app/src/main/jniLibs/<abi>/.
 *   3. En android/app/build.gradle(.kts): implementation(fileTree("libs") { include("*.jar") })
 *   4. Rellenar los TODO de abajo con las llamadas del SDK (FingerprintSensor,
 *      ZKFingerService.verify/identify/merge). Las plantillas viajan en base64.
 *   5. Correr las pruebas del README › "Lector de huella".
 *
 * Todo lo que bloquea esperando un dedo corre en un hilo aparte: nunca en el
 * hilo principal de Android.
 */
class LectorZkPlugin private constructor(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        fun registrar(context: Context, messenger: BinaryMessenger) {
            MethodChannel(messenger, "arypsa/lector_zk").setMethodCallHandler(LectorZkPlugin(context.applicationContext))
        }
    }

    /** true cuando el SDK está integrado (cambiar al terminar el paso 4). */
    private val sdkIntegrado = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "disponible") {
            // TODO(SDK): además de sdkIntegrado, revisar que haya un lector
            // conectado (UsbManager.deviceList con el vendorId de ZKTeco 0x1b55).
            result.success(sdkIntegrado)
            return
        }
        if (!sdkIntegrado) {
            result.error("sdk", "El SDK del lector ZKTeco aún no está integrado en este APK.", null)
            return
        }
        when (call.method) {
            // TODO(SDK): abrir el sensor (pedir permiso USB si hace falta) e
            //            inicializar el motor de comparación 1:N.
            "abrir" -> result.notImplemented()
            // TODO(SDK): limpiar la base en memoria y agregar cada
            //            {id, plantilla(base64)}; responder cuántas se cargaron.
            "cargar" -> result.notImplemented()
            // TODO(SDK): esperar un dedo, identificar 1:N; responder
            //            mapOf("id" to id, "puntaje" to score) o null si no hay coincidencia.
            "identificar" -> result.notImplemented()
            // TODO(SDK): una captura; responder mapOf("plantilla" to b64, "calidad" to q).
            "capturar" -> result.notImplemented()
            // TODO(SDK): unir 3 capturas (merge) en la plantilla de registro.
            "combinar" -> result.notImplemented()
            // TODO(SDK): soltar la espera en curso con result.error("cancelado", …).
            "cancelar" -> result.success(null)
            "cerrar" -> result.success(null)
            else -> result.notImplemented()
        }
    }
}
