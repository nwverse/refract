package com.example.refract.selection

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Native JVM test for the drop-target cancellation and unicode contract.
 *
 * These tests run against a plain JVM (Robolectric not required) and exercise the
 * same gating logic the generated Kotlin emits: a drop is accepted only when the
 * payload is non-empty, and a Unicode (non-BMP + CJK) payload round-trips unchanged.
 * No real clipboard is read; payloads are synthetic local strings.
 *
 * Evidence level: source / Native JVM. Not an emulator, not a device.
 */
class DropTargetContractTest {
    /** Mirrors the gate in the generated Kotlin wrapper for a `dropTarget` operation. */
    private fun gate(payload: String?, action: (String) -> Unit): Boolean {
        val text = payload ?: return false
        if (text.isEmpty()) return false
        action(text)
        return true
    }

    @Test
    fun emptyPayloadCancelsDropWithoutCallingAction() {
        var called = false
        val accepted = gate("") { called = true }
        assertFalse(accepted)
        assertFalse(called)
    }

    @Test
    fun nullPayloadCancelsDropWithoutCallingAction() {
        var called = false
        val accepted = gate(null) { called = true }
        assertFalse(accepted)
        assertFalse(called)
    }

    @Test
    fun nonEmptyPayloadInvokesActionOnce() {
        val received = mutableListOf<String>()
        val accepted = gate("hello") { received.add(it) }
        assertTrue(accepted)
        assertEquals(listOf("hello"), received)
    }

    @Test
    fun nonBmpEmojiPayloadRoundTripsUnchanged() {
        // 🌸 U+1F33A is outside the BMP and exercises surrogate-pair handling.
        val payload = "🌸"
        val received = mutableListOf<String>()
        val accepted = gate(payload) { received.add(it) }
        assertTrue(accepted)
        assertEquals(listOf(payload), received)
        // Length sanity: one code point, two UTF-16 code units.
        assertEquals(2, received[0].length)
        assertEquals(1, received[0].codePointCount(0, received[0].length))
    }

    @Test
    fun cjkPayloadRoundTripsUnchanged() {
        val payload = "汉字"
        val received = mutableListOf<String>()
        val accepted = gate(payload) { received.add(it) }
        assertTrue(accepted)
        assertEquals(listOf(payload), received)
    }

    @Test
    fun mixedUnicodePayloadRoundTripsUnchanged() {
        val payload = "🌸 汉字 mixed ascii"
        val received = mutableListOf<String>()
        val accepted = gate(payload) { received.add(it) }
        assertTrue(accepted)
        assertEquals(listOf(payload), received)
    }

    @Test
    fun whitespaceOnlyPayloadIsAcceptedByGate() {
        // Whitespace is not "empty": the generated gate rejects only the empty string,
        // not blank payloads. The model layer is responsible for further trimming.
        val received = mutableListOf<String>()
        val accepted = gate("  ") { received.add(it) }
        assertTrue(accepted)
        assertEquals(listOf("  "), received)
    }
}
