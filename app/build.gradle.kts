plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "bbs.binmt.cc"
    compileSdk = 36
    defaultConfig {
        applicationId = "bbs.binmt.cc"
        minSdk = 24
        targetSdk = 36
        versionCode = 68
        versionName = "1.6.16"
        ndk { abiFilters += "arm64-v8a" }
    }
    signingConfigs {
        create("release") {
            storeFile = rootProject.file(System.getenv("MT_KEYSTORE") ?: "signing/release-signing.p12")
            storeType = "PKCS12"
            storePassword = System.getenv("MT_STORE_PASSWORD")
            keyAlias = "infinitycm"
            keyPassword = System.getenv("MT_STORE_PASSWORD")
        }
    }
    buildTypes { release {
        signingConfig = signingConfigs.getByName("release")
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
    } }
    buildFeatures { compose = true }
    testOptions { unitTests.isIncludeAndroidResources = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    packaging { jniLibs.excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**") }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.08.01"))
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended:1.7.8")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("io.coil-kt:coil-gif:2.7.0")
    implementation("org.jsoup:jsoup:1.21.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    testImplementation("androidx.compose.ui:ui-test-manifest")
    testImplementation("org.json:json:20250517")
}
