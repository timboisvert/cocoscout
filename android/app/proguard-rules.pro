# CocoScout's own keep rules for the release build (R8). The libraries
# (Hotwire Native, Stripe Terminal, Firebase, ML Kit, CameraX, Compose,
# kotlinx.serialization) ship theirs inside their packages.

# Crash reports stay readable: line numbers kept, file names hidden. Play
# gets the mapping file with each bundle and turns the names back.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Hotwire Native core's rules, restated (its own are switched off in
# build.gradle.kts: they kept every com.google, org.apache and javax class,
# which left most of the app un-renamed). Check these against the library's
# proguard.txt when Hotwire is upgraded.
-keepclassmembers class dev.hotwire.core.turbo.session.Session {
    @android.webkit.JavascriptInterface <methods>;
}
-keepclassmembers class dev.hotwire.core.bridge.Bridge {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keep class dev.hotwire.core.** { *; }
-dontwarn java.lang.invoke.StringConcatFactory

# Gson (Hotwire reads the path configuration with it): the library itself,
# and the generic signatures its TypeTokens read at runtime.
-keep class com.google.gson.** { *; }
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-keep class * extends com.google.gson.reflect.TypeToken
-keep class sun.misc.Unsafe { *; }

# Classes stay in their own packages; their names are still shortened.
# Stripe's Tap to Pay rules pin single classes in kotlin, kotlinx, androidx
# and dagger exactly as they are. R8 was moving their package-private
# relatives out to the top level, and the app died at launch
# (IllegalAccessError on kotlin.collections, 2026-11-04).
-keeppackagenames **
