import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Wraps export bytes for `fileExporter`.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The CSV export as a folder of one file per table.
struct CSVFolderDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.folder]
    }

    let files: [String: Data]

    init(files: [String: Data]) {
        self.files = files
    }

    init(configuration: ReadConfiguration) throws {
        files = [:]
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: files
            .mapValues { FileWrapper(regularFileWithContents: $0) })
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}
