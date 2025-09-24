plugins {
  `lifecycle-base`
}

tasks.named("clean") {
  dependsOn(gradle.includedBuilds.map { it.task(":${this.name}") })
}

tasks.named("check") {
  dependsOn(gradle.includedBuilds.map { it.task(":${this.name}") })
}
