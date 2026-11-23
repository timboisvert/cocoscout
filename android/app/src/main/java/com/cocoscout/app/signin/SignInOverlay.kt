package com.cocoscout.app.signin

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.cocoscout.app.AppShell
import com.cocoscout.app.MainActivity
import com.cocoscout.app.R
import com.cocoscout.app.ui.ButtonSize
import com.cocoscout.app.ui.SharedButton
import com.cocoscout.app.ui.Tailwind

private val Coustard = FontFamily(Font(R.font.coustard_regular))
private val Gray200 = Color(0xFFE5E7EB)
private val Gray500 = Color(0xFF6A7282)
private val Pink50 = Color(0xFFFDF2F8)
private val Pink200 = Color(0xFFFCCEE8)
private val Pink700 = Color(0xFFC4005F)

/**
 * The app's own sign-in screens over everything while nobody's signed in
 * (sign-in plan phase 3), worded like the website's /signin: the email
 * address first, with Continue with Apple and Continue with Google below an
 * "or" (Tim, 2026-11-22), then whichever step the server names next. Mirrors
 * ios/CocoScout/SignIn/SignInScreen.swift.
 */
@Composable
fun SignInOverlay() {
    val shell by AppShell.state.collectAsState()
    val handedOff by AppShell.signInHandedOff.collectAsState()
    if (shell.signedIn || handedOff) return

    val activity = LocalContext.current as MainActivity
    val flow = SignInFlow
    Dialog(
        onDismissRequest = {
            // Back: a step goes back to the start; the start leaves the app.
            if (flow.screen == SignInFlow.Screen.Start) activity.moveTaskToBack(true) else flow.startOver(activity)
        },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnClickOutside = false)
    ) {
        LaunchedEffect(Unit) { flow.offerSaved(activity) }
        Box(Modifier.fillMaxSize().background(Color.White)) {
            Column(
                Modifier
                    .fillMaxSize()
                    .systemBarsPadding()
                    .imePadding()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp, vertical = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Column(Modifier.widthIn(max = 480.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    Text(
                        "CocoScout",
                        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).semantics { heading() },
                        style = TextStyle(fontFamily = Coustard, fontSize = 30.sp, color = Tailwind.Pink500, textAlign = TextAlign.Center)
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(title(flow), style = TextStyle(fontFamily = Coustard, fontSize = 26.sp, lineHeight = 32.sp, color = Tailwind.Gray900))
                        Text(lede(flow), fontSize = 16.sp, lineHeight = 22.sp, color = Gray500)
                    }
                    flow.error?.let { Banner(it, error = true) } ?: flow.notice?.let { Banner(it, error = false) }
                    when (flow.screen) {
                        SignInFlow.Screen.Start -> Start(activity)
                        SignInFlow.Screen.Password, SignInFlow.Screen.Connect -> PasswordStep(activity)
                        SignInFlow.Screen.Code -> CodeStep(activity)
                        SignInFlow.Screen.Create -> CreateStep(activity)
                        SignInFlow.Screen.AddEmail -> AddEmailStep(activity)
                    }
                }
            }
            if (flow.busy) {
                CircularProgressIndicator(Modifier.align(Alignment.Center), color = Tailwind.Pink500)
            }
        }
    }
}

@Composable
private fun Start(activity: MainActivity) {
    val flow = SignInFlow
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Field("Email address", flow.email, { flow.email = it }, ContentType.EmailAddress + ContentType.Username,
            KeyboardType.Email, ImeAction.Go, placeholder = "you@example.com") { flow.continueWithEmail(activity) }
        SharedButton("Continue", onClick = { flow.continueWithEmail(activity) }, size = ButtonSize.Large, fullWidth = true)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            HorizontalDivider(Modifier.weight(1f), color = Gray200)
            Text("or", fontSize = 14.sp, color = Gray500)
            HorizontalDivider(Modifier.weight(1f), color = Gray200)
        }
        ProviderButton("Continue with Google", R.drawable.ic_google_g, Color.White, Tailwind.Gray900, tintIcon = false) {
            flow.continueWithGoogle(activity)
        }
        ProviderButton("Continue with Apple", R.drawable.ic_apple, Color.Black, Color.White, tintIcon = true) {
            flow.continueWithApple(activity)
        }
    }
}

@Composable
private fun PasswordStep(activity: MainActivity) {
    val flow = SignInFlow
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        AccountRow(flow.email) { flow.startOver(activity) }
        Field("Password", flow.password, { flow.password = it }, ContentType.Password, KeyboardType.Password, ImeAction.Go,
            placeholder = "Your password", secret = true) { flow.submitPassword(activity) }
        SharedButton(if (flow.screen == SignInFlow.Screen.Connect) "Connect and sign in" else "Sign in",
            onClick = { flow.submitPassword(activity) }, size = ButtonSize.Large, fullWidth = true)
        if (!flow.superadmin) LinkButton("Email me a code instead") { flow.sendCode(activity) }
    }
}

@Composable
private fun CodeStep(activity: MainActivity) {
    val flow = SignInFlow
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        AccountRow(flow.email) { flow.startOver(activity) }
        Field("6-digit code", flow.code, { value ->
            val digits = value.filter(Char::isDigit).take(6)
            flow.code = digits
            if (digits.length == 6) flow.submitCode(activity)
        }, ContentType.SmsOtpCode, KeyboardType.NumberPassword, ImeAction.Go, placeholder = "123456") { flow.submitCode(activity) }
        SharedButton("Continue", onClick = { flow.submitCode(activity) }, size = ButtonSize.Large, fullWidth = true)
        LinkButton("Send a new code") { flow.sendCode(activity) }
    }
}

