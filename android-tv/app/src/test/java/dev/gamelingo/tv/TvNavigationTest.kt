package dev.gamelingo.tv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.provider.Settings
import android.view.KeyEvent
import android.view.View
import android.widget.Button
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.*
import org.robolectric.annotation.*
import org.robolectric.shadows.ShadowSettings
import java.io.File
import java.io.FileOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28],qualifiers="w1920dp-h1080dp-land-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
class TvNavigationTest {
    private fun app() = RuntimeEnvironment.getApplication()
    private fun fixture() {
        ShadowSettings.setCanDrawOverlays(false)
        app().getSharedPreferences("overlay",Context.MODE_PRIVATE).edit().clear()
            .putString("host","192.168.1.42").putString("token","synthetic-encrypted-token")
            .putString("fingerprint","a".repeat(64)).putString("position","TOP")
            .putString("display_settings","{\"font_size\":42}")
            .putBoolean("diagnostics_enabled",false).commit()
    }
    private fun key(activity: MainActivity, code: Int) {
        // Activity.dispatchKeyEvent bypasses ViewRootImpl's focus-navigation
        // stage. Feed actual synthetic D-pad events into that root instead.
        val decor = activity.window.decorView
        val root = View::class.java.getMethod("getViewRootImpl").invoke(decor)
        assertNotNull("Remote events require an attached window root",root)
        val dispatch = root.javaClass.getMethod("dispatchInputEvent",android.view.InputEvent::class.java)
        val now = android.os.SystemClock.uptimeMillis()
        for (action in listOf(KeyEvent.ACTION_DOWN,KeyEvent.ACTION_UP)) {
            val event = KeyEvent(now,now+action,action,code,0,0,android.view.KeyCharacterMap.VIRTUAL_KEYBOARD,0,
                KeyEvent.FLAG_FROM_SYSTEM,android.view.InputDevice.SOURCE_DPAD)
            dispatch.invoke(root,event)
            Shadows.shadowOf(Looper.getMainLooper()).idle()
        }
        println("TV key=$code focus=${decor.findFocus()?.id}")
    }
    private fun layout(activity: MainActivity) {
        val view = activity.window.decorView
        view.measure(View.MeasureSpec.makeMeasureSpec(1920,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(1080,View.MeasureSpec.EXACTLY))
        view.layout(0,0,1920,1080)
    }
    @Test fun remoteArrowsOpenConnectionAndBackReturnsToPrimaryWithoutChangingIdentity() {
        fixture()
        val prefs = app().getSharedPreferences("overlay",Context.MODE_PRIVATE)
        val before = prefs.all.toMap()
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup().visible().windowFocusChanged(true)
        try {
            val activity = controller.get(); layout(activity)
            val primary = activity.findViewById<Button>(R.id.tv_primary)
            assertTrue(primary.text.contains("السماح"))
            assertTrue("Expected primary focus; actual=${activity.window.decorView.findFocus()?.id}",primary.hasFocus())
            assertTrue(activity.findViewById<Button>(R.id.tv_nav_home).requestFocus())
            assertEquals(R.id.tv_nav_home,activity.window.decorView.findFocus()?.id)
            key(activity,KeyEvent.KEYCODE_DPAD_LEFT)
            assertEquals(R.id.tv_nav_connection,activity.window.decorView.findFocus()?.id)
            key(activity,KeyEvent.KEYCODE_DPAD_CENTER)
            assertNotNull(activity.findViewById<TextView>(R.id.tv_saved_source))
            key(activity,KeyEvent.KEYCODE_BACK)
            assertNotNull(activity.findViewById<Button>(R.id.tv_primary))
            assertEquals(R.id.tv_primary,activity.window.decorView.findFocus()?.id)
            assertEquals(before,prefs.all)
            assertNull(Shadows.shadowOf(app()).nextStartedService)
        } finally { controller.pause().stop().destroy() }
    }
    @Test fun firstActionOpensPermissionWithoutStartingPreviewOrReplacingPairing() {
        fixture()
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup().visible().windowFocusChanged(true)
        try {
            val activity = controller.get()
            activity.findViewById<Button>(R.id.tv_primary).performClick()
            assertEquals(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,Shadows.shadowOf(activity).nextStartedActivity.action)
            assertNull(Shadows.shadowOf(app()).nextStartedService)
            assertEquals("synthetic-encrypted-token",app().getSharedPreferences("overlay",Context.MODE_PRIVATE).getString("token",null))
        } finally { controller.pause().stop().destroy() }
    }
    @Test fun pagesRenderInArabicAtNormalAndLargeTextWithoutWritingSettings() {
        fixture()
        val prefs = app().getSharedPreferences("overlay",Context.MODE_PRIVATE)
        val before = prefs.all.toMap()
        val output = File(System.getProperty("gamelingo.renderOutput"),"tv-navigation").apply { mkdirs() }
        for (scale in listOf(1f,1.5f)) {
            val resources = app().resources
            val configuration = android.content.res.Configuration(resources.configuration).apply { fontScale = scale }
            resources.updateConfiguration(configuration,resources.displayMetrics)
            val controller = Robolectric.buildActivity(MainActivity::class.java).setup().visible().windowFocusChanged(true)
            try {
                val activity = controller.get()
                for ((name,id) in listOf("home" to R.id.tv_nav_home,"connection" to R.id.tv_nav_connection,"appearance" to R.id.tv_nav_appearance,"help" to R.id.tv_nav_help)) {
                    activity.findViewById<Button>(id).apply { requestFocus(); performClick() }
                    layout(activity)
                    val bitmap = Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888)
                    activity.window.decorView.draw(Canvas(bitmap))
                    FileOutputStream(File(output,"$name-$scale.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
                    var low = 255; var high = 0
                    for (y in 0 until bitmap.height step 8) for (x in 0 until bitmap.width step 8) {
                        val pixel = bitmap.getPixel(x,y)
                        val brightness = (android.graphics.Color.red(pixel)+android.graphics.Color.green(pixel)+android.graphics.Color.blue(pixel))/3
                        low = minOf(low,brightness); high = maxOf(high,brightness)
                    }
                    assertTrue("Blank screenshot: $name-$scale, range=${high-low}",high-low > 80)
                    bitmap.recycle()
                }
                assertEquals(before,prefs.all)
                assertNull(Shadows.shadowOf(app()).nextStartedService)
            } finally { controller.pause().stop().destroy() }
        }
    }
}
