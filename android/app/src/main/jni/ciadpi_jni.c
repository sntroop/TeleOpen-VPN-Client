// ciadpi_jni.c
//
// JNI-обёртка между Kotlin-объектом space.teleopen.app.CiadpiNative и движком
// ByeDPI (ciadpi). Реализует две нативные функции:
//
//   nativeStart(args, ip, port, protector) — БЛОКИРУЮЩАЯ. Поднимает SOCKS5 на
//       ip:port с десинхронизацией по args и крутит цикл приёма до nativeStop().
//       Для КАЖДОГО исходящего сокета вызывает protector.protect(fd) (Java),
//       чтобы прямые соединения шли мимо VPN-туннеля.
//   nativeStop() — выставляет флаг остановки и будит цикл.
//
// ВАЖНО: этот файл линкуется с исходниками ciadpi (vendored/, см. README.md).
// Движок ByeByeDPI уже содержит хук защиты сокета — мы лишь предоставляем
// C-функцию android_protect_socket(fd), которую ciadpi зовёт после socket().
// Если вендоришь ванильный hufrea/byedpi — нужно добавить такой вызов в его
// функцию создания исходящего сокета (одна строка, см. README.md, шаг 4).

#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <android/log.h>

#define LOG_TAG "ciadpi-jni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── Точки входа ciadpi (объявлены в vendored/ciadpi заголовках) ──────────────
// main_loop()/stop() — это адаптер вокруг main() ciadpi: разбирает argv и
// запускает приёмный цикл. См. README.md шаг 3 (как их получить из исходников).
extern int  ciadpi_main(int argc, char **argv);   // блокирующий запуск
extern void ciadpi_stop(void);                     // сигнал остановки

// ── Глобальный колбэк защиты сокета ──────────────────────────────────────────
static JavaVM *g_vm = NULL;
static jobject g_protector = NULL;     // global ref на CiadpiNative.SocketProtector
static jmethodID g_protect_mid = NULL;

// Зовётся из ciadpi для каждого исходящего fd. Возвращает 1 при успехе.
int android_protect_socket(int fd) {
    if (g_vm == NULL || g_protector == NULL || g_protect_mid == NULL) return 0;
    JNIEnv *env = NULL;
    int attached = 0;
    if ((*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) != JNI_OK) return 0;
        attached = 1;
    }
    jboolean ok = (*env)->CallBooleanMethod(env, g_protector, g_protect_mid, (jint)fd);
    if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); ok = JNI_FALSE; }
    if (attached) (*g_vm)->DetachCurrentThread(g_vm);
    return ok == JNI_TRUE ? 1 : 0;
}

JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM *vm, void *reserved) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

// space.teleopen.app.CiadpiNative.nativeStart(String[], String, int, SocketProtector)
JNIEXPORT jint JNICALL
Java_space_teleopen_app_CiadpiNative_nativeStart(
        JNIEnv *env, jobject thiz,
        jobjectArray jargs, jstring jip, jint port, jobject jprotector) {

    // 1) Сохраняем колбэк защиты сокета как global ref.
    if (g_protector != NULL) { (*env)->DeleteGlobalRef(env, g_protector); g_protector = NULL; }
    g_protector = (*env)->NewGlobalRef(env, jprotector);
    jclass pcls = (*env)->GetObjectClass(env, jprotector);
    g_protect_mid = (*env)->GetMethodID(env, pcls, "protect", "(I)Z");
    if (g_protect_mid == NULL) {
        LOGE("protect(I)Z method not found");
        return -1;
    }

    // 2) Собираем argv: ["ciadpi", "-i", <ip>, "-p", <port>, <args...>]
    const char *ip = (*env)->GetStringUTFChars(env, jip, NULL);
    char portbuf[16];
    snprintf(portbuf, sizeof(portbuf), "%d", (int)port);

    jsize n = (*env)->GetArrayLength(env, jargs);
    int argc = (int)n + 5;
    char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
    int k = 0;
    argv[k++] = strdup("ciadpi");
    argv[k++] = strdup("-i");
    argv[k++] = strdup(ip);
    argv[k++] = strdup("-p");
    argv[k++] = strdup(portbuf);
    for (jsize i = 0; i < n; i++) {
        jstring s = (jstring)(*env)->GetObjectArrayElement(env, jargs, i);
        const char *cs = (*env)->GetStringUTFChars(env, s, NULL);
        argv[k++] = strdup(cs);
        (*env)->ReleaseStringUTFChars(env, s, cs);
        (*env)->DeleteLocalRef(env, s);
    }
    argv[k] = NULL;
    (*env)->ReleaseStringUTFChars(env, jip, ip);

    LOGI("starting ciadpi on %s:%d with %d extra args", "127.0.0.1", (int)port, (int)n);

    // 3) Блокирующий запуск движка. Вернётся после ciadpi_stop().
    int rc = ciadpi_main(argc, argv);

    // 4) Очистка argv.
    for (int i = 0; i < k; i++) free(argv[i]);
    free(argv);

    LOGI("ciadpi_main returned %d", rc);
    return rc;
}

// space.teleopen.app.CiadpiNative.nativeStop()
JNIEXPORT void JNICALL
Java_space_teleopen_app_CiadpiNative_nativeStop(JNIEnv *env, jobject thiz) {
    LOGI("nativeStop");
    ciadpi_stop();
    if (g_protector != NULL) {
        (*env)->DeleteGlobalRef(env, g_protector);
        g_protector = NULL;
        g_protect_mid = NULL;
    }
}
