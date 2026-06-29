#!/usr/bin/env bash
#
# build_ciadpi.sh — собирает libciadpi.so (движок ByeDPI) под все ABI и
# раскладывает в ../jniLibs/<abi>/. Запусти ОДИН раз; .so в гит не коммитятся.
#
#   cd android/app/src/main/jni
#   ./build_ciadpi.sh
#
# Требуется: Android NDK + cmake. Путь к NDK берётся из $ANDROID_NDK_HOME,
# $NDK, либо ищется в $ANDROID_SDK_ROOT/ndk/*. Можно передать явно:
#   NDK=~/Android/Sdk/ndk/26.3.11579264 ./build_ciadpi.sh
#
# Что делает (без ручного патчинга исходников byedpi):
#   1) вендорит hufrea/byedpi в vendored/byedpi (если ещё нет);
#   2) читает SRC= из его Makefile → vendored/sources.cmake (список .c);
#   3) генерит vendored/android_shim.c: ciadpi_stop() + __wrap_socket();
#   4) cmake-сборка под каждый ABI → ../jniLibs/<abi>/libciadpi.so.
#
# main()→ciadpi_main и защита сокетов делаются флагами компилятора/линкера
# (см. CMakeLists.txt), сами исходники byedpi НЕ модифицируются.

set -euo pipefail
cd "$(dirname "$0")"
JNI_DIR="$(pwd)"

ABIS=(arm64-v8a armeabi-v7a x86_64)
API=24
BYEDPI_REPO="https://github.com/hufrea/byedpi"

# ── 0. Найти NDK ─────────────────────────────────────────────────────────────
find_ndk() {
  for c in "${NDK:-}" "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    [ -n "$c" ] && [ -d "$c" ] && { echo "$c"; return; }
  done
  for root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    [ -d "$root/ndk" ] || continue
    # самая свежая версия
    local latest
    latest="$(ls -1 "$root/ndk" 2>/dev/null | sort -V | tail -1)"
    [ -n "$latest" ] && { echo "$root/ndk/$latest"; return; }
  done
}
NDK="$(find_ndk || true)"
if [ -z "${NDK:-}" ] || [ ! -d "$NDK" ]; then
  echo "ОШИБКА: NDK не найден. Установи (sdkmanager \"ndk;26.3.11579264\")" >&2
  echo "или укажи путь: NDK=/path/to/ndk ./build_ciadpi.sh" >&2
  exit 1
fi
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
[ -f "$TOOLCHAIN" ] || { echo "ОШИБКА: нет $TOOLCHAIN" >&2; exit 1; }
echo "==> NDK: $NDK"

command -v cmake >/dev/null || { echo "ОШИБКА: cmake не в PATH" >&2; exit 1; }

# ── 1. Завендорить byedpi ────────────────────────────────────────────────────
mkdir -p vendored
if [ ! -d vendored/byedpi/.git ] && [ ! -f vendored/byedpi/main.c ]; then
  echo "==> git clone $BYEDPI_REPO → vendored/byedpi"
  git clone --depth=1 "$BYEDPI_REPO" vendored/byedpi
else
  echo "==> vendored/byedpi уже есть, пропускаю clone"
fi
[ -f vendored/byedpi/main.c ] || { echo "ОШИБКА: vendored/byedpi/main.c не найден" >&2; exit 1; }

# ── 2. Список .c из Makefile (SRC=...) → sources.cmake ───────────────────────
echo "==> генерирую vendored/sources.cmake из Makefile (SRC=)"
SRC_LINE="$(grep -E '^[[:space:]]*SRC[[:space:]]*=' vendored/byedpi/Makefile | head -1 | cut -d= -f2-)"
if [ -z "$SRC_LINE" ]; then
  echo "   SRC= не найден, fallback на *.c из каталога"
  SRC_FILES="$(cd vendored/byedpi && ls *.c | grep -vE '^(win_service)\.c$' | tr '\n' ' ')"
else
  # выкидываем win_service.c (только под Windows)
  SRC_FILES="$(echo "$SRC_LINE" | tr ' ' '\n' | grep -E '\.c$' | grep -vE '^win_service\.c$' | tr '\n' ' ')"
fi
echo "   .c движка: $SRC_FILES"
{
  echo "# Автогенерёно build_ciadpi.sh из byedpi Makefile (SRC=). Не редактировать."
  echo -n "set(CIADPI_SRC_NAMES"
  for f in $SRC_FILES; do echo -n " $f"; done
  echo ")"
} > vendored/sources.cmake

# ── 3. android_shim.c: ciadpi_stop() + __wrap_socket() ───────────────────────
# server_fd — глобал byedpi (proxy.c), on_cancel делает shutdown(server_fd).
# Повторяем то же из ciadpi_stop(). __wrap_socket перехватывает ВСЕ socket()
# движка (--wrap=socket в CMakeLists) и защищает каждый fd через JNI.
echo "==> генерирую vendored/android_shim.c"
cat > vendored/android_shim.c <<'SHIM'
// Автогенерёно build_ciadpi.sh. Мост Android ↔ движок byedpi без правки его кода.
#include <sys/socket.h>
#include <unistd.h>
#include <android/log.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "ciadpi-shim", __VA_ARGS__)

// Защита сокета (реализована в ciadpi_jni.c через JNI protect(fd)).
extern int android_protect_socket(int fd);

// Реальный socket() из libc (подставляет линкер при --wrap=socket).
extern int __real_socket(int domain, int type, int protocol);

// Перехват ВСЕХ socket() движка: защищаем каждый исходящий fd, чтобы прямые
// соединения ciadpi шли мимо VPN-туннеля.
int __wrap_socket(int domain, int type, int protocol) {
    int fd = __real_socket(domain, type, protocol);
    if (fd >= 0) android_protect_socket(fd);
    return fd;
}

// Глобал byedpi: дескриптор слушающего сокета (proxy.c). on_cancel/on_hup
// делают shutdown(server_fd) для выхода из event-loop — повторяем это.
extern int server_fd;

void ciadpi_stop(void) {
    LOGI("ciadpi_stop: shutdown server_fd=%d", server_fd);
    if (server_fd > 0) {
        shutdown(server_fd, SHUT_RDWR);
        close(server_fd);
    }
}
SHIM

# ── 4. Сборка под все ABI ────────────────────────────────────────────────────
OUT_BASE="$JNI_DIR/../jniLibs"
for ABI in "${ABIS[@]}"; do
  echo "==> cmake $ABI"
  cmake -B "build/$ABI" -S . \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build "build/$ABI" --config Release
  mkdir -p "$OUT_BASE/$ABI"
  cp "build/$ABI/libciadpi.so" "$OUT_BASE/$ABI/"
  echo "    → $OUT_BASE/$ABI/libciadpi.so"
done

echo
echo "ГОТОВО. libciadpi.so собрана под: ${ABIS[*]}"
echo "Дальше:"
echo "  1) flutter build apk --debug"
echo "  2) пришли Клоду вывод: vendored/byedpi/ciadpi --help  (сверить флаги)"
