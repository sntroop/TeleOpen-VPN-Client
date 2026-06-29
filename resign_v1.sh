#!/bin/bash
# Ручная переподпись APK со ВСЕМИ схемами (v1+v2+v3) — на случай, когда нужен
# v1 (JAR) для совсем старых Android (<7.0). Обычная flutter-сборка даёт v2+v3,
# чего достаточно при minSdk=24, так что этот скрипт нужен редко.
#
# Пароль keystore НЕ хранится в скрипте (он попал бы в git-историю). Берём из
# окружения. Можно подхватить из android/key.properties, который не в гите.
#
# Запуск:
#   KEYSTORE_PASS='...' ./resign_v1.sh
# либо, если пароль лежит в android/key.properties (storePassword=...):
#   ./resign_v1.sh        # сам прочитает оттуда
set -euo pipefail
cd /root/my_vpn

KS=android/teleopen-release.jks
APK=build/app/outputs/flutter-apk/teleopen-v1.apk
TOOL=/opt/android-sdk/build-tools/36.0.0/apksigner

# Пароль: из env KEYSTORE_PASS, иначе из key.properties (storePassword=).
PW="${KEYSTORE_PASS:-}"
if [[ -z "$PW" && -f android/key.properties ]]; then
  PW="$(grep -E '^storePassword=' android/key.properties | head -1 | cut -d= -f2-)"
fi
if [[ -z "$PW" ]]; then
  echo "✗ Нет пароля keystore. Запусти: KEYSTORE_PASS='...' $0" >&2
  echo "  (или положи storePassword= в android/key.properties)" >&2
  exit 1
fi

"$TOOL" sign --ks "$KS" --ks-key-alias teleopen \
  --ks-pass "pass:$PW" --key-pass "pass:$PW" \
  --min-sdk-version 21 \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  "$APK"
"$TOOL" verify -v "$APK"
