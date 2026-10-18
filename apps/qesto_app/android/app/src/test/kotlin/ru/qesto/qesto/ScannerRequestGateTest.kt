package ru.qesto.qesto

import org.junit.Assert.*
import org.junit.Test

class ScannerRequestGateTest {
    private class Result {
        val terminals = mutableListOf<String>()
    }

    @Test fun synchronousExceptionReleasesRequestAndAllowsRetry() {
        val gate = ScannerRequestGate<Result>()
        val result = Result()
        val request = gate.begin(result)!!
        try {
            throw NullPointerException("SDK startup")
        } catch (_: Exception) {
            gate.complete(request) { it.terminals += "receipt_scan_failed" }
        }
        assertEquals(listOf("receipt_scan_failed"), result.terminals)
        assertNull(gate.current)
        assertNotNull(gate.begin(Result()))
    }

    @Test fun successIsDeliveredOnlyOnce() {
        val gate = ScannerRequestGate<Result>()
        val result = Result()
        val request = gate.begin(result)!!
        assertTrue(gate.complete(request) { it.terminals += "success" })
        assertFalse(gate.complete(request) { it.terminals += "success" })
        assertEquals(listOf("success"), result.terminals)
    }

    @Test fun asyncFailureReleasesRequest() {
        val gate = ScannerRequestGate<Result>()
        val result = Result()
        val request = gate.begin(result)!!
        gate.complete(request) { it.terminals += "failure" }
        assertNull(gate.current)
        assertEquals(listOf("failure"), result.terminals)
        assertNotNull(gate.begin(Result()))
    }

    @Test fun cancelDoesNotProduceSuccessDataAndAllowsRetry() {
        val gate = ScannerRequestGate<Result>()
        val result = Result()
        val request = gate.begin(result)!!
        gate.complete(request) { it.terminals += "cancel:null" }
        assertEquals(listOf("cancel:null"), result.terminals)
        assertNotNull(gate.begin(Result()))
    }

    @Test fun overlappingTapDoesNotReplaceActiveResult() {
        val gate = ScannerRequestGate<Result>()
        val first = Result()
        val request = gate.begin(first)!!
        assertNull(gate.begin(Result()))
        assertSame(request, gate.current)
        assertTrue(gate.owns(request))
        gate.complete(request) { it.terminals += "success" }
        assertEquals(listOf("success"), first.terminals)
    }

    @Test fun activityDestroyDeliversOneTerminalAndRejectsLateCallbacks() {
        val gate = ScannerRequestGate<Result>()
        val result = Result()
        val request = gate.begin(result)!!
        gate.close { it.terminals += "closed" }
        gate.close { it.terminals += "closed" }
        assertFalse(gate.complete(request) { it.terminals += "late" })
        assertNull(gate.current)
        assertNull(gate.begin(Result()))
        assertEquals(listOf("closed"), result.terminals)
    }

    @Test fun lateCallbackNeverFinishesNewRequest() {
        val gate = ScannerRequestGate<Result>()
        val oldResult = Result()
        val old = gate.begin(oldResult)!!
        gate.complete(old) { it.terminals += "failure" }
        val newResult = Result()
        val next = gate.begin(newResult)!!
        assertFalse(gate.complete(old) { it.terminals += "late" })
        assertSame(next, gate.current)
        assertTrue(newResult.terminals.isEmpty())
        gate.complete(next) { it.terminals += "success" }
        assertEquals(listOf("failure"), oldResult.terminals)
        assertEquals(listOf("success"), newResult.terminals)
    }

    @Test fun requestReleasedBeforeTerminalResultAllowsReentrantRetry() {
        val gate = ScannerRequestGate<Result>()
        val request = gate.begin(Result())!!
        gate.complete(request) { assertNotNull(gate.begin(Result())) }
        assertNotNull(gate.current)
    }

    @Test fun recreatedActivityUsesDifferentResultCodeAndOwner() {
        val oldGate = ScannerRequestGate<Result>()
        val old = oldGate.begin(Result())!!
        oldGate.close { it.terminals += "closed" }
        val newGate = ScannerRequestGate<Result>()
        val next = newGate.begin(Result())!!
        assertNotEquals(old.id, next.id)
        assertFalse(newGate.complete(old) { fail("old Activity result") })
        assertSame(next, newGate.current)
    }

    @Test fun documentAndQrResultsDoNotShareTheirLease() {
        val qr = ScannerRequestGate<Result>()
        val document = ScannerRequestGate<Result>()
        val qrRequest = qr.begin(Result())!!
        val docResult = Result()
        val docRequest = document.begin(docResult)!!
        assertFalse(document.complete(qrRequest) { fail("wrong flow") })
        qr.close { it.terminals += "closed" }
        assertTrue(document.owns(docRequest))
        document.complete(docRequest) { it.terminals += "success" }
        assertEquals(listOf("success"), docResult.terminals)
    }
}
