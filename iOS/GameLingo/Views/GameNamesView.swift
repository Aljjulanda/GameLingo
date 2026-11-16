import SwiftUI
import UniformTypeIdentifiers

@MainActor final class GameNamesLibrary: ObservableObject {
    @Published private(set) var snapshot = GameNamesSnapshot(game:"general")
    @Published private(set) var message = ""
    private(set) var store: GameNamesStore?
    private let root: URL
    private var selection: String?
    var onChange: ((GameNamesStore?,GameNamesSnapshot) -> Void)?
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("names",isDirectory:true)
        select(nil)
    }
    func select(_ selected: String?) {
        guard store == nil || selection != selected else { return }
        let game = selected ?? "general"
        do {
            let folder = root.appendingPathComponent(selected == nil ? "general" : "games",isDirectory:true)
            let store = try GameNamesStore(root:folder,game:game,general:selected == nil); self.store = store; selection = selected
            store.onChange = { [weak self,weak store] in DispatchQueue.main.async {
                guard let self, let store, self.store === store else { return }; self.refresh()
            } }
            message = ""; refresh()
        } catch { store = nil; selection = selected; snapshot = GameNamesSnapshot(game:game,general:selected == nil ? true : nil); message = "تعذر تحميل الأسماء؛ لم يُستبدل الملف السابق"; onChange?(nil,snapshot) }
    }
    private func refresh() { if let store { snapshot = store.snapshot }; onChange?(store,snapshot) }
    @discardableResult func save(_ name: GameName) -> Bool {
        guard let store else { message = "تعذر فتح مخزن الأسماء؛ لم يُحفظ التعديل"; return false }
        do { try store.upsert(name,explicit:true); message = "حُفظت التهجئة اليدوية"; refresh(); return true }
        catch { message = error.localizedDescription; return false }
    }
    func remove(_ name: GameName) { do { try store?.remove(name.english); message = "حُذف الاسم ولن يُتعلّم مجددًا؛ يمكن إعادته بإضافة يدوية صريحة"; refresh() } catch { message = error.localizedDescription } }
    func seed(_ pairs: [(String,String)]) {
        do { for (english,arabic) in pairs { try store?.upsert(GameName(english:english,type:.person,arabic:arabic,source:.pack,count:0)) }; refresh() }
        catch { message = "تعذر حفظ بعض أسماء الحزمة" }
    }
    func export() -> URL? { do { return try store?.export() } catch { message = "تعذر تصدير الأسماء"; return nil } }
    func importFile(_ url: URL) {
        guard let store else { return }
        message = "جارٍ قراءة ملف الأسماء"
        UserLibraryFile.read(url) { [weak self] result in
            guard let self, self.store === store else { return }
            do { try store.importData(result.get()); self.message = "استُوردت الأسماء مع حفظ التهجئات اليدوية والمحذوفات"; self.refresh() }
            catch { self.message = error.localizedDescription }
        }
    }
}

/// Shared small user-data import route; the game-pack universal importer remains
/// independent. No executing, unpacking or uploading these JSON files.
enum UserLibraryFile {
    static func read(_ url: URL, completion: @escaping (Result<Data,Error>) -> Void) {
        let scoped = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos:.utility).async {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var coordination: NSError?, result: Result<Data,Error> = .failure(LingoError.invalid("تعذرت قراءة الملف"))
            NSFileCoordinator().coordinate(readingItemAt:url,options:.withoutChanges,error:&coordination) { file in result = Result { try UserDataFile.read(file) } }
            let final = coordination.map { Result<Data,Error>.failure($0) } ?? result
            DispatchQueue.main.async { completion(final) }
        }
    }
}

struct GameNamesView: View {
    @ObservedObject var library: GameNamesLibrary
    @State private var importing = false
    @State private var adding = false
    @State private var exportURL: URL?
    var body: some View {
        List {
            Section {
                Text("اللعبة: "+(library.snapshot.general == true ? "عام · دون لعبة محددة" : library.snapshot.game))
                Text("الأسماء المحذوفة بقرارك: \(library.snapshot.userDeletions)")
                Button("إضافة اسم") { adding = true }
                Button("استيراد أسماء من ملف JSON") { importing = true }
                Button("تجهيز ملف الأسماء للتصدير") { exportURL = library.export() }
                if let exportURL { ShareLink("تصدير names/\(library.snapshot.game).json",item:exportURL) }
                if !library.message.isEmpty { Text(library.message).font(.footnote) }
                Text("التهجئة المقترحة تقريبية وقابلة للتعديل. تهجئتك اليدوية تتقدّم على الحزمة والتعلم التلقائي. لا تحتوي هذه القائمة على سجل الحوارات.").font(.footnote)
            }
            ForEach(library.snapshot.entries.sorted{$0.id < $1.id}) { name in
                NavigationLink {
                    GameNameEditor(library:library,existing:name)
                } label: {
                    VStack(alignment:.leading) {
                        Text(name.english+" · "+name.arabic)
                        Text(name.source.title+" · "+name.type.title+" · \(name.count) مرات").font(.caption).foregroundColor(.secondary)
                    }
                }.swipeActions { Button("حذف",role:.destructive) { library.remove(name) } }
            }
        }.navigationTitle("أسماء اللعبة")
            .onChange(of:library.snapshot.scopeKey) { _ in exportURL = nil }
            .sheet(isPresented:$adding) { NavigationStack { GameNameEditor(library:library,existing:nil) } }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.item]) { result in if case .success(let url) = result { library.importFile(url) } }
    }
}

private struct GameNameEditor: View {
    @ObservedObject var library: GameNamesLibrary
    let existing: GameName?
    @Environment(\.dismiss) private var dismiss
    @State private var english = ""
    @State private var arabic = ""
    @State private var type: GameNameType = .person
    @State private var editingScope = ""
    var body: some View {
        Form {
            TextField("الاسم الإنجليزي",text:$english).autocorrectionDisabled().textInputAutocapitalization(.never).disabled(existing != nil)
            TextField("التهجئة العربية",text:$arabic)
            Picker("النوع",selection:$type) { ForEach(GameNameType.allCases,id:\.rawValue) { Text($0.title).tag($0) } }
            Button("اقتراح تهجئة تقريبية") { arabic = NameTransliteration.arabic(english) }
            Button("حفظ") {
                let name = GameName(english:DialogueText.normalized(english),type:type,arabic:arabic.trimmingCharacters(in:.whitespacesAndNewlines),source:.manual,count:existing?.count ?? 0)
                guard name.valid, editingScope == library.snapshot.scopeKey else { return }; if library.save(name) { dismiss() }
            }.disabled(editingScope != library.snapshot.scopeKey || !GameName(english:english,type:type,arabic:arabic,source:.manual,count:0).valid)
            if !editingScope.isEmpty && editingScope != library.snapshot.scopeKey { Text("تغيّرت اللعبة؛ ارجع وافتح قائمة الأسماء من جديد").foregroundColor(.orange) }
            if !library.message.isEmpty { Text(library.message).font(.footnote) }
        }.navigationTitle(existing == nil ? "إضافة اسم" : "تعديل التهجئة")
            .onAppear { editingScope = library.snapshot.scopeKey; if let existing { english = existing.english; arabic = existing.arabic; type = existing.type } }
    }
}
