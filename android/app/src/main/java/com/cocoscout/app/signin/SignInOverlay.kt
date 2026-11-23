package com.cocoscout.app.signin

import androidx.compose.animation.AnimatedContent
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.platform.LocalView
import androidx.compose.runtime.SideEffect
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.lerp
import kotlinx.coroutines.delay
import kotlin.math.roundToInt
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.outlined.Drafts
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.cocoscout.app.AppConfig
import com.cocoscout.app.AppShell
import com.cocoscout.app.MainActivity
import com.cocoscout.app.R
import com.cocoscout.app.ui.Tailwind

private val Coustard = FontFamily(Font(R.font.coustard_regular))
private val Gray200 = Color(0xFFE5E7EB)
private val Gray500 = Color(0xFF6A7282)
private val Pink50 = Color(0xFFFDF2F8)
private val Pink200 = Color(0xFFFCCEE8)
private val Pink700 = Color(0xFFC4005F)
/** Coco's artwork is 721 × 768. */
private const val COCO_RATIO = 768f / 721f

/**
 * The sign-in screens over everything while nobody's signed in, designed for
 * the phone (Tim, 2026-11-22, direction A on
 * https://claude.ai/artifact/X1sA6FoXBSPJseGxFzdExn): a pink landing with
 * Coco, then the steps on a white sheet that rises over it. Mirrors
 * ios/CocoScout/SignIn/SignInScreen.swift, with Google as the only provider.
 *
 * Coco comes in three sizes, always rising out of the top of something
 * (Tim's rule): the hero on the first-time landing, anchored to the bottom of
 * the screen; the card on Welcome back, exactly as wide as the card; and the
 * peek over a low sheet. When a step raises the sheet near the top there's no
 * room, and she steps off.
 */
@Composable
fun SignInOverlay() {
    val shell by AppShell.state.collectAsState()
    val handedOff by AppShell.signInHandedOff.collectAsState()
    if (shell.signedIn || handedOff) return

    val activity = LocalContext.current as MainActivity
    val flow = SignInFlow
    LaunchedEffect(Unit) { flow.load(activity) }
    Dialog(
        onDismissRequest = {
            // Back: a step goes back to the email step, the email step to the
            // landing, and the landing leaves the app.
            when (flow.screen) {
                SignInFlow.Screen.Landing -> activity.moveTaskToBack(true)
                SignInFlow.Screen.Email -> flow.closeSheet(activity)
                else -> flow.startOver(activity)
            }
        },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnClickOutside = false)
    ) {
        // Straight onto the pink window, as it opens: no dialog fade or
        // dimming between them (1.4.1).
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect {
            window?.setDimAmount(0f)
            window?.setWindowAnimations(0)
        }
        BoxWithConstraints(Modifier.fillMaxSize().background(Tailwind.Pink500)) {
            val width = maxWidth
            val height = maxHeight
            AnimatedContent(
                targetState = flow.screen == SignInFlow.Screen.Landing,
                transitionSpec = {
                    if (targetState) fadeIn() togetherWith slideOutVertically { it }
                    else slideInVertically { it } togetherWith fadeOut()
                },
                label = "landing or sheet"
            ) { landing ->
                if (landing) Landing(activity, width) else StepSheet(activity, height)
            }
            if (flow.busy) {
                CircularProgressIndicator(
                    Modifier.align(Alignment.Center),
                    color = if (flow.screen == SignInFlow.Screen.Landing) Color.White else Tailwind.Pink500
                )
            }
        }
    }
}

/** Reports a shorter height than it draws, so what comes next overlaps its bottom. */
private fun Modifier.overlapBelow(overlap: Dp) = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    layout(placeable.width, (placeable.height - overlap.roundToPx()).coerceAtLeast(0)) { placeable.place(0, 0) }
}

// The landing

/**
 * The pink screen the app opens on, with what to do on top (Tim, 2026-11-23,
 * for 1.4.1): the wordmark, the tagline, and the hero Coco come first, as the
 * iPhone's launch screen does, and nothing about them moves. First time, Get
 * started rises onto it. Coming back, or a link waiting, the card rises and
 * Coco settles from the hero to the card's width, head and shoulders over its
 * top edge (Coco always rises out of the top of something).
 */
