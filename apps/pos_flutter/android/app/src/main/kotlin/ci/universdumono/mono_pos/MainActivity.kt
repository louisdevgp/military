package ci.universdumono.mono_pos

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var photos: PhotoBridge
    private lateinit var printer: PrinterBridge
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        photos = PhotoBridge(this)
        printer = PrinterBridge(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ci.universdumono/photos")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "choose" -> photos.choose(result)
                    "discardDraft" -> photos.discardDraft(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ci.universdumono/printer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> printer.status(result)
                    "printReceipt" -> printer.print(call.argument<List<*>>("blocks"), result)
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Android legacy activity callback used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PhotoBridge.REQUEST_CODE && ::photos.isInitialized) photos.onResult(resultCode, data)
    }

    override fun onDestroy() {
        if (::photos.isInitialized) photos.close()
        if (::printer.isInitialized) printer.close()
        super.onDestroy()
    }
}
