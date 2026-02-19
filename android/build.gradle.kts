import org.gradle.api.file.Directory
import com.android.build.api.variant.AndroidComponentsExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()

rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // ✅ ย้าย build output ของแต่ละ subproject ไปที่ ../../build/<project>
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // =====================================================
    // ✅ GLOBAL FIX: MergeJavaRes VerifyException (plugins + app)
    // - Apply ผ่าน AndroidComponents (Variant API)
    // - สำคัญ: ต้อง register เร็ว -> ห้าม evaluationDependsOn(":app") (ทำให้ "too late")
    // =====================================================

    plugins.withId("com.android.application") {
        val ac = extensions.getByType(AndroidComponentsExtension::class.java)
        ac.onVariants { variant ->
            variant.packaging.resources.excludes.add("META-INF/**")
        }
    }

    plugins.withId("com.android.library") {
        val ac = extensions.getByType(AndroidComponentsExtension::class.java)
        ac.onVariants { variant ->
            variant.packaging.resources.excludes.add("META-INF/**")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
