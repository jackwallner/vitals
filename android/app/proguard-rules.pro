# RevenueCat publishes consumer ProGuard rules with its Android SDK.

# WorkManager (pulled in by Glance for the widget) builds its Room database by
# reflection; R8 stripped the generated implementation and the release build
# crashed on launch. Keep every Room database's generated constructor.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
