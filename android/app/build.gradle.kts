import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties
import java.util.Base64
import org.gradle.api.tasks.compile.JavaCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
fun signingValue(name: String, env: String): String? =
    providers.environmentVariable(env).orNull ?: releaseProperties.getProperty(name)
val releaseStore = signingValue("storeFile", "YOMASHI_KEYSTORE")
val releasePassword = signingValue("storePassword", "YOMASHI_STORE_PASSWORD")
val releaseAlias = signingValue("keyAlias", "YOMASHI_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "YOMASHI_KEY_PASSWORD")
val hasReleaseSigning = listOf(releaseStore, releasePassword, releaseAlias, releaseKeyPassword).all { !it.isNullOrBlank() }
val dartDefines = providers.gradleProperty("dart-defines").orNull.orEmpty().split(',').mapNotNull {
    runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull()
}.toSet()
val personalRelease = "YOMASHI_PERSONAL_RELEASE=true" in dartDefines
val integrationApplication = "YOMA_INTEGRATION_QA=true" in dartDefines
val testApplication = "YOMASHI_QA=true" in dartDefines

android {
    buildFeatures { buildConfig = true }
    signingConfigs {
        if (hasReleaseSigning) create("release") {
            storeFile = file(releaseStore!!)
            storePassword = releasePassword
            keyAlias = releaseAlias
            keyPassword = releaseKeyPassword
        }
    }
    namespace = "app.yomashi.reader"
    compileSdk = 36
    ndkVersion = providers.gradleProperty("yomashi.ndkVersion").getOrElse(flutter.ndkVersion)

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (integrationApplication) "app.yoma.integration.qa" else if (testApplication) "app.yomashi.reader.qa" else "app.yomashi.reader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Uso personal explícito: conserva el certificado de la instalación existente.
            signingConfig = if (personalRelease || testApplication) signingConfigs.getByName("debug") else signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":anime-engine"))
    // Match the instrumentation dependencies also linked by Flutter integration_test in debug.
    debugImplementation("androidx.test:runner:1.6.2")
    debugImplementation("androidx.test:rules:1.6.1")
    debugImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    implementation("androidx.activity:activity-ktx:1.9.0")
    implementation("androidx.webkit:webkit:1.14.0")
    testImplementation("junit:junit:4.13.2")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    // WorkManager devuelve ListenableFuture (Guava); antes llegaba con media3, en esta misma versión.
    implementation("com.google.guava:guava:33.3.1-android")
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("com.google.mlkit:translate:17.0.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
// Flutter 3.47.5 conserva plugins de desarrollo en el registrador Java de release,
// aunque los excluye del classpath: https://github.com/flutter/flutter/issues/186800
// Compilar una copia filtrada solo en release. No modificar el SDK ni el archivo
// generado original, que sigue usándose en debug/profile con integration_test.
val originalRegistrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
val releaseRegistrant = layout.buildDirectory.file("generated/yomashi-release/io/flutter/plugins/GeneratedPluginRegistrant.java")
val prepareReleaseRegistrant = tasks.register("prepareYomashiReleaseRegistrant") {
    inputs.file(originalRegistrant)
    outputs.file(releaseRegistrant)
    doLast {
        val source = originalRegistrant.readText()
        val testBlock = Regex("""(?m)^    try \{\r?\n      flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\r?\n    \} catch \(Exception e\) \{\r?\n      Log\.e\(TAG, "[^"]*", e\);\r?\n    \}\r?\n""")
        val filtered = source.replace(testBlock, "")
        check(!filtered.contains("dev.flutter.plugins.integration_test")) { "Revisar el formato del registrador de Flutter antes de compilar release" }
        releaseRegistrant.get().asFile.apply { parentFile.mkdirs(); writeText(filtered) }
    }
}
gradle.projectsEvaluated {
    tasks.named<JavaCompile>("compileReleaseJavaWithJavac").configure {
        dependsOn(prepareReleaseRegistrant)
        exclude { it.file.canonicalFile == originalRegistrant.canonicalFile }
        source(releaseRegistrant)
    }
}
// Una entrega nunca debe publicarse accidentalmente con la clave de depuración.
gradle.taskGraph.whenReady {
    if (!hasReleaseSigning && !personalRelease && !testApplication && allTasks.any { it.project == project &&
        (it.name.startsWith("assemble") || it.name.startsWith("bundle") || it.name.startsWith("package")) &&
        it.name.contains("Release") }) {
        throw GradleException("Configura android/key.properties o YOMASHI_KEYSTORE, YOMASHI_STORE_PASSWORD, YOMASHI_KEY_ALIAS y YOMASHI_KEY_PASSWORD para compilar release.")
    }
}
