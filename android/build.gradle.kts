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
    // Plugins live in the pub cache. On Windows that is often a different drive than the
    // project (C: vs E:), and Gradle cannot relate paths across drives, so only redirect
    // the build folder of modules that are on the same drive as the project.
    val sameDrive =
        project.projectDir.toPath().root == rootProject.projectDir.toPath().root
    if (sameDrive) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
