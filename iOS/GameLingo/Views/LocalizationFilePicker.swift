import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A separate UIKit presentation avoids sharing SwiftUI file-importer presentation
/// preferences with the Argos importer on the parent Translation screen.
struct LocalizationFilePicker: UIViewControllerRepresentable {
    var directory: URL?
    let selected: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        Self.controller(directory:directory,delegate:context.coordinator)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    static func controller(directory: URL?, delegate: UIDocumentPickerDelegate?) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes:GamePackDocument.pickerTypes,asCopy:true)
        controller.delegate = delegate; controller.allowsMultipleSelection = false
        controller.shouldShowFileExtensions = true; controller.directoryURL = directory
        controller.title = "إضافة ملف تعريب"
        return controller
    }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL?) -> Void
        init(_ selected: @escaping (URL?) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { selected(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selected(nil) }
    }
}

struct LocalizationInbox {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]) { self.directory = directory }
    func prepare() throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let instructions = directory.appendingPathComponent("GameLingo-Import.txt")
        if !FileManager.default.fileExists(atPath:instructions.path) {
            try Data("انسخ ملف التعريب إلى هذا المجلد، ثم افتح GameLingo ← الترجمة ← مكتبة ترجمات الألعاب ← تحديث ملفات المجلد، واضغط اسم الملف لفحصه. نسخ الملف لا يثبّت ترجمة قبل التحقق منها.\n".utf8).write(to:instructions,options:.atomic)
        }
    }
    func files() throws -> [URL] {
        try prepare()
        let keys: Set<URLResourceKey> = [.isRegularFileKey,.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at:directory,includingPropertiesForKeys:Array(keys),options:[.skipsHiddenFiles,.skipsSubdirectoryDescendants]) else { return [] }
        var result: [URL] = [], count = 0
        for case let url as URL in enumerator {
            count += 1; guard count <= 256 else { throw LocalizationImportFailure.limit }
            let values = try url.resourceValues(forKeys:keys)
            if values.isRegularFile == true, values.isSymbolicLink != true, url.lastPathComponent != "GameLingo-Import.txt" { result.append(url) }
        }
        return result.sorted {$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}
    }
}
