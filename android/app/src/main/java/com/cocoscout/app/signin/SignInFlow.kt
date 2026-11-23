package com.cocoscout.app.signin

import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import com.cocoscout.app.AppConfig
import com.cocoscout.app.AppShell
import com.cocoscout.app.MainActivity
import com.cocoscout.app.routing.BrowserTab
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import java.security.MessageDigest
import java.security.SecureRandom

/** Who last signed in on this phone, kept on the phone only (the iPhone's KnownAccount). */
@Serializable
data class KnownAccount(val email: String, val firstName: String? = null, val method: String)

/**
 * The sign-in screens, redesigned for the phone (direction A on
 * https://claude.ai/artifact/X1sA6FoXBSPJseGxFzdExn): a pink landing, and the
 * steps on a white sheet that rises over it. The server decides every next
 * step (App::SignInController); this only shows the one it names. Mirrors
 * ios/CocoScout/SignIn/SignInModel.swift, with Google as the only provider:
 * every account has a real address, so a code always gets someone in.
 */
object SignInFlow {
    enum class Screen {
        Landing, Email, Password, Code, Create, Connect, AddEmail;

        /** The sheet sits low with Coco peeking over it; the rest raise it near the top. */
        val sheetIsLow: Boolean get() = this == Email || this == AddEmail
    }

    var screen by mutableStateOf(Screen.Landing)
    var email by mutableStateOf("")
    var password by mutableStateOf("")
    var code by mutableStateOf("")
    var firstName by mutableStateOf("")
    var lastName by mutableStateOf("")
    var busy by mutableStateOf(false)
    /** A step went wrong: shown in pink. */
    var error by mutableStateOf<String?>(null)
    /** Something to know (a code sent moments ago): shown in gray. */
    var notice by mutableStateOf<String?>(null)
    var provider by mutableStateOf<String?>(null)
    var codeLifetime by mutableStateOf("10 minutes")
    var superadmin by mutableStateOf(false)
    /** Who last signed in here: the landing welcomes them back. */
    var known by mutableStateOf<KnownAccount?>(null)
    /** A link that came in while signed out, waiting for sign-in, in words. */
    var waiting by mutableStateOf<String?>(null)
    /** Who just signed in here and how, for the offer to make a passkey (PasskeyOffer). */
    var justSignedIn: KnownAccount? = null
        private set

    private val json = Json { ignoreUnknownKeys = true }
    private const val PREFS = "sign_in"
    private const val KNOWN_KEY = "known_account"
    private var loaded = false
    /** The secret behind a Custom Tab's challenge (Apple), until it comes back. */
    private var tabSecret: String? = null
    private var savedOffered = false

