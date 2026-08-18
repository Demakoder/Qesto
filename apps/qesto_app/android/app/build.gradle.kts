import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.isFile) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
    val requiredSigningProperties =
        listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missingSigningProperties = requiredSigningProperties.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }
    if (missingSigningProperties.isNotEmpty()) {
        throw GradleException(
            "Missing Android signing properties: ${missingSigningProperties.joinToString()}"
        )
    }
}
val allowDebugReleaseSigning =
    System.getenv("QESTO_ALLOW_DEBUG_RELEASE_SIGNING") == "1"

android {
    namespace = "ru.qesto.qesto"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ru.qesto.qesto"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.isFile) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.isFile) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugReleaseSigning) {
                signingConfig = signingConfigs.getByName("debug")
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { task ->
        task.path.contains("Release", ignoreCase = true)
    }
    if (buildsRelease && !keystorePropertiesFile.isFile && !allowDebugReleaseSigning) {
        throw GradleException(
            "Release signing is not configured. Copy android/key.properties.example " +
                "to android/key.properties and provide a private keystore. " +
                "For a local throwaway build only, set QESTO_ALLOW_DEBUG_RELEASE_SIGNING=1."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
}
