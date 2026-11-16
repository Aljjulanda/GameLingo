import Foundation

/// Only names and explicit user corrections use this storage. No automatic
/// dialogue history. Callers serialize access and validate their bounded schema.
enum UserDataFile {
    static let limit = 4*1024*1024
    static func validGame(_ value: String) -> Bool {
        value.range(of:"^[a-z0-9][a-z0-9._-]{0,63}$",options:.regularExpression) != nil && value != "." && value != ".."
    }
    static func url(root: URL, game: String) throws -> URL {
        guard validGame(game) else { throw LingoError.invalid("معرّف اللعبة غير صالح") }
        return root.appendingPathComponent(game+".json")
    }
    static func read(_ file: URL) throws -> Data {
        guard (try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? limit+1) <= limit else { throw LingoError.invalid("ملف البيانات كبير جدًا") }
        let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount:65536), !chunk.isEmpty {
            guard data.count+chunk.count <= limit else { throw LingoError.invalid("ملف البيانات كبير جدًا") }; data.append(chunk)
        }
        return data
    }
    static func write(_ data: Data, to file: URL) throws {
        guard data.count <= limit else { throw LingoError.invalid("ملف البيانات كبير جدًا") }
        let folder = file.deletingLastPathComponent(), fm = FileManager.default
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        var protected = folder, attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try protected.setResourceValues(attributes)
        #if os(iOS)
        // Names/corrections must remain readable by the existing background
        // session after first unlock. Test captures use the stricter COMPLETE.
        try fm.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:folder.path)
        try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        try fm.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:file.path)
        #else
        try data.write(to:file,options:.atomic)
        #endif
    }
}
