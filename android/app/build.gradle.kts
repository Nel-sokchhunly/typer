plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// android/build.sh fills these: the engine for each ABI (cargo-ndk) and the data TSVs.
val rustOut = layout.buildDirectory.dir("rust")
val repo = rootDir.parentFile

// The version comes from the v* tag (CI sets TYPER_VERSION=4.0.1): versionCode 40001, so Play sees it go up.
val typerVersion = System.getenv("TYPER_VERSION") ?: "0.0.1"
val (major, minor, patch) = (typerVersion.split(".").map { it.takeWhile(Char::isDigit).toIntOrNull() ?: 0 } + listOf(0, 0, 0)).take(3)

// Release signing, on v* tags only: one keystore from the repo secrets with two keys.
// "app" is Typer's app signing key (it signs the GitHub APK; Play holds a copy). "upload" signs the AAB for Play.
val releaseKeystore = System.getenv("TYPER_KEYSTORE")

android {
    namespace = "com.chhunly.typer"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.chhunly.typer"
        minSdk = 24
        targetSdk = 36
        versionCode = major * 10000 + minor * 100 + patch
        versionName = typerVersion
    }

    signingConfigs {
        // Shared by every dev (a debug key is not a secret), so debug builds from any machine update each other.
        getByName("debug") { storeFile = file("debug.keystore") }
        if (releaseKeystore != null) create("release") {
            storeFile = file(releaseKeystore)
            storePassword = System.getenv("TYPER_KEYSTORE_PASSWORD")
            keyPassword = System.getenv("TYPER_KEYSTORE_PASSWORD")
            keyAlias = findProperty("typerKey")?.toString() ?: "app"  // -PtyperKey=upload for the AAB
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }

    sourceSets["main"].jniLibs.srcDir(rustOut.map { it.dir("jniLibs") })
    sourceSets["main"].assets.srcDir(rustOut.map { it.dir("assets") })

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // The data TSVs are already text; compressing them only slows the first-run copy.
    androidResources { noCompress += "tsv" }

    testOptions {
        unitTests.all {
            // JVM tests drive the core against the real engine, built for this machine:
            //   cargo build --release --manifest-path android/jni/Cargo.toml
            it.systemProperty("java.library.path", File(repo, "android/jni/target/release").path)
            it.systemProperty("typer.data", File(repo, "data/out").path)
            it.systemProperty("typer.fixtures", File(repo, "fixtures").path)
            it.inputs.dir(File(repo, "fixtures"))  // a fixture edit reruns the tests
            it.inputs.dir(File(repo, "data/out")).optional()
            it.testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
        }
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    // Companion app only; the Keyboard draws its own View and uses none of these.
    implementation(platform("androidx.compose:compose-bom:2026.06.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.12.4")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20180813")
}
