package com.cocoscout.app.door

import androidx.camera.core.ImageAnalysis
import androidx.camera.mlkit.vision.MlKitAnalyzer
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FlashlightOff
import androidx.compose.material.icons.filled.FlashlightOn
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.cocoscout.app.R
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode

private val Pink = Color(0xFFF6339A)
private val Gray900 = Color(0xFF101828)
private val Green600 = Color(0xFF00A63E)
private val Amber300 = Color(0xFFFFD230)
private val Red600 = Color(0xFFE7000B)
private val Coustard = FontFamily(Font(R.font.coustard_regular))

/**
 * Everything on the scanner: the camera, the show at the top with close and
 * the flashlight, a frame to aim with, and the last result at the bottom in
 * the door page's banner colors (green in, amber already in, red no). Like
 * ScannerOverlay.swift.
 */
@Composable
fun ScannerScreen(controller: ScannerController, onClose: () -> Unit, onOpenSettings: () -> Unit) {
    val model = controller.model
    val running = model.camera == ScannerModel.Camera.RUNNING
    val cameraController = if (running) rememberCameraController(controller) else null

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (cameraController != null) {
            AndroidView(
                factory = { context -> PreviewView(context).also { it.controller = cameraController } },
                modifier = Modifier.fillMaxSize()
            )
        }

        Column(
            modifier = Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            TopBar(model, onClose) {
                val on = !model.torchOn
                cameraController?.enableTorch(on)
                model.torchOn = on
            }
            Spacer(Modifier.weight(1f))
            Middle(controller, onOpenSettings)
            Spacer(Modifier.weight(1f))
            Bottom(controller)
        }
    }
}

/** CameraX with ML Kit reading QR tickets and the barcodes other ticket sites print. */
@Composable
private fun rememberCameraController(controller: ScannerController): LifecycleCameraController {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val cameraController = remember { LifecycleCameraController(context) }

    DisposableEffect(lifecycleOwner) {
        val scanner = BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(
                    Barcode.FORMAT_QR_CODE, Barcode.FORMAT_AZTEC, Barcode.FORMAT_PDF417, Barcode.FORMAT_DATA_MATRIX,
                    Barcode.FORMAT_CODE_128, Barcode.FORMAT_CODE_39, Barcode.FORMAT_EAN_13
                )
                .build()
        )
        val executor = ContextCompat.getMainExecutor(context)
        cameraController.setImageAnalysisAnalyzer(
            executor,
            MlKitAnalyzer(listOf(scanner), ImageAnalysis.COORDINATE_SYSTEM_ORIGINAL, executor) { result ->
                result.getValue(scanner)?.firstNotNullOfOrNull { it.rawValue }?.let { controller.found(it) }
            }
        )
        cameraController.bindToLifecycle(lifecycleOwner)
        cameraController.initializationFuture.addListener({
            controller.model.hasTorch = cameraController.cameraInfo?.hasFlashUnit() == true
        }, executor)

        onDispose {
            cameraController.enableTorch(false)
            cameraController.unbind()
            scanner.close()
        }
    }
    return cameraController
}

@Composable
private fun TopBar(model: ScannerModel, onClose: () -> Unit, onTorch: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        RoundButton(onClick = onClose, description = "Close the scanner") {
            Icon(Icons.Filled.Close, contentDescription = null, tint = Color.White)
        }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(model.title, color = Color.White, fontFamily = Coustard, fontSize = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (model.subtitle.isNotEmpty()) {
                Text(model.subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            }
        }
        if (model.hasTorch) {
            RoundButton(
                onClick = onTorch,
                description = if (model.torchOn) "Turn the flashlight off" else "Turn the flashlight on",
                highlighted = model.torchOn
            ) {
                Icon(
                    if (model.torchOn) Icons.Filled.FlashlightOn else Icons.Filled.FlashlightOff,
                    contentDescription = null,
                    tint = if (model.torchOn) Gray900 else Color.White
                )
            }
        } else {
            Spacer(Modifier.size(44.dp))
        }
    }
}

@Composable
private fun RoundButton(onClick: () -> Unit, description: String, highlighted: Boolean = false, content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(if (highlighted) Color.White else Color.Black.copy(alpha = 0.45f))
            .clickable(onClickLabel = description, onClick = onClick),
        contentAlignment = Alignment.Center
    ) { content() }
}

