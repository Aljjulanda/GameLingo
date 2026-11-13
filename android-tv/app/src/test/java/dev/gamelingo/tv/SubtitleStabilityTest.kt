package dev.gamelingo.tv
import org.junit.Assert.*
import org.junit.Test

class SubtitleStabilityTest {
    private val box=SourceBox(.2,.65,.6,.1)
    @Test fun paraphraseAndGlyphCorrectionDoNotRewriteOrRenew() {
        val s=SubtitleState()
        s.show("a","حدث شيء ما",0,4000,3,"Something happened",box)
        s.show("b","لقد حصل أمر ما",500,8000,3,"Something happene",box)
        assertEquals(1,s.entries.size);assertEquals("حدث شيء ما",s.entries.single().text)
        assertEquals(4000L,s.entries.single().until)
    }
    @Test fun negationAndNumbersCannotBeCoalesced() {
        val s=SubtitleState();s.show("a","سنذهب",0,4000,3,"We will go",box)
        s.show("b","لن نذهب",300,4000,3,"We will not go",box)
        assertEquals(2,s.entries.size)
    }
    @Test fun importantCorrectionUsesSameCardAndClock() {
        val s=SubtitleState();s.show("a","سنذهب",0,4000,3,"We will go",box)
        s.show("a","لن نذهب",300,8000,3,"We will not go",box,meaningfulCorrection=true)
        assertEquals("لن نذهب",s.entries.single().text);assertEquals(4000L,s.entries.single().until)
    }
    @Test fun differentSpeakerAndExplicitFreshEventAreNotDuplicates() {
        val s=SubtitleState();s.show("a","انتظر",0,4000,3,"Wait",box,speaker="Arthur")
        s.show("b","انتظر",300,4000,3,"Wait",box,speaker="John")
        assertEquals(2,s.visibleEntries().size)
        s.clear();s.show("a","انتظر",0,4000,3,"Wait",box)
        s.show("b","انتظر",1000,4000,3,"Wait",box,freshEvent=true)
        assertEquals(2,s.entries.size);assertEquals(1000L,s.entries.last().shownAt)
    }
}
