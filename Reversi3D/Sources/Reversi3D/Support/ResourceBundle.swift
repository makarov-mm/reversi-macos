import Foundation

/// The program's files, the shaders and the icon, in the resource bundle that the package builds. It is looked for in
/// the application's resources, where build.sh puts it, and beside the executable, where `swift run` leaves it.
enum ResourceBundle {
    static let name = "Reversi3D_Reversi3D.bundle"

    static func url(forResource resource: String, withExtension type: String, subdirectory: String? = nil) -> URL? {
        var places: [URL] = []
        if let resources = Bundle.main.resourceURL {
            places.append(resources)
        }
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            places.append(executable.deletingLastPathComponent())
        }
        places.append(Bundle.main.bundleURL)
        for place in places {
            let path = place.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: path.path), let bundle = Bundle(url: path) else { continue }
            if let url = bundle.url(forResource: resource, withExtension: type, subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }
}
