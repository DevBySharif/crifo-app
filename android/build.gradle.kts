allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val configureAction = Action<Project> {
        if (extensions.findByName("android") != null) {
            val androidExtension = extensions.getByName("android")
            
            // 1. Inject Namespace if missing
            val namespaceMethod = androidExtension.javaClass.methods.find { it.name == "setNamespace" }
            val getNamespaceMethod = androidExtension.javaClass.methods.find { it.name == "getNamespace" }
            if (namespaceMethod != null && getNamespaceMethod != null) {
                val currentNamespace = getNamespaceMethod.invoke(androidExtension)
                if (currentNamespace == null) {
                    val ns = "com." + name.replace("_", ".")
                    namespaceMethod.invoke(androidExtension, ns)
                }
            }

            // 2. Align source/target compatibility and Kotlin JVM target to Java 17
            try {
                val compileOptions = androidExtension.javaClass.getMethod("getCompileOptions").invoke(androidExtension)
                val setSource = compileOptions.javaClass.methods.find { it.name == "setSourceCompatibility" }
                val setTarget = compileOptions.javaClass.methods.find { it.name == "setTargetCompatibility" }
                setSource?.invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_17)
                setTarget?.invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_17)
            } catch (e: Exception) {
                // Ignore
            }

            // 3. Automatically strip package attribute from manifest (AGP 8+ requirement)
            try {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val content = manifestFile.readText()
                    if (content.contains("package=")) {
                        val cleanedContent = content.replace(Regex("""package="[^"]*""""), "")
                        manifestFile.writeText(cleanedContent)
                    }
                }
            } catch (e: Exception) {
                // Ignore if read/write fails
            }
        }
    }

    if (state.executed) {
        configureAction.execute(this)
    } else {
        afterEvaluate(configureAction)
    }

    // 4. Force JVM 17 compatibility for Kotlin compiler tasks
    tasks.configureEach {
        if (this.javaClass.name.contains("KotlinCompile")) {
            try {
                val kotlinOptions = this.javaClass.getMethod("getKotlinOptions").invoke(this)
                val setJvmTarget = kotlinOptions.javaClass.methods.find { it.name == "setJvmTarget" }
                if (setJvmTarget != null) {
                    setJvmTarget.invoke(kotlinOptions, "17")
                } else {
                    val getCompilerOptions = this.javaClass.getMethod("getCompilerOptions").invoke(this)
                    val getJvmTarget = getCompilerOptions.javaClass.getMethod("getJvmTarget")
                    val jvmTargetProp = getJvmTarget.invoke(getCompilerOptions)
                    val jvmTargetClass = jvmTargetProp.javaClass.classLoader.loadClass("org.jetbrains.kotlin.gradle.dsl.JvmTarget")
                    val jvm17 = jvmTargetClass.getField("JVM_17").get(null)
                    jvmTargetProp.javaClass.getMethod("set", Object::class.java).invoke(jvmTargetProp, jvm17)
                }
            } catch (e: Exception) {
                // Ignore
            }
        }
    }
}
