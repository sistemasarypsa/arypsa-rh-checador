# Arypsa RH + Checador

Sistema de control de personal de Arypsa: dos apps Flutter que comparten una
base de datos en Supabase.

| App | Carpeta | Para qué |
|---|---|---|
| **Arypsa RH** | `apps/rh` | Recursos Humanos: altas, expedientes, turnos, asistencia, permisos, dashboard |
| **Arypsa Checador** | `apps/checador` | Tablet de planta: identifica por rostro / huella / número y registra entradas y salidas |

## Estructura

```
apps/
  rh/                 App de RH (su propio código, Android, ícono y APK)
  checador/           App del checador (su propio código, Android, ícono y APK)
packages/             Código compartido por las dos apps (en construcción)
supabase/
  migrations/         Cambios de la base de datos, en orden (001, 002, ...)
pubspec.yaml          Agrupa las apps (pub workspace); un solo pubspec.lock
```

Reglas:
- Una app nunca importa código de la otra; lo que usan las dos va en `packages/`.
- Commits con prefijo: `rh:`, `checador:`, `core:`, `db:`, `repo:`.

## Requisitos

Flutter estable (3.35 o más reciente), Android Studio con el SDK y el NDK que
pida Flutter, y un teléfono o tablet Android con depuración USB.

## Correr

Desde la raíz del repo:

```bash
flutter pub get            # una vez, instala lo de las dos apps
cd apps/rh                 # o apps/checador
flutter run
```

Compilar APK: `flutter build apk --release` dentro de la carpeta de la app.
Queda en `build/app/outputs/flutter-apk/app-release.apk`.

## Base de datos

Proyecto de Supabase `arypsa-rh`. Los scripts de `supabase/migrations/` se
corren en orden en el SQL Editor; todos se pueden volver a correr sin romper
nada.
