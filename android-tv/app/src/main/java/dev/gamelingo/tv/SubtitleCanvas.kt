package dev.gamelingo.tv

import android.content.Context
import android.graphics.*
import android.os.SystemClock
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextDirectionHeuristics
import android.view.View
import org.json.JSONObject

class SubtitleCanvas(context: Context, private val report: (String)->Unit) : View(context) {
    val state = SubtitleState()
    private val pending=java.util.ArrayDeque<Triple<String,String,Long>>()
    var style = JSONObject()
    private val ink = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private var previewUntil = 0L
    private var warned=false
    private var lastGeometry=""
    private val sample = "هذه تجربة لعرض الترجمة العربية داخل الألعاب"
    private fun n(key: String, default: Double) = style.optDouble(key,default).toFloat()
    private fun b(key: String, default: Boolean) = style.optBoolean(key,default)
    private fun color(key: String, fallback: String, opacity: Float = 100f): Int {
        val raw = try { Color.parseColor(style.optString(key,fallback)) } catch (_:Exception) { Color.parseColor(fallback) }
        return (raw and 0x00ffffff) or ((opacity.coerceIn(0f,100f)*2.55f).toInt() shl 24)
    }
    private val tick = object : Runnable {
        override fun run() {
            state.expire(SystemClock.elapsedRealtime()); invalidate()
            if (state.entries.isNotEmpty() || previewUntil > SystemClock.elapsedRealtime()) postDelayed(this,100)
        }
    }
    fun message(message: JSONObject?) {
        val now=SystemClock.elapsedRealtime()
        if (message==null) { state.clear(); pending.clear(); previewUntil=0; invalidate(); return }
        if(message.has("settings")) style=message.getJSONObject("settings")
        when(message.optString("type")) {
            "settings_sync", "subtitle_style_update", "subtitle_position_update", "subtitle_timing_update" -> {
                style=message.getJSONObject("settings"); while(state.entries.size>n("max_entries",3.0).toInt().coerceIn(1,3)) state.entries.removeAt(0); invalidate()
            }
            "subtitle_preview_show" -> { previewUntil=now+8000; removeCallbacks(tick); post(tick) }
            "subtitle_preview_hide" -> { previewUntil=0; invalidate() }
            "subtitle_show", "subtitle_update" -> {
                previewUntil=0
                val text=message.getString("translated")
                val duration=state.duration(text,b("adaptive",true),n("reading_speed",13.0).toDouble(),
                    (n("min_seconds",4.0)*1000).toLong(),(n("max_seconds",8.0)*1000).toLong(),(n("fixed_seconds",5.0)*1000).toLong())
                pending.add(Triple(message.getString("id"),text,duration))
                while(pending.size>3) pending.removeFirst()
                removeCallbacks(tick); post(tick)
            }
            "subtitle_clear", "subtitle_hide" -> { state.clear();pending.clear(); invalidate() }
        }
    }
    override fun onDetachedFromWindow() { removeCallbacks(tick); super.onDetachedFromWindow() }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val now=SystemClock.elapsedRealtime()
        while(pending.isNotEmpty()) {
            val entry=pending.removeFirst()
            state.show(entry.first,entry.second,now,entry.third,n("max_entries",3.0).toInt())
            android.util.Log.i("GameLingoEntries","visible=" + state.entries.map {it.id} + " newestUntil=" + state.entries.lastOrNull()?.until)
        }
        val texts=if(previewUntil>now) listOf("جملة سابقة للمعاينة",sample) else state.entries.map { it.text }
        if(texts.isEmpty()) return
        val density=resources.displayMetrics.density
        ink.typeface=Typeface.create(Typeface.create(style.optString("font_family","sans-serif"),Typeface.NORMAL),maxOf(if(b("bold",false)) 700 else 100,n("font_weight",400.0).toInt().coerceIn(100,900)),false)
        ink.textSize=n("font_size",25.0).coerceIn(10f,100f)*density
        val px=n("padding_x",18.0).coerceIn(0f,100f); val py=n("padding_y",8.0).coerceIn(0f,100f)
        val safe=n("margin",24.0).coerceIn(0f,width/4f)
        val boxWidth=(width*n("max_width",88.0).coerceIn(10f,100f)/100).toInt().coerceAtMost((width-2*safe).toInt()).coerceAtLeast(100)
        val align=when(style.optString("alignment","center")) { "right"->Layout.Alignment.ALIGN_NORMAL; "left"->Layout.Alignment.ALIGN_OPPOSITE; else->Layout.Alignment.ALIGN_CENTER }
        val layouts=texts.map {
            StaticLayout.Builder.obtain(it,0,it.length,ink,(if(b("wrap",true)) boxWidth-2*px else maxOf(boxWidth-2*px,ink.measureText(it)+2)).toInt().coerceAtLeast(30))
                .setAlignment(align).setTextDirection(TextDirectionHeuristics.RTL).setIncludePad(false).setLineSpacing(n("line_spacing",3.0),1f)
                .setBreakStrategy(if(b("wrap",true)) Layout.BREAK_STRATEGY_HIGH_QUALITY else Layout.BREAK_STRATEGY_SIMPLE).build()
        }
        val anchor=LayoutPolicy.anchor(width.toFloat(),height.toFloat(),boxWidth.toFloat(),layouts.last().height+2*py,safe,n("x",0.0),n("y",0.0))
        val anchorX=anchor.first; val bottom=anchor.second
        val geometry="anchor=" + anchorX + "," + bottom + " output=" + width + "x" + height
        if(geometry!=lastGeometry) { android.util.Log.i("GameLingoPosition",geometry);lastGeometry=geometry; context.getSharedPreferences("overlay",Context.MODE_PRIVATE).edit().putFloat("anchor_x",anchorX).putFloat("anchor_y",bottom).apply() }
        val maxHeight=height*n("max_height",25.0).coerceIn(10f,90f)/100
        val gap=n("spacing",10.0).coerceIn(0f,80f)
        val retained=LayoutPolicy.retained(layouts.map {it.height+2*py},maxHeight,gap)
        var used=0f
        var top=bottom
        var drawn=0
        for(i in texts.indices.reversed()) {
            val layout=layouts[i]; val h=layout.height+2*py
            if(drawn>0 && (drawn>=retained || top-h<safe)) {
                if(previewUntil<=now) while(state.entries.size>drawn) state.entries.removeAt(0)
                break
            }
            if(drawn==0 && h>maxHeight && !warned) { report("الجملة تتجاوز ارتفاع منطقة الترجمة المحدد"); warned=true }
            top-=h
            val left=anchorX-boxWidth/2
            val alpha=if(i==texts.lastIndex) 1f else n("older_opacity",85.0)/100
            val bg=Paint(Paint.ANTI_ALIAS_FLAG)
            val rect=RectF(left,top,left+boxWidth,top+h)
            if(b("background",true)) { bg.color=color("background_color","#000000",n("background_opacity",65.0)*alpha); canvas.drawRoundRect(rect,n("radius",9.0),n("radius",9.0),bg) }
            if(b("border",false)) { bg.style=Paint.Style.STROKE; bg.strokeWidth=n("border_width",1.0);bg.color=color("border_color","#FFFFFF",100*alpha);canvas.drawRoundRect(rect,n("radius",9.0),n("radius",9.0),bg) }
            if(!b("wrap",true) && layout.width>boxWidth-2*px && !warned) { report("النص أعرض من المنطقة؛ فعّل التفاف النص");warned=true }
            canvas.save();canvas.clipRect(rect);canvas.translate(left+px,top+py)
            ink.clearShadowLayer()
            if(b("shadow",true)) ink.setShadowLayer(n("shadow_blur",2.0),n("shadow_x",0.0),n("shadow_y",2.0),color("shadow_color","#000000",n("shadow_opacity",80.0)*alpha))
            if(b("outline",true)) { ink.style=Paint.Style.STROKE;ink.strokeWidth=n("outline_width",2.0);ink.color=color("outline_color","#000000",100*alpha);layout.draw(canvas) }
            ink.style=Paint.Style.FILL;ink.color=color("text_color","#FFFFFF",n("text_opacity",100.0)*alpha);layout.draw(canvas);canvas.restore()
            top-=gap;used+=h+gap;drawn++
        }
    }
}

