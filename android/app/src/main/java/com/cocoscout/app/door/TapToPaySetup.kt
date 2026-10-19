package com.cocoscout.app.door

import android.content.Context
import com.cocoscout.app.MainActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable

/**
 * What the server says about Tap to Pay for whoever's signed in
 * (NativeAppHelper#native_tap_to_pay, with the menu): sent only to someone
 * who can sell at a door that has it switched on, in a copy of the app that
 * has it.
 */
@Serializable
data class TapToPayInfo(
    /** Tap to Pay's own page (door/tap_to_pay). */
    val settingsPath: String,
    /** Who's signed in, so "set up here" is per person. */
    val userKey: String,
    /** The organization's Terminal Location, when it has one yet. */
    val locationId: String? = null,
    val connectionTokenUrl: String
)

/**
 * Tap to Pay on this phone. Like TapToPaySetup.swift, less Apple's terms
 * (Android has none): warmed up at launch and on coming back to the front,
 * set up on purpose from its own page, asking for location access there
 * rather than in a sale, and saying where it stands while it gets ready.
 */
object TapToPaySetup {
    sealed interface State {
        data object NotSetUp : State
        data class Preparing(val progress: Float = 0f) : State
        data object Ready : State
        data class Failed(val message: String) : State
    }

    /** Outlives any one page, so a connection a page started finishes after it's gone. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var appContext: Context

    private val _state = MutableStateFlow<State>(State.NotSetUp)
    /** Where it stands; Tap to Pay's page hears every change. */
    val state: StateFlow<State> = _state.asStateFlow()

    var info: TapToPayInfo? = null
        private set

    fun start(context: Context) {
        appContext = context.applicationContext
    }

    // Who's signed in

    fun update(info: TapToPayInfo?) {
        val changedPerson = info?.userKey != this.info?.userKey
        this.info = info
        if (changedPerson) _state.value = State.NotSetUp
        warmUp()
    }

    private val prefs get() = appContext.getSharedPreferences("tap_to_pay", Context.MODE_PRIVATE)

    /**
     * Set up once on this phone by this person (a connection went through):
     * from then on the app warms Terminal up on its own.
     */
    private val setUpKey: String? get() = info?.let { "setUp.${it.userKey}" }

    val hasBeenSetUp: Boolean get() = setUpKey?.let { prefs.getBoolean(it, false) } ?: false

    // Getting ready

    /**
     * At launch, with every menu and whenever the app comes back to the
     * front: connect in the background so the payment screen opens at once.
     * Never asks for anything; that only happens when someone sets it up.
     */
    fun warmUp() {
        if (!::appContext.isInitialized) return
        val info = info ?: return
        val locationId = info.locationId?.takeIf { it.isNotBlank() } ?: return
        if (!hasBeenSetUp || !TapToPayLocation.isGranted(appContext) || TapToPayReader.isConnected(locationId)) return
        scope.launch { connect(locationId, info.connectionTokenUrl) }
    }

    /** "Set up Tap to Pay" on its page: location access, then the connection. */
    suspend fun enable(activity: MainActivity, locationId: String, tokenUrl: String): State {
        if (!TapToPayLocation.ask(activity)) return State.Failed(TapToPayReader.locationMessage).also { _state.value = it }
        return connect(locationId, tokenUrl)
    }

    /** Ready for a sale at this Location, connecting first when it isn't. */
    suspend fun ensureReady(activity: MainActivity, locationId: String, tokenUrl: String): State {
        if (!TapToPayLocation.ask(activity)) return State.Failed(TapToPayReader.locationMessage).also { _state.value = it }
        if (TapToPayReader.isConnected(locationId)) return State.Ready.also { _state.value = it }
        return connect(locationId, tokenUrl)
    }

    /**
     * How this phone stands right now, for the page's first look. A phone
     * that was set up here gets ready again on its own, and says so.
     */
    fun currentState(locationId: String, tokenUrl: String): State {
        val current = _state.value
        if (current is State.Preparing) return current
        if (locationId.isNotBlank() && TapToPayReader.isConnected(locationId)) return State.Ready
        if (hasBeenSetUp && locationId.isNotBlank() && TapToPayLocation.isGranted(appContext)) {
            scope.launch { connect(locationId, tokenUrl) }
            return State.Preparing()
        }
        return State.NotSetUp
    }

    private var connecting: Deferred<State>? = null

    private suspend fun connect(locationId: String, tokenUrl: String): State {
        connecting?.let { return it.await() }
        if (_state.value == State.Ready && TapToPayReader.isConnected(locationId)) return State.Ready

        _state.value = State.Preparing()
        val task = scope.async {
            try {
                TapToPayReader.connect(appContext, locationId, tokenUrl)
                setUpKey?.let { prefs.edit().putBoolean(it, true).apply() }
                State.Ready
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                State.Failed(TapToPayReader.message(e))
            }
        }
        connecting = task
        val result = task.await()
        connecting = null
        _state.value = result
        return result
    }
}
