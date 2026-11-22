package com.example.refract.ime

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.text.Spanned
import android.view.inputmethod.InputMethodManager
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real software-keyboard evidence for the exact staged generated host.
 *
 * This test never sets text, invokes InputConnection, injects keys, pastes, or
 * creates a Chinese candidate. Missing prerequisites are failures, not skips.
 */
@RunWith(AndroidJUnit4::class)
class RealChineseImeInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private lateinit var device: UiDevice
    private lateinit var scenario: ActivityScenario<RealImeHostActivity>
    private lateinit var requiredIme: ComponentName
    private lateinit var requiredVersion: String
    private lateinit var requiredLocale: String
    private lateinit var requiredMode: String
    private lateinit var requiredTarget: String
    private lateinit var requiredHostClass: String
    private lateinit var candidate: String
    private var keyResourcePrefix: String? = null
    private var doneResourceId: String? = null

    @Before
    fun requireNamedRealChineseIme() {
        val arguments = InstrumentationRegistry.getArguments()
        requiredIme = ComponentName.unflattenFromString(required(arguments, "requiredIme"))
            ?: throw AssertionError("requiredIme must be a flattened Android component")
        requiredVersion = required(arguments, "requiredImeVersion")
        requiredLocale = required(arguments, "requiredImeLocale")
        requiredMode = required(arguments, "requiredImeMode")
        requiredTarget = required(arguments, "requiredTarget")
        requiredHostClass = required(arguments, "requiredHostClass")
        require(requiredHostClass == "emulator" || requiredHostClass == "device") {
            "requiredHostClass must be exactly emulator or device"
        }
        candidate = required(arguments, "requiredCandidate")
        require(candidate.codePointCount(0, candidate.length) == 1) {
            "requiredCandidate must identify one candidate, not composed test input"
        }
        require(Character.UnicodeScript.of(candidate.codePointAt(0)) == Character.UnicodeScript.HAN) {
            "This bounded test requires an actual Han candidate; it never synthesizes one"
        }
        keyResourcePrefix = arguments.getString("imeKeyResourcePrefix")?.ifBlank { null }
        doneResourceId = arguments.getString("imeDoneResourceId")?.ifBlank { null }

        val context = instrumentation.targetContext
        val packageManager = context.packageManager
        val inputMethods = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        val actualDefault = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.DEFAULT_INPUT_METHOD,
        )
        assertEquals(
            "Select the authorized IME in system Settings before this test; the test never changes it",
            requiredIme.flattenToShortString(),
            actualDefault,
        )
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_INPUT_METHODS,
        ).orEmpty().split(':')
        assertTrue("The named IME must already be enabled", requiredIme.flattenToShortString() in enabled)

        val info = inputMethods.enabledInputMethodList.firstOrNull {
            ComponentName(it.packageName, it.serviceName) == requiredIme
        } ?: throw AssertionError("The named IME is not exposed as an enabled input method")
        assertEquals(
            "Record and pass the exact installed IME version",
            requiredVersion,
            packageManager.getPackageInfo(requiredIme.packageName, 0).versionName,
        )
        val service = packageManager.getServiceInfo(requiredIme, 0)
        assertEquals("The selected component must be an input-method service",
            android.Manifest.permission.BIND_INPUT_METHOD, service.permission)

        val currentSubtype = inputMethods.currentInputMethodSubtype
            ?: throw AssertionError("No selected input-method subtype is observable")
        assertEquals(
            "Select the named Chinese Pinyin subtype in the IME/system UI before testing",
            requiredLocale,
            currentSubtype.locale,
        )
        assertEquals(
            "Select the named Pinyin mode in the IME/system UI before testing",
            requiredMode,
            currentSubtype.mode,
        )
        assertEquals("Chinese", "zh", currentSubtype.locale.substringBefore('_').substringBefore('-'))
        val subtypes = List(info.subtypeCount) { info.getSubtypeAt(it) }
        assertTrue("The selected subtype must belong to the named IME", subtypes.any {
            it.locale == currentSubtype.locale && it.mode == currentSubtype.mode
        })

        device = UiDevice.getInstance(instrumentation)
        device.waitForIdle()
        println(
            "REAL_IME_TARGET package=${requiredIme.packageName} version=$requiredVersion " +
                "component=${requiredIme.flattenToShortString()} locale=${currentSubtype.locale} " +
                "mode=${currentSubtype.mode} sdk=${Build.VERSION.SDK_INT} " +
                "release=${Build.VERSION.RELEASE} sdkBuild=${Build.VERSION.SDK_INT} build=${Build.ID} " +
                "target=$requiredTarget host=$requiredHostClass",
        )
        scenario = ActivityScenario.launch(RealImeHostActivity::class.java)
        resetHost()
    }

    @After
    fun closeHost() {
        if (::scenario.isInitialized) scenario.close()
    }

    @Test
    fun pinyinCandidateFocusDoneAndRetainedDraftUseRealKeyboard() {
        clickGeneratedHost()
        requireImeWindow()

        clickImeKey('n')
        assertNative("the first actual Pinyin key") {
            it.text == "n" && it.parentDraft.isEmpty() && it.composing && it.composingSpan
        }
        clickImeKey('i')
        assertNative("the complete actual Pinyin preedit") {
            it.text == "ni" && it.parentDraft.isEmpty() && it.composing && it.composingSpan
        }
        assertEquals("Candidate selection has not happened yet", emptyList<String>(), nativeSnapshot().events)

        scenario.onActivity { RealImeHostState.unrelatedRevision += 1 }
        assertNative("host recomposition") {
            it.text == "ni" && it.parentDraft.isEmpty() && it.composing && it.composingSpan
        }

        val choices = device.wait(Until.findObjects(imeSelector(By.text(candidate))), IME_WAIT_MS)
            .filter { it.visibleBounds.height() > 0 && it.visibleBounds.width() > 0 }
        assertEquals("Exactly one visible candidate named by the target owner is required",
            1, choices.size)
        choices.single().click()
        assertNative("the real candidate commit") {
            it.text == candidate && it.parentDraft == candidate &&
                !it.composing && !it.composingSpan && it.events.isEmpty()
        }

        clickApp("otherField", "Other field")
        assertNative("focus transfer to another native field") {
            !it.focused && it.text == candidate && it.parentDraft == candidate && !it.composing
        }
        assertTrue("The other field must actually own focus", device.wait(
            Until.hasObject(By.res(APP_PACKAGE, "otherField").focused(true)), TIMEOUT_MS,
        ))

        val selectionBeforeRestore = nativeSnapshot()
        clickApp("restoreFocus", "Restore generated focus")
        assertNative("focusRequest restoration") {
            it.focused && it.text == candidate && it.parentDraft == candidate &&
                it.selectionStart == selectionBeforeRestore.selectionStart &&
                it.selectionEnd == selectionBeforeRestore.selectionEnd
        }
        requireImeWindow()

        val doneSelectors = doneResourceId?.let { listOf(imeSelector(By.res(it))) } ?: listOf(
            imeSelector(By.desc("Done")), imeSelector(By.text("Done")),
            imeSelector(By.desc("完成")), imeSelector(By.text("完成")),
        )
        findUniqueImeControl(*doneSelectors.toTypedArray()).click()
        assertNative("native Done ordering and keyboard dismissal") {
            it.events == listOf("draft:$candidate", "commit") && !it.focused &&
                it.text == candidate && it.parentDraft == candidate
        }
        assertTrue("Done must dismiss the actual software keyboard",
            device.wait(Until.gone(By.pkg(requiredIme.packageName)), IME_WAIT_MS))

        clickApp("removeHost", "Remove host")
        assertTrue("The generated host must be removed",
            device.wait(Until.gone(By.res(APP_PACKAGE, "generatedHost")), TIMEOUT_MS))
        assertEquals(candidate, nativeModelDraft())
        clickApp("restoreHost", "Restore host")
        assertNative("parent-owned draft after host recreation") {
            it.focused && it.text == candidate && it.parentDraft == candidate &&
                it.events == listOf("draft:$candidate", "commit")
        }
        println("REAL_IME_RESULT candidate=$candidate preedit=ni focus=restored done=ordered draft=retained")
    }

    private fun clickGeneratedHost() {
        assertTrue("The exact generated host must be visible", device.wait(
            Until.hasObject(By.res(APP_PACKAGE, "generatedHost")), TIMEOUT_MS,
        ))
        device.findObject(By.res(APP_PACKAGE, "generatedHost")).click()
        assertNative("native focus before typing") { it.focused }
    }

    private fun requireImeWindow() {
        val keys = device.wait(Until.findObjects(By.pkg(requiredIme.packageName)), IME_WAIT_MS)
        assertTrue("The named IME has no visible software-keyboard window", keys.any {
            it.visibleBounds.height() > 0 && it.visibleBounds.width() > 0
        })
    }

    private fun clickImeKey(letter: Char) {
        val prefix = keyResourcePrefix
        val selectors = if (prefix != null) {
            listOf(imeSelector(By.res(prefix + letter)))
        } else {
            listOf(imeSelector(By.text(letter.toString())), imeSelector(By.desc(letter.toString())))
        }
        findUniqueImeControl(*selectors.toTypedArray()).click()
    }

    private fun findUniqueImeControl(vararg selectors: BySelector): UiObject2 {
        val deadline = SystemClock.uptimeMillis() + IME_WAIT_MS
        var matches = emptyList<UiObject2>()
        do {
            matches = selectors.flatMap { device.findObjects(it) }
                .filter { it.visibleBounds.height() > 0 && it.visibleBounds.width() > 0 }
                .distinctBy { it.visibleBounds }
            if (matches.size == 1) return matches.single()
            SystemClock.sleep(POLL_MS)
        } while (SystemClock.uptimeMillis() < deadline)
        throw AssertionError(
            "The named IME must expose one visible real keyboard control; found ${matches.size}. " +
                "Provide its key resource prefix or choose a supported Pinyin layout. Never inject text instead.",
        )
    }

    private fun imeSelector(selector: BySelector): BySelector = selector.pkg(requiredIme.packageName)

    private fun clickApp(resourceId: String, visibleText: String) {
        val selector = By.res(APP_PACKAGE, resourceId)
        assertTrue("Missing test control $visibleText", device.wait(Until.hasObject(selector), TIMEOUT_MS))
        device.findObject(selector).click()
    }

    private fun nativeSnapshot(): EditorSnapshot = assertNative("an attached generated host") { true }

    private fun assertNative(description: String, predicate: (EditorSnapshot) -> Boolean): EditorSnapshot {
        val deadline = SystemClock.uptimeMillis() + TIMEOUT_MS
        var latest: EditorSnapshot? = null
        do {
            var snapshot: EditorSnapshot? = null
            scenario.onActivity {
                val editor = RealImeHostState.editor
                if (editor != null && editor.value.isAttachedToWindow) {
                    val text = editor.value.text
                    val spans = text.getSpans(0, text.length, Any::class.java)
                    snapshot = EditorSnapshot(
                        text = text.toString(),
                        parentDraft = RealImeHostState.model.draft,
                        events = RealImeHostState.model.events.toList(),
                        composing = editor.hasComposition,
                        composingSpan = spans.any {
                            text.getSpanFlags(it) and Spanned.SPAN_COMPOSING != 0
                        },
                        focused = editor.value.isFocused,
                        selectionStart = editor.value.selectionStart,
                        selectionEnd = editor.value.selectionEnd,
                    )
                }
            }
            snapshot?.let {
                latest = it
                if (predicate(it)) return it
            }
            SystemClock.sleep(POLL_MS)
        } while (SystemClock.uptimeMillis() < deadline)
        throw AssertionError("Native state did not satisfy $description; last=$latest")
    }

    private fun nativeModelDraft(): String {
        var draft: String? = null
        scenario.onActivity { draft = RealImeHostState.model.draft }
        return draft ?: throw AssertionError("The host activity is unavailable")
    }

    private fun resetHost() {
        scenario.onActivity {
            val stale = RealImeHostState.editor
            RealImeHostState.editor = null
            stale?.release()
            RealImeHostState.hostVisible = false
        }
        assertTrue("The old host must be removed before resetting state", device.wait(
            Until.gone(By.res(APP_PACKAGE, "generatedHost")), TIMEOUT_MS,
        ))
        scenario.onActivity {
            RealImeHostState.model = RecordingComposerModel()
            RealImeHostState.unrelatedRevision = 0
            RealImeHostState.hostVisible = true
        }
        assertNative("a fresh empty generated host") {
            it.focused && it.text.isEmpty() && it.parentDraft.isEmpty() && it.events.isEmpty()
        }
    }

    private data class EditorSnapshot(
        val text: String,
        val parentDraft: String,
        val events: List<String>,
        val composing: Boolean,
        val composingSpan: Boolean,
        val focused: Boolean,
        val selectionStart: Int,
        val selectionEnd: Int,
    )

    private companion object {
        const val APP_PACKAGE = "com.example.refract.ime"
        const val TIMEOUT_MS = 5_000L
        const val IME_WAIT_MS = 8_000L
        const val POLL_MS = 100L

        fun required(arguments: Bundle, name: String): String =
            arguments.getString(name)?.takeIf { it.isNotBlank() }
                ?: throw AssertionError("Missing instrumentation argument -e $name <value>; refusing to guess")
    }
}
