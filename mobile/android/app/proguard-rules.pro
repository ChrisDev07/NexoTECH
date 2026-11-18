# Reglas de ofuscación y protección binaria OWASP Mobile M7
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-keep class org.vosk.** { *; }
-dontwarn com.sun.jna.**
-dontwarn java.awt.**

# Eliminación de logs sensibles de depuración en compilaciones de producción
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
