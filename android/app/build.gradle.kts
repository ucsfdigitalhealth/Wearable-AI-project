plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "org.ucsfdigitalhealth.wearableai"
    compileSdk = 35

    defaultConfig {
        applicationId = "org.ucsfdigitalhealth.wearableai"
        minSdk = 33 // Polar BLE SDK 8.x requirement
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        val key = providers.gradleProperty("DROPBOX_APP_KEY").orElse("").get()
        buildConfigField("String", "DROPBOX_APP_KEY", "\"$key\"")
        manifestPlaceholders["dropboxKey"] = key.ifBlank { "unconfigured" }
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    kotlinOptions { jvmTarget = "21" }
    buildFeatures { compose = true; buildConfig = true }
    packaging {
        resources.excludes += listOf("META-INF/DEPENDENCIES", "META-INF/LICENSE.md", "META-INF/LICENSE-notice.md")
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.github.polarofficial:polar-ble-sdk:8.3.0")
    implementation("com.dropbox.core:dropbox-core-sdk:6.1.0")
    testImplementation("junit:junit:4.13.2")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
