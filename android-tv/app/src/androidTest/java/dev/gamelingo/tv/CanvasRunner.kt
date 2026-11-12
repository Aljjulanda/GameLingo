package dev.gamelingo.tv

import android.app.Instrumentation
import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.PixelFormat
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import org.json.JSONObject

/** Real Android View/StaticLayout/Handler regression test; no game image is read. */
class CanvasRunner : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val result=Bundle();var view: SubtitleCanvas?=null;var bitmap: Bitmap?=null;var shortAnchor: Pair<Float,Float>?=null
        val wm=targetContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        fun message(id: String,text: String)=JSONObject().put("type","subtitle_show").put("id",id).put("translated",text)
        try {
            runOnMainSync {
                view=SubtitleCanvas(targetContext) {}
                wm.addView(view,WindowManager.LayoutParams(1920,1080,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,PixelFormat.TRANSLUCENT))
                view!!.style=JSONObject().put("max_width",60).put("min_seconds",1).put("max_seconds",1).put("hard_seconds",1).put("x",500)
                view!!.layout(0,0,1920,1080)
                bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888)
                view!!.message(message("final","انتظر!"));view!!.draw(Canvas(bitmap!!))
                check(view!!.state.entries.size==1)
                check(view!!.measuredBoxes.single().first<400)
                result.putFloat("short_box_width",view!!.measuredBoxes.single().first)
                shortAnchor=view!!.measuredAnchor
            }
            SystemClock.sleep(1500)
            runOnMainSync {
                check(view!!.state.entries.isEmpty()) {"Final subtitle never expired without new messages"}
                view!!.message(message("final","انتظر!"));view!!.draw(Canvas(bitmap!!))
                check(view!!.state.entries.isEmpty()) {"Late duplicate resurrected subtitle"}
                view!!.message(message("long","هذه جملة طويلة للتحقق من التفاف الترجمة العربية وحجم الخلفية حول النص فقط ".repeat(5)))
                view!!.draw(Canvas(bitmap!!))
                check(view!!.measuredBoxes.single().first<=1152f)
                check(view!!.measuredBoxes.single().second>60)
                check(view!!.measuredAnchor==shortAnchor) {"Content widths moved the selected anchor"}
                result.putFloat("long_box_width",view!!.measuredBoxes.single().first)
                result.putFloat("long_box_height",view!!.measuredBoxes.single().second)
                view!!.message(null)
                view!!.style.put("min_seconds",4).put("max_seconds",8).put("hard_seconds",8).put("x",0)
                for(i in 1..4) {view!!.message(message("$i","الجملة $i"));view!!.draw(Canvas(bitmap!!))}
                check(view!!.state.entries.map {it.id}==listOf("2","3","4"))
                val anchor=view!!.measuredAnchor
                view!!.style.put("x",1);view!!.draw(Canvas(bitmap!!))
                check(view!!.measuredAnchor.first-anchor.first==1f)
                check(view!!.measuredAnchor.second==anchor.second)
                view!!.message(null);check(view!!.state.entries.isEmpty())
                view!!.message(JSONObject().put("type","context_show").put("translated","افتح").put("x",.42).put("y",.36).put("w",.08).put("h",.03))
                view!!.draw(Canvas(bitmap!!))
                check(kotlin.math.abs(view!!.measuredContext!!.centerX()-883.2f)<.1f)
                check(kotlin.math.abs(view!!.measuredContext!!.top-431.2f)<.1f)
                result.putFloat("context_center_x",view!!.measuredContext!!.centerX())
                result.putFloat("context_top",view!!.measuredContext!!.top)
            }
            SystemClock.sleep(2200)
            runOnMainSync {view!!.draw(Canvas(bitmap!!));check(view!!.measuredContext==null)}
            result.putString("result","PASS: real Canvas content sizing, RTL wrap, isolated expiry, duplicate, stacking, pixel anchor, disconnect clear, nearby mapping and expiry")
            finish(Activity.RESULT_OK,result)
        } catch(t: Throwable) {result.putString("error",t.toString());finish(Activity.RESULT_CANCELED,result)}
        finally { runOnMainSync {view?.let {wm.removeViewImmediate(it)};bitmap?.recycle()} }
    }
}