@Composable
private fun Landing(activity: MainActivity, width: Dp) {
    val flow = SignInFlow
    val known = flow.known
    val waiting = flow.waiting
    val hasCard = known != null || waiting != null
    val density = LocalDensity.current
    val shown = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        delay(150)
        shown.animateTo(1f, spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow))
    }
    // Read in composition, not just in a drawing layer: a layer-only change
    // can go undrawn in the sign-in dialog until the next touch (seen on the
    // emulator), and the button stayed half faded.
    val rise = 24.dp
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val boxHeight = constraints.maxHeight.toFloat()
        LandingTitle()
        val heroWidth = width * 1.07f
        // The hero's feet sit 40 below the screen's bottom.
        val heroGap = with(density) { -40.dp.toPx() }
        if (hasCard) {
            val cardWidth = width - 40.dp
            val imageHeight = cardWidth * COCO_RATIO
            val showing = cardWidth * (260f / 350f)
            var cardTop by remember { mutableStateOf<Float?>(null) }
            val t = shown.value
            // Behind the card: from the hero to the card's width, her feet
            // from below the screen to behind the card.
            val cardGap = cardTop?.let { boxHeight - it - with(density) { (imageHeight - showing).toPx() } } ?: heroGap
            val gap = heroGap + (cardGap - heroGap) * t
            Image(painterResource(R.drawable.coco), contentDescription = "Coco, the CocoScout cat", contentScale = ContentScale.FillWidth,
                modifier = Modifier.align(Alignment.BottomCenter).requiredWidth(lerp(heroWidth, cardWidth, t))
                    .offset { IntOffset(0, (-gap).roundToInt()) })
            Column(
                Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(start = 20.dp, end = 20.dp, bottom = 16.dp)
                    .onGloballyPositioned { cardTop = it.positionInRoot().y }
                    .alpha(t).offset(y = rise * (1 - t))
                    .width(cardWidth)
                    .shadow(14.dp, RoundedCornerShape(28.dp))
                    .background(Color.White, RoundedCornerShape(28.dp))
                    .padding(start = 18.dp, end = 18.dp, top = 20.dp, bottom = 10.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (known != null) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(known.firstName?.let { "Welcome back, $it" } ?: "Welcome back",
                            style = TextStyle(fontFamily = Coustard, fontSize = 26.sp, lineHeight = 30.sp, color = Tailwind.Gray900))
                        Text(known.email, fontSize = 15.sp, color = Gray500, maxLines = 1)
                    }
                    waiting?.let { WaitingNote(it) }
                    flow.error?.let { Banner(it, error = true) }
                    PrimaryButton("Continue", fingerprint = known.method in setOf("password", "passkey")) { flow.continueAsKnown(activity) }
                    LinkButton("Use a different email") { flow.useDifferentEmail(activity) }
                } else if (waiting != null) {
                    WaitingNote(waiting)
                    PrimaryButton("Sign in to see it") { flow.getStarted(activity) }
                    Spacer(Modifier.height(6.dp))
                }
            }
        } else {
            HeroCoco(width)
            Button(
                onClick = { flow.getStarted(activity) },
                modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(start = 24.dp, end = 24.dp, bottom = 24.dp)
                    .alpha(shown.value).offset(y = rise * (1 - shown.value))
                    .fillMaxWidth().height(56.dp),
                shape = RoundedCornerShape(28.dp),
                elevation = ButtonDefaults.buttonElevation(defaultElevation = 6.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Tailwind.Pink600)
            ) {
                Text("Get started", fontSize = 18.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

/** The wordmark and the tagline, where the app opens with them. */
@Composable
private fun BoxScope.LandingTitle() {
    Column(
        Modifier.align(Alignment.TopCenter).fillMaxWidth().statusBarsPadding().padding(top = 64.dp, start = 32.dp, end = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("CocoScout", modifier = Modifier.semantics { heading() },
            style = TextStyle(fontFamily = Coustard, fontSize = 52.sp, color = Color.White))
        Text("The platform for live entertainment production", textAlign = TextAlign.Center,
            fontSize = 19.sp, fontWeight = FontWeight.Medium, color = Color.White,
            modifier = Modifier.widthIn290())
    }
}

/** The hero: a touch wider than the screen, her feet 40 below its bottom. */
@Composable
private fun BoxScope.HeroCoco(width: Dp) {
    Image(painterResource(R.drawable.coco), contentDescription = "Coco, the CocoScout cat", contentScale = ContentScale.FillWidth,
        modifier = Modifier.align(Alignment.BottomCenter).requiredWidth(width * 1.07f).offset(y = 40.dp))
}

/**
 * The pink screen the app opens on, drawn in the app's own window while
 * nobody's signed in (MainActivity): it's there with the first frame, where
 * the sign-in screens' dialog window takes a moment longer to appear, and the
 * landing lands on it exactly (1.4.1).
 */
@Composable
fun SignInBackdrop() {
    val shell by AppShell.state.collectAsState()
    val handedOff by AppShell.signInHandedOff.collectAsState()
    if (shell.signedIn || handedOff) return
    BoxWithConstraints(Modifier.fillMaxSize().background(Tailwind.Pink500)) {
        LandingTitle()
        HeroCoco(maxWidth)
    }
}

private fun Modifier.widthIn290() = this.then(Modifier.width(290.dp))

/** What a link that came in while signed out is waiting to show. */
@Composable
private fun WaitingNote(text: String) {
    Row(
        Modifier.fillMaxWidth().background(Pink50, RoundedCornerShape(14.dp)).border(1.dp, Pink200, RoundedCornerShape(14.dp)).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(Icons.Outlined.Drafts, contentDescription = null, tint = Tailwind.Pink600, modifier = Modifier.size(22.dp))
        Column {
            Text(text, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Tailwind.Gray900)
            Text("Sign in and it opens right after.", fontSize = 14.sp, color = Gray500)
        }
    }
}

// The sheet

@Composable
private fun StepSheet(activity: MainActivity, height: Dp) {
    val flow = SignInFlow
    val low = flow.screen.sheetIsLow
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.align(Alignment.BottomCenter), horizontalAlignment = Alignment.CenterHorizontally) {
            if (low) {
                // The peek: 220 wide, 150 showing over the sheet.
                Image(painterResource(R.drawable.coco), contentDescription = null, contentScale = ContentScale.FillWidth,
                    modifier = Modifier.width(220.dp).overlapBelow(220.dp * COCO_RATIO - 150.dp))
            }
            Box(
                Modifier.fillMaxWidth().height(if (low) height - 150.dp else height - 50.dp)
                    .background(Color.White, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                    .navigationBarsPadding()
                    .imePadding()
            ) {
                when (flow.screen) {
                    SignInFlow.Screen.Email -> EmailStep(activity)
                    SignInFlow.Screen.AddEmail -> AddEmailStep(activity)
                    SignInFlow.Screen.Password, SignInFlow.Screen.Connect -> PasswordStep(activity)
                    SignInFlow.Screen.Code -> CodeStep(activity)
                    SignInFlow.Screen.Create -> NameStep(activity)
                    SignInFlow.Screen.Landing -> Unit
                }
            }
        }
    }
}

@Composable
private fun EmailStep(activity: MainActivity) {
    val flow = SignInFlow
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 24.dp, end = 24.dp, top = 12.dp, bottom = 24.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            CircleButton(Icons.Filled.Close, "Close") { flow.closeSheet(activity) }
        }
        StepTitle("What's your email?", "Use the address your organizations know you by. We'll sign you in, or set you up if you're new.")
        Notices()
        Spacer(Modifier.height(22.dp))
        Field("Email address", flow.email, { flow.email = it }, ContentType.EmailAddress + ContentType.Username, KeyboardType.Email, ImeAction.Go,
            placeholder = "you@example.com") { flow.continueWithEmail(activity) }
        Spacer(Modifier.height(16.dp))
        PrimaryButton("Continue") { flow.continueWithEmail(activity) }
        Row(Modifier.padding(vertical = 22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            HorizontalDivider(Modifier.weight(1f), color = Gray200)
            Text("or", fontSize = 14.sp, color = Gray500)
            HorizontalDivider(Modifier.weight(1f), color = Gray200)
        }
        OutlinedButton(
            onClick = { flow.continueWithGoogle(activity) },
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
            shape = RoundedCornerShape(28.dp),
            border = BorderStroke(1.dp, Color(0xFF747775)),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.White, contentColor = Color(0xFF1F1F1F))
        ) {
            Icon(painterResource(R.drawable.ic_google_g), contentDescription = null, tint = Color.Unspecified, modifier = Modifier.size(20.dp))
            Spacer(Modifier.size(12.dp))
            Text("Continue with Google", fontSize = 17.sp, fontWeight = FontWeight.Medium)
        }
        Spacer(Modifier.height(24.dp))
        Terms(activity)
    }
}

@Composable
private fun AddEmailStep(activity: MainActivity) {
    val flow = SignInFlow
    val name = flow.provider ?: "Apple"
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 24.dp, end = 24.dp, top = 28.dp, bottom = 24.dp)) {
        StepTitle("Add your email address",
            "$name kept your address private. Enter the one organizations know you by, so your invitations, contracts, and tickets find you. We'll send it a code.")
        Notices()
        Spacer(Modifier.height(22.dp))
        Field("Email address", flow.email, { flow.email = it }, ContentType.EmailAddress, KeyboardType.Email, ImeAction.Go,
            placeholder = "you@example.com", autofocus = true) { flow.addEmail(activity) }
        Spacer(Modifier.height(16.dp))
        PrimaryButton("Continue") { flow.addEmail(activity) }
        LinkButton("Start over") { flow.startOver(activity) }
    }
}

