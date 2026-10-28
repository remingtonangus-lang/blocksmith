// Replaced by quest/tools/build-apk.sh with the commit being built.
enum QuestBuild {
    static let commit = "dev"
    static let milestone = "dev"
    static let versionCode = "0"
    static let meshHash = "dev"          // P400: hash of the sources that shape meshes and terrain (MeshCache.buildKey)
    static let reportURL = ""            // P480: where the in-game reporter sends (build-apk.sh fills it in; never in the repo)
}
