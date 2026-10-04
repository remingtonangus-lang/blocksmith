import Foundation

// Imported PNG textures (Sources/TextureImport.swift decodes them with AppKit). The Quest build uses the procedural
// materials only for now; Resources/Textures is empty on the main line.
enum TextureImport {
    static func image(_ name: String, size n: Int) -> [V4]? { nil }
}
