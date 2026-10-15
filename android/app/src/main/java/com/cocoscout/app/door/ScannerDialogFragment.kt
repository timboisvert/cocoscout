package com.cocoscout.app.door

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.content.ContextCompat
import androidx.fragment.app.DialogFragment

/**
 * The door's camera, full screen over the door page, scanning one ticket after
 * another until it's closed (ScannerScreen draws it). Asks for the camera the
 * first time; without it, or without a camera, it takes a typed code.
 */
class ScannerDialogFragment : DialogFragment() {
    private val controller: ScannerController? get() = ScannerController.current

    private val askForCamera = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        controller?.model?.camera = if (granted) ScannerModel.Camera.RUNNING else ScannerModel.Camera.DENIED
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setStyle(STYLE_NO_FRAME, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        // Brought back after the app was closed: nothing to scan for any more.
        if (controller == null) dismissAllowingStateLoss()
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val controller = controller ?: return View(requireContext())
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            controller.view = this
            setContent {
                ScannerScreen(
                    controller = controller,
                    onClose = { dismiss() },
                    onOpenSettings = {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", requireContext().packageName, null)))
                    }
                )
            }
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val model = controller?.model ?: return
        val hasCamera = requireContext().packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
        when {
            !hasCamera -> model.camera = ScannerModel.Camera.UNAVAILABLE
            ContextCompat.checkSelfPermission(requireContext(), Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED ->
                model.camera = ScannerModel.Camera.RUNNING
            else -> askForCamera.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onResume() {
        super.onResume()
        // Back from Settings with the camera now allowed.
        val model = controller?.model ?: return
        if (model.camera == ScannerModel.Camera.DENIED &&
            ContextCompat.checkSelfPermission(requireContext(), Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        ) {
            model.camera = ScannerModel.Camera.RUNNING
        }
    }

    override fun onDestroyView() {
        controller?.view = null
        super.onDestroyView()
    }

    override fun onDismiss(dialog: android.content.DialogInterface) {
        super.onDismiss(dialog)
        controller?.closed()
    }
}
