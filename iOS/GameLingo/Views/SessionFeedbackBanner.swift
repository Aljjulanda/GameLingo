import SwiftUI
import UIKit
import UserNotifications

struct SessionFeedbackBanner: View {
    @ObservedObject var feedback: SessionFeedbackPresenter
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let notice = feedback.notice {
                HStack(alignment:.top,spacing:12) {
                    Image(systemName:notice.symbol).font(.title2)
                        .foregroundStyle(notice.kind == .failed ? Color.orange : Color.teal)
                        .accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:4) {
                        Text(notice.title).font(.headline)
                        if !notice.body.isEmpty { Text(notice.body).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Button { feedback.dismiss() } label: {
                        Image(systemName:"xmark").font(.subheadline.weight(.semibold)).frame(width:44,height:44)
                    }.buttonStyle(.plain).accessibilityLabel("إغلاق التنبيه")
                }
                .padding(16).frame(maxWidth:500)
                .background {
                    if reduceTransparency { RoundedRectangle(cornerRadius:22).fill(Color(uiColor:.secondarySystemBackground)) }
                    else { RoundedRectangle(cornerRadius:22).fill(.ultraThinMaterial) }
                }
                .overlay { RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.35),lineWidth:1) }
                .shadow(color:.black.opacity(0.12),radius:16,y:6)
                .transition(reduceMotion ? .opacity : .move(edge:.top).combined(with:.opacity))
                .accessibilityIdentifier("session.feedback")
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration:0.22),value:feedback.notice?.id)
    }
}

struct SessionNotificationSettings: View {
    @ObservedObject var feedback: SessionFeedbackPresenter
    @Environment(\.openURL) private var openURL
    var body: some View {
        Section("تنبيهات حالة الترجمة") {
            Text("تنبيه زجاجي داخل التطبيق، وإشعار هادئ خارجه عند التشغيل أو الإيقاف أو التعذّر.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("اختبار التنبيه الزجاجي") { feedback.previewBanner() }
            Button("إرسال إشعار تجريبي") { Task { await feedback.testSystemNotification() } }
                .disabled(feedback.testingNotification)
            if feedback.authorization == .denied {
                Button("فتح إعدادات الإشعارات") { if let url = URL(string:UIApplication.openSettingsURLString) { openURL(url) } }
            } else if feedback.authorization == .notDetermined {
                Button("السماح بإشعارات الحالة") { feedback.requestAuthorizationIfNeeded() }
            } else {
                Label("إشعارات الحالة مسموحة",systemImage:"bell.badge")
            }
            if !feedback.notificationDiagnostic.isEmpty {
                Text(feedback.notificationDiagnostic).font(.footnote).foregroundStyle(.secondary)
            }
            if !feedback.presentationSummary.isEmpty {
                Text(feedback.presentationSummary).font(.footnote).foregroundStyle(.secondary)
            }
        }.task { await feedback.refreshAuthorization() }
    }
}

struct ControlInstallationSection: View {
    private let info = InstalledControlInfo.inspect()
    var body: some View {
        Section("النسخة المثبتة ومركز التحكم") {
            LabeledContent("الآيفون",value:info.appVersion+" ("+(info.appBuild ?? "؟")+")")
            if let build = info.controlBuild {
                LabeledContent("إضافة مركز التحكم",value:"موجودة · Build "+build)
                if info.versionsMatch == false {
                    Text("نسخة الإضافة تختلف عن التطبيق. اطلب من المتجر تثبيت التطبيق وإضافته من الحزمة نفسها.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } else {
                Text("إضافة مركز التحكم غير موجودة في هذه الحزمة. اطلب من المتجر تضمينها وتوقيعها مع التطبيق.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Text("هذا الفحص يؤكد وجود ملفات الإضافة ورقمها؛ لا يتحقق من توقيع المتجر أو تسجيلها في iOS.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
