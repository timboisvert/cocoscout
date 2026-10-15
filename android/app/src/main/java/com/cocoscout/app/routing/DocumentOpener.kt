package com.cocoscout.app.routing

import android.content.ActivityNotFoundException
import android.content.Intent
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import dev.hotwire.core.config.Hotwire
import dev.hotwire.navigation.activities.HotwireActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * Downloads a file the signed-in person can see (with the web view's
 * cookies) and opens it in the phone's viewer, which has Share and Print;
 * a calendar file opens in the calendar app. Like DocumentPresenter on iOS.
 */
object DocumentOpener {
    private data class Download(val file: File, val mimeType: String)

    fun open(activity: HotwireActivity, url: String) {
        activity.lifecycleScope.launch {
            val download = withContext(Dispatchers.IO) { runCatching { download(activity, url) }.getOrNull() }
            if (download == null) {
                Toast.makeText(activity, "Couldn't open that file. Check your connection and try again.", Toast.LENGTH_LONG).show()
                return@launch
            }
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.documents", download.file)
            val view = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, download.mimeType)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            try {
                activity.startActivity(view)
            } catch (e: ActivityNotFoundException) {
                // Nothing on the phone opens it: offer to share or save it instead.
                val share = Intent(Intent.ACTION_SEND)
                    .setType(download.mimeType)
                    .putExtra(Intent.EXTRA_STREAM, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                activity.startActivity(Intent.createChooser(share, download.file.name))
            }
        }
    }

    private fun download(activity: HotwireActivity, url: String): Download? {
        val connection = URL(url).openConnection() as HttpURLConnection
        CookieManager.getInstance().getCookie(url)?.let { connection.setRequestProperty("Cookie", it) }
        connection.setRequestProperty("User-Agent", Hotwire.config.userAgentWithWebViewDefault(activity))
        connection.instanceFollowRedirects = true
        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            val mimeType = connection.contentType?.substringBefore(";")?.trim()?.ifEmpty { null } ?: "application/octet-stream"
            if (mimeType == "text/html") return null

            val folder = File(activity.cacheDir, "documents/${UUID.randomUUID()}").apply { mkdirs() }
            val file = File(folder, fileName(connection, url, mimeType))
            connection.inputStream.use { input -> file.outputStream().use { input.copyTo(it) } }
            return Download(file, mimeType)
        } finally {
            connection.disconnect()
        }
    }

    private fun fileName(connection: HttpURLConnection, url: String, mimeType: String): String {
        val disposition = connection.getHeaderField("Content-Disposition").orEmpty()
        Regex("filename=\"?([^\";]+)\"?").find(disposition)?.groupValues?.get(1)?.let { return it.replace("/", "-") }
        val last = URL(url).path.substringAfterLast('/').ifEmpty { "document" }
        if (last.contains('.')) return last
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        return if (extension != null) "$last.$extension" else last
    }
}
