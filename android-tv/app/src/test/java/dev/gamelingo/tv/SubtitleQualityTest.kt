package dev.gamelingo.tv

import org.junit.Assert.*
import org.junit.Test

class SubtitleQualityTest {
    @Test fun absentFlagsRetainLegacyDirectionAndPhysicalAlignment() {
        val off=SubtitleQuality()
        for(body in listOf("Hello!","(نعم)؟","John قال: اجمع 11 قطعة.","123 ...")) assertTrue(QualityRenderPolicy.rtl(body,off))
        val on=SubtitleQuality(arabicParagraphDirection=true)
        assertFalse(QualityRenderPolicy.rtl("Hello, John!",on))
        assertFalse(QualityRenderPolicy.rtl("123 ?!",on))
        assertTrue(QualityRenderPolicy.rtl("John، هل وصلت؟",on))
        assertTrue(QualityRenderPolicy.rtl("(نعم!)",on))
        assertFalse(QualityRenderPolicy.hasArabicLetters("؟،؛"))
        assertTrue(QualityRenderPolicy.normalAlignment("right",true))
        assertFalse(QualityRenderPolicy.normalAlignment("right",false))
        assertFalse(QualityRenderPolicy.normalAlignment("left",true))
        assertTrue(QualityRenderPolicy.normalAlignment("left",false))
    }
    @Test fun sourceMetadataNeverAddsVisibleLabels() {
        for(origin in listOf("packExact","packNormalized","packPunctuationless")) {
            assertEquals("",SubtitleQuality(provenance=origin).badge)
            assertEquals("",SubtitleQuality(provenance="reuse",basis=origin).badge)
        }
        assertEquals("",SubtitleQuality(provenance="userCorrection").badge)
        assertEquals("",SubtitleQuality(provenance="reuse",basis="userCorrection").badge)
        for(origin in listOf("","rule","argosInference","argosCache","command","apple","arbitrary")) assertEquals("",SubtitleQuality(provenance=origin).badge)
        assertEquals("",SubtitleQuality(provenance="reuse",basis="argosInference").badge)
        assertFalse(SubtitleQuality().decorated)
    }
    @Test fun presentationLookupResolvesAliasesWithoutExtendingOrResurrectingCards() {
        val s=SubtitleState(); val box=SourceBox(.2,.72,.6,.08)
        s.show("first","انتظر هنا",0,4000,3,"Wait here",box)
        s.show("alias","انتظر هنا!",500,8000,3,"Wait here",box,freshEvent=true,boundary="continuity")
        assertSame(s.renderEntry("first"),s.renderEntry("alias"))
        assertEquals(4000L,s.renderEntry("alias")!!.until)
        s.expire(4000); assertNull(s.renderEntry("alias"))
        s.show("alias","انتظر هنا",4100,8000,3,"Wait here",box)
        assertNull(s.renderEntry("alias"))
    }
}