@Composable
private fun PasswordStep(activity: MainActivity) {
    val flow = SignInFlow
    val connecting = flow.screen == SignInFlow.Screen.Connect
    val name = flow.provider ?: "Google"
    var showing by remember { mutableStateOf(false) }
    PinnedStep(
        activity,
        button = if (connecting) "Connect and sign in" else "Sign in",
        onButton = { flow.submitPassword(activity) },
        footnote = if (connecting) null else "Your phone offers to save it, so your fingerprint can sign you in next time."
    ) {
        StepTitle(if (connecting) "Connect your $name account" else "Enter your password",
            if (connecting) "You already have a CocoScout account at this address. Enter its password once, and $name signs you in from then on." else null)
        Spacer(Modifier.height(16.dp))
        AccountChip(flow.email) { flow.startOver(activity) }
        Notices()
        Spacer(Modifier.height(20.dp))
        Field("Password", flow.password, { flow.password = it }, ContentType.Password, KeyboardType.Password, ImeAction.Go,
            placeholder = "Your password", secret = !showing, autofocus = true,
            trailing = {
                IconButton(onClick = { showing = !showing }) {
                    Icon(if (showing) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                        contentDescription = if (showing) "Hide password" else "Show password", tint = Gray500)
                }
            }) { flow.submitPassword(activity) }
        if (!flow.superadmin) {
            LinkButton("Email me a code instead", leading = true) { flow.sendCode(activity) }
            if (!connecting) Text("Forgot it? A code signs you in without it.", fontSize = 14.sp, color = Gray500)
        }
    }
}

