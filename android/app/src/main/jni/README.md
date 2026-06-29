# Сборка libciadpi.so (движок ByeDPI для режима «Обход DPI»)

Режим «Обход DPI» (экран Настройки → Сеть → «Обход DPI (ByeDPI)», тумблер
«Использовать обход DPI») гоняет трафик `TUN → tun2socks → локальный ciadpi →
напрямую в интернет`, применяя десинхронизацию пакетов. Сам движок —
нативная библиотека `libciadpi.so`, которой **нет в репозитории**: её нужно
собрать один раз через Android NDK и положить в `jniLibs/<abi>/`.

Пока `.so` не собрана — приложение НЕ падает: режим честно сообщает в VPN-логе
`libciadpi.so не загружена` и останавливается (мягкая деградация). Обычные
подключения к серверу (xray/hysteria) работают независимо.

## Что уже есть в репозитории
- `ciadpi_jni.c` — JNI-мост к `space.teleopen.app.CiadpiNative` (готов).
- `CMakeLists.txt` — сборочный скрипт (готов, правится список .c под версию).
- Kotlin-сторона: `CiadpiNative` + режим `startByeDpi` в `HysteriaTunVpnService`.

## Шаги сборки

### 1. Установить NDK
Android Studio → SDK Manager → SDK Tools → NDK (Side by side). Либо
`sdkmanager "ndk;26.3.11579264"`. Запомни путь, напр. `~/Android/Sdk/ndk/26.3.11579264`.

### 2. Завендорить исходники ciadpi
Берём порт из ByeByeDPI (там уже есть хук защиты сокета под Android):
```
cd android/app/src/main/jni
git clone --depth=1 https://github.com/dovecoteescapee/ByeByeDPI vendored/bbdpi
ln -s bbdpi/external/byedpi vendored/byedpi   # или скопировать каталог byedpi
```
Если берёшь ванильный `https://github.com/hufrea/byedpi` — переходи к шагу 4
(добавить хук вручную).

### 3. Адаптер точек входа `ciadpi_main` / `ciadpi_stop`
`ciadpi_jni.c` ожидает две функции:
- `int ciadpi_main(int argc, char **argv)` — блокирующий запуск (это `main()`
  ciadpi, переименованный, чтобы не конфликтовать с JNI).
- `void ciadpi_stop(void)` — выставляет глобальный флаг выхода из accept-цикла.

В исходниках ciadpi:
- переименуй `int main(...)` → `int ciadpi_main(...)` (в `main.c`);
- заведи глобальный `volatile int g_stop;` и проверяй его в главном цикле
  `proxy.c`; `ciadpi_stop()` ставит `g_stop = 1` и закрывает слушающий сокет.
ByeByeDPI-порт уже содержит эквивалент — сверь имена и поправь `extern` в
`ciadpi_jni.c` при необходимости.

### 4. Хук защиты сокета (если ванильный byedpi)
Чтобы прямые соединения ciadpi шли мимо VPN, после создания КАЖДОГО исходящего
сокета нужно вызвать защиту. Найди в ciadpi место `socket(AF_INET..., SOCK_STREAM...)`
для upstream-соединения (обычно `proxy.c`/`conev.c`) и добавь:
```c
#ifdef __ANDROID__
extern int android_protect_socket(int fd);
android_protect_socket(sfd);   // sfd — только что созданный исходящий fd
#endif
```
(В ByeByeDPI-порте такой вызов уже есть — менять ничего не нужно.)

### 5. Сверить список .c в CMakeLists.txt
Открой `Makefile` ciadpi, посмотри переменную `SRC`/`OBJ` и приведи `file(GLOB ...)`
в `CMakeLists.txt` к тому же набору файлов.

### 6. Собрать .so под все ABI
```
cd android/app/src/main/jni
for ABI in arm64-v8a armeabi-v7a x86_64; do
  cmake -B build/$ABI \
    -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=$ABI -DANDROID_PLATFORM=android-24 -S .
  cmake --build build/$ABI
  mkdir -p ../jniLibs/$ABI
  cp build/$ABI/libciadpi.so ../jniLibs/$ABI/
done
```
(`$NDK` — путь из шага 1. arm64-v8a обязателен; остальные — для совместимости.)

### 7. Сверить маппинг флагов
Запусти `./ciadpi --help` собранной версии и сверь буквы флагов с функцией
`buildByeDpiArgs` в `lib/state/app_settings.dart` (там подробный комментарий).
Если буквы отличаются — поправь только эту функцию.

### 8. Собрать и проверить
```
flutter build apk --debug
```
На устройстве: Настройки → «Обход DPI» → тумблер ВКЛ → на главном «Подключить».
В VPN-логе должны появиться строки `starting ciadpi on 127.0.0.1:...` и
`tun2socks: ...`. Открой заблокированный по SNI сайт — должен открыться без
VPN-сервера.

## Лицензия
ciadpi/byedpi — GPL-3.0; проект TeleOpen тоже GPL-3.0, совместимо. При
распространении приложите исходники ciadpi и текст лицензии.
