package com.cocoscout.app.signin

import android.net.Uri
import android.util.Base64
import com.cocoscout.app.MainActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import com.cocoscout.app.AppConfig
import com.cocoscout.app.AppShell
import com.cocoscout.app.routing.BrowserTab
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Which screen of the sign-in steps is showing, and what's typed into it.
 * The server decides every next step (App::SignInController); this only shows
 * the one it names. Mirrors ios/CocoScout/SignIn/SignInModel.swift.
 */
object SignInFlow {
    enum class Screen { Start, Password, Code, Create, Connect, AddEmail }

    var screen by mutableStateOf(Screen.Start)
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

    /** The secret behind a Custom Tab's challenge (Apple), until it comes back. */
    private var tabSecret: String? = null
    private var savedOffered = false

    /** Fresh for the next person: the screen comes back after signing out. */
    fun reset() {
        screen = Screen.Start
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

    // Steps

    fun continueWithEmail(activity: MainActivity) {
        val address = email.trim()
        if (address.isEmpty()) return
        run(activity, "identify", mapOf("email" to address))
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

    fun startOver(activity: MainActivity) {
        password = ""
        code = ""
        run(activity, "start_over")
    }

    // Saved passwords and Google, through Credential Manager

    /** Once per launch, on opening: a saved password or a Google account already used here. */
    fun offerSaved(activity: MainActivity) {
        if (savedOffered) return
        savedOffered = true
        activity.lifecycleScope.launch {
            val nonce = SignInClient.get(activity, "nonce")
            when (val picked = Credentials.offerSaved(activity, nonce.nonce, nonce.googleClientId)) {
                is Credentials.Picked.Password -> {
                    email = picked.email
                    run(activity, "identify", mapOf("email" to picked.email, "password" to picked.password))
                }
                is Credentials.Picked.Google -> run(activity, "provider", mapOf("provider" to "google", "id_token" to picked.idToken))
                null -> Unit
            }
        }
    }

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

    // Apple, in a Custom Tab

    /**
     * Apple has no sheet on Android: it runs in a Custom Tab at
     * /auth/app/apple with a challenge made from a secret only the app holds,
     * and comes back to cocoscout://auth?code=… (returnFromTab).
     */
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
            else -> error = "Apple couldn't confirm that sign-in. Try again, or continue with your email address."
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
            show(reply)
        }
    }

    private fun show(reply: SignInReply) {
        when (reply.status) {
            "signed_in" -> reply.landing?.let { AppShell.didSignIn(it) }
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
                    else -> Screen.Start
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
