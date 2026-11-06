# Arypsa RH

App (iOS / Android) para que Recursos Humanos dé de alta personal, controle
quién puede checar y dónde, y vea el tablero del día. Hace pareja con
**Arypsa Checador** (`../app_rh_reloj_checador`).

| Pestaña | Qué hace |
|---|---|
| **Hoy** | Asistencia del día: % presentes, retardos, sin checar, alertas (fuera de geocerca, GPS simulado). Navega por días. |
| **Personal** | Alta/edición con foto, sede, turno, consentimiento. Ficha con códigos QR para *registrar huella* y *vincular celular*, checadas recientes y revisión de alertas. |
| **Sedes** | Geocercas (centro + radio, con "usar mi ubicación" o pegar coordenadas de Google Maps) y turnos (entrada, salida, tolerancia, días). |
| **Equipos** | Kioscos y celulares activos, última vez vistos, alta de kiosco nuevo, baja de equipos perdidos. |

## Cómo encaja todo

```
            Supabase (proyecto aparte: arypsa-rh)
     tablas rh_* con RLS  ·  funciones rh_* (security definer)
          ▲  usuario RH (Auth)            ▲  llave anon + id/secreto del equipo
          │                               │
   ┌──────┴───────┐               ┌───────┴──────────────────────────┐
   │  Arypsa RH   │ ── código ──▶ │  Arypsa Checador                  │
   │  (teléfono)  │   QR 1 uso    │  · Kiosco: tablet + lector USB    │
   └──────────────┘               │  · Celular: biometría + GPS       │
                                  └───────────────────────────────────┘
```

* **Huella en kiosco**: el lector USB (ZKTeco) saca una *plantilla*; la
  comparación 1:N se hace en la tablet. El servidor solo recibe "fue el
  empleado X". Funciona sin internet (cola local).
* **Celular**: el sensor del teléfono no entrega la huella, solo "el dueño se
  autenticó". Por eso el celular se **amarra a un empleado** con un código de
  RH y cada checada exige biometría del teléfono + GPS dentro de una geocerca.
* El servidor decide entrada/salida, sede, distancia, retardo y estado
  (`valida`, `fuera_geocerca`, `revisar`, `anulada`).

## Puesta en marcha (una sola vez)

1. **Supabase**: crear un proyecto nuevo (recomendado, separado del portal).
   SQL Editor → correr `supabase/001_reloj_checador.sql`.
2. Authentication → Users → *Add user* (cuenta de RH). Luego, en SQL:
   ```sql
   insert into rh_perfiles (user_id, nombre, rol)
   select id, 'Recursos Humanos', 'admin' from auth.users where email = 'rh@arypsa.com';
   ```
   Y apagar *Allow new users to sign up*.
3. Copiar `supabase.json.example` a `supabase.json` (no se sube a git) con la
   URL y la llave **anon** de Settings → API. Mismo archivo en las dos apps.
4. `bash preparar.sh` — genera android/ios, permisos, íconos, `pub get`,
   `analyze` y `test`. Todo queda en `preparar.log`.

## Correr / compilar

```bash
flutter run --dart-define-from-file=supabase.json
flutter build apk --release --dart-define-from-file=supabase.json
flutter build ipa --dart-define-from-file=supabase.json    # requiere Xcode
```

En iOS: abrir `ios/Runner.xcworkspace`, elegir el *Team* de firma y, si
CocoaPods se queja de la versión mínima, poner `platform :ios, '15.5'` en
`ios/Podfile`.

## Flujo diario de RH

1. **Alta**: Personal → Alta. Foto, datos, sede, turno, y marcar el
   consentimiento cuando el empleado firme el aviso impreso (la huella es dato
   sensible, LFPDPPP).
2. **Huella**: en su ficha → *Registrar huella* → QR. En el kiosco: logo
   presionado 3 s → *Registrar huella* → escanear → 3 lecturas por dedo
   (mejor dos dedos).
3. **Administrativos**: tipo *Kiosco + celular* → *Vincular celular* → QR que
   el empleado escanea con Arypsa Checador en su teléfono.
4. **Baja**: menú de la ficha → *Dar de baja*. Borra huellas, corta equipos y
   conserva las checadas.
