#!/bin/bash
# Prepara el proyecto en la Mac: genera android/ e ios/, aplica permisos,
# baja paquetes, genera íconos y revisa el código. Todo queda en preparar.log.
#
#   cd ~/Proyectos/<carpeta> && bash preparar.sh
#
cd "$(dirname "$0")" || exit 1
APP=$(basename "$PWD")
case "$APP" in
  app_rh_alta) NOMBRE=arypsa_rh ;;
  app_rh_reloj_checador) NOMBRE=arypsa_checador ;;
  *) echo "Carpeta desconocida: $APP"; exit 1 ;;
esac

exec > >(tee preparar.log) 2>&1
echo "== $APP · $(date '+%Y-%m-%d %H:%M')"
command -v flutter >/dev/null || { echo "No encuentro flutter en el PATH"; exit 1; }
flutter --version | head -1

if [ ! -d android ] || [ ! -d ios ]; then
  echo "== flutter create (solo crea lo que falta; no toca lib/ ni pubspec.yaml)"
  flutter create --org com.arypsa --project-name "$NOMBRE" --platforms android,ios --no-pub . || exit 1
fi

echo "== parches"
python3 parches.py || exit 1

echo "== pub get"
flutter pub get || exit 1

echo "== iconos"
dart run flutter_launcher_icons >/dev/null 2>&1 && echo "ok" || echo "(no se generaron íconos; no es grave)"

if [ -f ../app_scanner_arypsa/revisar_dart.py ]; then
  echo "== revisar_dart.py"
  python3 ../app_scanner_arypsa/revisar_dart.py lib
fi

echo "== flutter analyze"
flutter analyze --no-fatal-infos
echo "== flutter test"
flutter test
echo "== FIN"
