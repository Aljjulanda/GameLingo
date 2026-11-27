package dev.gamelingo.tv

import android.graphics.Bitmap
import android.graphics.Canvas
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SpatialOverlayTest {
    private fun message()=JSONObject().put("spatial",true).put("frame_aspect",16.0/9)
        .put("lease_ms",1800).put("appearance",JSONObject().put("side","right").put("background",true))
        .put("items",JSONArray().put(JSONObject().put("translated","إعدادات الرسومات").put("alignment","right")
            .put("box",JSONObject().put("x",.1).put("y",.2).put("w",.25).put("h",.05))))
    @Test fun spatialTextIsClippedToNormalizedRegionAndClearsOnExpiry() {
        for(size in listOf(1920 to 1080,1280 to 720,1024 to 768)) {
            val overlay=MenuOverlay();overlay.apply(message(),100)
            val bitmap=Bitmap.createBitmap(size.first,size.second,Bitmap.Config.ARGB_8888)
            overlay.draw(Canvas(bitmap),size.first,size.second,200)
            val scale=minOf(size.first/16.0,size.second/9.0)
            val vw=scale*16;val vh=scale*9;val ox=(size.first-vw)/2;val oy=(size.second-vh)/2
            var drawn=0
            for(y in 0 until size.second step 2) for(x in 0 until size.first step 2) {
                if(bitmap.getPixel(x,y)!=0) {
                    drawn++; assertTrue(x>=ox+.1*vw-2 && x<=ox+.35*vw+2)
                    assertTrue(y>=oy+.2*vh-2 && y<=oy+.25*vh+2)
                }
            }
            assertTrue("Arabic region rendered at $size",drawn>0)
            overlay.draw(Canvas(bitmap),size.first,size.second,1901);assertNull(overlay.snapshot)
        }
    }
    @Test fun malformedGeometryIsRejectedAndClearReplacesAllRegions() {
        val overlay=MenuOverlay();overlay.apply(message(),0);overlay.clear();assertNull(overlay.snapshot)
        val bad=message();bad.getJSONArray("items").getJSONObject(0).getJSONObject("box").put("x",1.1)
        try {overlay.apply(bad,0);fail("out-of-frame region accepted")} catch(_:IllegalArgumentException) {}
    }
}
