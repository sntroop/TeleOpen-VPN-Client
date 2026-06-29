import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Релизная подпись. Секреты лежат в android/key.properties (НЕ в git —
// см. .gitignore + key.properties.example). Если файла нет (CI без секретов,
// чужой клон), молча откатываемся на debug-подпись, чтобы сборка не падала.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "space.teleopen.app"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    // Lint на релизной сборке отключён: задача lintVitalRelease падает с
    // OutOfMemoryError в памяти-ограниченном окружении (heap Gradle намеренно
    // занижен в gradle.properties, см. комментарий там). Dart-код покрыт
    // `flutter analyze`, отдельный Android-lint для релизного APK не нужен.
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    defaultConfig {
        applicationId = "space.teleopen.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                // Явно включаем ВСЕ схемы подписи. По умолчанию AGP для нашей
                // конфигурации выдавал v2-only — а часть OEM-установщиков и
                // путь через Play Protect при sideload опираются на v1 (JAR)
                // как fallback. Без v1 пакет отвергается с немым «приложение
                // не установлено» даже на чистом устройстве. v3 — корректная
                // поддержка на новых Android + готовность к ротации ключа.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // Прод-подпись из key.properties; fallback на debug, если ключа нет.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt"
            )
        }
    }

    configurations.all {
        exclude(group = "com.github.singbox-android", module = "libbox")
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
    // androidx.core нужен для ServiceCompat.startForeground(...) с явным
    // foregroundServiceType — обязательно на Android 14+ (targetSdk 34..36).
    // Обычно подтягивается транзитивно, но фиксируем версию явно.
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.google.android.play:core:1.10.3")
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
}
