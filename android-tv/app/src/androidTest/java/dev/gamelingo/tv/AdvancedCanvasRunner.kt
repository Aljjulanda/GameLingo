package dev.gamelingo.tv

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Bundle
import android.text.Spanned
import android.view.WindowManager
import org.json.JSONObject

/** Real Android spans, StaticLayout, outline and Canvas; preferably -PlabBuild. */
class AdvancedCanvasRunner : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val result=Bundle();var code=Activity.RESULT_CANCELED
        var view:SubtitleCanvas?=null;var bitmap:Bitmap?=null
        val prefs=targetContext.getSharedPreferences("advanced_canvas_fixture",Context.MODE_PRIVATE)
        val isolated=object:ContextWrapper(targetContext) {
            override fun getSharedPreferences(name:String,mode:Int):SharedPreferences = prefs
        }
        val wm=targetContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            runOnMainSync {
                val text=SpeakerText.inline("علينا التحرك الآن","Arthur",true,Color.rgb(166,199,216))
                check(text is Spanned && text.toString().startsWith("\u2068Arthur:\u2069 ") && !text.contains('\n'))
                check(text.getSpans(0,text.length,SpeakerColorSpan::class.java).single().color==Color.rgb(166,199,216))
                check(SpeakerText.inline("علينا التحرك الآن","Arthur",false,Color.RED).toString()=="علينا التحرك الآن")
                view=SubtitleCanvas(isolated) {}
                wm.addView(view,WindowManager.LayoutParams(1920,1080,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,PixelFormat.TRANSLUCENT))
                view!!.style=JSONObject().put("font_size",25).put("show_speakers",true).put("speaker_color","#A6C7D8").put("max_width",60)
                view!!.layout(0,0,1920,1080)
                bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888)
                fun caption(id:String,source:String,translated:String,speaker:String)=JSONObject().put("type","subtitle_show")
                    .put("id",id).put("source",source).put("translated",translated).put("speaker",JSONObject().put("name",speaker))
                view!!.message(caption("a","Follow me","اتبعني","Arthur"));view!!.draw(Canvas(bitmap!!))
                check(view!!.state.entries.single().speaker=="Arthur")
                check(view!!.measuredBoxes.single().second<120) {"Speaker unexpectedly created a separate row"}
                val anchor=view!!.measuredAnchor
                val until=view!!.state.entries.single().until
                view!!.message(caption("a","Follow me!","سر ورائي","Arthur"));view!!.draw(Canvas(bitmap!!))
                check(view!!.state.entries.single().text=="اتبعني")
                check(view!!.state.entries.single().until==until)
                view!!.message(null)
                view!!.message(caption("long","Follow me to the old gate", "علينا التحرك قبل أن يصل الحراس إلى البوابة القديمة. ".repeat(5),"John"))
                view!!.draw(Canvas(bitmap!!))
                check(view!!.measuredBoxes.single().first<=1152)
                check(view!!.measuredBoxes.single().second>120)
                check(view!!.measuredAnchor==anchor) {"Wrapping shifted the chosen anchor"}
                view!!.message(JSONObject().put("type","document_show").put("translated","لن نغادر قبل أن تجمع 11 قطعة نقدية. ".repeat(12)).put("page",1).put("pages",2))
                view!!.draw(Canvas(bitmap!!))
                check(view!!.measuredDocument!!.width()>1500 && view!!.state.entries.isEmpty())
                view!!.message(JSONObject().put("type","document_show").put("translated","هذه الصفحة الثانية.").put("page",2).put("pages",2))
                view!!.draw(Canvas(bitmap!!));check(view!!.measuredDocument!=null)
                view!!.message(JSONObject().put("type","document_hide"));view!!.draw(Canvas(bitmap!!))
                check(view!!.measuredDocument==null)
                view!!.message(caption("after-reading","Follow me","اتبعني","Arthur"));view!!.draw(Canvas(bitmap!!))
                check(view!!.state.entries.single().id=="after-reading")
            }
            result.putString("result","PASS: inline speaker/color/RTL/wrap, stable card/clock/anchor, document pages and return to dialogue")
            code=Activity.RESULT_OK
        } catch(t:Throwable) { result.putString("error",t.message ?: "Advanced Canvas fixture failed") }
        finally {runOnMainSync {view?.let {wm.removeViewImmediate(it)};bitmap?.recycle();prefs.edit().clear().commit()} }
        finish(code,result)
    }
}
