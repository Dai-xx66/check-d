package com.daixx66.check_d

import android.graphics.BitmapFactory
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val localOcrChannel = "check_d/local_ocr"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, localOcrChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                if (bitmap == null) {
                    result.error("image_decode_failed", "无法读取图片", null)
                    return@setMethodCallHandler
                }
                val recognizer = TextRecognition.getClient(
                    ChineseTextRecognizerOptions.Builder().build()
                )
                recognizer.process(InputImage.fromBitmap(bitmap, 0))
                    .addOnSuccessListener { text ->
                        val tokens = text.textBlocks.flatMap { block ->
                            block.lines.mapNotNull { line ->
                                line.boundingBox?.let { box ->
                                    mapOf(
                                        "text" to line.text,
                                        "left" to box.left.toDouble(),
                                        "top" to box.top.toDouble(),
                                        "right" to box.right.toDouble(),
                                        "bottom" to box.bottom.toDouble(),
                                    )
                                }
                            }
                        }
                        recognizer.close()
                        result.success(
                            mapOf(
                                "imageWidth" to bitmap.width.toDouble(),
                                "imageHeight" to bitmap.height.toDouble(),
                                "tokens" to tokens,
                            )
                        )
                    }
                    .addOnFailureListener { error ->
                        recognizer.close()
                        result.error("ocr_failed", error.message ?: "本地 OCR 失败", null)
                    }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "check_d/home_widget")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveSnapshot") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val json = call.argument<String>("json")
                if (json == null) {
                    result.error("invalid_snapshot", "Widget 快照为空", null)
                    return@setMethodCallHandler
                }
                getSharedPreferences("check_d_home_widget", Context.MODE_PRIVATE)
                    .edit()
                    .putString("snapshot", json)
                    .apply()
                val manager = AppWidgetManager.getInstance(this)
                val provider = ComponentName(this, CheckDHomeWidgetProvider::class.java)
                manager.getAppWidgetIds(provider).forEach { id ->
                    CheckDHomeWidgetProvider.update(this, manager, id)
                }
                result.success(null)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "check_d/lock_screen_status")
            .setMethodCallHandler { call, result ->
                if (call.method != "sync") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val json = call.argument<String>("json")
                if (json == null) {
                    result.error("invalid_snapshot", "锁屏状态为空", null)
                    return@setMethodCallHandler
                }
                try {
                    val visible = LockScreenStatusNotifier.sync(this, json)
                    result.success(mapOf("visible" to visible))
                } catch (error: Exception) {
                    result.error("live_status_failed", error.message ?: "实时状态更新失败", null)
                }
            }
    }
}
