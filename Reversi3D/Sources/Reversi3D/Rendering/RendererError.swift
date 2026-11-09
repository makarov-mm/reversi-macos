/// Why the game cannot draw.
enum RendererError: Error, CustomStringConvertible {
    case noDevice
    case missingResource(String)
    case shaderCompilation(String)
    case missingFunction(String)
    case creationFailed(String)

    var description: String {
        switch self {
        case .noDevice: "This Mac has no graphics device that supports Metal."
        case .missingResource(let name): "A file is missing from the program: \(name)."
        case .shaderCompilation(let log): "The shaders do not compile:\n\(log)"
        case .missingFunction(let name): "The shader function \(name) is missing."
        case .creationFailed(let what): "The \(what) could not be created."
        }
    }
}
