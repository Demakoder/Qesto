# PdfBox-Android treats the JP2/JPEG2000 decoder as an optional dependency.
# Qesto extracts statement text and deliberately does not bundle that decoder.
-dontwarn com.gemalto.jp2.JP2Decoder

# ML Kit discovers these two manifest registrars reflectively. Stage 6A's
# release mapping/usage and device log show R8 removed their no-arg constructors
# (NoSuchMethodException), leaving SharedPrefManager null in code scanner.
# Keep only the required constructors/classes, not the SDK or all its members.
-keep class com.google.mlkit.common.internal.CommonComponentRegistrar {
    public <init>();
}
-keep class com.google.mlkit.vision.common.internal.VisionCommonRegistrar {
    public <init>();
}
