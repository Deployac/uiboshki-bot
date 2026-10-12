package ru.uiboshki.app

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ru.uiboshki.app.widget.WidgetBridge

class MainActivity : FlutterActivity() {
    // Иконка на выбор (5.79): у каждой — свой activity-alias в AndroidManifest.xml
    // (.IconClassic, .IconDepth…), включён ровно один. Имена — AppIcon.* в Dart.
    private val icons = listOf("classic", "depth", "indigo", "terracotta", "page", "sunset", "library")

    private fun alias(name: String) =
        ComponentName(this, "ru.uiboshki.app.Icon" + name.replaceFirstChar { it.uppercase() })

    private fun enabled(name: String): Boolean =
        when (packageManager.getComponentEnabledSetting(alias(name))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> name == "classic" // как в манифесте
            else -> false
        }

    private fun current(): String = icons.firstOrNull { enabled(it) } ?: "classic"

    private fun switchTo(name: String) {
        if (current() == name) return
        val pm = packageManager
        // сначала включить новую, потом выключить остальные — без иконки не остаться
        pm.setComponentEnabledSetting(
            alias(name),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for (other in icons) {
            if (other == name) continue
            pm.setComponentEnabledSetting(
                alias(other),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // виджеты рабочего стола: снимок дня из приложения (widget/WidgetBridge.kt)
        WidgetBridge.attach(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uiboshki/icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(true)
                "getIcon" -> result.success(current().takeIf { it != "classic" })
                "setIcon" -> {
                    val name = (call.arguments as? String) ?: "classic"
                    if (name !in icons) {
                        result.error("unknown", "Нет такой иконки: $name", null)
                    } else {
                        try {
                            switchTo(name)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
