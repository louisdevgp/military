package ci.universdumono.mono_pos

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var photos: PhotoBridge
    private lateinit var printer: PrinterBridge
    private lateinit var secrets: SecureStoreBridge
    private lateinit var exports: ExportBridge
    private lateinit var backups: BackupBridge
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        photos = PhotoBridge(this)
        printer = PrinterBridge(applicationContext)
        secrets = SecureStoreBridge(applicationContext)
        exports = ExportBridge(this)
        backups = BackupBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ci.universdumono/backup")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "encrypt" -> backups.encrypt(call.argument<ByteArray>("data"), call.argument<String>("passphrase"), result)
                    "decrypt" -> backups.decrypt(call.argument<ByteArray>("data"), call.argument<String>("passphrase"), result)
                    "save" -> backups.save(call.argument<String>("name"), call.argument<ByteArray>("data"), result)
                    "open" -> backups.open(result)
                    "relaunch" -> backups.relaunch()
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ci.universdumono/export")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveCsv") {
                    exports.save(call.argument<String>("name"), call.argument<String>("content"), result)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ci.universdumono/secure")
            .setMethodCallHandler { call, result ->
                val name = call.argument<String>("key")
                when (call.method) {
                    "write" -> secrets.write(name, call.argument<String>("value"), result)
                    "read" -> secrets.read(name, result)
                    "delete" -> secrets.delete(name, result)
                    else -> result.notImplemented()
                }
            }
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
        if (requestCode == ExportBridge.REQUEST_CODE && ::exports.isInitialized) exports.onResult(resultCode, data)
        if ((requestCode == BackupBridge.SAVE_REQUEST || requestCode == BackupBridge.OPEN_REQUEST) && ::backups.isInitialized) {
            backups.onResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        if (::photos.isInitialized) photos.close()
        if (::printer.isInitialized) printer.close()
        if (::exports.isInitialized) exports.close()
        if (::backups.isInitialized) backups.close()
        super.onDestroy()
    }
}
