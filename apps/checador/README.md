# Arypsa Checador

Reloj checador de Arypsa. Una sola app con dos modos, que se decide al
activarla con el código QR que genera **Arypsa RH** (`../app_rh_alta`):

| Modo | Equipo | Cómo identifica | Ubicación |
|---|---|---|---|
| **Kiosco** | Tablet / handheld Android fija, con lector USB-OTG | Huella en el lector, 1:N contra todo el personal | GPS cada 5 min (detecta si se lo llevan) |
| **Mi celular** | Teléfono del administrativo (Android o iPhone) | Huella / Face ID del propio teléfono, amarrado al empleado | GPS fresco en cada checada; solo dentro de la geocerca |

El esquema de base de datos está en `../app_rh_alta/supabase/001_reloj_checador.sql`.

## Kiosco

* Pantalla oscura con reloj grande, círculo del lector siempre escuchando y
  confirmación a pantalla completa con foto, ENTRADA/SALIDA, hora y retardo.
* **Sin internet sigue checando**: reconoce contra la copia local del personal
  y guarda la checada; se envía sola al volver la red (cada una lleva un
  `cliente_id`, así que reintentar nunca duplica).
* Menú de administración: **mantener presionado el logo 3 segundos** →
  Registrar huella · Sincronizar · Enviar pendientes · Cambiar lector.
* Pantalla siempre encendida y modo inmersivo. Para que nadie salga de la
  app, activar *Fijar pantalla* (Android) o un MDM en modo kiosco.

## Celular

Botón grande que solo se habilita dentro de la geocerca de una sede. Al
tocarlo pide huella/Face ID, toma GPS fresco, revisa la geocerca y envía. Si
el teléfono reporta ubicación simulada, la checada queda *en revisión* para RH.

## Lector de huella

Hoy el APK trabaja en **MODO PRUEBA**: un teclado donde el número de empleado
hace de dedo. Todo el flujo (registro, checada, offline, tablero de RH) se
prueba así sin hardware.

Lector recomendado: **ZKTeco SLK20R** (o ZK9500 / Live20R), USB, con SDK para
Android. Para integrarlo:

1. Pedir al distribuidor el *ZKFinger SDK for Android*.
2. `.jar` → `android/app/libs/`, `.so` → `android/app/src/main/jniLibs/<abi>/`.
3. Llenar los `TODO(SDK)` de `LectorZkPlugin.kt` y poner `sdkIntegrado = true`.
   El contrato del canal está documentado en `lib/lector/lector_zk.dart`.
4. En el kiosco: logo 3 s → *Usar lector ZKTeco*. Las huellas de prueba
   (formato `sim`) no sirven con el lector real: hay que registrar de nuevo.

## Correr / compilar

```bash
bash preparar.sh                                   # una vez (genera android/ios, permisos, íconos)
flutter run --dart-define-from-file=supabase.json
flutter build apk --release --dart-define-from-file=supabase.json
```

`supabase.json` es el mismo de Arypsa RH (URL + llave anon).

## Reconocimiento facial con IA

El kiosco reconoce caras con la cámara frontal, **dentro de la tablet** (sin
nube, funciona sin internet):

1. **Google ML Kit** detecta la cara y revisa que esté de frente, cerca y con luz.
2. **MobileFaceNet** (TensorFlow Lite, `assets/models/`) la convierte en un
   vector de 192 números. Eso es lo que se guarda en `rh_rostros`; la foto no.
3. Se compara contra todo el personal; hace falta coincidir en 2 lecturas
   seguidas y pasar la **prueba de vida** (parpadear o girar un poco la
   cabeza) para que no se pueda checar con una foto.

Modo por sede (app de RH › Sedes): *Rostro o huella*, *Rostro con huella de
respaldo* (default) o *Rostro y huella* (doble factor). La exigencia del
reconocimiento (umbral, 0.85 por default) también se ajusta por sede.

Registro: logo 3 s › *Registrar rostro / huella* › QR de RH › 5 tomas
automáticas. Las miniaturas que aparecen sirven para revisar que el recorte de
la cara salga derecho.

Diagnóstico: en la consola (`flutter run` o `adb logcat`) salen líneas
`[Rostro] mejor=… d=0.62 2da=1.05 umbral=0.85 → OK`. Si personas distintas
dan distancias menores a ~0.9, bajar el umbral; si la misma persona da más de
0.85, subirlo.

Requiere `sql/002_reconocimiento_facial.sql` (está en
`../app_rh_alta/supabase/`) y Android 8.0+ en la tablet.
