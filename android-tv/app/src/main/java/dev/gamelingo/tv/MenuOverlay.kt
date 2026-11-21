package dev.gamelingo.tv

import android.graphics.*
import android.text.*
import org.json.JSONObject

/** Separate from dialogue clocks. Every current-frame snapshot replaces the list. */
class MenuOverlay {
    var snapshot: JSONObject? = null; private set
    var until = 0L; private set
    fun clear() { snapshot=null;until=0 }
    fun apply(message:JSONObject,now:Long) {
        val items=message.optJSONArray("items") ?: return
        require(items.length()<=24)
        val style=message.getJSONObject("appearance")
        require(style.optString("side") in listOf("left","right"))
        for(i in 0 until items.length()) {
            val item=items.getJSONObject(i);require(item.getString("translated").length in 1..400)
            val box=item.getJSONObject("box")
            require(listOf("x","y","w","h").all {box.optDouble(it,-1.0).let {v->v.isFinite() && v in 0.0..1.0}})
            require(box.getDouble("w")>0 && box.getDouble("h")>0 && box.getDouble("x")+box.getDouble("w")<=1.001 && box.getDouble("y")+box.getDouble("h")<=1.001)
        }
        snapshot=JSONObject(message.toString());until=now+message.optLong("lease_ms",1800).coerceIn(200,2000)
    }
    fun draw(canvas:Canvas,width:Int,height:Int,now:Long) {
        val value=snapshot ?: return
        if(now>=until) {clear();return}
        val style=value.getJSONObject("appearance");val items=value.getJSONArray("items")
        val paint=TextPaint(Paint.ANTI_ALIAS_FLAG)
        paint.textSize=(style.optDouble("fontSize",22.0).coerceIn(10.0,72.0)*width/1920).toFloat()
        val boxWidth=(width*.25f).toInt().coerceAtLeast(40)
        for(i in 0 until items.length()) {
            val item=items.getJSONObject(i);val box=item.getJSONObject("box")
            val left=style.optString("side")=="left";val gap=style.optDouble("gap",.012).coerceIn(0.0,.15)*width
            val x=(if(left) box.getDouble("x")*width-gap-boxWidth else (box.getDouble("x")+box.getDouble("w"))*width+gap).toFloat().coerceIn(0f,(width-boxWidth).toFloat().coerceAtLeast(0f))
            val rawColor=if(style.optBoolean("matchColor")) item.optString("color",style.optString("color","#FFFFFF")) else style.optString("color","#FFFFFF")
            paint.color=try{Color.parseColor(rawColor)}catch(_:Exception){Color.WHITE}
            val text=item.getString("translated")
            val layout=StaticLayout.Builder.obtain(text,0,text.length,paint,boxWidth)
                .setAlignment(if(left) Layout.Alignment.ALIGN_OPPOSITE else Layout.Alignment.ALIGN_NORMAL)
                .setTextDirection(TextDirectionHeuristics.FIRSTSTRONG_RTL).setIncludePad(false).build()
            val y=(box.getDouble("y")*height).toFloat().coerceIn(0f,(height-layout.height).toFloat().coerceAtLeast(0f))
            if(style.optBoolean("background",true)) canvas.drawRoundRect(x-4,y-3,x+boxWidth+4,y+layout.height+3,4f,4f,Paint().apply{color=0xbb000000.toInt()})
            canvas.save();canvas.translate(x,y)
            if(style.optBoolean("outline",true)) {val saved=paint.color;paint.style=Paint.Style.STROKE;paint.strokeWidth=2f;paint.color=Color.BLACK;layout.draw(canvas);paint.style=Paint.Style.FILL;paint.color=saved}
            if(style.optBoolean("shadow",true)) paint.setShadowLayer(2f,1f,1f,Color.BLACK)
            layout.draw(canvas);paint.clearShadowLayer();canvas.restore()
        }
    }
}
