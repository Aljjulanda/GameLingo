package dev.gamelingo.tv

import android.app.Activity
import android.app.Instrumentation
import android.graphics.*
import android.os.Bundle
import android.text.*
import android.view.WindowManager
import android.widget.ImageView
import android.os.SystemClock
import java.io.File

/** Device-only glyph-position assertions plus a shareable Canvas fixture image. */
class Rtl021Runner:Instrumentation() {
    override fun onCreate(arguments:Bundle?) {super.onCreate(arguments);start()}
    override fun onStart() {
        val result=Bundle();var code=Activity.RESULT_CANCELED
        var bitmap:Bitmap?=null
        var preview:ImageView?=null
        val wm=targetContext.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
        try {
            runOnMainSync {
                val paint=TextPaint(Paint.ANTI_ALIAS_FLAG).apply {color=Color.WHITE;textSize=34f;typeface=Typeface.DEFAULT}
                fun layout(text:CharSequence,width:Int=1720)=StaticLayout.Builder.obtain(text,0,text.length,paint,width)
                    .setTextDirection(TextDirectionHeuristics.RTL).setAlignment(Layout.Alignment.ALIGN_NORMAL)
                    .setIncludePad(false).setLineSpacing(4f,1f).build()
                fun bounds(layout:StaticLayout,start:Int,end:Int):RectF {
                    val path=Path();layout.getSelectionPath(start,end,path)
                    return RectF().apply {path.computeBounds(this,true)}
                }
                bitmap=Bitmap.createBitmap(1800,1500,Bitmap.Config.ARGB_8888)
                val canvas=Canvas(bitmap!!);canvas.drawColor(Color.rgb(16,37,41))
                val heading=Paint(Paint.ANTI_ALIAS_FLAG).apply {color=Color.LTGRAY;textSize=27f}
                canvas.drawText("GameLingo 0.2.1 / actual TCL StaticLayout",40f,45f,heading)
                val names=listOf("Arthur","John","Master Chief","Lara Croft","O'Brien","Dr. Smith")
                val arabic="لازم نتحرك من هنا قبل وصول John (11)."
                var y=75f
                for(name in names) {
                    val text=SpeakerText.inline(arabic,name,true,Color.rgb(166,199,216))
                    check(text is Spanned)
                    val prefix=TextPresentation.prefix(name)
                    val rendered=layout(text)
                    val nameBox=bounds(rendered,1,1+name.length)
                    val colon=prefix.indexOf(':')
                    val colonBox=bounds(rendered,colon,colon+1)
                    val bodyBox=bounds(rendered,prefix.length,prefix.length+4)
                    check(rendered.getParagraphDirection(0)==-1) {"Paragraph is not RTL"}
                    check(!rendered.isRtlCharAt(1)) {"English name lost LTR direction"}
                    check(colonBox.right <= nameBox.left+1) {"Colon is on the far side of $name"}
                    check(bodyBox.right <= colonBox.left+1) {"Arabic is not after the colon in RTL reading order"}
                    check(rendered.getLineForOffset(colon)==rendered.getLineForOffset(prefix.length)) {"Standalone speaker line"}
                    val span=text.getSpans(0,text.length,SpeakerColorSpan::class.java).single()
                    check(span.color==Color.rgb(166,199,216) && text.getSpanStart(span)==1 && text.getSpanEnd(span)==1+name.length)
                    check(TextPresentation.clean(text.toString()).replace('\u00a0',' ')=="$name: $arabic")
                    val wrapped=layout(text,600)
                    check(wrapped.lineCount>1 && wrapped.getLineForOffset(prefix.length)==0)
                    canvas.save();canvas.translate(40f,y);rendered.draw(canvas);canvas.restore();y+=100
                }
                // Reproduce the old source bug with actual positions, not a string assertion.
                val legacy="\u2068Arthur:\u2069 $arabic"
                val legacyLayout=layout(legacy)
                check(bounds(legacyLayout,7,8).centerX()>bounds(legacyLayout,1,7).centerX()) {"Legacy colon-position reproduction changed"}
                canvas.drawText("Before: colon isolated with the English name",40f,y+20,heading);y+=45
                canvas.save();canvas.translate(40f,y);legacyLayout.draw(canvas);canvas.restore();y+=110
                val formatter=android.text.BidiFormatter.getInstance(true)
                val alternative=formatter.unicodeWrap("Arthur",TextDirectionHeuristics.LTR,true)+": $arabic"
                canvas.drawText("BidiFormatter alternative evaluated",40f,y+20,heading);y+=45
                canvas.save();canvas.translate(40f,y);layout(alternative).draw(canvas);canvas.restore();y+=110
                for(body in listOf("(تحرك الآن) [صوت إطلاق نار] لماذا؟","اذهب إلى (Old Gate) واجمع [11] قطعة، ثم اسأل: أين John؟","قال: «لن نذهب» وكتب \"John\".\n[نص متعدد الأسطر]","خسرت -11 نقطة ثم قابلت García قرب البوابة.")) {
                    val formatted=TextPresentation.body(body)
                    check(TextPresentation.clean(formatted)==body) {"Meaningful punctuation changed"}
                    val bodyLayout=layout(formatted)
                    // Both bracket glyph selections must enclose their contents on the same line.
                    if(body.contains("(Old Gate)")) {
                        val open=formatted.indexOf('(');val close=formatted.indexOf(')')
                        val a=bounds(bodyLayout,open,open+1);val b=bounds(bodyLayout,close,close+1)
                        val word=formatted.indexOf("Old Gate");val inner=bounds(bodyLayout,word,word+8)
                        check(minOf(a.centerX(),b.centerX())<inner.centerX() && maxOf(a.centerX(),b.centerX())>inner.centerX())
                    }
                    if(body.contains("-11")) {
                        val minus=formatted.indexOf("-11")
                        check(bounds(bodyLayout,minus,minus+1).centerX()<bounds(bodyLayout,minus+1,minus+3).centerX()) {"Numeric minus changed sides"}
                    }
                    canvas.save();canvas.translate(40f,y);bodyLayout.draw(canvas);canvas.restore();y+=110
                }
                val start=System.nanoTime()
                val cached=SpeakerText.inline(arabic,"Arthur",true,Color.rgb(166,199,216))
                repeat(1000) {check(SpeakerText.inline(arabic,"Arthur",true,Color.rgb(166,199,216))===cached)}
                result.putString("cached_inline_1000_ms",((System.nanoTime()-start)/1_000_000.0).toString())
                File(targetContext.filesDir,"rtl021.png").outputStream().use {bitmap!!.compress(Bitmap.CompressFormat.PNG,100,it)}
                preview=ImageView(targetContext).apply {setBackgroundColor(Color.BLACK);setImageBitmap(bitmap);scaleType=ImageView.ScaleType.FIT_CENTER}
                wm.addView(preview,WindowManager.LayoutParams(-1,-1,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,PixelFormat.OPAQUE))
            }
            sendStatus(0,Bundle().apply {putString("rendered_image_ready","rtl021.png")})
            SystemClock.sleep(12000)
            result.putString("result","PASS: six names, LTR name + external RTL colon + Arabic glyph bounds, inline color, natural wrapping, balanced punctuation/quotes/numbers, actual legacy bug reproduction and cached presentation")
            code=Activity.RESULT_OK
        } catch(t:Throwable) {result.putString("error",t.message ?: "RTL rendering fixture failed")}
        finally {runOnMainSync {preview?.let {wm.removeViewImmediate(it)};bitmap?.recycle()} }
        finish(code,result)
    }
}
