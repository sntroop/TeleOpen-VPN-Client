# CMakeLists.txt — сборка libciadpi.so (JNI-обёртка + движок ciadpi/byedpi)
#
# Используется только для генерации .so через NDK (в Gradle проект НЕ подключён
# намеренно — .so кладётся готовым в jniLibs/<abi>/). Запускается скриптом
# build_ciadpi.sh (в этой же папке), который вендорит исходники byedpi и генерирует
# два файла рядом с исходниками:
#   vendored/sources.cmake   — список .c движка (взят из byedpi Makefile, SRC=)
#   vendored/android_shim.c  — ciadpi_stop() + __wrap_socket() (защита сокетов)
# См. README.md.

cmake_minimum_required(VERSION 3.18.1)
project(ciadpi C)

set(CMAKE_C_STANDARD 11)

set(CIADPI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendored/byedpi)

# Список .c движка генерируется build_ciadpi.sh из Makefile byedpi (SRC=...),
# чтобы не зависеть от версии. Определяет CIADPI_SRC_NAMES (только имена файлов).
include(${CMAKE_CURRENT_SOURCE_DIR}/vendored/sources.cmake)
list(TRANSFORM CIADPI_SRC_NAMES PREPEND ${CIADPI_DIR}/)

add_library(ciadpi SHARED
    ciadpi_jni.c
    ${CMAKE_CURRENT_SOURCE_DIR}/vendored/android_shim.c
    ${CIADPI_SRC_NAMES}
)

target_include_directories(ciadpi PRIVATE ${CIADPI_DIR})
target_compile_definitions(ciadpi PRIVATE ANDROID=1 __ANDROID__=1)

# main() движка → ciadpi_main() БЕЗ правки исходников: макрос на этапе сборки.
# ciadpi_jni.c зовёт extern ciadpi_main(argc, argv).
set_source_files_properties(${CIADPI_DIR}/main.c PROPERTIES
    COMPILE_DEFINITIONS "main=ciadpi_main")

# Защита сокетов БЕЗ правки исходников: все вызовы socket() в движке
# перехватываются __wrap_socket() (android_shim.c), который зовёт
# android_protect_socket(fd) → исходящие соединения ciadpi идут мимо VPN.
target_link_options(ciadpi PRIVATE "-Wl,--wrap=socket")

find_library(log-lib log)
target_link_libraries(ciadpi ${log-lib})
