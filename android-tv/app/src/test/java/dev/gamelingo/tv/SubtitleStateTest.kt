package dev.gamelingo.tv
import org.junit.Assert.*
import org.junit.Test
class SubtitleStateTest {
    @Test fun finalEntryExpiresWithoutAnyNewMessagesAndCannotResurrect() {
        val s=SubtitleState();s.show("last","last",1000,8000,3)
        for(now in 2000L..8000L step 1000L) s.show("last","last",now,8000,3)
        s.expire(9000);assertTrue(s.entries.isEmpty())
        s.show("last","last",9100,8000,3);assertTrue(s.entries.isEmpty())
    }
    @Test fun disappearanceRespectsMinimumAndGraceAndFade() {
        val s=SubtitleState();s.show("a","sentence",0,8000,3)
        s.disappeared("a",1000,4000,1500)
        assertEquals(4000L,s.entries[0].until)
        assertEquals(.5f,s.alpha(s.entries[0],3900,200),.001f)
        s.show("b","second",2000,8000,3)
        s.expire(4000);assertEquals(listOf("b"),s.entries.map{it.id})
        s.clear();s.show("a","sentence",5000,4000,3);assertEquals(1,s.entries.size)
    }
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
