package dev.gamelingo.tv
import org.junit.Assert.*
import org.junit.Test
class SubtitleStateTest {
    @Test fun tenSentencesAndIndependentTimers() {
        val s=SubtitleState()
        for(i in 0..9) {
            s.show("$i","sentence $i",i*1000L,4000,3)
            assertTrue(s.entries.size<=3)
            assertEquals("$i",s.entries.last().id)
            assertEquals(i*1000L,s.entries.last().shownAt)
            if(i>=3) assertEquals("${i-2}",s.entries.first().id)
        }
        s.expire(11000);assertEquals(listOf("8","9"),s.entries.map{it.id})
        s.expire(13000);assertTrue(s.entries.isEmpty())
    }
    @Test fun correctionsDoNotResetTimersAndDuplicateDoesNotStack() {
        val s=SubtitleState();s.show("a","first",0,4000,3)
        s.show("a","corrected",1000,8000,3);s.show("b","corrected",2000,8000,3)
        assertEquals(1,s.entries.size);assertEquals(4000L,s.entries[0].until)
    }
    @Test fun durationsAndReset() {
        val s=SubtitleState()
        assertEquals(4000L,s.duration("hi",true,13.0,4000,8000,5000))
        assertEquals(8000L,s.duration("x".repeat(300),true,13.0,4000,8000,5000))
        assertEquals(6000L,s.duration("hi",false,13.0,4000,8000,6000))
        s.show("a","first",0,4000,3);s.clear();assertTrue(s.entries.isEmpty())
    }
}
