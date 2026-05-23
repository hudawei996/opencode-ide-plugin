plugins {
    id("java")
    id("org.jetbrains.intellij.platform") version "2.2.1"
    kotlin("jvm") version "1.9.23"
}

group = "goals.opencode"
version = "26.5.15"

val guiOnly = project.findProperty("guiOnly")?.toString()?.toBoolean() ?: false
val webguiDist = project.findProperty("webguiDist")?.toString()
val repoRoot = rootProject.rootDir.resolve("../..").canonicalFile
val opencodeDist = repoRoot.resolve("packages/opencode/dist")
val webguiDistDir = if (webguiDist != null) file(webguiDist) else repoRoot.resolve("packages/opencode/webgui-dist")
val bundledOpencodeResources = layout.buildDirectory.dir("generated/opencodeResources")
val bundledWebguiResources = layout.buildDirectory.dir("generated/webguiResources")
val bundledOpencodeBinaries = listOf(
    Triple("opencode-linux-x64/bin/opencode", "linux/amd64", "opencode"),
    Triple("opencode-linux-arm64/bin/opencode", "linux/arm64", "opencode"),
    Triple("opencode-darwin-x64/bin/opencode", "macos/amd64", "opencode"),
    Triple("opencode-darwin-arm64/bin/opencode", "macos/arm64", "opencode"),
    Triple("opencode-windows-x64/bin/opencode.exe", "windows/amd64", "opencode.exe"),
)
val currentBundledOpencodeBinary = run {
    val os = System.getProperty("os.name").lowercase()
    val arch = System.getProperty("os.arch").lowercase()
    val osDir = when {
        os.contains("win") -> "windows"
        os.contains("mac") || os.contains("darwin") -> "macos"
        os.contains("nux") || os.contains("linux") -> "linux"
        else -> null
    }
    val archDir = when {
        arch.contains("aarch64") || arch.contains("arm64") -> "arm64"
        arch.contains("64") -> "amd64"
        else -> null
    }
    bundledOpencodeBinaries.firstOrNull { it.second == "$osDir/$archDir" }
}

repositories {
    mavenCentral()
    intellijPlatform {
        defaultRepositories()
    }
}

java {
    // Align with IntelliJ Platform 2024.3+ requirement
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}

kotlin {
    jvmToolchain(21)
}

sourceSets {
    main {
        resources {
            exclude("bin/**")
        }
    }

    test {
        kotlin {
            srcDir("src/test/kotlin")
        }
    }
    
    // Create a separate source set for unit tests that don't need IntelliJ
    create("unitTest") {
        kotlin {
            srcDir("src/unitTest/kotlin")
        }
        resources {
            srcDir("src/unitTest/resources")
        }
        compileClasspath += sourceSets.main.get().output
        runtimeClasspath += output + compileClasspath
    }
}

dependencies {
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.17.1")

    // IntelliJ Platform dependencies
    intellijPlatform {
        intellijIdeaCommunity("2024.3")
        bundledPlugin("com.intellij.java")
        bundledPlugin("org.jetbrains.plugins.terminal")

        pluginVerifier()
        zipSigner()
    }

    testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")
    testImplementation("org.mockito:mockito-core:5.5.0")
    testImplementation("org.mockito:mockito-inline:5.2.0")
    testImplementation("org.mockito.kotlin:mockito-kotlin:5.1.0")
    testImplementation(kotlin("test"))
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    
    // Unit test dependencies (no IntelliJ, no JUnit)
    "unitTestImplementation"("com.fasterxml.jackson.module:jackson-module-kotlin:2.17.1")
    "unitTestImplementation"(kotlin("stdlib"))
}

intellijPlatform {
    pluginConfiguration {
        ideaVersion {
            sinceBuild.set("243")
        }
        // Provide metadata without setting an upper build bound (no untilBuild)
        description = providers.provider {
            val f = file("description.html")
            if (!f.isFile) {
                return@provider "Runs local OpenCode backend and displays the chat UI."
            }

            val text = f.readText().trim()
            if (text.isEmpty()) {
                "Runs local OpenCode backend and displays the chat UI."
            } else {
                text
            }
        }
        changeNotes = providers.provider {
            val f = file("changelog.html")
            if (!f.isFile) {
                return@provider "See CHANGELOG.md for details."
            }

            val text = f.readText().trim()
            if (text.isEmpty()) {
                "See CHANGELOG.md for details."
            } else {
                text
            }
        }
    }
}

