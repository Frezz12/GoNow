# Retrofit
-keepattributes Signature
-keepattributes *Annotation*
-keep class frezzy.gonow.models.** { *; }
-keepclassmembers class frezzy.gonow.models.** { *; }

# Kotlinx Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers @kotlinx.serialization.Serializable class frezzy.gonow.models.** {
    *** Companion;
    *** INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class frezzy.gonow.models.**$$serializer { *; }
-keepclassmembers class frezzy.gonow.models.** {
    *** Companion;
}
-keepclasseswithmembers class frezzy.gonow.models.** {
    kotlinx.serialization.KSerializer serializer(...);
}
