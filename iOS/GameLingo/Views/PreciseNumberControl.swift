import SwiftUI

struct PreciseNumberControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var defaultValue: Double = 0
    var integer = false
    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Text(title)
                Spacer()
                Button { assign(defaultValue) } label: { Image(systemName:"arrow.counterclockwise").frame(width:44,height:44) }
                    .accessibilityLabel("استعادة \(title) الافتراضية")
            }
            HStack(spacing:12) {
                Button { assign(value-step) } label: { Image(systemName:"minus").frame(width:44,height:44) }.disabled(value<=range.lowerBound)
                    .accessibilityLabel("تقليل \(title)")
                TextField("",text:$draft).font(.system(.body,design:.monospaced)).multilineTextAlignment(.center)
                    .keyboardType(range.lowerBound<0 ? .numbersAndPunctuation : .decimalPad).focused($focused)
                    .onSubmit { commit() }.accessibilityLabel(title)
                Button { assign(value+step) } label: { Image(systemName:"plus").frame(width:44,height:44) }.disabled(value>=range.upperBound)
                    .accessibilityLabel("زيادة \(title)")
            }.buttonStyle(.bordered).environment(\.layoutDirection,.leftToRight)
            Text("الحدود: \(NumericInput.format(range.lowerBound)) … \(NumericInput.format(range.upperBound))").font(.caption).foregroundColor(.secondary)
            if focused {
                HStack {
                    Button("تطبيق") { commit() }
                    Button("إلغاء") { draft = NumericInput.format(value); invalid = false; focused = false }
                }.buttonStyle(.bordered)
            }
            if invalid { Text("أدخل رقمًا صالحًا؛ لم تتغير القيمة المحفوظة").font(.caption).foregroundColor(.red) }
        }
        .onAppear { draft = NumericInput.format(value) }
        .onChange(of:value) { if !focused { draft = NumericInput.format($0) } }
        .onChange(of:focused) { if !$0 { commit() } }
    }
    private func assign(_ number: Double) {
        let bounded = min(range.upperBound,max(range.lowerBound,integer ? number.rounded() : number))
        if value != bounded { value = bounded }
        draft = NumericInput.format(value); invalid = false; focused = false
    }
    private func commit() {
        guard let number = NumericInput.parse(draft,range:range,integer:integer) else { invalid = true; return }
        assign(number)
    }
}