tasks {
    val buildBundledWebgui = register<Exec>("buildBundledWebgui") {
        onlyIf {
            !webguiDistDir.resolve("index.html").isFile
        }
        workingDir = repoRoot.resolve("packages/opencode/webgui")
        if (System.getProperty("os.name").lowercase().contains("win")) {
            commandLine("cmd", "/c", "bun", "run", "build")
        } else {
            commandLine("bun", "run", "build")
        }
    }

    val prepareBundledWebguiResources = register<Sync>("prepareBundledWebguiResources") {
        dependsOn(buildBundledWebgui)
        from(webguiDistDir)
        into(bundledWebguiResources.map { it.dir("webgui-app") })

        doLast {
            val webguiDir = bundledWebguiResources.get().asFile.resolve("webgui-app")
            val files = webguiDir.walkTopDown()
                .filter { it.isFile && it.name != "file-list.txt" }
                .map { it.relativeTo(webguiDir).invariantSeparatorsPath }
                .sorted()
                .toList()
            File(webguiDir, "file-list.txt").writeText(files.joinToString("\n") + "\n")
            logger.lifecycle("Generated webgui-app/file-list.txt with ${files.size} entries")
        }
    }

    val buildBundledOpencode = register<Exec>("buildBundledOpencode") {
        onlyIf {
            !guiOnly && currentBundledOpencodeBinary?.let { !opencodeDist.resolve(it.first).isFile } != false
        }
        workingDir = repoRoot
        if (System.getProperty("os.name").lowercase().contains("win")) {
            commandLine("cmd", "/c", repoRoot.resolve("hosts/scripts/build_opencode.bat").absolutePath)
        } else {
            commandLine(repoRoot.resolve("hosts/scripts/build_opencode.sh").absolutePath)
        }
    }

    val prepareBundledOpencodeResources = register<Sync>("prepareBundledOpencodeResources") {
        dependsOn(buildBundledOpencode)
        into(bundledOpencodeResources)

        bundledOpencodeBinaries.forEach { binary ->
            from(opencodeDist.resolve(binary.first)) {
                into("bin/${binary.second}")
                rename { binary.third }
            }
        }

        doLast {
            val copied = bundledOpencodeBinaries
                .map { bundledOpencodeResources.get().asFile.resolve("bin/${it.second}/${it.third}") }
                .filter { it.isFile }

            check(copied.isNotEmpty()) {
                "No bundled opencode binaries were prepared from ${opencodeDist.absolutePath}"
            }

            currentBundledOpencodeBinary?.let {
                check(bundledOpencodeResources.get().asFile.resolve("bin/${it.second}/${it.third}").isFile) {
                    "Missing bundled opencode binary for this build platform: bin/${it.second}/${it.third}"
                }
            }
        }
    }

    processResources {
        val minVersion = project.findProperty("opencode.min.version")?.toString() ?: "1.1.1"
        inputs.property("opencodeMinVersion", minVersion)
        filesMatching("opencode-build.properties") {
            expand("opencodeMinVersion" to minVersion)
        }

        dependsOn(prepareBundledWebguiResources)
        from(bundledWebguiResources)

        if (!guiOnly) {
            dependsOn(prepareBundledOpencodeResources)
            from(bundledOpencodeResources)
        } else {
            exclude("bin/**")
        }
    }

    // Ensure no upper build bound is set in plugin.xml so the plugin stays compatible with newer IDEs
    patchPluginXml {
        // keep sinceBuild from pluginConfiguration, but expand upper bound to newer IDE builds
        untilBuild.set("261.*")

        if (guiOnly) {
            pluginId.set("goals.opencode-ux-plus-gui-only")
            pluginName.set("OpenCode UX+ GUI Only (unofficial) updates")
        }
    }

    prepareSandbox {
        from(rootProject.rootDir.resolve("LICENSE")) {
            into("${intellijPlatform.projectName.get()}")
        }
    }

    // Rename output archive for gui-only variant
    if (guiOnly) {
        named<Zip>("buildPlugin") {
            archiveBaseName.set("opencode-plugin-gui-only")
        }
    }

    
    // Configure test task for IntelliJ integration tests
    test {
        useJUnitPlatform()
        
        systemProperty("java.awt.headless", "true")
        systemProperty("idea.test.cyclic.buffer.size", "1048576")
        systemProperty("idea.home.path", "")
        
        jvmArgs(
            "-Djava.awt.headless=true",
            "--add-opens=java.base/java.lang=ALL-UNNAMED",
            "--add-opens=java.base/java.util=ALL-UNNAMED"
        )
    }
    
    // Create unit test task that runs without IntelliJ dependencies
    register<JavaExec>("unitTest") {
        dependsOn("compileUnitTestKotlin")
        
        mainClass.set("paviko.opencode.ui.StandaloneMessageTestKt")
        classpath = sourceSets["unitTest"].runtimeClasspath
        
        systemProperty("java.awt.headless", "true")
        
        jvmArgs(
            "-Djava.awt.headless=true",
            "--add-opens=java.base/java.lang=ALL-UNNAMED",
            "--add-opens=java.base/java.util=ALL-UNNAMED"
        )
    }
    
    // Make build depend on unit tests
    build {
        dependsOn("unitTest")
    }
}
