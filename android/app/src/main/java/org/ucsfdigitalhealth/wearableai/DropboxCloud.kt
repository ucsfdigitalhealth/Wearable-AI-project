package org.ucsfdigitalhealth.wearableai

import android.app.Activity
import com.dropbox.core.DbxRequestConfig
import com.dropbox.core.android.Auth
import com.dropbox.core.oauth.DbxCredential
import com.dropbox.core.v2.DbxClientV2
import com.dropbox.core.v2.files.WriteMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.FileInputStream

/** Direct Dropbox OAuth2 PKCE: the app key is public, but no access token is committed. */
class DropboxCloud {
    private var credential: DbxCredential? = null
    private var awaitingCallback = false
    private val _status = MutableStateFlow("Not connected to Dropbox")
    val status: StateFlow<String> = _status
    val isLinked: Boolean get() = credential != null
    val isConfigured: Boolean get() = BuildConfig.DROPBOX_APP_KEY.isNotBlank()

    fun connect(activity: Activity) {
        if (!isConfigured) {
            _status.value = "Set DROPBOX_APP_KEY in ~/.gradle/gradle.properties to enable Dropbox"
            return
        }
        awaitingCallback = true
        _status.value = "Connecting to Dropbox..."
        try {
            Auth.startOAuth2PKCE(activity, BuildConfig.DROPBOX_APP_KEY,
                DbxRequestConfig("WearableAI-Android"), listOf("files.content.write"))
        } catch (ex: Exception) {
            awaitingCallback = false
            _status.value = "Dropbox authorization failed: " + ex.message
        }
    }

    fun onResumeAfterAuth() {
        if (!awaitingCallback) return
        awaitingCallback = false
        val result = Auth.getDbxCredential()
        if (result != null) {
            credential = result
            _status.value = "Dropbox connected (this app session)"
        } else {
            _status.value = "Dropbox authorization canceled or incomplete"
        }
    }

    /** User-triggered upload only. Never sends biometric or GPS data without explicit action. */
    suspend fun upload(files: List<RecordingStore.ExportFile>, participantId: String) = withContext(Dispatchers.IO) {
        val token = credential ?: error("Connect Dropbox first")
        require(participantId.matches(Regex("[A-Za-z0-9_-]{1,40}"))) {
            "Participant ID must contain only letters, numbers, _ or -"
        }
        require(files.isNotEmpty()) { "There are no exported files to upload" }
        val client = DbxClientV2(DbxRequestConfig("WearableAI-Android"), token)
        var done = 0
        for (item in files) {
            require(item.file.isFile) { "CSV missing: " + item.file.name }
            require(item.bytes < 140L * 1024 * 1024) {
                "File exceeds 140MB single-upload safety limit: " + item.file.name
            }
            val remote = "/VeritySense_Study/$participantId/${item.day}/${item.file.name}"
            FileInputStream(item.file).use { input ->
                client.files().uploadBuilder(remote).withMode(WriteMode.OVERWRITE).uploadAndFinish(input)
            }
            done++
            _status.value = "Uploaded $done/${files.size} files"
        }
        _status.value = "Dropbox upload complete: $done files"
    }

    fun report(error: Throwable) { _status.value = "Dropbox upload failed: " + error.message }
}
