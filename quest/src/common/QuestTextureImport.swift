import Foundation

// Imported textures on the Quest. The Mac decodes Resources/Textures/<name>.png with AppKit (Sources/TextureImport.swift);
// Android has no ImageIO, so tools/texpack.py packs the same PNGs into Resources/texpack.bin, which the APK carries as
// assets/texpack.bin. AndroidMain reads it through the AAssetManager into `pack` before the textures are painted;
// without a pack (or an empty one) every layer stays procedural, as before.
enum TextureImport {
    static var pack: TexPack?
    // The pack's content hash, kept after release() (TextureCache keys on it).
    private(set) static var hash: String?

    static func load(_ d: Data?) {
        guard let d else { print("textures: no texpack.bin, procedural only"); return }
        guard let p = TexPack(d) else { print("textures: texpack.bin (\(d.count) bytes) is invalid, ignored"); return }
        pack = p
        hash = p.hash
        print("textures: texpack.bin \(p.entries.count) imported at \(p.tile) px (hash \(p.hash))")
    }

    static func image(_ name: String, size n: Int) -> [V4]? { pack?.image(name, size: n) }

    // Drops the unpacked pixels (57 MB at 128 px) once the layers are painted or read from the cache.
    static func release() { pack = nil }
}