@Composable
private fun CreateStep(activity: MainActivity) {
    val flow = SignInFlow
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        AccountRow(flow.email) { flow.startOver(activity) }
        Field("First name", flow.firstName, { flow.firstName = it }, ContentType.PersonFirstName, KeyboardType.Text, ImeAction.Next) {}
        Field("Last name", flow.lastName, { flow.lastName = it }, ContentType.PersonLastName, KeyboardType.Text, ImeAction.Done) {
            flow.createAccount(activity)
        }
        SharedButton("Create account", onClick = { flow.createAccount(activity) }, size = ButtonSize.Large, fullWidth = true)
        Text("Free to join · No card needed", fontSize = 14.sp, color = Gray500, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun AddEmailStep(activity: MainActivity) {
    val flow = SignInFlow
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Field("Email address", flow.email, { flow.email = it }, ContentType.EmailAddress, KeyboardType.Email, ImeAction.Go,
            placeholder = "you@example.com") { flow.addEmail(activity) }
        SharedButton("Continue", onClick = { flow.addEmail(activity) }, size = ButtonSize.Large, fullWidth = true)
        LinkButton("Start over") { flow.startOver(activity) }
    }
}

private fun title(flow: SignInFlow): String {
    val name = flow.provider ?: "Apple"
    return when (flow.screen) {
        SignInFlow.Screen.Start -> "Sign in or create an account"
        SignInFlow.Screen.Password -> "Enter your password"
        SignInFlow.Screen.Code -> "Enter your code"
        SignInFlow.Screen.Create -> "Create your account"
        SignInFlow.Screen.Connect -> "Connect your $name account"
        SignInFlow.Screen.AddEmail -> "Add your email address"
    }
}

private fun lede(flow: SignInFlow): String {
    val name = flow.provider ?: "Apple"
    return when (flow.screen) {
        SignInFlow.Screen.Start ->
            "Your calendar, cast messages, contracts and pay, and the door scanner when you're working it. Enter your email address to sign in or to create your account."
        SignInFlow.Screen.Password -> "Your calendar, cast messages, contracts, and pay are waiting in there."
        SignInFlow.Screen.Code -> "We sent a 6-digit code to ${flow.email}. It works for ${flow.codeLifetime}."
        SignInFlow.Screen.Create -> {
            val base = "Enter your name the way organizations should see it on cast lists, messages, and contracts."
            if (flow.provider == null) base else "$base $name signs you in from now on."
        }
        SignInFlow.Screen.Connect ->
            "You already have a CocoScout account at this address. Enter its password once, and $name signs you in from then on."
        SignInFlow.Screen.AddEmail ->
            "$name kept your address private. Enter the one organizations know you by, so your invitations, contracts, and tickets find you. We'll send it a code."
    }
}

// Pieces

@Composable
private fun Field(
    label: String,
    value: String,
    onChange: (String) -> Unit,
    contentType: ContentType,
    keyboard: KeyboardType,
    ime: ImeAction,
    placeholder: String? = null,
    secret: Boolean = false,
    onDone: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Tailwind.Gray700)
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            modifier = Modifier.fillMaxWidth().semantics { this.contentType = contentType },
            singleLine = true,
            placeholder = placeholder?.let { { Text(it, color = Gray500) } },
            visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = keyboard, imeAction = ime, autoCorrectEnabled = false),
            keyboardActions = KeyboardActions(onAny = { onDone() }),
            shape = RoundedCornerShape(6.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Tailwind.Pink500,
                unfocusedBorderColor = Tailwind.Gray300,
                cursorColor = Tailwind.Pink500,
                focusedTextColor = Tailwind.Gray900,
                unfocusedTextColor = Tailwind.Gray900
            )
        )
    }
}

@Composable
private fun ProviderButton(text: String, icon: Int, background: Color, content: Color, tintIcon: Boolean, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
        shape = RoundedCornerShape(6.dp),
        border = BorderStroke(1.dp, if (background == Color.White) Tailwind.Gray300 else background),
        colors = androidx.compose.material3.ButtonDefaults.outlinedButtonColors(containerColor = background, contentColor = content)
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = if (tintIcon) content else Color.Unspecified, modifier = Modifier.size(20.dp))
        Spacer(Modifier.size(10.dp))
        Text(text, fontSize = 17.sp, fontWeight = FontWeight.Medium)
    }
}

/** The address the step is for, with Change to go back (shared/auth/_account_row). */
@Composable
private fun AccountRow(email: String, change: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(Tailwind.Gray50, RoundedCornerShape(6.dp))
            .border(1.dp, Gray200, RoundedCornerShape(6.dp))
            .padding(start = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f).padding(vertical = 12.dp)) {
            Text("Account", fontSize = 12.sp, fontWeight = FontWeight.Medium, color = Gray500)
            Text(email, fontSize = 16.sp, color = Tailwind.Gray900, maxLines = 1)
        }
        TextButton(onClick = change) { Text("Change", color = Tailwind.Pink600, fontWeight = FontWeight.Medium) }
    }
}

@Composable
private fun LinkButton(text: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.fillMaxWidth().height(48.dp)) {
        Text(text, color = Tailwind.Pink600, fontWeight = FontWeight.Medium, fontSize = 15.sp)
    }
}

/** shared/auth/_notice: pink for something that went wrong, gray to know. */
@Composable
private fun Banner(text: String, error: Boolean) {
    Text(
        text,
        modifier = Modifier
            .fillMaxWidth()
            .background(if (error) Pink50 else Tailwind.Gray50, RoundedCornerShape(6.dp))
            .border(1.dp, if (error) Pink200 else Gray200, RoundedCornerShape(6.dp))
            .padding(12.dp),
        fontSize = 15.sp,
        color = if (error) Pink700 else Tailwind.Gray700
    )
}
