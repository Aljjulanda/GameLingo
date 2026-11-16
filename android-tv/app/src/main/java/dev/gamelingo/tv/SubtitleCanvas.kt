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
    var onRendered: ((String)->Unit)? = null
    var onRenderedTrace: ((String,String)->Unit)? = null
    private val traceRequested = java.util.LinkedHashSet<String>()
    private val acknowledged=java.util.LinkedHashSet<String>()
    private var document:JSONObject?=null
    var measuredDocument:RectF?=null;private set
    val state = SubtitleState()
    var measuredBoxes: List<Pair<Float,Float>> = emptyList(); private set
    var measuredAnchor: Pair<Float,Float> = Pair(0f,0f); private set
    var measuredContext: RectF? = null; private set
    private data class Queued(val id:String,val text:String,val duration:Long,val receivedAt:Long,val source:String,val box:SourceBox?,val speaker:String,val fresh:Boolean,val meaningful:Boolean,val boundary:String?,val gap:Long)
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
        if (message==null) { state.clear(); pending.clear(); previewUntil=0;contextLabel=null;contextUntil=0;document=null; invalidate(); return }
        if(message.has("settings")) style=message.getJSONObject("settings")
        when(message.optString("type")) {
            "document_show" -> {
                if(message.optString("translated").length !in 1..2400) return
                document=message;state.clear();pending.clear();previewUntil=0;contextLabel=null;contextUntil=0
                removeCallbacks(tick);invalidate()
            }
            "document_hide" -> { document=null;invalidate() }
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
                val eventId = message.getString("id")
                if(message.optBoolean("quality_trace",false)) traceRequested.add(eventId) else traceRequested.remove(eventId)
                while(traceRequested.size > 64) traceRequested.remove(traceRequested.first())
                val text=message.getString("translated")
                val duration=state.duration(text,b("adaptive",true),n("reading_speed",13.0).toDouble(),
                    (n("min_seconds",4.0)*1000).toLong(),(n("max_seconds",8.0)*1000).toLong(),(n("fixed_seconds",5.0)*1000).toLong()).coerceAtMost((n("hard_seconds",8.0)*1000).toLong())
                val box=if(listOf("x","y","w","h").all {message.has(it)}) SourceBox(message.optDouble("x"),message.optDouble("y"),message.optDouble("w"),message.optDouble("h")) else null
                val speaker=message.optJSONObject("speaker")?.optString("name","")?.take(40) ?: ""
                pending.add(Queued(message.getString("id"),text,duration,now,message.optString("source",""),box,speaker,message.optBoolean("event_fresh",false),message.optBoolean("meaningful_correction",false),if(message.has("event_boundary")) message.optString("event_boundary") else null,message.optLong("source_gap_ms",0)))
                while(pending.size>3) pending.removeFirst()
                removeCallbacks(tick); post(tick)
            }
            "subtitle_clear", "subtitle_hide" -> { state.clear();pending.clear();contextLabel=null;contextUntil=0;document=null; invalidate() }
        }
    }
    override fun onDetachedFromWindow() { removeCallbacks(tick); super.onDetachedFromWindow() }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val now=SystemClock.elapsedRealtime()
        measuredDocument=null
        if(document!=null) { drawDocument(canvas);return }
        state.expire(now)
        val hadPending=pending.isNotEmpty()
        while(pending.isNotEmpty()) {
            val entry=pending.removeFirst()
            if(now-entry.receivedAt>(n("hard_seconds",8.0)*1000).toLong()) continue
            val merges=state.coalesced
            state.show(entry.id,entry.text,now,entry.duration,n("max_entries",3.0).toInt(),entry.source,entry.box,entry.speaker,entry.fresh,entry.meaningful,entry.boundary,entry.gap)
            if(state.coalesced>merges) android.util.Log.i("GameLingoDedup","coalesced="+state.coalesced+" incoming="+entry.id+" active="+state.entries.size)
            android.util.Log.i("GameLingoEntries","visible=" + state.entries.map {it.id} + " newestUntil=" + state.entries.lastOrNull()?.until)
        }
        // The first tick can execute before onDraw creates the first entry.
        // Always arm the local clock after making queued entries visible.
        if(hadPending) { removeCallbacks(tick); postDelayed(tick,50) }
        val compactions=state.visualCompactions
        val renderEntries=state.visibleEntries()
        if(state.visualCompactions>compactions) android.util.Log.i("GameLingoDedup","visual_compactions="+state.visualCompactions+" visible="+renderEntries.size+" active_events="+state.entries.size)
        val texts:List<CharSequence> = if(previewUntil>now) listOf(
            SpeakerText.inline("جملة سابقة للمعاينة","Morgan",b("show_speakers",false),color("speaker_color","#A6C7D8")),
            SpeakerText.inline(sample,"Alex",b("show_speakers",false),color("speaker_color","#A6C7D8"))) else renderEntries.map {
            SpeakerText.inline(it.text,it.speaker,b("show_speakers",true),color("speaker_color","#A6C7D8"))
        }
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
                if(previewUntil<=now) {
                    val retainedIds=renderEntries.takeLast(drawn).map {it.id}.toSet()
                    state.entries.removeAll {it.id !in retainedIds}
                }
                break
            }
            if(drawn==0 && h>maxHeight && !warned) { report("الجملة تتجاوز ارتفاع منطقة الترجمة المحدد"); warned=true }
            top-=h
            val actualWidth=widths[i]
            val left=anchorX-actualWidth/2
            val fade=if(previewUntil>now) 1f else state.alpha(renderEntries[i],now,n("fade_ms",200.0).toLong())
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
            if(previewUntil<=now && acknowledged.add(renderEntries[i].id)) {
                if(acknowledged.size>128) acknowledged.remove(acknowledged.first())
                if(traceRequested.contains(renderEntries[i].id) && onRenderedTrace != null) {
                    onRenderedTrace?.invoke(renderEntries[i].id,PunctuationTrace.signature(texts[i].toString(),layouts[i].getParagraphDirection(0)))
                } else onRendered?.invoke(renderEntries[i].id)
            }
            top-=gap;used+=h+gap;drawn++
        }
    }
    private fun drawDocument(canvas: Canvas) {
        val message=document ?: return
        val text=TextPresentation.body(message.optString("translated"))
        val panel=RectF(width*.07f,height*.07f,width*.93f,height*.93f)
        measuredDocument=panel
        val paint=TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color=Color.WHITE
            textSize=minOf(n("font_size",25.0).coerceIn(24f,32f)*resources.displayMetrics.density,height/28f)
            typeface=Typeface.create(this@SubtitleCanvas.style.optString("font_family","sans-serif"),Typeface.NORMAL)
        }
        val padding=24f
        val contentWidth=(panel.width()-2*padding).toInt().coerceAtLeast(40)
        fun layout()=StaticLayout.Builder.obtain(text,0,text.length,paint,contentWidth)
            .setTextDirection(TextDirectionHeuristics.RTL).setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false).setLineSpacing(5f,1f).build()
        var body=layout()
        while(body.height>panel.height()-112 && paint.textSize>16) {paint.textSize-=2;body=layout()}
        canvas.drawRoundRect(panel,14f,14f,Paint(Paint.ANTI_ALIAS_FLAG).apply {color=0xf0102024.toInt()})
        val heading=TextPaint(Paint.ANTI_ALIAS_FLAG).apply {color=Color.rgb(166,199,216);textSize=24f;typeface=Typeface.DEFAULT_BOLD}
        canvas.drawText("Smart Reading",panel.left+padding,panel.top+36,heading)
        canvas.save();canvas.clipRect(panel.left+padding,panel.top+58,panel.right-padding,panel.bottom-42)
        canvas.translate(panel.left+padding,panel.top+58);body.draw(canvas);canvas.restore()
        val footer="${message.optInt("page",1)} / ${message.optInt("pages",1)}"
        canvas.drawText(footer,panel.centerX()-heading.measureText(footer)/2,panel.bottom-16,heading)
    }
    private fun drawContext(canvas: Canvas, now: Long) {
        measuredContext=null
        if(now>=contextUntil) {contextLabel=null;return}
        val label=contextLabel ?: return
        val text=TextPresentation.body(label.optString("translated"))
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

