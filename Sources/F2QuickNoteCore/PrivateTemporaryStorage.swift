import Foundation

/// Creates and cleans only app-owned, UUID-named private temporary folders.
/// It never reads captured file contents and refuses symbolic-link bases.
public enum PrivateTemporaryStorage {
    public enum StorageError: Error {
        case unsafeBaseDirectory
    }

    public static func makeCaptureDirectory(
        in requestedBase: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = requestedBase.standardizedFileURL
        guard base.isFileURL,
              base.path != "/",
              base.path != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path else {
            throw StorageError.unsafeBaseDirectory
        }

        if fileManager.fileExists(atPath: base.path) {
            guard (try? fileManager.destinationOfSymbolicLink(atPath: base.path)) == nil else {
                throw StorageError.unsafeBaseDirectory
            }
            let attributes = try fileManager.attributesOfItem(atPath: base.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw StorageError.unsafeBaseDirectory
            }
        } else {
            try fileManager.createDirectory(
                at: base,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)

        let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.path) else {
            throw StorageError.unsafeBaseDirectory
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory
    }

    public static func cleanOwnedDirectories(
        in requestedBase: URL,
        fileManager: FileManager = .default
    ) {
        let base = requestedBase.standardizedFileURL
        guard base.isFileURL,
              base.path != "/",
              base.path != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path,
              fileManager.fileExists(atPath: base.path),
              (try? fileManager.destinationOfSymbolicLink(atPath: base.path)) == nil,
              (try? fileManager.attributesOfItem(atPath: base.path)[.type] as? FileAttributeType) == .typeDirectory else {
            return
        }
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        let entries = (try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }
}
