allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// ---------------------------------------------------------------------------
// Force every Android subproject (app + plugins) to compile against SDK 36.
//
// Some plugins still hard-code an older `compileSdk` in their own build.gradle
// (e.g. file_picker pins 34). When another dependency in the graph —
// flutter_plugin_android_lifecycle — requires compileSdk 36, that plugin's
// `checkAarMetadata` task fails the whole build. This raises the compileSdk of
// each Android module to 36 without editing the plugins and without touching
// min/target SDK — so device support and runtime behaviour are unchanged. Uses
// the Groovy builder so the root script needs no AGP import.
//
// The `:app` project is already evaluated here (forced by evaluationDependsOn
// above), so we configure it directly; the plugin modules are configured once
// they finish evaluating.
// ---------------------------------------------------------------------------
subprojects {
    val raiseCompileSdk = {
        extensions.findByName("android")?.withGroovyBuilder {
            try {
                "compileSdkVersion"(36)
            } catch (e: Exception) {
                // Newer AGP DSL exposes the `compileSdk` property setter instead.
                "setCompileSdk"(36)
            }
        }
        Unit
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