@Composable
private fun CodeStep(activity: MainActivity) {
    val flow = SignInFlow
    PinnedStep(activity, button = "Continue", onButton = { flow.submitCode(activity) }, enabled = flow.code.length == 6,
        footnote = "Continues by itself once all six are in.") {
        StepTitle("Check your email", "We sent a 6-digit code to ${flow.email}. It works for ${flow.codeLifetime}.")
        Notices()
        Spacer(Modifier.height(28.dp))
        CodeBoxes(flow.code, onChange = { value ->
            val digits = value.filter(Char::isDigit).take(6)
            flow.code = digits
            if (digits.length == 6) flow.submitCode(activity)
        })
        Spacer(Modifier.height(8.dp))
        LinkButton("Send a new code", leading = true) { flow.sendCode(activity) }
    }
}

@Composable
private fun NameStep(activity: MainActivity) {
    val flow = SignInFlow
    PinnedStep(activity, button = "Create account", onButton = { flow.createAccount(activity) }, footnote = "Free to join · No card needed") {
        StepTitle("What should we call you?",
            "Your name is used on cast lists, messages, and contracts, so use the name you perform or work under.")
        Notices()
        Spacer(Modifier.height(24.dp))
        Field("First name", flow.firstName, { flow.firstName = it }, ContentType.PersonFirstName, KeyboardType.Text, ImeAction.Next,
            autofocus = flow.firstName.isEmpty()) {}
        Spacer(Modifier.height(12.dp))
        Field("Last name", flow.lastName, { flow.lastName = it }, ContentType.PersonLastName, KeyboardType.Text, ImeAction.Done) {
            flow.createAccount(activity)
        }
        Spacer(Modifier.height(18.dp))
        Row(
            Modifier.fillMaxWidth().background(Tailwind.Gray50, RoundedCornerShape(14.dp)).border(1.dp, Gray200, RoundedCornerShape(14.dp))
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = Tailwind.Pink600, modifier = Modifier.size(18.dp))
            Text("${flow.email} is confirmed", fontSize = 14.sp, color = Tailwind.Gray700)
        }
    }
}

