import Foundation
import Metal

/// The shaders, compiled at start from the Metal sources in the program's resources. The files are put together in
/// order, so that the later ones use what the earlier ones define, each marked with its name for the compiler's
/// messages.
struct ShaderLibrary {
    private static let files = ["Common", "Lighting", "Disc", "Surface", "Shadow", "PostProcess", "Interface", "Probes"]

    private let library: MTLLibrary

    init(device: MTLDevice) throws {
        var source = ""
        for name in Self.files {
            guard let url = ResourceBundle.url(forResource: name, withExtension: "metal", subdirectory: "Shaders") else {
                throw RendererError.missingResource("Shaders/\(name).metal")
            }
            source += "#line 1 \"\(name).metal\"\n"
            source += try String(contentsOf: url, encoding: .utf8)
            source += "\n"
        }
        do {
            library = try device.makeLibrary(source: source, options: MTLCompileOptions())
        } catch {
            throw RendererError.shaderCompilation(error.localizedDescription)
        }
    }

    func function(_ name: String) throws -> MTLFunction {
        guard let function = library.makeFunction(name: name) else { throw RendererError.missingFunction(name) }
        return function
    }
}
