package com.example.refract.rendercheck

import android.app.Application
import android.content.ComponentName
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.example.refract.R
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w400dp-h800dp-xxhdpi", application = Application::class)
class ResourceResolutionTest {
    @Test
    fun reportApplicationAndTargetPackages() {
        val application = ApplicationProvider.getApplicationContext<Application>()
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        println("NATIVE_JVM_APPLICATION_PACKAGE=" + application.packageName)
        println("NATIVE_JVM_TARGET_PACKAGE=" + target.packageName)
        println("NATIVE_JVM_QUALIFIERS=" + application.resources.configuration)
        println("NATIVE_JVM_MANIFEST=" + System.getProperty("robolectric.manifest"))
        println("NATIVE_JVM_MAIN=" + target.packageManager.getActivityInfo(
            ComponentName("com.example.refract", "com.example.refract.MainActivity"), 0,
        ))
        println("NATIVE_JVM_ACTIVITIES=" + target.packageManager.getPackageInfo(
            application.packageName, PackageManager.GET_ACTIVITIES,
        ).activities?.joinToString { it.name })
        println("NATIVE_JVM_ACTIVITY=" + runCatching {
            target.packageManager.getActivityInfo(ComponentName(application, RenderCheckActivity::class.java), 0)
        })
        assertEquals("Profile", application.resources.getString(R.string.settings_profile))
        assertEquals("Notifications", application.resources.getString(R.string.settings_notifications))
        assertEquals("Save", application.resources.getString(R.string.settings_save))
    }
}
