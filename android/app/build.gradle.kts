plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
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

    buildTypes {
        debug {
            // The emulator reaches the Rails server on this Mac at localhost
            // through `adb reverse tcp:3000 tcp:3000`.
            buildConfigField("String", "BASE_URL", "\"http://localhost:3000\"")
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
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

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons)
    implementation(libs.activity.compose)
    implementation(libs.coil.compose)
}
