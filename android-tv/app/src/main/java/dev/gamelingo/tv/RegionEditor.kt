package dev.gamelingo.tv

import android.graphics.*
import android.view.KeyEvent
import org.json.JSONObject

/** Full source-frame coordinates; never subtitle placement coordinates. */
class RegionEditor(private val finish:(JSONObject)->Unit) {
    var active=false;private set
    private var ticket=""
    var box=SourceBox(.16,.65,.68,.28);private set
    private var mode=0
    private var panel=true
    fun start(message:JSONObject) {
        val b=message.getJSONObject("box")
        val proposed=SourceBox(b.getDouble("x"),b.getDouble("y"),b.getDouble("w"),b.getDouble("h"))
        require(listOf(proposed.x,proposed.y,proposed.w,proposed.h).all{it.isFinite() && it in 0.0..1.0} && proposed.w>0 && proposed.h>0 && proposed.x+proposed.w<=1.001 && proposed.y+proposed.h<=1.001)
        ticket=message.getString("ticket");require(ticket.length<=64)
        box=proposed;active=true;mode=0;panel=true
    }
    fun end() {active=false}
    private fun result(save:Boolean) {active=false;finish(JSONObject().put("type","roi_edit_result").put("ticket",ticket).put("save",save).put("box",JSONObject().put("x",box.x).put("y",box.y).put("w",box.w).put("h",box.h)))}
    fun key(code:Int):Boolean {
        if(!active)return false
        if(code==KeyEvent.KEYCODE_BACK) {result(false);return true}
        if(code==KeyEvent.KEYCODE_DPAD_CENTER || code==KeyEvent.KEYCODE_ENTER) {
            if(!panel) {panel=true;return true}
            when(mode) {3->result(true);4->{box=SourceBox(.16,.65,.68,.28);mode=0};5->result(false);else->panel=false};return true
        }
        val dx=when(code){KeyEvent.KEYCODE_DPAD_LEFT->-.005;KeyEvent.KEYCODE_DPAD_RIGHT->.005;else->0.0}
        val dy=when(code){KeyEvent.KEYCODE_DPAD_UP->-.005;KeyEvent.KEYCODE_DPAD_DOWN->.005;else->0.0}
        if(dx==0.0 && dy==0.0)return false
        if(panel) {mode=(mode+(if(dx+dy>0)1 else 5))%6;return true}
        box=when(mode) {
            1->box.copy(w=(box.w+dx+dy).coerceIn(.02,1-box.x))
            2->box.copy(h=(box.h+dx+dy).coerceIn(.02,1-box.y))
            else->box.copy(x=(box.x+dx).coerceIn(0.0,1-box.w),y=(box.y+dy).coerceIn(0.0,1-box.h))
        };return true
    }
    fun draw(canvas:Canvas,width:Int,height:Int) {
        if(!active)return
        val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply {color=Color.YELLOW;style=Paint.Style.STROKE;strokeWidth=3f}
        canvas.drawRect((box.x*width).toFloat(),(box.y*height).toFloat(),((box.x+box.w)*width).toFloat(),((box.y+box.h)*height).toFloat(),paint)
        paint.style=Paint.Style.FILL;paint.color=0xdd000000.toInt();canvas.drawRect(0f,0f,width.toFloat(),130f,paint)
        paint.color=Color.WHITE;paint.textSize=26f
        val modes=listOf("تحريك","العرض","الارتفاع","حفظ","افتراضي","إلغاء")
        canvas.drawText("منطقة قراءة الحوار · ${modes[mode]} · ${if(panel) "الأسهم للاختيار، OK للتنفيذ" else "الأسهم للتعديل، OK للخيارات"}",30f,48f,paint)
        canvas.drawText("رجوع = إلغاء · احفظ بعد محاذاة الإطار مع صورة البث بما فيها الأشرطة",30f,96f,paint)
    }
}
