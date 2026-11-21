import Foundation
import Combine

/// Only catalog-pinned packages. Resume blobs are local, bounded, protected and
/// never contain TV/PS5 credentials. Installation verifies size+SHA separately.
final class ModelDownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private(set) var fraction = 0.0
    @Published private(set) var status = "لم يبدأ التنزيل"
    @Published private(set) var active = false
    private var task: URLSessionDownloadTask?
    private var cancelled = Set<Int>()
    private var delivered = Set<Int>()
    private var generation = UUID()
    private let root: URL
    private lazy var session = URLSession(configuration:.default,delegate:self,delegateQueue:.main)
    var completion: ((Result<URL,Error>) -> Void)?
    private var resumeFile: URL { root.appendingPathComponent("argos-resume.data") }
    var resumable: Bool { FileManager.default.fileExists(atPath:resumeFile.path) }
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ModelDownloads",isDirectory:true)
        super.init()
    }
    func start() {
        guard !active else { return }
        generation = UUID()
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let values = try root.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])
            guard (values.volumeAvailableCapacityForImportantUsage ?? 0) > 400*1024*1024 else { throw LingoError.invalid("يلزم 400 MB من المساحة الحرة للتنزيل والتثبيت الآمن") }
            var folder = root; var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true; try folder.setResourceValues(excluded)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:root.path)
            #endif
            if let data = try? UserDataFile.read(resumeFile), !data.isEmpty {
                task = session.downloadTask(withResumeData:data)
                // Consume the blob. If the OS rejects stale/corrupt resume data
                // without returning a new blob, the next action starts cleanly.
                try? FileManager.default.removeItem(at:resumeFile)
            }
            else {
                var request = URLRequest(url:OfflineTranslator.modelURL)
                request.setValue("GameLingo/1.0",forHTTPHeaderField:"User-Agent"); request.setValue("application/octet-stream",forHTTPHeaderField:"Accept")
                task = session.downloadTask(with:request)
            }
            active = true; status = "تنزيل Argos EN → AR مع التحقق بعد الاكتمال"; task?.resume()
        } catch { completion?(.failure(error)) }
    }
    func pause(keepingResume: Bool = true) {
        guard let task else { return }
        cancelled.insert(task.taskIdentifier); self.task = nil; active = false; status = "توقف التنزيل؛ يمكن استئنافه"
        generation = UUID(); let id = generation
        task.cancel { [weak self] data in
            DispatchQueue.main.async {
                guard let self, keepingResume, self.generation == id, let data, data.count <= UserDataFile.limit else { return }
                try? UserDataFile.write(data,to:self.resumeFile)
            }
        }
    }
    func discard() { pause(keepingResume:false); try? FileManager.default.removeItem(at:resumeFile); fraction = 0; status = "حُذف التنزيل الجزئي" }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard task?.taskIdentifier == downloadTask.taskIdentifier else { return }
        guard totalBytesWritten <= OfflineTranslator.modelSize else { downloadTask.cancel();return }
        fraction = min(1,Double(totalBytesWritten)/Double(OfflineTranslator.modelSize))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard task?.taskIdentifier == downloadTask.taskIdentifier, !cancelled.contains(downloadTask.taskIdentifier) else { return }
        do {
            guard [200,206].contains((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0), downloadTask.response?.url?.scheme == "https",
                  try location.resourceValues(forKeys:[.fileSizeKey]).fileSize == Int(OfflineTranslator.modelSize) else { throw LingoError.invalid("استجابة أو حجم حزمة النموذج غير صالح") }
            let ready = root.appendingPathComponent("verified-next-"+UUID().uuidString+".argosmodel")
            try FileManager.default.moveItem(at:location,to:ready)
            delivered.insert(downloadTask.taskIdentifier); task = nil; active = false; fraction = 1; status = "اكتمل التنزيل؛ جارٍ فحص SHA-256 والتثبيت"
            try? FileManager.default.removeItem(at:resumeFile)
            completion?(.success(ready))
        } catch { delivered.insert(downloadTask.taskIdentifier); task = nil; active = false; status = "رُفضت الحزمة"; completion?(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if cancelled.remove(task.taskIdentifier) != nil || delivered.remove(task.taskIdentifier) != nil { return }
        guard self.task?.taskIdentifier == task.taskIdentifier else { return }
        self.task = nil; active = false
        if let error {
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data, data.count <= UserDataFile.limit { try? UserDataFile.write(data,to:resumeFile) }
            status = "تعثر التنزيل؛ يمكن المحاولة أو الاستئناف"; completion?(.failure(error))
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https", let host = request.url?.host, ["argos-net.com","www.argos-net.com"].contains(host) else { completionHandler(nil); return }
        completionHandler(request)
    }
}
