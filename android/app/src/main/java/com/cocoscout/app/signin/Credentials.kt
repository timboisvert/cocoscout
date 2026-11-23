package com.cocoscout.app.signin

import android.app.Activity
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialOption
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPasswordOption
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PasswordCredential
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.publickeycredential.CreatePublicKeyCredentialDomException
import androidx.credentials.exceptions.domerrors.InvalidStateError
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException

/**
 * Android's Credential Manager: its bottom sheet offers the passkeys and
 * passwords saved for CocoScout and the Google accounts on the phone, and
 * Continue with Google signs in with one of them. Passkeys (sign-in plan
 * phase 4) take the server's WebAuthn JSON as it comes and answer in the
 * same JSON (SignIn::Passkeys). Google's ID token carries the nonce the
 * server issued and names the website's client id as its audience
 * (App::SignInController#provider checks both).
 */
object Credentials {
    sealed interface Picked {
        data class Password(val email: String, val password: String) : Picked
        data class Google(val idToken: String) : Picked
        /** A passkey's answer, as the JSON App::SignInController#passkey reads. */
        data class Passkey(val json: String) : Picked
    }

    sealed interface Made {
        /** The new passkey, as the JSON App::PasskeysController#create reads. */
        data class Passkey(val json: String) : Made
        data object Canceled : Made
        /** Google Password Manager already holds one for this account. */
        data object Exists : Made
        data object Failed : Made
    }

    sealed interface Result {
        data class Token(val idToken: String) : Result
        data object Canceled : Result
        data object Failed : Result
    }

    /** On opening: a passkey, a saved password, or a Google account already used here. Nothing shows when there's none. */
    suspend fun offerSaved(activity: Activity, nonce: String?, clientId: String?, passkeyOptions: String?): Picked? {
        val options = mutableListOf<CredentialOption>(GetPasswordOption())
        passkeyOptions?.let { options += GetPublicKeyCredentialOption(it) }
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
                credential is PublicKeyCredential -> Picked.Passkey(credential.authenticationResponseJson)
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

    /** Welcome back's Continue: a passkey or a password saved for CocoScout, if there's one. */
    suspend fun savedSignIn(activity: Activity, passkeyOptions: String?): Picked? = try {
        val options = mutableListOf<CredentialOption>(GetPasswordOption())
        passkeyOptions?.let { options += GetPublicKeyCredentialOption(it) }
        when (val credential = CredentialManager.create(activity).getCredential(activity, GetCredentialRequest(options)).credential) {
            is PasswordCredential -> Picked.Password(credential.id, credential.password)
            is PublicKeyCredential -> Picked.Passkey(credential.authenticationResponseJson)
            else -> null
        }
    } catch (_: GetCredentialException) {
        null
    }

    /** Makes a passkey for the signed-in account, from App::PasskeysController's options. */
    suspend fun createPasskey(activity: Activity, requestJson: String): Made = try {
        val response = CredentialManager.create(activity).createCredential(activity, CreatePublicKeyCredentialRequest(requestJson))
        (response as? CreatePublicKeyCredentialResponse)?.let { Made.Passkey(it.registrationResponseJson) } ?: Made.Failed
    } catch (_: CreateCredentialCancellationException) {
        Made.Canceled
    } catch (error: CreatePublicKeyCredentialDomException) {
        if (error.domError is InvalidStateError) Made.Exists else Made.Failed
    } catch (_: CreateCredentialException) {
        Made.Failed
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
