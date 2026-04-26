import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
val hasReleaseSigning = keyPropertiesFile.exists()

if (hasReleaseSigning) {
    keyPropertiesFile.inputStream().use(keyProperties::load)
}

android {
    namespace = "cn.onelap.onelap_strava_sync"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cn.onelap.onelap_strava_sync"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            check(hasReleaseSigning) {
                "Release signing requires android/key.properties and android/app/upload-keystore.jks"
            }
            signingConfig = signingConfigs.create("release") {
                val storeFilePath = keyProperties.getProperty("storeFile")
                    ?: error("Missing 'storeFile' in android/key.properties")
                val storePasswordValue = keyProperties.getProperty("storePassword")
                    ?: error("Missing 'storePassword' in android/key.properties")
                val keyAliasValue = keyProperties.getProperty("keyAlias")
                    ?: error("Missing 'keyAlias' in android/key.properties")
                val keyPasswordValue = keyProperties.getProperty("keyPassword")
                    ?: error("Missing 'keyPassword' in android/key.properties")

                storeFile = rootProject.file(storeFilePath)
                check(storeFile?.exists() == true) {
                    "Release signing keystore not found at ${storeFile?.path}"
                }
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
