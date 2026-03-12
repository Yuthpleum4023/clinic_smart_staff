// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin ต้องอยู่ล่างสุด
    id("dev.flutter.flutter-gradle-plugin")
}

// ✅ โหลด key.properties (อยู่ที่ android/key.properties)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ✅ IMPORTANT: ห้ามใช้ com.example
    namespace = "com.clinicsmartstaff.app"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // ✅ IMPORTANT: ต้องตรงกับ namespace (แนะนำให้เหมือนกัน)
        applicationId = "com.clinicsmartstaff.app"

        // ✅ FIX: Biometric (local_auth) แนะนำ minSdk >= 23
        // (ถ้าใช้ flutter.minSdkVersion มักจะเป็น 21 และจะงอแงบนบางเครื่อง)
        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ✅ RELEASE SIGNING CONFIG
    signingConfigs {
        create("release") {
            // ถ้า key.properties ไม่มีไฟล์/ค่า จะพังตอน build release
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // ✅ ใช้ release signing (สำคัญมาก)
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = false
            isShrinkResources = false
        }

        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // =====================================================
    // ✅ FIX mergeDebugJavaResource / resource conflicts
    // =====================================================
    packaging {
        resources {
            excludes += setOf("META-INF/**")
            pickFirsts += setOf("**/*")
        }
    }
}

flutter {
    source = "../.."
}
