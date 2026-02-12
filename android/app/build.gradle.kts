plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin ต้องอยู่ล่างสุด
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.clinic_payroll"
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
        applicationId = "com.example.clinic_payroll"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // ใช้ debug signing ไปก่อน (รันเครื่องได้)
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // =====================================================
    // ✅ FIX mergeDebugJavaResource (pdf / printing / kotlin)
    // =====================================================
    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/LICENSE.md",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/NOTICE.md",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/*.kotlin_module",
                "META-INF/*.version",
                "META-INF/INDEX.LIST",
                "META-INF/io.netty.versions.properties"
            )
        }
    }
}

flutter {
    source = "../.."
}
