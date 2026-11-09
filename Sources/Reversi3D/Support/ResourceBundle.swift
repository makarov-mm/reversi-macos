import Foundation

/// The program's files, the shaders and the icon, in the resource bundle that the package builds, named after the
/// package and the target. It is looked for in the application's resources, where build.sh puts it, and beside the
/// executable, where `swift run` leaves it.
enum ResourceBundle {
    private static let suffix = "_Reversi3D.bundle"

    static func url(forResource resource: String, withExtension type: String, subdirectory: String? = nil) -> URL? {
        for bundle in bundles {
            if let url = bundle.url(forResource: resource, withExtension: type, subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }

    private static var bundles: [Bundle] {
        var places: [URL] = []
        if let resources = Bundle.main.resourceURL {
            places.append(resources)
        }
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            places.append(executable.deletingLastPathComponent())
        }
        places.append(Bundle.main.bundleURL)
        return places.flatMap { place in
            let contents = (try? FileManager.default.contentsOfDirectory(at: place, includingPropertiesForKeys: nil)) ?? []
            return contents.filter { $0.lastPathComponent.hasSuffix(suffix) }.compactMap { Bundle(url: $0) }
        }
    }
}
