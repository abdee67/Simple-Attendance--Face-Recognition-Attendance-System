plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.simple_attendance"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.simple_attendance"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // Use the full TensorFlow Lite package with GPU included
    implementation("org.tensorflow:tensorflow-lite-gpu:2.14.0")
    implementation("com.google.android.material:material:1.10.0")
    // Add these additional keep rules for the GPU delegate
    implementation("org.tensorflow:tensorflow-lite-gpu-delegate-plugin:0.4.4") {
        exclude(group = "org.tensorflow", module = "tensorflow-lite")
    }
    // Support library
    implementation("org.tensorflow:tensorflow-lite-support:0.4.4")
    // Multidex support
    implementation("androidx.multidex:multidex:2.0.1")
    // Core library desugaring for Java 8 features
    //implementation("com.android.tools:desugar_jdk_libs:1.2.2")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}