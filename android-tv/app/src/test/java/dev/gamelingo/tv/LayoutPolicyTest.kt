package dev.gamelingo.tv
import org.junit.Assert.*
import org.junit.Test
class LayoutPolicyTest {
    @Test fun onePixelAndStableNewest() {
        val a=LayoutPolicy.anchor(1920f,1080f,1200f,50f,24f,0f,0f)
        val b=LayoutPolicy.anchor(1920f,1080f,1200f,50f,24f,1f,-1f)
        assertEquals(1f,b.first-a.first,.001f);assertEquals(-1f,b.second-a.second,.001f)
        val wrapped=LayoutPolicy.anchor(1920f,1080f,1200f,100f,24f,0f,0f)
        assertEquals(a,wrapped)
    }
    @Test fun safeBoundsAndOldestEviction() {
        val a=LayoutPolicy.anchor(1920f,1080f,1200f,50f,24f,10000f,10000f)
        assertTrue(a.first<=1296f);assertTrue(a.second<=1056f)
        assertEquals(2,LayoutPolicy.retained(listOf(60f,60f,60f),140f,10f))
        assertEquals(1,LayoutPolicy.retained(listOf(200f),100f,10f))
    }
}
