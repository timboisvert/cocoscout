import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    // Reads app/google-services.json (Firebase, for notifications). It's kept
    // out of git; the copy is in 1Password with the upload key.
    alias(libs.plugins.google.services)
}

// Google Play's upload key: keystores/ and keystore.properties are kept out
// of git (both are in 1Password). Without them, release builds are unsigned.
val uploadKey = rootProject.file("keystore.properties").takeIf { it.exists() }?.let { file ->
    Properties().apply { file.inputStream().use { load(it) } }
}

android {
    namespace = "com.cocoscout.app"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "com.cocoscout.app"
        // Hotwire Native Android needs Android 9 or later.
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        buildConfigField("String", "BASE_URL", "\"https://cocoscout.com\"")
    }

    signingConfigs {
        if (uploadKey != null) {
            create("upload") {
                storeFile = rootProject.file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // The emulator reaches the Rails server on this Mac at localhost
            // through `adb reverse tcp:3000 tcp:3000`.
            buildConfigField("String", "BASE_URL", "\"http://localhost:3000\"")
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.findByName("upload")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // The app's page rules ship inside it too (the server's copy is fetched on
    // launch), from the one file the iOS app and the website share.
    sourceSets["main"].assets.srcDir("../../public/hotwire-native")
}

dependencies {
    implementation(libs.hotwire.core)
    implementation(libs.hotwire.navigation)
    implementation(libs.material)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.lifecycle.runtime)
    implementation(libs.browser)

    // The door's scanner: CameraX with ML Kit's on-device barcode reader.
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.camerax.mlkit)
    implementation(libs.mlkit.barcode)

    // Notifications: Firebase Cloud Messaging (push/).
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons)
    implementation(libs.activity.compose)
    implementation(libs.coil.compose)
}