/** A step on the raised sheet: back at the top, its content, and its one button pinned at the bottom. */
@Composable
private fun PinnedStep(
    activity: MainActivity,
    button: String,
    onButton: () -> Unit,
    enabled: Boolean = true,
    footnote: String? = null,
    content: @Composable () -> Unit
) {
    Column(Modifier.fillMaxSize().padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = 16.dp)) {
        CircleButton(Icons.AutoMirrored.Filled.ArrowBack, "Back") { SignInFlow.startOver(activity) }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 22.dp)) {
            content()
        }
        PrimaryButton(button, enabled = enabled, onClick = onButton)
        footnote?.let {
            Text(it, fontSize = 13.sp, color = Gray500, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 10.dp))
        }
    }
}

// Pieces

@Composable
private fun StepTitle(title: String, lede: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, modifier = Modifier.semantics { heading() },
            style = TextStyle(fontFamily = Coustard, fontSize = 30.sp, lineHeight = 35.sp, color = Tailwind.Gray900))
        lede?.let { Text(it, fontSize = 16.sp, lineHeight = 23.sp, color = Gray500) }
    }
}

@Composable
private fun Notices() {
    val flow = SignInFlow
    flow.error?.let {
        Spacer(Modifier.height(16.dp))
        Banner(it, error = true)
    } ?: flow.notice?.let {
        Spacer(Modifier.height(16.dp))
        Banner(it, error = false)
    }
}

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
    autofocus: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
    onDone: () -> Unit
) {
    val focus = remember { FocusRequester() }
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = Modifier.fillMaxWidth().focusRequester(focus).semantics { this.contentType = contentType },
        label = { Text(label) },
        singleLine = true,
        placeholder = placeholder?.let { { Text(it, color = Gray500) } },
        trailingIcon = trailing,
        visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard, imeAction = ime, autoCorrectEnabled = false),
        keyboardActions = KeyboardActions(onAny = { onDone() }),
        textStyle = TextStyle(fontSize = 17.sp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Tailwind.Pink500,
            focusedLabelColor = Tailwind.Pink600,
            unfocusedBorderColor = Color(0xFF79747E),
            cursorColor = Tailwind.Pink500,
            focusedTextColor = Tailwind.Gray900,
            unfocusedTextColor = Tailwind.Gray900
        )
    )
    if (autofocus) LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

