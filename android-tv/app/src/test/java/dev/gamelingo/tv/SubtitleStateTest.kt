package dev.gamelingo.tv
import org.junit.Assert.*
import org.junit.Test
class SubtitleStateTest {
    private val captionBox=SourceBox(.2,.65,.6,.1)
    @Test fun distinctEventsWithIdenticalArabicRenderOnceWithoutLosingNewEventClock() {
        val s=SubtitleState()
        s.show("a","انتظر!",0,8000,3,"Wait!",captionBox)
        s.show("b","انتظر.",500,4000,3,"Hold on!",captionBox)
        assertEquals(2,s.entries.size)
        assertEquals(listOf("b"),s.visibleEntries().map {it.id})
        assertEquals(4500L,s.visibleEntries().single().until)
        s.expire(4500);assertTrue(s.visibleEntries().isEmpty())
        s.show("c","انتظر!",4600,4000,3,"Wait!",captionBox)
        assertEquals(listOf("c"),s.visibleEntries().map {it.id})
        assertEquals(8600L,s.visibleEntries().single().until)
    }
    @Test fun dropoutReappearanceAndGlyphCorrectionDoNotStackOrRenew() {
        val s=SubtitleState()
        s.show("a","انتظر هنا!",0,4000,3,"Wait here!",captionBox)
        s.disappeared("a",1500,4000,1500)
        s.show("b","انتظر هنا.",2000,8000,3,"Wait nere!",captionBox)
        assertEquals(1,s.entries.size);assertEquals(4000L,s.entries.single().until)
        s.show("b","انتظر هنا!",2500,8000,3,"Wait here!",captionBox)
        assertEquals(1,s.entries.size);assertEquals(4000L,s.entries.single().until)
        s.disappeared("b",2600,1000,500);assertEquals(3100L,s.entries.single().until)
        s.expire(3100);s.show("b","انتظر هنا!",3200,8000,3,"Wait here!",captionBox)
        assertTrue(s.entries.isEmpty())
        s.show("fresh-repeat","انتظر هنا!",3300,4000,3,"Wait here!",captionBox)
        assertEquals(3300L,s.entries.single().shownAt)
    }
    @Test fun identicalArabicIsNotEnoughAndNumbersRemainDistinct() {
        val s=SubtitleState()
        s.show("a","انتظر!",0,4000,3,"Wait!",captionBox)
        s.show("b","انتظر!",500,4000,3,"Hold on!",captionBox)
        assertEquals(2,s.entries.size)
        s.clear();s.show("a","اجمع العملات",0,4000,3,"Collect 10 coins",captionBox)
        s.show("b","اجمع العملات",500,4000,3,"Collect 11 coins",captionBox)
        assertEquals(2,s.entries.size)
    }
    @Test fun genuineRepeatAfterInterveningDialogueMovesToNewestWithNewClock() {
        val s=SubtitleState();s.show("a","انتظر!",0,4000,3,"Wait!",captionBox)
        s.show("b","اركض!",500,4000,3,"Run!",captionBox)
        s.show("c","انتظر!",1000,4000,3,"Wait!",captionBox)
        assertEquals(listOf("b","c"),s.entries.map {it.id});assertEquals(1000L,s.entries.last().shownAt)
        assertEquals(5000L,s.entries.last().until)
    }
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
        s.show("a","corrected",1000,8000,3);s.show("a","corrected",2000,8000,3)
        assertEquals(1,s.entries.size);assertEquals(4000L,s.entries[0].until)
        s.show("b","corrected",2100,8000,3)
        assertEquals(2,s.entries.size) // A genuine new event may have identical Arabic.
    }
    @Test fun repeatedArabicAroundAnotherEventIsNotSuppressed() {
        val s=SubtitleState();s.show("a","انتظر!",0,4000,3)
        s.show("b","اركض!",500,4000,3);s.show("c","انتظر!",1000,4000,3)
        s.show("a","انتظر هنا!",1200,8000,3)
        assertEquals(listOf("a","b","c"),s.entries.map{it.id})
        assertEquals(4000L,s.entries.first().until)
    }
    @Test fun durationsAndReset() {
        val s=SubtitleState()
        assertEquals(4000L,s.duration("hi",true,13.0,4000,8000,5000))
        assertEquals(8000L,s.duration("x".repeat(300),true,13.0,4000,8000,5000))
        assertEquals(6000L,s.duration("hi",false,13.0,4000,8000,6000))
        s.show("a","first",0,4000,3);s.clear();assertTrue(s.entries.isEmpty())
    }
}
