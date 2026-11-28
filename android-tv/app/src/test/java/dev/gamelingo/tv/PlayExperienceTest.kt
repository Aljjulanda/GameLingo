package dev.gamelingo.tv

import android.graphics.*
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import org.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.*
import org.robolectric.annotation.*
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28],qualifiers="w1920dp-h1080dp-land-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
class PlayExperienceTest {
    @Test fun oldScopedMenuClearCannotDeleteNewSnapshot() {
        val overlay=MenuOverlay()
        val value=menu("حديث").put("menu_id","new")
        overlay.apply(value,0);overlay.clear("old");assertNotNull(overlay.snapshot)
        overlay.clear("new");assertNull(overlay.snapshot)
    }
    @Test fun sourceGoneBeforeCanvasDrawCannotResurrectQueuedTranslation() {
        val context:android.content.Context=RuntimeEnvironment.getApplication()
        val view=SubtitleCanvas(context){}
        view.layout(0,0,1920,1080)
        view.message(JSONObject().put("type","subtitle_show").put("id","queued").put("source_generation",1).put("translated","متأخر"))
        view.message(JSONObject().put("type","subtitle_source_gone").put("id","queued").put("source_generation",1))
        val bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bitmap));bitmap.recycle()
        assertTrue(view.state.entries.isEmpty())
    }
    private fun canvas()=SubtitleCanvas(RuntimeEnvironment.getApplication()){}.apply {
        measure(View.MeasureSpec.makeMeasureSpec(1920,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(1080,View.MeasureSpec.EXACTLY));layout(0,0,1920,1080)
    }
    private fun draw(view:SubtitleCanvas):Bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888).also{view.draw(Canvas(it))}
    private fun line(id:String)=JSONObject().put("type","subtitle_show").put("id",id).put("source","Do not leave").put("translated","لا تغادر")
    @Test fun previewPersistsForAnHourAndDialogueClearCannotEndIt() {
        val view=canvas();view.message(JSONObject().put("type","subtitle_preview_show"));val before=draw(view)
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofHours(1))
        view.message(line("during-preview"));view.message(JSONObject().put("type","subtitle_clear"))
        assertTrue(view.previewActive);assertTrue(before.sameAs(draw(view)))
        view.message(JSONObject().put("type","subtitle_preview_hide"));assertFalse(view.previewActive);assertTrue(view.state.entries.isEmpty())
        val hidden=draw(view);assertTrue(hidden.sameAs(Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888)))
    }
    @Test fun liveStyleChangesWhilePreviewIsActiveWithoutDialogueTimer() {
        val view=canvas();view.message(JSONObject().put("type","subtitle_preview_show"));val before=draw(view)
        view.message(JSONObject().put("type","settings_sync").put("settings",JSONObject().put("text_color","#00FF00").put("font_size",52)))
        assertTrue(view.previewActive);assertFalse(before.sameAs(draw(view)))
    }
    private fun menu(text:String)=JSONObject().put("type","menu_snapshot").put("lease_ms",1800)
        .put("appearance",JSONObject().put("side","right").put("fontSize",22))
        .put("items",JSONArray().put(JSONObject().put("id","row").put("translated",text).put("box",JSONObject().put("x",.1).put("y",.2).put("w",.2).put("h",.04))))
    @Test fun menuCurrentFrameReplacesValuesAndHasIndependentLiveness() {
        val overlay=MenuOverlay();overlay.apply(menu("قطع 11"),0);overlay.apply(menu("قطع 12"),1200)
        assertEquals(1,overlay.snapshot!!.getJSONArray("items").length())
        assertEquals("قطع 12",overlay.snapshot!!.getJSONArray("items").getJSONObject(0).getString("translated"))
        val bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888)
        overlay.draw(Canvas(bitmap),1920,1080,2900);assertNotNull(overlay.snapshot)
        overlay.draw(Canvas(bitmap),1920,1080,3001);assertNull(overlay.snapshot)
        overlay.apply(menu("جديد"),4000);overlay.clear();assertNull(overlay.snapshot)
    }
    @Test fun remoteEditorMovesResizesSavesCancelsAndReturnsTheSessionTicket() {
        val results=mutableListOf<JSONObject>();val editor=RegionEditor{results.add(it)}
        fun start()=editor.start(JSONObject().put("ticket","test-ticket").put("box",JSONObject().put("x",.1).put("y",.6).put("w",.7).put("h",.2)))
        start();editor.key(KeyEvent.KEYCODE_DPAD_CENTER);repeat(300){editor.key(KeyEvent.KEYCODE_DPAD_RIGHT)}
        assertEquals(.3,editor.box.x,.0001)
        editor.key(KeyEvent.KEYCODE_DPAD_CENTER);editor.key(KeyEvent.KEYCODE_DPAD_RIGHT);editor.key(KeyEvent.KEYCODE_DPAD_CENTER)
        repeat(200){editor.key(KeyEvent.KEYCODE_DPAD_LEFT)};assertEquals(.02,editor.box.w,.0001)
        editor.key(KeyEvent.KEYCODE_BACK);assertFalse(results.last().getBoolean("save"));assertFalse(editor.active)
        start();repeat(3){editor.key(KeyEvent.KEYCODE_DPAD_RIGHT)};editor.key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertTrue(results.last().getBoolean("save"));assertEquals("test-ticket",results.last().getString("ticket"))
    }
    @Test fun menuGlyphsStayAdjacentToOriginalOnEitherSideForArabicAndLatin() {
        for(left in listOf(false,true)) for(text in listOf("نعم","John: نعم 11","Yes 11")) {
            val message=menu(text)
            message.getJSONObject("appearance").put("side",if(left) "left" else "right").put("background",false).put("outline",false).put("shadow",false)
            message.getJSONArray("items").getJSONObject(0).getJSONObject("box").put("x",.6).put("w",.1)
            val overlay=MenuOverlay();overlay.apply(message,0)
            val bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888);overlay.draw(Canvas(bitmap),1920,1080,1)
            val pixels=IntArray(1920*1080);bitmap.getPixels(pixels,0,1920,0,0,1920,1080)
            var minX=1920;var maxX=-1
            for(index in pixels.indices) if(Color.alpha(pixels[index])>30) {minX=minOf(minX,index%1920);maxX=maxOf(maxX,index%1920)}
            assertTrue(maxX>=minX)
            if(left) assertTrue("Left label must end beside original, not at the far edge: $text $maxX",maxX in 1110..1135)
            else assertTrue("Right label must start beside original: $text $minX",minX in 1360..1385)
            bitmap.recycle()
        }
    }
}
