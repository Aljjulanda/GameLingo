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
    var measuredBoxes: List<Pair<Float,Float>> = emptyList(); private set
    var measuredAnchor: Pair<Float,Float> = Pair(0f,0f); private set
    var measuredContext: RectF? = null; private set
    private data class Queued(val id:String,val text:String,val duration:Long,val receivedAt:Long)
    private val pending=java.util.ArrayDeque<Queued>()
    var style = JSONObject()
    private val ink = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private var previewUntil = 0L
    private var contextLabel: JSONObject? = null
    private var contextUntil=0L
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
            val now=SystemClock.elapsedRealtime()
            val before=state.entries.size
            state.expire(now); invalidate()
            if(before!=state.entries.size) android.util.Log.i("GameLingoExpiry","active="+state.entries.size)
            if (state.entries.isNotEmpty() || pending.isNotEmpty() || previewUntil > now || contextUntil>now) {
                val deadline=listOfNotNull(state.entries.minOfOrNull { it.until-n("fade_ms",200.0).toLong() },
                    previewUntil.takeIf {it>now},contextUntil.takeIf {it>now}).minOrNull() ?: now
                postDelayed(this,(deadline-now).coerceIn(50,1000))
            }
        }
    }
    fun message(message: JSONObject?) {
        val now=SystemClock.elapsedRealtime()
        if (message==null) { state.clear(); pending.clear(); previewUntil=0;contextLabel=null;contextUntil=0; invalidate(); return }
        if(message.has("settings")) style=message.getJSONObject("settings")
        when(message.optString("type")) {
            "context_clear" -> { contextLabel=null;contextUntil=0;invalidate() }
            "context_show" -> {
                if(message.optString("translated").length !in 1..200) return
                if(listOf("x","y","w","h").any { !message.optDouble(it,-1.0).let { v->v.isFinite() && v>=0 && v<=1 } }) return
                contextLabel=message;contextUntil=now+1800;removeCallbacks(tick);post(tick)
            }
            "context_present" -> { if(contextLabel!=null) {
                if(listOf("x","y","w","h").all {message.optDouble(it,-1.0).let {v->v.isFinite() && v>=0 && v<=1}})
                    for(key in listOf("x","y","w","h")) contextLabel?.put(key,message.getDouble(key))
                contextUntil=now+1800;removeCallbacks(tick);post(tick)
            } }
            "settings_sync", "subtitle_style_update", "subtitle_position_update", "subtitle_timing_update" -> {
                style=message.getJSONObject("settings"); while(state.entries.size>n("max_entries",3.0).toInt().coerceIn(1,3)) state.entries.removeAt(0); invalidate()
            }
            "subtitle_preview_show" -> { previewUntil=now+8000; removeCallbacks(tick); post(tick) }
            "subtitle_preview_hide" -> { previewUntil=0; invalidate() }
            "subtitle_source_gone" -> {
                state.disappeared(message.optString("id"),now,(n("min_seconds",4.0)*1000).toLong(),(n("disappearance_grace",1.5)*1000).toLong())
                removeCallbacks(tick); post(tick)
            }
            "subtitle_show", "subtitle_update" -> {
                previewUntil=0
                val text=message.getString("translated")
                val duration=state.duration(text,b("adaptive",true),n("reading_speed",13.0).toDouble(),
                    (n("min_seconds",4.0)*1000).toLong(),(n("max_seconds",8.0)*1000).toLong(),(n("fixed_seconds",5.0)*1000).toLong()).coerceAtMost((n("hard_seconds",8.0)*1000).toLong())
                pending.add(Queued(message.getString("id"),text,duration,now))
                while(pending.size>3) pending.removeFirst()
                removeCallbacks(tick); post(tick)
            }
            "subtitle_clear", "subtitle_hide" -> { state.clear();pending.clear();contextLabel=null;contextUntil=0; invalidate() }
        }
    }
    override fun onDetachedFromWindow() { removeCallbacks(tick); super.onDetachedFromWindow() }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val now=SystemClock.elapsedRealtime()
        state.expire(now)
        val hadPending=pending.isNotEmpty()
        while(pending.isNotEmpty()) {
            val entry=pending.removeFirst()
            if(now-entry.receivedAt>(n("hard_seconds",8.0)*1000).toLong()) continue
            state.show(entry.id,entry.text,now,entry.duration,n("max_entries",3.0).toInt())
            android.util.Log.i("GameLingoEntries","visible=" + state.entries.map {it.id} + " newestUntil=" + state.entries.lastOrNull()?.until)
        }
        // The first tick can execute before onDraw creates the first entry.
        // Always arm the local clock after making queued entries visible.
        if(hadPending) { removeCallbacks(tick); postDelayed(tick,50) }
        val texts=if(previewUntil>now) listOf("جملة سابقة للمعاينة",sample) else state.entries.map { it.text }
        drawContext(canvas,now)
        if(texts.isEmpty()) return
        val density=resources.displayMetrics.density
        ink.typeface=Typeface.create(Typeface.create(style.optString("font_family","sans-serif"),Typeface.NORMAL),maxOf(if(b("bold",false)) 700 else 100,n("font_weight",400.0).toInt().coerceIn(100,900)),false)
        ink.textSize=n("font_size",25.0).coerceIn(10f,100f)*density
        val px=n("padding_x",18.0).coerceIn(0f,100f); val py=n("padding_y",8.0).coerceIn(0f,100f)
        val safe=n("margin",24.0).coerceIn(0f,width/4f)
        val boxWidth=(width*n("max_width",60.0).coerceIn(10f,100f)/100).toInt().coerceAtMost((width-2*safe).toInt()).coerceAtLeast(100)
        val align=when(style.optString("alignment","center")) { "right"->Layout.Alignment.ALIGN_NORMAL; "left"->Layout.Alignment.ALIGN_OPPOSITE; else->Layout.Alignment.ALIGN_CENTER }
        val layouts=texts.map {
            val available=(boxWidth-2*px).coerceAtLeast(30f)
            val desired=Layout.getDesiredWidth(it,ink)+2f
            val contentWidth=if(b("fit_background",true)) minOf(available,desired) else available
            StaticLayout.Builder.obtain(it,0,it.length,ink,(if(b("wrap",true)) contentWidth else maxOf(contentWidth,desired)).toInt().coerceAtLeast(30))
                .setAlignment(align).setTextDirection(TextDirectionHeuristics.RTL).setIncludePad(false).setLineSpacing(n("line_spacing",3.0),1f)
                .setBreakStrategy(if(b("wrap",true)) Layout.BREAK_STRATEGY_HIGH_QUALITY else Layout.BREAK_STRATEGY_SIMPLE).build()
        }
        val widths=layouts.map { minOf(boxWidth.toFloat(),it.width+2*px) }
        measuredBoxes=layouts.indices.map { Pair(widths[it],layouts[it].height+2*py) }
        // Reserve the configured width for the anchor clamp. Content-sized boxes
        // must not shift the anchor as old lines enter/leave near screen edges.
        val anchor=LayoutPolicy.anchor(width.toFloat(),height.toFloat(),boxWidth.toFloat(),layouts.last().height+2*py,safe,n("x",0.0),n("y",0.0))
        val anchorX=anchor.first; val bottom=anchor.second
        measuredAnchor=anchor
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
            val actualWidth=widths[i]
            val left=anchorX-actualWidth/2
            val fade=if(previewUntil>now) 1f else state.alpha(state.entries[i],now,n("fade_ms",200.0).toLong())
            val alpha=(if(i==texts.lastIndex) 1f else n("older_opacity",85.0)/100)*fade
            val bg=Paint(Paint.ANTI_ALIAS_FLAG)
            val rect=RectF(left,top,left+actualWidth,top+h)
            if(hadPending) android.util.Log.i("GameLingoBox","width="+actualWidth+" height="+h+" max="+boxWidth)
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
    private fun drawContext(canvas: Canvas, now: Long) {
        measuredContext=null
        if(now>=contextUntil) {contextLabel=null;return}
        val label=contextLabel ?: return
        val text=label.optString("translated")
        val paint=TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface=Typeface.create(this@SubtitleCanvas.style.optString("font_family","sans-serif"),Typeface.NORMAL)
            textSize=n("context_font_size",17.0).coerceIn(10f,40f)*resources.displayMetrics.density
            color=color("context_text_color","#FFFFFF")
        }
        val contentWidth=minOf(Layout.getDesiredWidth(text,paint)+2,width*n("context_max_width",20.0).coerceIn(5f,40f)/100-16).toInt().coerceAtLeast(30)
        val layout=StaticLayout.Builder.obtain(text,0,text.length,paint,contentWidth).setTextDirection(TextDirectionHeuristics.RTL)
            .setAlignment(Layout.Alignment.ALIGN_CENTER).setIncludePad(false).build()
        val w=contentWidth+16f;val h=layout.height+12f
        val sourceX=label.optDouble("x").toFloat()*width; val sourceY=label.optDouble("y").toFloat()*height
        val sourceW=label.optDouble("w").toFloat()*width; val sourceH=label.optDouble("h").toFloat()*height
        val left=(sourceX+sourceW/2-w/2).coerceIn(12f,maxOf(12f,width-w-12))
        var top=sourceY+sourceH+10
        val dialogueTop=height*.92f+n("y",0.0)-height*n("max_height",25.0)/100
        if(top+h>height-12 || (state.entries.isNotEmpty() && top+h>dialogueTop)) top=sourceY-h-10
        top=top.coerceIn(12f,maxOf(12f,height-h-12))
        val bg=Paint(Paint.ANTI_ALIAS_FLAG).apply {color=color("context_background_color","#000000",n("context_background_opacity",65.0))}
        val rect=RectF(left,top,left+w,top+h);measuredContext=rect
        canvas.drawRoundRect(rect,7f,7f,bg)
        canvas.save();canvas.translate(left+8,top+6);layout.draw(canvas);canvas.restore()
    }
}

