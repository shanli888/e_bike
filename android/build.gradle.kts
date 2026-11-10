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

// 把插件的 compileSdk 提升到与应用一致。
// flutter_blue_plus 等插件自身仍声明 compileSdk 33，而它们依赖的
// androidx 库要求 34+，不统一会导致 checkReleaseAarMetadata 失败。
// 注意：必须在下面的 evaluationDependsOn 之前注册 afterEvaluate。
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            val current = androidExt.compileSdkVersion?.removePrefix("android-")?.toIntOrNull()
            if (current != null && current < 36) {
                androidExt.compileSdkVersion(36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
