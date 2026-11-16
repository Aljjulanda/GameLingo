package dev.gamelingo.tv

import android.content.Context
import android.graphics.*
import android.os.Looper
import android.text.*
import android.text.style.RelativeSizeSpan
import android.view.View
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.LooperMode
import org.robolectric.Shadows.shadowOf
import java.io.File

/** Real Android StaticLayout/Skia on the host. Not a TCL HDMI/device test. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28],qualifiers="w1920dp-h1080dp-land-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
class QualityCanvasTest {
    private val speakerColor=Color.rgb(166,199,216)
    private val mutedColor=Color.rgb(160,172,180)
    private fun caption(id:String,body:String="هل وصلت إلى (Old Gate)؟"):JSONObject=JSONObject()
        .put("type","subtitle_show").put("id",id).put("source","Have you reached the Old Gate?")
        .put("translated",body).put("speaker",JSONObject().put("name","Arthur"))
    private fun canvas():SubtitleCanvas=SubtitleCanvas(RuntimeEnvironment.getApplication()) {}.apply {
        style=JSONObject().put("font_size",32).put("show_speakers",true).put("max_width",60)
            .put("speaker_color","#A6C7D8").put("outline",true).put("shadow",true)
        measure(View.MeasureSpec.makeMeasureSpec(1920,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(1080,View.MeasureSpec.EXACTLY))
        layout(0,0,1920,1080)
    }
    private fun draw(view:SubtitleCanvas):Bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888).also { view.draw(Canvas(it)) }
    private fun save(bitmap:Bitmap,name:String) {
        val folder=File(requireNotNull(System.getProperty("gamelingo.renderOutput")));check(folder.mkdirs() || folder.isDirectory)
        File(folder,name+".png").outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,it)) }
    }
    @Test fun allOffMatchesFrozenReleaseCanvasPixelForPixel() {
        val view=canvas()
        val baseline=ReleaseBaselineCanvas(RuntimeEnvironment.getApplication()) {}.apply {
            style=JSONObject(view.style.toString())
            measure(View.MeasureSpec.makeMeasureSpec(1920,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(1080,View.MeasureSpec.EXACTLY))
            layout(0,0,1920,1080)
        }
        for((index,body) in listOf("هل وصلت؟","(نعم!) [11]","John قال: اجمع -11 قطعة.","سطر أول\nسطر ثان","Hello!").withIndex()) {
            view.message(null);baseline.message(null)
            val message=caption("baseline-$index",body)
            view.message(message);baseline.message(message)
            val actual=draw(view)
            val expected=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888).also {baseline.draw(Canvas(it))}
            assertTrue("All-OFF pixels diverged from the published release: fixture $index",expected.sameAs(actual))
            assertEquals(baseline.measuredBoxes,view.measuredBoxes);assertEquals(baseline.measuredAnchor,view.measuredAnchor)
            assertEquals(baseline.state.entries.single().until,view.state.entries.single().until)
            actual.recycle();expected.recycle()
        }
        view.message(null);baseline.message(null)
    }
    @Test fun legacyAndAllOffUseExactlyTheExistingTextSpans() {
        for(body in listOf("هل وصلت؟","(نعم!) [11]","John قال: لا نغادر.","سطر أول\nسطر ثان","Hello!")) for(show in listOf(false,true)) {
            val legacy=SpeakerText.inline(body,"Arthur",show,speakerColor)
            val current=QualitySubtitleText.inline(body,"Arthur",show,speakerColor,mutedColor,SubtitleQuality())
            assertSame("OFF must call the original renderer",legacy,current)
        }
        val malformed=SubtitleQuality.parse(JSONObject().put("cue",123).put("cue_only","true").put("arabic_paragraph_direction","true")
            .put("speaker",JSONObject().put("arabic",JSONObject())))
        assertEquals(SubtitleQuality(),malformed)
        assertEquals("",SubtitleQuality.parse(JSONObject().put("cue","سطر\nثان")).cue)
        assertEquals("",SubtitleQuality.parse(JSONObject().put("cue","x".repeat(161))).cue)
    }
    @Test fun paragraphSwitchKeepsPhysicalLeftAndRightAlignment() {
        fun glyphBounds(bitmap:Bitmap):Pair<Int,Int> {
            val pixels=IntArray(bitmap.width*bitmap.height);bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height)
            var left=bitmap.width;var right=-1
            for(index in pixels.indices) if(Color.alpha(pixels[index])>16) { val x=index%bitmap.width;left=minOf(left,x);right=maxOf(right,x) }
            check(right>=left);return left to right
        }
        for(alignment in listOf("left","right")) {
            val view=canvas();view.style.put("alignment",alignment).put("fit_background",false).put("show_speakers",false)
                .put("background",false).put("outline",false).put("shadow",false)
            view.message(caption("align","Follow John!"));val before=draw(view)
            val oldBounds=glyphBounds(before);val anchor=view.measuredAnchor
            view.message(caption("align","Follow John!").put("arabic_paragraph_direction",true));val after=draw(view)
            val newBounds=glyphBounds(after)
            assertEquals(listOf(1),view.measuredParagraphDirections);assertEquals(anchor,view.measuredAnchor)
            assertTrue("Physical $alignment moved with paragraph direction",kotlin.math.abs((if(alignment=="left") oldBounds.first else oldBounds.second)-(if(alignment=="left") newBounds.first else newBounds.second))<=2)
            view.message(caption("align","Follow John!").put("arabic_paragraph_direction",false).put("cue","(همس)").put("provenance","packExact"))
            draw(view).recycle();assertEquals("Direction OFF keeps legacy RTL while other metadata remains ON",listOf(-1),view.measuredParagraphDirections)
            before.recycle();after.recycle();view.message(null)
        }
    }
    @Test fun oldTVIgnoresOptionalFieldsAndNewTVRollsThemBackWithoutRenewingTheClock() {
        val view=canvas()
        val baseline=ReleaseBaselineCanvas(RuntimeEnvironment.getApplication()) {}.apply {
            style=JSONObject(view.style.toString());layout(0,0,1920,1080)
        }
        val plain=caption("compat")
        baseline.message(plain)
        val old=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888).also { baseline.draw(Canvas(it)) }
        val rich=caption("compat").put("speaker",JSONObject().put("name","Arthur").put("arabic","آرثر"))
            .put("cue","(همس)").put("provenance","packExact").put("arabic_paragraph_direction",true)
        baseline.message(rich)
        val ignored=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888).also {baseline.draw(Canvas(it))}
        assertTrue("Old TV ignores the new optional fields",old.sameAs(ignored))
        view.message(rich);val decorated=draw(view)
        assertFalse(old.sameAs(decorated));assertEquals(baseline.measuredAnchor,view.measuredAnchor)
        val deadline=view.state.entries.single().until
        view.message(plain);val rolledBack=draw(view)
        assertTrue("Absent optional fields restore the published legacy pixels",old.sameAs(rolledBack))
        assertEquals(deadline,view.state.entries.single().until)
        old.recycle();ignored.recycle();decorated.recycle();rolledBack.recycle()
        view.message(null);baseline.message(null)
    }
    @Test fun cueNameAndBadgeAreInlineIsolatedStyledAndIndependentlyReversible() {
        val body="John، اجمع 11 قطعة (الآن)؟"
        val q=SubtitleQuality(arabicName="آرثر",cue="(همس)",provenance="packExact",arabicParagraphDirection=true)
        val text=QualitySubtitleText.inline(body,"Arthur",true,speakerColor,mutedColor,q) as Spanned
        val visible=TextPresentation.clean(text.toString()).replace('\u00a0',' ')
        assertEquals("(همس) آرثر: $body ◆ حزمة",visible)
        assertTrue(text.toString().startsWith("\u2067(همس)\u2069"))
        assertTrue(text.toString().contains("\u2068آرثر\u2069"))
        assertEquals(3,text.getSpans(0,text.length,SpeakerColorSpan::class.java).size)
        assertEquals(.60f,text.getSpans(0,text.length,RelativeSizeSpan::class.java).single().sizeChange,0f)
        val muted=text.getSpans(0,text.length,SpeakerColorSpan::class.java).first {it.color==mutedColor}
        val paint=TextPaint().apply { color=Color.RED;alpha=77;style=Paint.Style.STROKE }
        muted.updateDrawState(paint);assertEquals(Color.RED and 0x00ffffff,paint.color and 0x00ffffff);assertEquals(77,paint.alpha)
        paint.style=Paint.Style.FILL;muted.updateDrawState(paint);assertEquals(mutedColor and 0x00ffffff,paint.color and 0x00ffffff);assertEquals(77,paint.alpha)
        fun visible(value:SubtitleQuality)=TextPresentation.clean(QualitySubtitleText.inline(body,"Arthur",true,speakerColor,mutedColor,value).toString())
        assertFalse(visible(q.copy(cue="")).contains("همس"))
        assertFalse(visible(q.copy(provenance="")).contains("حزمة"))
        assertTrue(visible(q.copy(arabicName="")).contains("Arthur"))
        assertFalse(QualitySubtitleText.inline(body,"Arthur",false,speakerColor,mutedColor,q).contains("آرثر"))
        val cueOnly=QualitySubtitleText.inline("(ضحك)","",true,speakerColor,mutedColor,SubtitleQuality(cue="(ضحك)",cueOnly=true))
        assertEquals("(ضحك)",TextPresentation.clean(cueOnly.toString()).trim())
        val mismatched=QualitySubtitleText.inline("لا تحذف هذا الحوار.","",true,speakerColor,mutedColor,SubtitleQuality(cue="(ضحك)",cueOnly=true))
        assertTrue(mismatched.contains("لا تحذف هذا الحوار."))
        val authored="مُورْغَنْ ".repeat(7).trim()
        val fullName=QualitySubtitleText.inline("انتظر.","Morgan",true,speakerColor,mutedColor,SubtitleQuality(arabicName=authored))
        assertTrue("Keep explicit long Arabic spelling and vowel marks",fullName.contains(authored))
    }
    @Test fun actualCanvasFixturesKeepClocksAnchorsWrappingAndLegacyPixels() {
        val view=canvas()
        view.message(caption("legacy"));val legacy=draw(view)
        val anchor=view.measuredAnchor;val boxes=view.measuredBoxes;val until=view.state.entries.single().until
        assertEquals(listOf(-1),view.measuredParagraphDirections)
        save(legacy,"01-legacy")
        // Explicit false/empty fields are equivalent to absent optional fields.
        view.message(caption("legacy").put("arabic_paragraph_direction",false).put("cue","").put("provenance",""))
        val off=draw(view);assertTrue(legacy.sameAs(off));assertEquals(until,view.state.entries.single().until)
        val fixtures=listOf(
            "mixed-name-cue" to "John، هل وصلت إلى (Old Gate)؟",
            "brackets-digits" to "(لن نغادر!) [11] هل فهمت؟",
            "latin-start" to "Arthur قال: اجمع -11 نقطة، ثم اذهب.",
            "multiline" to "هذه الجملة الأولى.\nوهذه الجملة الثانية!",
            "english" to "Follow John to the Old Gate!",
            "wrapped" to "علينا التحرك قبل أن يصل الحراس إلى البوابة القديمة. ".repeat(5)
        )
        for((index,fixture) in fixtures.withIndex()) {
            view.message(null)
            val message=caption("fixture-$index",fixture.second).put("arabic_paragraph_direction",true)
                .put("cue","(همس)").put("provenance",if(index%2==0) "packExact" else "userCorrection")
            if(index==0) message.put("speaker",JSONObject().put("name","Arthur").put("arabic","آرثر"))
            view.message(message);val bitmap=draw(view)
            assertEquals(anchor,view.measuredAnchor)
            assertEquals(listOf(if(fixture.first=="english") 1 else -1),view.measuredParagraphDirections)
            assertTrue(view.measuredBoxes.single().first<=1152f)
            if(fixture.first=="wrapped") assertTrue(view.measuredBoxes.single().second>boxes.single().second)
            save(bitmap,"${index+2}-${fixture.first}");bitmap.recycle()
        }
        view.message(null);view.message(caption("a","اتبعني").put("provenance","packExact"));val initial=draw(view)
        val deadline=view.state.entries.single().until
        val alias=caption("b","سر ورائي").put("event_fresh",true).put("event_boundary","continuity").put("provenance","userCorrection")
        view.message(alias);val frozen=draw(view)
        assertTrue("A frozen paraphrase must retain the displayed translation's provenance",initial.sameAs(frozen))
        initial.recycle();frozen.recycle()
        assertEquals(1,view.state.entries.size);assertEquals(deadline,view.state.entries.single().until)
        assertEquals("اتبعني",view.state.entries.single().text)
        view.message(JSONObject().put("type","subtitle_source_gone").put("id","b"));draw(view).recycle()
        assertTrue(view.state.entries.single().until<=deadline)
        view.state.expire(deadline);view.message(alias);draw(view).recycle()
        assertTrue("Metadata on a tombstoned alias cannot resurrect a subtitle",view.state.entries.isEmpty())
        view.message(null);draw(view).recycle();assertTrue(view.state.entries.isEmpty())
        legacy.recycle();off.recycle();shadowOf(Looper.getMainLooper()).idle()
    }
}
