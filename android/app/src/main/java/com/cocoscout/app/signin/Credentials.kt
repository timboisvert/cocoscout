package com.cocoscout.app.signin

import android.app.Activity
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialOption
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPasswordOption
import androidx.credentials.PasswordCredential
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException

/**
 * Android's Credential Manager: its bottom sheet offers the passwords saved
 * for CocoScout and the Google accounts on the phone, and Continue with
 * Google signs in with one of them. Google's ID token carries the nonce the
 * server issued and names the website's client id as its audience
 * (App::SignInController#provider checks both).
 */
object Credentials {
    sealed interface Picked {
        data class Password(val email: String, val password: String) : Picked
        data class Google(val idToken: String) : Picked
    }

    sealed interface Result {
        data class Token(val idToken: String) : Result
        data object Canceled : Result
        data object Failed : Result
    }

    /** On opening: a saved password, or a Google account already used here. Nothing shows when there's neither. */
    suspend fun offerSaved(activity: Activity, nonce: String?, clientId: String?): Picked? {
        val options = mutableListOf<CredentialOption>(GetPasswordOption())
        if (nonce != null && clientId != null) {
            options += GetGoogleIdOption.Builder()
                .setFilterByAuthorizedAccounts(true)
                .setServerClientId(clientId)
                .setNonce(nonce)
                .build()
        }
        return try {
            val credential = CredentialManager.create(activity).getCredential(activity, GetCredentialRequest(options)).credential
            when {
                credential is PasswordCredential -> Picked.Password(credential.id, credential.password)
                credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL ->
                    Picked.Google(GoogleIdTokenCredential.createFrom(credential.data).idToken)
                else -> null
            }
        } catch (_: GetCredentialException) {
            null
        } catch (_: GoogleIdTokenParsingException) {
            null
        }
    }

    /** Welcome back's Continue: a password saved for CocoScout, if there's one. */
    suspend fun savedPassword(activity: Activity): Picked.Password? = try {
        val credential = CredentialManager.create(activity).getCredential(activity, GetCredentialRequest(listOf(GetPasswordOption()))).credential
        (credential as? PasswordCredential)?.let { Picked.Password(it.id, it.password) }
    } catch (_: GetCredentialException) {
        null
    }

    /** Continue with Google: every Google account on the phone, or adding one. */
    suspend fun google(activity: Activity, nonce: String, clientId: String): Result {
        val option = GetSignInWithGoogleOption.Builder(clientId).setNonce(nonce).build()
        return try {
            val credential = CredentialManager.create(activity).getCredential(activity, GetCredentialRequest(listOf(option))).credential
            if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                Result.Token(GoogleIdTokenCredential.createFrom(credential.data).idToken)
            } else {
                Result.Failed
            }
        } catch (_: GetCredentialCancellationException) {
            Result.Canceled
        } catch (_: GetCredentialException) {
            Result.Failed
        } catch (_: GoogleIdTokenParsingException) {
            Result.Failed
        }
    }
}