/** Six boxes over one field, so the code can be typed, pasted, or filled in by the keyboard. */
@Composable
private fun CodeBoxes(code: String, onChange: (String) -> Unit) {
    val focus = remember { FocusRequester() }
    BasicTextField(
        value = code,
        onValueChange = onChange,
        modifier = Modifier.fillMaxWidth().focusRequester(focus)
            .semantics { contentType = ContentType.SmsOtpCode; contentDescription = "6-digit code" },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
        singleLine = true,
        decorationBox = { _ ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(6) { index ->
                    val digit = code.getOrNull(index)?.toString().orEmpty()
                    val current = index == code.length
                    Box(
                        Modifier.weight(1f).height(62.dp)
                            .background(if (digit.isNotEmpty()) Tailwind.Gray50 else Color.White, RoundedCornerShape(14.dp))
                            .border(if (current) 2.dp else 1.dp, if (current) Tailwind.Pink500 else Tailwind.Gray300, RoundedCornerShape(14.dp)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(digit, fontSize = 26.sp, fontWeight = FontWeight.Medium, color = Tailwind.Gray900)
                    }
                }
            }
        }
    )
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

@Composable
private fun AccountChip(email: String, change: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(Tailwind.Gray50, RoundedCornerShape(16.dp)).border(1.dp, Gray200, RoundedCornerShape(16.dp))
            .padding(start = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f).padding(vertical = 10.dp)) {
            Text("Signing in as", fontSize = 13.sp, color = Gray500)
            Text(email, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Tailwind.Gray900, maxLines = 1)
        }
        TextButton(onClick = change) { Text("Change", color = Tailwind.Pink600, fontWeight = FontWeight.Medium) }
    }
}

@Composable
private fun PrimaryButton(text: String, enabled: Boolean = true, fingerprint: Boolean = false, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.fillMaxWidth().height(56.dp),
        shape = RoundedCornerShape(28.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Tailwind.Pink500, contentColor = Color.White,
            disabledContainerColor = Tailwind.Pink500.copy(alpha = 0.45f), disabledContentColor = Color.White)
    ) {
        if (fingerprint) {
            Icon(Icons.Filled.Fingerprint, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(Modifier.size(10.dp))
        }
        Text(text, fontSize = 17.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun LinkButton(text: String, leading: Boolean = false, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth(), contentAlignment = if (leading) Alignment.CenterStart else Alignment.Center) {
        TextButton(onClick = onClick, modifier = Modifier.height(48.dp)) {
            Text(text, color = Tailwind.Pink600, fontWeight = FontWeight.Medium, fontSize = 16.sp)
        }
    }
}

@Composable
private fun CircleButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(44.dp),
        colors = IconButtonDefaults.iconButtonColors(containerColor = Color(0xFFF3F4F6), contentColor = Tailwind.Gray900)
    ) {
        Icon(icon, contentDescription = label)
    }
}

@Composable
private fun Terms(@Suppress("UNUSED_PARAMETER") activity: MainActivity) {
    val links = TextLinkStyles(style = SpanStyle(textDecoration = TextDecoration.Underline))
    Text(
        buildAnnotatedString {
            append("By continuing you agree to the ")
            withLink(LinkAnnotation.Url(AppConfig.url("/terms"), links)) { append("Terms of Service") }
            append(" and ")
            withLink(LinkAnnotation.Url(AppConfig.url("/privacy"), links)) { append("Privacy Policy") }
            append(".")
        },
        fontSize = 12.sp, lineHeight = 18.sp, color = Gray500, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
    )
}

/** shared/auth/_notice: pink for something that went wrong, gray to know. */
@Composable
private fun Banner(text: String, error: Boolean) {
    Text(
        text,
        modifier = Modifier.fillMaxWidth()
            .background(if (error) Pink50 else Tailwind.Gray50, RoundedCornerShape(12.dp))
            .border(1.dp, if (error) Pink200 else Gray200, RoundedCornerShape(12.dp))
            .padding(12.dp),
        fontSize = 15.sp,
        color = if (error) Pink700 else Tailwind.Gray700
    )
}
