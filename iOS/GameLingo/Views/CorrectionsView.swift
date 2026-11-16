import SwiftUI
import UniformTypeIdentifiers

@MainActor final class CorrectionsLibrary: ObservableObject {
    @Published private(set) var snapshot = CorrectionsSnapshot(game:"general",general:true)
    @Published private(set) var recent: [RecentPublishedLine] = []
    @Published private(set) var message = ""
    private(set) var store: GameCorrectionsStore?
    private let root: URL
    private var selection: String?
    private var history = RecentPublishedLines()
    var onChange: ((CorrectionsSnapshot) -> Void)?
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("corrections",isDirectory:true)
        select(nil)
    }
    func select(_ selected: String?) {
        guard store == nil || selection != selected else { return }
        let game = selected ?? "general"
        do {
            let folder = root.appendingPathComponent(selected == nil ? "general" : "games",isDirectory:true)
            let opened = try GameCorrectionsStore(root:folder,game:game,general:selected == nil)
            store = opened; selection = selected
            opened.onChange = { [weak self,weak opened] in DispatchQueue.main.async {
                guard let self, let opened, self.store === opened else { return }; self.refresh()
            } }
            message = ""; refresh()
        } catch {
            store = nil; selection = selected
            snapshot = CorrectionsSnapshot(game:game,general:selected == nil ? true : nil)
            message = "تعذر تحميل التصحيحات؛ لم يُستبدل الملف السابق"
            history.select(snapshot.scopeKey); recent = history.entries; onChange?(snapshot)
        }
    }
    private func refresh() {
        if let store { snapshot = store.snapshot }
        history.select(snapshot.scopeKey); recent = history.entries; onChange?(snapshot)
    }
    // Receives only successfully published dialogues, never raw OCR candidates.
    func published(_ line: RecentPublishedLine) { history.published(line); recent = history.entries }
    func clearRecent() { history.clear(); recent = [] }
    @discardableResult func save(source: String, target: String, id: String? = nil) -> Bool {
        guard let store else { message = "تعذر فتح مخزن التصحيحات؛ لم يُحفظ التعديل"; return false }
        do { try store.save(source:source,target:target,id:id); message = "حُفظ التصحيح للمرات القادمة"; refresh(); return true }
        catch { message = error.localizedDescription; return false }
    }
    func remove(_ correction: UserCorrection) {
        do { try store?.remove(correction.id); message = "حُذف التصحيح"; refresh() }
        catch { message = error.localizedDescription }
    }
    func export() -> URL? { do { return try store?.export() } catch { message = "تعذر تصدير التصحيحات"; return nil } }
    func importFile(_ url: URL) {
        guard let store else { return }; message = "جارٍ قراءة التصحيحات"
        UserLibraryFile.read(url) { [weak self] result in
            guard let self, self.store === store else { return }
            do { try store.importData(result.get()); self.message = "استُوردت التصحيحات للعبة المختارة"; self.refresh() }
            catch { self.message = error.localizedDescription }
        }
    }
}

struct CorrectionsView: View {
    @ObservedObject var library: CorrectionsLibrary
    @State private var importing = false
    @State private var adding = false
    @State private var exportURL: URL?
    var body: some View {
        List {
            Section {
                Text("اللعبة: "+(library.snapshot.general == true ? "عام · دون لعبة محددة" : library.snapshot.game))
                Text("يُستخدم التصحيح في المرات القادمة عند تطابق الإنجليزية، مع قبول اختلاف الأحرف والمسافات. لا يُعاد عرض حوار قديم.").font(.footnote)
                Button("إضافة تصحيح") { adding = true }
                Button("استيراد تصحيحات JSON") { importing = true }
                Button("تجهيز التصحيحات للتصدير") { exportURL = library.export() }
                if let exportURL { ShareLink("تصدير corrections/\(library.snapshot.game).json",item:exportURL) }
                if !library.message.isEmpty { Text(library.message).font(.footnote) }
            }
            Section("حوارات نُشرت مؤخرًا · في الذاكرة فقط") {
                Text("آخر 20 حوارًا منشورًا. تُمسح عند إيقاف الترجمة أو تغيير اللعبة. لا يُحفظ منها إلا ما تعدّله صراحةً.").font(.footnote)
                ForEach(library.recent.reversed()) { line in
                    NavigationLink {
                        CorrectionEditor(library:library,source:line.source,target:line.target)
                    } label: {
                        VStack(alignment:.leading) { Text(line.source); Text(line.target); Text("تعديل").font(.caption) }
                    }
                }
            }
            Section("التصحيحات المحفوظة") {
                ForEach(library.snapshot.entries) { entry in
                    NavigationLink {
                        CorrectionEditor(library:library,source:entry.source,target:entry.target,existingID:entry.id)
                    } label: { VStack(alignment:.leading) { Text(entry.source); Text(entry.target) } }
                    .swipeActions { Button("حذف",role:.destructive) { library.remove(entry) } }
                }
            }
        }.navigationTitle("تصحيحاتي")
            .onChange(of:library.snapshot.scopeKey) { _ in exportURL = nil }
            .sheet(isPresented:$adding) { NavigationStack { CorrectionEditor(library:library,source:"",target:"") } }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.item]) { result in if case .success(let url) = result { library.importFile(url) } }
    }
}

private struct CorrectionEditor: View {
    @ObservedObject var library: CorrectionsLibrary
    let source: String
    let target: String
    var existingID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var english = ""
    @State private var arabic = ""
    @State private var editingScope = ""
    @State private var editingStore: GameCorrectionsStore?
    var body: some View {
        Form {
            TextField("النص الإنجليزي",text:$english,axis:.vertical).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("التصحيح العربي",text:$arabic,axis:.vertical)
            Button("حفظ التصحيح") {
                guard editingScope == library.snapshot.scopeKey, library.store === editingStore else { return }
                if library.save(source:english.trimmingCharacters(in:.whitespacesAndNewlines),target:arabic.trimmingCharacters(in:.whitespacesAndNewlines),id:existingID) { dismiss() }
            }.disabled(editingScope != library.snapshot.scopeKey || library.store !== editingStore || english.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || arabic.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            if !editingScope.isEmpty && editingScope != library.snapshot.scopeKey { Text("تغيّرت اللعبة؛ ارجع وافتح التصحيح من جديد").foregroundColor(.orange) }
            if !library.message.isEmpty { Text(library.message).font(.footnote) }
        }.navigationTitle("تعديل الترجمة")
            .onAppear { english = source; arabic = target; editingScope = library.snapshot.scopeKey; editingStore = library.store }
    }
}
