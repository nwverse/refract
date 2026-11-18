package com.example.refract.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import refract.generated.ChatBlock

/** Plain host-JVM projection behavior; no Android device, emulator or rendering claim. */
class MessageProjectionTest {
    @Test
    fun appendAndUpdateRetainOrderAndIndependentStableIds() {
        val projection = MessageProjection(messageCapacity = 2, blockCapacity = 3)
        projection.create("m1", 1, listOf(block("b1", "first"), block("b2", "second")))
        val initial = projection.snapshot
        projection.append("m1", 2, listOf(block("b3", "third 🌸")))
        assertEquals(listOf("b1", "b2", "b3"), projection.snapshot.single().blocks.map { it.id })
        assertNotSame(initial, projection.snapshot)

        val appended = projection.snapshot
        projection.update("m1", 3, block("b2", "updated"))
        assertEquals(listOf("first", "updated", "third 🌸"), projection.snapshot.single().blocks.map { it.text })
        assertEquals(3L, projection.snapshot.single().revision)
        assertSame(appended.single().blocks[0], projection.snapshot.single().blocks[0])

        projection.create("m2", 1, listOf(block("other", "independent")))
        assertEquals(listOf("m1", "m2"), projection.snapshot.map { it.id })
    }

    @Test
    fun duplicateIsNoOpAndConflictingOrStaleInputIsAtomic() {
        val projection = MessageProjection(2, 3)
        projection.create("m1", 1)
        projection.append("m1", 2, listOf(block("b1", "accepted")))
        val accepted = projection.snapshot
        projection.append("m1", 2, listOf(block("b1", "accepted")))
        assertSame(accepted, projection.snapshot)
        assertRejected(ProjectionRejection.CONFLICTING_REVISION, projection) {
            projection.append("m1", 2, listOf(block("b2", "conflict")))
        }
        assertRejected(ProjectionRejection.STALE_REVISION, projection) {
            projection.update("m1", 1, block("b1", "stale"))
        }
        assertRejected(ProjectionRejection.DUPLICATE_APPEND, projection) {
            projection.append("m1", 3, listOf(block("b2", "new"), block("b1", "duplicate")))
        }
        assertEquals(listOf("b1"), projection.snapshot.single().blocks.map { it.id })
    }

    @Test
    fun terminalFinalizeIsIdempotentAndRejectsEveryLaterMutation() {
        val projection = MessageProjection(1, 2)
        projection.create("m1", 1, listOf(block("b1", "text")))
        projection.finalize("m1", 2)
        val finalized = projection.snapshot
        projection.finalize("m1", 2)
        assertSame(finalized, projection.snapshot)
        assertTrue(projection.snapshot.single().finalized)
        assertRejected(ProjectionRejection.ALREADY_FINAL, projection) {
            projection.update("m1", 3, block("b1", "reopened"))
        }
        assertRejected(ProjectionRejection.ALREADY_FINAL, projection) {
            projection.append("m1", 4, listOf(block("b2", "late")))
        }
        assertRejected(ProjectionRejection.CONFLICTING_REVISION, projection) {
            projection.finalize("m1", 3)
        }
    }

    @Test
    fun finalizedReplayUsesRevisionBeforeTerminalBarrierAndKeepsExactDuplicateNoOp() {
        val projection = MessageProjection(1, 3)
        projection.create("m1", 1, listOf(block("b1", "text")))
        projection.finalize("m1", 2)
        val finalized = projection.snapshot
        projection.append("m1", 2, listOf(block("b1", "text")))
        assertSame(finalized, projection.snapshot)
        projection.update("m1", 2, block("b1", "text"))
        assertSame(finalized, projection.snapshot)
        assertRejected(ProjectionRejection.STALE_REVISION, projection) {
            projection.update("m1", 1, block("b1", "text"))
        }
        assertRejected(ProjectionRejection.ALREADY_FINAL, projection) {
            projection.append("m1", 3, listOf(block("b2", "new")))
        }
        // An empty append has no identical prior payload; the same revision conflicts before the terminal barrier.
        assertRejected(ProjectionRejection.CONFLICTING_REVISION, projection) {
            projection.append("m1", 2, emptyList())
        }
    }

    @Test
    fun capacityAndOwnershipHaveNoImplicitEvictionOrBlockMove() {
        val projection = MessageProjection(1, 1)
        projection.create("m1", 1, listOf(block("shared", "first")))
        val full = projection.snapshot
        assertRejected(ProjectionRejection.CAPACITY, projection) {
            projection.create("m2", 1)
        }
        assertRejected(ProjectionRejection.CAPACITY, projection) {
            projection.append("m1", 2, listOf(block("new", "overflow")))
        }
        projection.update("m1", 2, block("shared", "updated"))
        val twoMessages = MessageProjection(2, 2)
        twoMessages.create("m1", 1, listOf(block("shared", "first")))
        twoMessages.create("m2", 1)
        val before = twoMessages.snapshot
        assertRejected(ProjectionRejection.BLOCK_OWNERSHIP, twoMessages) {
            twoMessages.append("m2", 2, listOf(block("shared", "moved")))
        }
    }

    @Test
    fun invalidRevisionAndIdentitiesAreRejectedBeforePublishing() {
        val projection = MessageProjection(1, 2)
        assertRejected(ProjectionRejection.REVISION_RANGE, projection) {
            projection.create("m1", 0)
        }
        assertRejected(ProjectionRejection.REVISION_RANGE, projection) {
            projection.create("m1", -1)
        }
        projection.create("m1", Long.MAX_VALUE, listOf(block("b1", "maximum")))
        assertEquals(Long.MAX_VALUE, projection.snapshot.single().revision)
        assertRejected(ProjectionRejection.INVALID_IDENTITY, projection) {
            projection.create("", 1)
        }
    }

    private fun assertRejected(reason: ProjectionRejection, projection: MessageProjection, action: () -> Unit) {
        val before = projection.snapshot
        val failure = try {
            action()
            null
        } catch (error: ProjectionException) {
            error
        }
        assertEquals(reason, failure?.reason)
        assertSame(before, projection.snapshot)
    }

    private fun block(id: String, text: String) = ChatBlock(id = id, text = text)
}
