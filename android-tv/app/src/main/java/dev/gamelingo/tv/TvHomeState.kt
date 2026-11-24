package dev.gamelingo.tv

internal enum class TvHomeAction { PERMISSION, PAIR, CONNECT, STOP }

/** UI state only. Saved credentials and protocol/session state retain their owners. */
internal data class TvHomeState(val title: String, val detail: String, val button: String, val action: TvHomeAction) {
    companion object {
        fun describe(permission: Boolean, paired: Boolean, active: Boolean, connected: Boolean, connecting: Boolean, preview: Boolean): TvHomeState = when {
            !permission -> TvHomeState("يلزم إذن عرض الترجمة", "اسمح بالظهور فوق التطبيقات لتظهر العربية فوق مدخل اللعب.", "السماح بعرض الترجمة", TvHomeAction.PERMISSION)
            active && connected -> TvHomeState("التلفزيون متصل", "ابدأ الترجمة من GameLingo على الآيفون أو Windows، ثم اختر مدخل PS5 بالريموت.", "إيقاف استقبال الترجمة", TvHomeAction.STOP)
            active && connecting -> TvHomeState("جارٍ الاتصال بالمصدر", "أبقِ GameLingo مفتوحًا على المصدر وتأكد أن الجهازين على الشبكة المحلية نفسها.", "إيقاف محاولة الاتصال", TvHomeAction.STOP)
            active && !preview -> TvHomeState("الاتصال يحتاج مراجعة", "افتح الاتصال لمعرفة السبب والخطوة المطلوبة؛ اقترانك المحفوظ لم يُحذف.", "مراجعة الاتصال", TvHomeAction.PAIR)
            !paired -> TvHomeState(if (preview) "معاينة النص فقط" else "اربط مصدر الترجمة", "اقترن بالآيفون عبر QR، أو أدخل عنوان المصدر ورمزه يدويًا.", "إعداد الاتصال", TvHomeAction.PAIR)
            preview -> TvHomeState("معاينة النص فقط", "هذه عينة مظهر؛ استقبال الترجمة متوقف. يمكنك الاتصال بالمصدر المحفوظ دون اقتران جديد.", "بدء استقبال الترجمة", TvHomeAction.CONNECT)
            else -> TvHomeState("استقبال الترجمة متوقف", "المصدر محفوظ. ابدأ الاستقبال دون إعادة الاقتران؛ الترجمة نفسها تبدأ من الآيفون أو Windows.", "بدء استقبال الترجمة", TvHomeAction.CONNECT)
        }
    }
}
