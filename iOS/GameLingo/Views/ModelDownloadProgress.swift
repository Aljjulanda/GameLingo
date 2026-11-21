import SwiftUI

struct ModelDownloadProgress: View {
    @ObservedObject var service: ModelDownloadService
    var body: some View {
        if service.active { ProgressView(value:service.fraction);Text("\(Int(service.fraction*100))% · "+service.status).font(.caption) }
        else if service.resumable { Text("يوجد تنزيل جزئي؛ زر التنزيل يستأنفه. قد يعيد الخادم التنزيل من البداية.").font(.caption) }
    }
}
