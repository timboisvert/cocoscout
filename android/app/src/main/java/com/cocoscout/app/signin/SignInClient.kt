package com.cocoscout.app.signin

import android.content.Context
import android.webkit.CookieManager
import com.cocoscout.app.AppConfig
import dev.hotwire.core.config.Hotwire
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.HttpURLConnection
import java.net.URL

/** One answer from the server's sign-in steps (App::SignInController). */
@Serializable
data class SignInReply(
    /** "step", "signed_in", or "error". */
    val status: String,
    val step: String? = null,
    val email: String? = null,
    val notice: String? = null,
    @SerialName("code_lifetime") val codeLifetime: String? = null,
    val provider: String? = null,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
    val superadmin: Boolean? = null,
    val landing: String? = null,
    val error: String? = null,
    val message: String? = null,
    val nonce: String? = null,
    @SerialName("google_client_id") val googleClientId: String? = null,
    /** With "signed_in": how they signed in ("password", "code", "apple", "google"). */
    val method: String? = null
)

/**
 * Talks to the server's sign-in steps as the web view: with its cookies and
 * its user agent, writing the cookies that come back into its store, so the
 * session a step starts is the web view's own (the sign-in plan's handoff, as
 * AppShell.signOut already does for signing out). No link ever signs anyone in.
 */
object SignInClient {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun post(context: Context, step: String, body: Map<String, String?> = emptyMap()): SignInReply =
        send(context, step, JsonObject(body.filterValues { it != null }.mapValues { JsonPrimitive(it.value) }).toString())

    suspend fun get(context: Context, step: String): SignInReply = send(context, step, null)

    private suspend fun send(context: Context, step: String, body: String?): SignInReply = withContext(Dispatchers.IO) {
        val url = AppConfig.url("/app/sign_in/$step")
        val cookies = CookieManager.getInstance()
        runCatching {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = false
            cookies.getCookie(url)?.let { connection.setRequestProperty("Cookie", it) }
            connection.setRequestProperty("User-Agent", Hotwire.config.userAgentWithWebViewDefault(context))
            connection.setRequestProperty("Accept", "application/json")
            if (body != null) {
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toByteArray()) }
            }
            val code = connection.responseCode
            // Whatever the server set (the session, the step) goes into the
            // web view's store before anything else loads.
            connection.headerFields.entries
                .filter { it.key.equals("Set-Cookie", ignoreCase = true) }
                .flatMap { it.value }
                .forEach { cookies.setCookie(url, it) }
            cookies.flush()
            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            connection.disconnect()
            json.decodeFromString(SignInReply.serializer(), text)
        }.getOrElse {
            SignInReply(status = "error", error = "network", message = "CocoScout couldn't be reached. Check your connection and try again.")
        }
    }
}
