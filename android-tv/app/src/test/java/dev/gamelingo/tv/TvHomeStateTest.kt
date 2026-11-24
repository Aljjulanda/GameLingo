package dev.gamelingo.tv

import org.junit.Assert.*
import org.junit.Test

class TvHomeStateTest {
    @Test fun permissionIsTheOnlyPrerequisiteWhenMissing() {
        val state = TvHomeState.describe(false,true,true,true,false,false)
        assertEquals(TvHomeAction.PERMISSION,state.action)
        assertFalse(state.title.contains("متصل"))
    }
    @Test fun firstRunOffersPairingWithoutClaimingReadiness() {
        assertEquals(TvHomeAction.PAIR,TvHomeState.describe(true,false,false,false,false,false).action)
    }
    @Test fun savedSourceReconnectsWithoutNewPairing() {
        assertEquals(TvHomeAction.CONNECT,TvHomeState.describe(true,true,false,false,false,false).action)
    }
    @Test fun previewIsClearlySeparateFromAuthenticatedReception() {
        val preview = TvHomeState.describe(true,true,true,false,false,true)
        assertEquals(TvHomeAction.CONNECT,preview.action)
        assertTrue(preview.title.contains("معاينة"))
        assertEquals(TvHomeAction.STOP,TvHomeState.describe(true,true,true,true,false,false).action)
    }
    @Test fun pendingAndTerminalFailuresHaveDifferentNextActions() {
        assertEquals(TvHomeAction.STOP,TvHomeState.describe(true,true,true,false,true,false).action)
        val terminal = TvHomeState.describe(true,true,true,false,false,false)
        assertEquals(TvHomeAction.PAIR,terminal.action)
        assertTrue(terminal.title.contains("مراجعة"))
    }
    @Test fun oldRuntimeStatusCannotClaimConnectionAfterServiceStopped() {
        val state = TvHomeState.describe(true,true,false,true,false,false)
        assertEquals(TvHomeAction.CONNECT,state.action)
        assertFalse(state.title.contains("متصل"))
    }
}