@Composable
private fun Middle(controller: ScannerController, onOpenSettings: () -> Unit) {
    when (controller.model.camera) {
        ScannerModel.Camera.STARTING, ScannerModel.Camera.RUNNING ->
            Box(Modifier.fillMaxWidth()) {
                Box(
                    Modifier
                        .align(Alignment.Center)
                        .widthIn(max = 280.dp)
                        .fillMaxWidth()
                        .aspectRatio(1f)
                        .border(3.dp, Color.White.copy(alpha = 0.9f), RoundedCornerShape(24.dp))
                )
            }
        ScannerModel.Camera.UNAVAILABLE ->
            TypeACode(controller, "No camera here", "Type the code from their ticket instead.", onOpenSettings = null)
        ScannerModel.Camera.DENIED ->
            TypeACode(
                controller,
                "The camera is off for CocoScout",
                "Turn it on in Settings to scan tickets, or type the code from their ticket.",
                onOpenSettings = onOpenSettings
            )
    }
}

@Composable
private fun TypeACode(controller: ScannerController, headline: String, detail: String, onOpenSettings: (() -> Unit)?) {
    val model = controller.model
    val canCheckIn = model.typedCode.isNotBlank() && !model.waiting
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        Text(headline, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text(detail, color = Color.White.copy(alpha = 0.85f), fontSize = 15.sp, textAlign = TextAlign.Center)
        if (onOpenSettings != null) {
            OutlinedButton(
                onClick = onOpenSettings,
                shape = RoundedCornerShape(6.dp),
                colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.White, contentColor = Gray900)
            ) { Text("Open Settings") }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextField(
                value = model.typedCode,
                onValueChange = { model.typedCode = it },
                placeholder = { Text("Ticket code") },
                singleLine = true,
                // Ticket codes are case-sensitive.
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { if (canCheckIn) controller.found(model.typedCode, typed = true) }),
                shape = RoundedCornerShape(8.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.White, unfocusedContainerColor = Color.White,
                    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
                    focusedTextColor = Gray900, unfocusedTextColor = Gray900
                ),
                modifier = Modifier.weight(1f)
            )
            Button(
                onClick = { controller.found(model.typedCode, typed = true) },
                enabled = canCheckIn,
                shape = RoundedCornerShape(6.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Pink, contentColor = Color.White)
            ) { Text("Check in") }
        }
    }
}

@Composable
private fun Bottom(controller: ScannerController) {
    val model = controller.model
    val result = model.result
    when {
        result != null -> ResultCard(result, model.delivering, onUndo = controller::undo, onFulfill = controller::fulfill)
        model.waiting -> Pill {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
            Text("Checking…", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Medium)
        }
        model.camera == ScannerModel.Camera.RUNNING || model.camera == ScannerModel.Camera.STARTING ->
            Pill { Text("Point at the code on their phone or printout", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Medium) }
    }
}

@Composable
private fun Pill(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(Color.Black.copy(alpha = 0.55f))
                .padding(horizontal = 16.dp, vertical = 10.dp)
        ) { content() }
    }
}

/**
 * The door page's result banner, in the hand: the name or the problem big,
 * the details under it, Undo on a fresh admit, and anything they pre-bought
 * with a Delivered button.
 */
@Composable
private fun ResultCard(result: DoorResult, delivering: List<String>, onUndo: (String) -> Unit, onFulfill: (String) -> Unit) {
    val textColor = if (result.tone == DoorResult.Tone.ALREADY) Gray900 else Color.White
    val background = when (result.tone) {
        DoorResult.Tone.ADMITTED -> Green600
        DoorResult.Tone.ALREADY -> Amber300
        DoorResult.Tone.ERROR -> Red600
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(background)
            .padding(16.dp)
    ) {
        result.shownLines.forEachIndexed { index, line ->
            Text(
                line,
                color = textColor,
                fontSize = if (index == 0) 24.sp else 15.sp,
                fontWeight = if (index == 0) FontWeight.Bold else FontWeight.Medium,
                textAlign = TextAlign.Center
            )
        }
        result.undoTicketId?.let { ticketId ->
            Text(
                "Undo",
                color = textColor,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                textDecoration = TextDecoration.Underline,
                modifier = Modifier.padding(top = 6.dp).clickable { onUndo(ticketId) }
            )
        }
        result.items.forEach { item ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .padding(top = 8.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color.White.copy(alpha = 0.92f))
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                Text(
                    if (item.fulfilled) "${item.label} · delivered" else item.label,
                    color = Gray900,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f)
                )
                if (!item.fulfilled) {
                    Button(
                        onClick = { onFulfill(item.fulfillUrl) },
                        enabled = item.fulfillUrl !in delivering,
                        shape = RoundedCornerShape(6.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Pink, contentColor = Color.White)
                    ) { Text("Delivered") }
                }
            }
        }
        Spacer(Modifier.height(0.dp))
    }
}
