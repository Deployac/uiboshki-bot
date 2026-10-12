package ru.uiboshki.app.widget

// Канал ru.uiboshki.app/widgets: приложение кладёт снимок дня (save), стирает
// его (clear) и спрашивает, стоит ли виджет (installed).

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object WidgetBridge {
    private const val CHANNEL = "ru.uiboshki.app/widgets"

    fun attach(ctx: Context, engine: FlutterEngine) {
        val app = ctx.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> {
                    WidgetStore.save(app, call.argument<String>("json"))
                    Widgets.updateAll(app)
                    result.success(null)
                }
                "clear" -> {
                    WidgetStore.save(app, null)
                    Widgets.updateAll(app)
                    result.success(null)
                }
                "installed" -> result.success(Widgets.count(app))
                else -> result.notImplemented()
            }
        }
    }
}
