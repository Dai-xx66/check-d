# ML Kit discovers these factories through Firebase Components. R8 full-mode
# optimization can otherwise invalidate the internal provider graph used when
# TextRecognition.getClient() creates the Chinese recognizer.
-keep class com.google.mlkit.vision.text.internal.** { *; }
-keep class com.google.mlkit.common.** { *; }