    fun load(context: Context) {
        if (loaded) return
        loaded = true
        known = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KNOWN_KEY, null)
            ?.let { runCatching { json.decodeFromString(KnownAccount.serializer(), it) }.getOrNull() }
    }

    /** Fresh for the next person after signing out; Welcome back stays. */
    fun reset() {
        screen = Screen.Landing
        email = ""
        password = ""
        code = ""
        firstName = ""
        lastName = ""
        error = null
        notice = null
        provider = null
        busy = false
    }

    // The landing

    /** Get started, or a link's "Sign in to see it": the email sheet, with any saved sign-in offered. */
    fun getStarted(activity: MainActivity) {
        error = null
        notice = null
        screen = Screen.Email
        if (!savedOffered) {
            savedOffered = true
            activity.lifecycleScope.launch {
                val nonce = SignInClient.get(activity, "nonce")
                val passkeys = passkeyOptions(activity)
                when (val picked = Credentials.offerSaved(activity, nonce.nonce, nonce.googleClientId, passkeys)) {
                    is Credentials.Picked.Password -> signIn(activity, picked.email, picked.password)
                    is Credentials.Picked.Google -> run(activity, "provider", mapOf("provider" to "google", "id_token" to picked.idToken))
                    is Credentials.Picked.Passkey -> signInWithPasskey(activity, picked.json)
                    null -> Unit
                }
            }
        }
    }

    /**
     * Welcome back's Continue: the same way in as last time. Google opens its
     * sheet; a passkey or a saved password comes from the phone's password
     * manager with a fingerprint; otherwise the address goes in, and the
     * server asks for the password or sends a code.
     */
    fun continueAsKnown(activity: MainActivity) {
        val account = known ?: return
        if (busy) return
        email = account.email
        error = null
        if (account.method == "google") return continueWithGoogle(activity)
        activity.lifecycleScope.launch {
            when (val saved = Credentials.savedSignIn(activity, passkeyOptions(activity))) {
                is Credentials.Picked.Passkey -> signInWithPasskey(activity, saved.json)
                is Credentials.Picked.Password ->
                    if (saved.email.equals(account.email, ignoreCase = true)) signIn(activity, saved.email, saved.password)
                    else run(activity, "identify", mapOf("email" to account.email))
                else -> run(activity, "identify", mapOf("email" to account.email))
            }
        }
    }

    /** The options for a passkey sheet that names no account, or null when there are none to have. */
    private suspend fun passkeyOptions(activity: MainActivity): String? =
        SignInClient.text(activity, "/app/sign_in/passkey_options")?.takeIf { "\"challenge\"" in it }

    private fun signInWithPasskey(activity: MainActivity, credential: String) {
        if (busy) return
        busy = true
        error = null
        activity.lifecycleScope.launch {
            val body = buildJsonObject { put("credential", json.parseToJsonElement(credential)) }
            val reply = SignInClient.postJson(activity, "passkey", body)
            busy = false
            show(activity, reply)
        }
    }

    /** After making a passkey: Welcome back's Continue opens it next time. */
    fun rememberMethod(context: Context, account: KnownAccount, method: String) {
        val updated = account.copy(method = method)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KNOWN_KEY, json.encodeToString(KnownAccount.serializer(), updated)).apply()
        known = updated
    }

    fun useDifferentEmail(activity: MainActivity) {
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KNOWN_KEY).apply()
        known = null
        email = ""
        getStarted(activity)
    }

    /** Closing the email sheet goes back to the landing. */
    fun closeSheet(activity: MainActivity) {
        error = null
        notice = null
        password = ""
        code = ""
        screen = Screen.Landing
        activity.lifecycleScope.launch { SignInClient.post(activity, "start_over") }
    }

    // Steps

    fun continueWithEmail(activity: MainActivity) {
        val address = email.trim()
        if (address.isEmpty()) return
        run(activity, "identify", mapOf("email" to address))
    }

    private fun signIn(activity: MainActivity, address: String, saved: String) {
        email = address
        run(activity, "identify", mapOf("email" to address, "password" to saved))
    }

    fun submitPassword(activity: MainActivity) {
        if (password.isEmpty()) return
        run(activity, if (screen == Screen.Connect) "connect" else "password", mapOf("password" to password))
    }

    fun sendCode(activity: MainActivity) = run(activity, "send_code")

    fun submitCode(activity: MainActivity) {
        val digits = code.filter(Char::isDigit)
        if (digits.length != 6) return
        run(activity, "code", mapOf("code" to digits))
    }

    fun createAccount(activity: MainActivity) =
        run(activity, "create", mapOf("first_name" to firstName, "last_name" to lastName))

    fun addEmail(activity: MainActivity) = run(activity, "add_email", mapOf("email" to email.trim()))

    /** Back from a step: to the email step, fresh. */
    fun startOver(activity: MainActivity) {
        password = ""
        code = ""
        run(activity, "start_over")
    }

    // Google, through Credential Manager

    fun continueWithGoogle(activity: MainActivity) {
        if (busy) return
        error = null
        activity.lifecycleScope.launch {
            val nonce = SignInClient.get(activity, "nonce")
            val clientId = nonce.googleClientId
            if (nonce.nonce == null || clientId == null) {
                error = "Continue with Google isn't available right now. Continue with your email address."
                return@launch
            }
            when (val result = Credentials.google(activity, nonce.nonce, clientId)) {
                is Credentials.Result.Token -> run(activity, "provider", mapOf("provider" to "google", "id_token" to result.idToken))
                Credentials.Result.Canceled -> Unit
                Credentials.Result.Failed -> error = "Google couldn't confirm that sign-in. Try again, or continue with your email address."
            }
        }
    }

    // Apple, in a Custom Tab. Android's screens don't offer it (Tim,
    // 2026-11-22: Google only on Android), and nothing calls this today; the
    // way back from the tab stays for a later choice.

    fun continueWithApple(activity: MainActivity) {
        if (busy) return
        error = null
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val secret = base64Url(bytes)
        val challenge = base64Url(MessageDigest.getInstance("SHA-256").digest(secret.toByteArray()))
        tabSecret = secret
        BrowserTab.open(activity, AppConfig.url("/auth/app/apple?challenge=$challenge"))
    }

    /** cocoscout://auth?code=… or ?error=…, from MainActivity. */
    fun returnFromTab(activity: MainActivity, uri: Uri) {
        val secret = tabSecret ?: return
        tabSecret = null
        val code = uri.getQueryParameter("code")
        when {
            code != null -> run(activity, "exchange", mapOf("code" to code, "secret" to secret))
            uri.getQueryParameter("error") == "canceled" -> Unit
            else -> error = "That sign-in didn't finish. Try again, or continue with your email address."
        }
    }

    // Talking to the server

    private fun run(activity: MainActivity, step: String, body: Map<String, String?> = emptyMap()) {
        if (busy) return
        busy = true
        error = null
        activity.lifecycleScope.launch {
            val reply = SignInClient.post(activity, step, body)
            busy = false
            show(activity, reply)
        }
    }

    private fun show(activity: MainActivity, reply: SignInReply) {
        when (reply.status) {
            "signed_in" -> {
                val address = reply.email
                val method = reply.method
                if (address != null && method != null) {
                    val account = KnownAccount(address, reply.firstName, method)
                    activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putString(KNOWN_KEY, json.encodeToString(KnownAccount.serializer(), account)).apply()
                    known = account
                    justSignedIn = account
                }
                reply.landing?.let { AppShell.didSignIn(it) }
            }
            "step" -> {
                notice = reply.notice
                reply.email?.let { email = it }
                provider = reply.provider
                superadmin = reply.superadmin ?: false
                reply.codeLifetime?.let { codeLifetime = it }
                reply.firstName?.let { if (firstName.isEmpty()) firstName = it }
                reply.lastName?.let { if (lastName.isEmpty()) lastName = it }
                val next = when (reply.step) {
                    "password" -> Screen.Password
                    "code" -> Screen.Code
                    "create" -> Screen.Create
                    "connect" -> Screen.Connect
                    "add_email" -> Screen.AddEmail
                    else -> Screen.Email
                }
                if (next != screen) {
                    password = ""
                    code = ""
                }
                if (next == Screen.AddEmail) email = ""
                screen = next
            }
            else -> {
                error = reply.message ?: "That didn't work. Please try again."
                if (reply.error in setOf("wrong", "expired", "locked")) code = ""
            }
        }
    }

    private fun base64Url(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
}
