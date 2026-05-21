import Foundation

// MARK: - AssetCatalog

/// A parsed `.xcassets` bundle — the set of named image and color assets it declares.
///
/// Build one via `AssetCatalogParser.parse(catalogURL:)` or merge several with
/// `AssetCatalog.merged(_:)` when a project has multiple catalogs.
public struct AssetCatalog: Sendable {
    /// URL of the `.xcassets` bundle this catalog was parsed from.
    public let url: URL
    /// Names of all image assets (`.imageset` directories), including namespaced ones.
    public let imageNames: Set<String>
    /// Names of all color assets (`.colorset` directories), including namespaced ones.
    public let colorNames: Set<String>

    public init(url: URL, imageNames: Set<String>, colorNames: Set<String>) {
        self.url = url
        self.imageNames = imageNames
        self.colorNames = colorNames
    }

    public func contains(image name: String) -> Bool { imageNames.contains(name) }
    public func contains(color name: String) -> Bool { colorNames.contains(name) }

    /// Total number of declared assets.
    public var count: Int { imageNames.count + colorNames.count }

    /// Merge multiple catalogs so a single `validate()` call covers all of them.
    /// `url` is taken from the first catalog (used in diagnostic messages).
    public static func merged(_ catalogs: [AssetCatalog]) -> AssetCatalog {
        AssetCatalog(
            url: catalogs.first?.url ?? URL(fileURLWithPath: "."),
            imageNames: catalogs.reduce(into: []) { $0.formUnion($1.imageNames) },
            colorNames: catalogs.reduce(into: []) { $0.formUnion($1.colorNames) }
        )
    }
}

// MARK: - AssetCatalogParser

/// Walks a `.xcassets` directory and extracts all named image and color assets.
///
/// Rules:
/// - `.imageset` directories → image names
/// - `.colorset` directories → color names
/// - `.appiconset`, `.symbolset`, `.dataset` → skipped (not accessed by name in user code)
/// - Folder groups with `"provides-namespace": true` in their `Contents.json`
///   prefix child asset names with the group name (matches Xcode's runtime behaviour)
public struct AssetCatalogParser: Sendable {

    // MARK: - Public API

    /// Parse a single `.xcassets` bundle.
    public static func parse(catalogURL: URL) throws -> AssetCatalog {
        var imageNames: Set<String> = []
        var colorNames: Set<String> = []
        collectAssets(in: catalogURL, namespace: "", imageNames: &imageNames, colorNames: &colorNames)
        return AssetCatalog(url: catalogURL, imageNames: imageNames, colorNames: colorNames)
    }

    /// Find every `.xcassets` bundle inside `directoryURL`, non-recursing into bundles.
    public static func findCatalogs(in directoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "xcassets" {
            results.append(url)
            enumerator.skipDescendants()   // don't descend into the catalog itself
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Parse every `.xcassets` catalog inside `directoryURL` and return a merged catalog.
    public static func parseCatalogs(in directoryURL: URL) throws -> AssetCatalog {
        let urls = findCatalogs(in: directoryURL)
        let catalogs = try urls.map { try parse(catalogURL: $0) }
        return AssetCatalog.merged(catalogs)
    }

    // MARK: - Private walk

    private static func collectAssets(
        in directory: URL,
        namespace: String,
        imageNames: inout Set<String>,
        colorNames: inout Set<String>
    ) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            let ext  = item.pathExtension
            let stem = item.deletingPathExtension().lastPathComponent

            switch ext {
            case "imageset":
                imageNames.insert(fullName(stem: stem, namespace: namespace))

            case "colorset":
                colorNames.insert(fullName(stem: stem, namespace: namespace))

            case "appiconset", "symbolset", "dataset", "brandassets",
                 "complicationset", "stickerspackextension":
                break  // not accessed by name in user code

            default:
                // Could be a folder group — descend if it's a directory
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir),
                      isDir.boolValue, ext != "xcassets"
                else { continue }

                let childNamespace = providesNamespace(directory: item)
                    ? fullName(stem: item.lastPathComponent, namespace: namespace)
                    : namespace
                collectAssets(in: item, namespace: childNamespace,
                              imageNames: &imageNames, colorNames: &colorNames)
            }
        }
    }

    /// Check `Contents.json` in a folder group for `properties.provides-namespace = true`.
    private static func providesNamespace(directory: URL) -> Bool {
        let contentsURL = directory.appendingPathComponent("Contents.json")
        guard
            let data       = try? Data(contentsOf: contentsURL),
            let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let properties = json["properties"] as? [String: Any],
            let flag       = properties["provides-namespace"] as? Bool
        else { return false }
        return flag
    }

    private static func fullName(stem: String, namespace: String) -> String {
        namespace.isEmpty ? stem : "\(namespace)/\(stem)"
    }
}
