package dev.gamelingo.tv

import org.junit.Assert.*
import org.junit.Test

class Maintenance021Test {
    private val box=SourceBox(.2,.72,.6,.08)
    @Test fun presentationPreservesMeaningfulPunctuation() {
        for(text in listOf("(تحرك الآن) [إطلاق نار] لماذا؟", "قال John: اجمع 11 قطعة، ثم اذهب إلى (Old Gate).", "«John» قال: \"لن نذهب\"", "سطر أول\nسطر ثان [11]")) {
            assertEquals(text,TextPresentation.clean(TextPresentation.body(text)))
        }
        assertEquals("(نص)",TextPresentation.clean("\u202e(نص)\u2069"))
        val signed=TextPresentation.body("خسرت -11 نقطة ثم قابلت García")
        assertTrue(signed.contains("\u2066-11\u2069"));assertTrue(signed.contains("\u2066García\u2069"))
        assertEquals("Arthur\u200f:\u00a0",TextPresentation.prefix("Arthur").replace("\u2066","").replace("\u2069",""))
    }
    @Test fun freshIdWithoutBoundaryEvidenceCannotStackSameLatestSource() {
        val s=SubtitleState();s.show("a","حدث شيء",0,4000,3,"Something happened",box,speaker="Arthur")
        s.show("b","لقد حصل أمر",500,8000,3,"Something happene",box,freshEvent=true,boundary="dialogue_change")
        assertEquals(1,s.entries.size);assertEquals("حدث شيء",s.entries.single().text);assertEquals(4000L,s.entries.single().until)
        s.show("b","حدث أمر",1000,8000,3,"Something happened",box,speaker="Arthur",boundary="continuity")
        assertEquals(1,s.entries.size);assertEquals(4000L,s.entries.single().until)
        s.expire(4000);s.show("b","حدث شيء",4100,8000,3,"Something happened",box,boundary="continuity")
        assertTrue(s.entries.isEmpty())
    }
    @Test fun confirmedGapAndInterveningDialogueStillAllowRealRepetition() {
        val s=SubtitleState();s.show("a","انتظر هنا",0,8000,3,"Wait here",box,speaker="Arthur")
        s.show("b","انتظر هنا",1000,8000,3,"Wait here",box,speaker="Arthur",freshEvent=true,boundary="source_gap",sourceGap=900)
        assertEquals(2,s.entries.size);assertEquals("b",s.visibleEntries().single().id)
        s.clear();s.show("a","انتظر هنا",0,8000,3,"Wait here",box,speaker="Arthur")
        s.show("b","ماذا حدث؟",500,8000,3,"What happened",box,speaker="John",freshEvent=true,boundary="speaker_change")
        s.show("c","انتظر هنا",1000,8000,3,"Wait here",box,speaker="Arthur",freshEvent=true,boundary="speaker_change")
        assertEquals(listOf("b","c"),s.visibleEntries().map {it.id});assertEquals(1000L,s.entries.last().shownAt)
    }
    @Test fun highValueInstructionsCannotCoalesce() {
        for(pair in listOf("We will go" to "We will not go","Go left" to "Go right","Collect 10 coins" to "Collect 11 coins","He is coming" to "She is coming","Open the door" to "Close the door","Follow the trail" to "Follow the train","Wait here" to "Wait there")) {
            val s=SubtitleState();s.show("a","تعليمات",0,4000,3,pair.first,box)
            s.show("b","تعليمات",200,4000,3,pair.second,box,freshEvent=true,boundary="dialogue_change")
            assertEquals(pair.toString(),2,s.entries.size);assertEquals(2,s.visibleEntries().size)
        }
    }
    @Test fun speakerEnrichmentDoesNotRenewClockAndUnknownGapIsNotProof() {
        val s=SubtitleState();s.show("a","انتظر هنا",0,4000,3,"Wait here",box)
        s.show("b","انتظر هنا!",1000,8000,3,"Wait here",box,speaker="Arthur",freshEvent=true,boundary="source_gap",sourceGap=100)
        assertEquals(1,s.entries.size);assertEquals("Arthur",s.entries.single().speaker);assertEquals(4000L,s.entries.single().until)
    }
}
