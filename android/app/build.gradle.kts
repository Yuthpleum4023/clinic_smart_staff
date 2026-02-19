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
    // ✅ FIX mergeDebugJavaResource (NUCLEAR - DEBUG PASS)
    // - ตัด META-INF ทั้งหมด -> กัน VerifyException (no message)
    // - pickFirsts "**/*" -> ให้ resource ซ้ำ “เลือกอันแรก” ทั้งหมด (กันพังเงียบ)
    // =====================================================
    packaging {
        resources {
            // ⭐ KILL SWITCH: กัน META-INF ชนกัน
            excludes += setOf("META-INF/**")

            // ⭐ NUCLEAR: กัน resource ซ้ำทุกชนิด (debug build ให้ผ่านก่อน)
            // หมายเหตุ: ใช้เพื่อให้รันได้คืนนี้ก่อน พรุ่งนี้ค่อยหรี่ให้แคบลง
            pickFirsts += setOf("**/*")
        }
    }
}

flutter {
    source = "../.."
}
