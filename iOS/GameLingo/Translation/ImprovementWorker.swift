import Foundation

/// Actual on-device, serial, bounded idle work using the installed free engine.
/// No computer/server is needed and the worker never trains model weights.
final class ImprovementWorker {
    private let queue = DispatchQueue(label:"dev.gamelingo.improvement",qos:.utility)
    private let lock = NSLock()
    private var generation = UUID()
    private var consent = false
    private var store: ImprovementMemoryStore?
    private var busy = false
    private var memoryVersion = 0
    private var queued = 0
    var onUpdate: ((String,ImprovedMemorySnapshot) -> Void)?
    init() {
        queue.async { [self] in
            do {
                let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LocalImprovement",isDirectory:true)
                store = try ImprovementMemoryStore(root:root); report("التحسين المحلي متوقف؛ لا جمع دون موافقة")
            } catch { report("تعذر فتح ذاكرة التحسين؛ حُفظ الأصل دون تغيير") }
        }
    }
    func setConsent(_ value: Bool) { queue.async { self.consent = value; self.report(value ? "الجمع المحلي مفعّل · نصوص فقط · 200 مثال / 7 أيام" : "توقف الجمع والمعالجة؛ الذاكرة المعتمدة باقية") }; if !value { cancel() } }
    func observe(_ example: ImprovementExample) {
        // Bound ingress before dispatching, including while disk writes are slow.
        lock.lock(); guard queued < 16 else { lock.unlock(); return }; queued += 1; lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); queued -= 1; lock.unlock() }
            guard consent, let store else { return }
            // Two real OCR observations suffice; do not rewrite a file every frame.
            if let old = store.raw.first(where:{$0.game == example.game && PackLookupKey.normalized($0.source) == PackLookupKey.normalized(example.source) && $0.context == example.context}), old.observations >= 3, old.trustedTarget != nil { return }
            do {
                try store.observe(example,consent:consent)
                let count = try store.approveAutomatic()
                if count > 0 { report("تعلم تلقائي محلي · مرجع مستقل معتمد؛ دون تدريب النموذج") }
            } catch { report("تعذر حفظ المثال المحلي؛ لم يُستخدم لتحسين الترجمة") }
        }
    }
    func cancel() { lock.lock(); generation = UUID(); lock.unlock() }
    private func accepts(_ id: UUID) -> Bool { lock.lock();defer{lock.unlock()};return generation == id }
    private func report(_ status: String) {
        memoryVersion += 1; let snapshot = ImprovedMemorySnapshot(entries:store?.approved ?? [],version:memoryVersion)
        DispatchQueue.main.async { self.onUpdate?(status,snapshot) }
    }
    func run(translator: OfflineTranslator) {
        lock.lock(); let id = generation; lock.unlock()
        queue.async { [self] in
            guard consent, !busy, accepts(id), let store else { return }
            do { try store.prune() } catch { report("تعذر تنظيف الأمثلة؛ توقفت الدورة");return }
            let handled = Set(store.proposals.map(\.id))
            let work = Array(store.raw.filter{!handled.contains($0.id) && $0.observations >= 2 && $0.confidence >= 0.9 && !$0.context.isEmpty && $0.authority?.hasPrefix("pack-exact:") == true && $0.trustedTarget != nil}.prefix(10))
            guard !work.isEmpty else { report("لا أمثلة مؤهلة بعد؛ يلزم OCR متكرر ومرجع حزمة حرفي وسياق");return }
            busy = true; report("دورة محلية محدودة خارج اللعب · \(work.count) أمثلة")
            process(work,index:0,accepted:0,id:id,translator:translator)
        }
    }
    private func process(_ work: [ImprovementExample], index: Int, accepted: Int, id: UUID, translator: OfflineTranslator) {
        guard accepts(id), consent, index < work.count else { busy = false;report("انتهت/توقفت الدورة · اعتمدت \(accepted) · لا ادعاء بتحسن الجمل غير المغطاة");return }
        let example = work[index]
        translator.propose(example.source) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.accepts(id), self.consent else { self.busy = false;return }
                var count = accepted
                do {
                    if case .success(let candidate) = result, try self.store?.record(example,candidate:candidate) == true { count += 1 }
                } catch { self.busy = false;self.report("فشل حفظ نتيجة الدورة؛ لم تُغير التصحيحات أو النموذج");return }
                self.process(work,index:index+1,accepted:count,id:id,translator:translator)
            }
        }
    }
    func deleteCollected() { cancel();queue.async { do {try self.store?.deleteCollected(); self.report("حُذفت النصوص الخام والاقتراحات")} catch {self.report("تعذر الحذف")} } }
    func rollback() { cancel();queue.async { do {try self.store?.rollbackApproved(); self.report("أُزيلت إضافات الذاكرة المعتمدة؛ الأصول والتصحيحات محفوظة")} catch {self.report("تعذر التراجع")} } }
    func export(_ completion: @escaping (URL?) -> Void) { queue.async {let url = try? self.store?.export();DispatchQueue.main.async{completion(url)}} }
}
