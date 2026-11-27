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
        if(message.optBoolean("spatial")) require(message.optDouble("frame_aspect",16.0/9).let {it.isFinite() && it in 0.5..4.0})
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
        if(value.optBoolean("spatial")) { drawSpatial(canvas,width,height,value,style);return }
        val paint=TextPaint(Paint.ANTI_ALIAS_FLAG)
        paint.textSize=(style.optDouble("fontSize",22.0).coerceIn(10.0,72.0)*width/1920).toFloat()
        val boxWidth=(width*.25f).toInt().coerceAtLeast(40)
        for(i in 0 until items.length()) {
            val item=items.getJSONObject(i);val box=item.getJSONObject("box")
            val left=style.optString("side")=="left";val gap=style.optDouble("gap",.012).coerceIn(0.0,.15)*width
            val x=(if(left) box.getDouble("x")*width-gap-boxWidth else (box.getDouble("x")+box.getDouble("w"))*width+gap).toFloat().coerceIn(0f,(width-boxWidth).toFloat().coerceAtLeast(0f))
            val rawColor=if(style.optBoolean("matchColor")) item.optString("color",style.optString("color","#FFFFFF")) else style.optString("color","#FFFFFF")
            paint.color=try{Color.parseColor(rawColor)}catch(_:Exception){Color.WHITE}
            val text=TextPresentation.body(item.getString("translated"))
            val rtl=QualityRenderPolicy.hasArabicLetters(text)
            val alignment=if(QualityRenderPolicy.normalAlignment(if(left) "right" else "left",rtl)) Layout.Alignment.ALIGN_NORMAL else Layout.Alignment.ALIGN_OPPOSITE
            val layout=StaticLayout.Builder.obtain(text,0,text.length,paint,boxWidth)
                .setAlignment(alignment)
                .setTextDirection(if(rtl) TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR).setIncludePad(false).build()
            val y=(box.getDouble("y")*height).toFloat().coerceIn(0f,(height-layout.height).toFloat().coerceAtLeast(0f))
            if(style.optBoolean("background",true)) canvas.drawRoundRect(x-4,y-3,x+boxWidth+4,y+layout.height+3,4f,4f,Paint().apply{color=0xbb000000.toInt()})
            canvas.save();canvas.translate(x,y)
            if(style.optBoolean("outline",true)) {val saved=paint.color;paint.style=Paint.Style.STROKE;paint.strokeWidth=2f;paint.color=Color.BLACK;layout.draw(canvas);paint.style=Paint.Style.FILL;paint.color=saved}
            if(style.optBoolean("shadow",true)) paint.setShadowLayer(2f,1f,1f,Color.BLACK)
            layout.draw(canvas);paint.clearShadowLayer();canvas.restore()
        }
    }
    private fun drawSpatial(canvas:Canvas,width:Int,height:Int,value:JSONObject,style:JSONObject) {
        val aspect=value.optDouble("frame_aspect",16.0/9).coerceIn(0.5,4.0)
        val overscan=style.optDouble("overscan",0.0).let {if(it.isFinite()) it.coerceIn(0.0,0.08) else 0.0}
        val availableW=width*(1-2*overscan);val availableH=height*(1-2*overscan)
        val vw=minOf(availableW,availableH*aspect).toFloat();val vh=(vw/aspect).toFloat()
        val ox=(width-vw)/2;val oy=(height-vh)/2
        val occupied=mutableListOf<RectF>()
        val items=value.getJSONArray("items")
        for(i in 0 until items.length()) {
            val item=items.getJSONObject(i);val box=item.getJSONObject("box")
            val x=(ox+box.getDouble("x")*vw).toFloat();val y=(oy+box.getDouble("y")*vh).toFloat()
            val bw=(box.getDouble("w")*vw).toFloat().coerceAtLeast(1f)
            val bh=(box.getDouble("h")*vh).toFloat().coerceAtLeast(1f)
            val bounds=RectF(x,y,minOf(ox+vw,x+bw),minOf(oy+vh,y+bh))
            // Suppress colliding regions rather than hide neighbouring content.
            if(bounds.width()<8 || bounds.height()<6 || occupied.any {RectF.intersects(it,bounds)}) continue
            val text=TextPresentation.body(item.getString("translated"))
            val paint=TextPaint(Paint.ANTI_ALIAS_FLAG).apply {color=Color.WHITE}
            val minFont=(10f*vw/1920).coerceAtLeast(5f)
            paint.textSize=(bh*.85f).coerceIn(minFont,maxOf(minFont,48f*vw/1920))
            val align=when(item.optString("alignment","right")) {"left"->Layout.Alignment.ALIGN_OPPOSITE;"center"->Layout.Alignment.ALIGN_CENTER;else->Layout.Alignment.ALIGN_NORMAL}
            fun layout():StaticLayout = StaticLayout.Builder.obtain(text,0,text.length,paint,bounds.width().toInt().coerceAtLeast(1))
                .setAlignment(align).setTextDirection(TextDirectionHeuristics.RTL).setIncludePad(false)
                .setMaxLines(maxOf(1,(bounds.height()/paint.textSize).toInt())).setEllipsize(TextUtils.TruncateAt.END).build()
            var laidOut=layout()
            while((laidOut.height>bounds.height() || paint.measureText(text)>bounds.width()*maxOf(1,(bounds.height()/paint.textSize).toInt())) && paint.textSize>minFont) {
                paint.textSize=maxOf(minFont,paint.textSize*.9f);laidOut=layout()
            }
            occupied.add(bounds)
            if(style.optBoolean("background",true)) canvas.drawRoundRect(bounds,3f,3f,Paint().apply{color=0xcc000000.toInt()})
            canvas.save();canvas.clipRect(bounds);canvas.translate(bounds.left,bounds.top)
            if(style.optBoolean("outline",true)) paint.setShadowLayer(1.5f,0f,0f,Color.BLACK)
            laidOut.draw(canvas);canvas.restore()
        }
    }
}
