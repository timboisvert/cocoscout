import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    // Reads app/google-services.json (Firebase, for notifications). It's kept
    // out of git; the copy is in 1Password with the upload key.
    alias(libs.plugins.google.services)
    // Uploads the release bundle to Google Play (docs/app_release_automation.md).
    alias(libs.plugins.play.publisher)
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
        versionCode = 4
        versionName = "1.1"
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

// Google Play uploads: the service account's key lives outside the repo, at
// ~/.config/cocoscout/play-service-account.json (its copy is in 1Password), or
// comes in through ANDROID_PUBLISHER_CREDENTIALS. Without either, everything
// builds as before and only the publish tasks fail. A bare publish goes to
// internal testing as a draft; a store release names its track
// (docs/app_release_automation.md).
play {
    val key = File(System.getProperty("user.home"), ".config/cocoscout/play-service-account.json")
    if (key.exists()) serviceAccountCredentials.set(key)
    defaultToAppBundles.set(true)
    track.set("internal")
    releaseStatus.set(com.github.triplet.gradle.androidpublisher.ReleaseStatus.DRAFT)
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

    // Tap to Pay at the door: Stripe Terminal with its Tap to Pay reader
    // (door/TapToPayReader). It needs Kotlin 2.3.21 or later.
    implementation(libs.stripe.terminal.core)
    implementation(libs.stripe.terminal.taptopay)
    // Stripe brings okhttp-tls 4.12, built against OkHttp 4's internals;
    // Hotwire Native brings OkHttp 5, so the 4.12 one fails at its first
    // request (NoClassDefFoundError: okhttp3/internal/Util). OkHttp 5's own
    // okhttp-tls has the same API.
    implementation(libs.okhttp.tls)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons)
    implementation(libs.activity.compose)
    implementation(libs.coil.compose)
}
