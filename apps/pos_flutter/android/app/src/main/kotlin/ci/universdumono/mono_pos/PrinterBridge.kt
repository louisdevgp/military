package ci.universdumono.mono_pos

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.RemoteException
import io.flutter.plugin.common.MethodChannel
import recieptservice.com.recieptservice.PrinterInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Drives the H10 built-in printer through the SRPrinter system service.
 * Every call answers Flutter exactly once (success or error code), never blocks
 * the UI thread, and never claims that paper came out: the service exposes no
 * paper or cover status.
 */
class PrinterBridge(private val context: Context) {
    companion object {
        const val SERVICE_PACKAGE = "recieptservice.com.recieptservice"
        const val SERVICE_CLASS = "recieptservice.com.recieptservice.service.PrinterService"
        const val CONNECT_TIMEOUT_SECONDS = 4L
        const val MAX_BLOCKS = 400
        const val MAX_TEXT = 256
        const val MAX_IMAGE_BYTES = 1024 * 1024
    }

    private class PrinterError(val code: String, message: String) : Exception(message)

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val lock = Object()
    @Volatile private var printer: PrinterInterface? = null
    private var connected = CountDownLatch(1)
    private var bound = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            printer = PrinterInterface.Stub.asInterface(service)
            connected.countDown()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            printer = null
        }

        override fun onBindingDied(name: ComponentName) {
            printer = null
            synchronized(lock) { unbind() }
        }

        override fun onNullBinding(name: ComponentName) {
            connected.countDown()
        }
    }

    fun status(result: MethodChannel.Result) = run(result) { connect().serviceVersion ?: "" }

    fun print(blocks: List<*>?, result: MethodChannel.Result) = run(result) {
        val commands = parse(blocks)
        val service = connect()
        service.beginWork()
        try {
            commands.forEach { it(service) }
        } finally {
            service.endWork()
        }
        null
    }

    fun close() {
        executor.shutdownNow()
        synchronized(lock) { unbind() }
    }

    private fun run(result: MethodChannel.Result, body: () -> Any?) {
        executor.execute {
            try {
                val value = body()
                main.post { result.success(value) }
            } catch (e: PrinterError) {
                main.post { result.error(e.code, e.message, null) }
            } catch (_: RemoteException) {
                printer = null
                main.post { result.error("SERVICE_DISCONNECTED", "Service d’impression interrompu.", null) }
            } catch (e: Exception) {
                main.post { result.error("PRINT_FAILED", e.javaClass.simpleName, null) }
            }
        }
    }

    private fun connect(): PrinterInterface {
        printer?.takeIf { it.asBinder().isBinderAlive }?.let { return it }
        val latch = synchronized(lock) {
            if (!bound) {
                connected = CountDownLatch(1)
                val intent = Intent().setClassName(SERVICE_PACKAGE, SERVICE_CLASS)
                val ok = try {
                    context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
                } catch (_: SecurityException) {
                    false
                }
                if (!ok) {
                    // Android asks to release a failed binding as well.
                    try {
                        context.unbindService(connection)
                    } catch (_: IllegalArgumentException) {
                    }
                    throw PrinterError("SERVICE_UNAVAILABLE", "Service d’impression SRPrinter introuvable.")
                }
                bound = true
            }
            connected
        }
        if (!latch.await(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            throw PrinterError("SERVICE_TIMEOUT", "Le service d’impression ne répond pas.")
        }
        return printer ?: throw PrinterError("SERVICE_UNAVAILABLE", "Service d’impression indisponible.")
    }

    private fun unbind() {
        if (!bound) return
        bound = false
        printer = null
        try {
            context.unbindService(connection)
        } catch (_: IllegalArgumentException) {
        }
    }

    /** Validates the whole receipt before the first printer call. */
    private fun parse(blocks: List<*>?): List<(PrinterInterface) -> Unit> {
        if (blocks == null || blocks.isEmpty() || blocks.size > MAX_BLOCKS) invalid()
        return blocks.map { raw ->
            val block = raw as? Map<*, *> ?: invalid()
            when (block["type"]) {
                "text" -> {
                    val text = string(block["text"])
                    val align = align(block["align"])
                    val bold = block["bold"] == true
                    val size = size(block["size"])
                    val command: (PrinterInterface) -> Unit = { p ->
                        p.setAlignment(align)
                        p.setTextSize(size)
                        p.setTextBold(bold)
                        p.printText("$text\n")
                        if (bold) p.setTextBold(false)
                    }
                    command
                }
                "row" -> {
                    val cells = (block["cells"] as? List<*>)?.map { string(it) } ?: invalid()
                    val weights = (block["weights"] as? List<*>)?.map { (it as? Int)?.takeIf { w -> w in 1..20 } ?: invalid() } ?: invalid()
                    val aligns = (block["aligns"] as? List<*>)?.map { align(it) } ?: invalid()
                    if (cells.isEmpty() || cells.size > 6 || cells.size != weights.size || cells.size != aligns.size) invalid()
                    val bold = block["bold"] == true
                    val size = size(block["size"])
                    val command: (PrinterInterface) -> Unit = { p ->
                        p.setTextSize(size)
                        p.setTextBold(bold)
                        p.printTableText(cells.toTypedArray(), weights.toIntArray(), aligns.toIntArray())
                        if (bold) p.setTextBold(false)
                    }
                    command
                }
                "image" -> {
                    val png = block["png"] as? ByteArray ?: invalid()
                    val paper = (block["paper"] as? Int)?.takeIf { it in 16..576 } ?: invalid()
                    val width = (block["width"] as? Int)?.takeIf { it in 16..paper } ?: invalid()
                    if (png.isEmpty() || png.size > MAX_IMAGE_BYTES) invalid()
                    val bitmap = centered(png, width, paper)
                    val command: (PrinterInterface) -> Unit = { p ->
                        p.printBitmap(bitmap)
                        // Observed on the H10: text otherwise continues beside the image.
                        p.printText("\n")
                    }
                    command
                }
                "feed" -> {
                    val lines = (block["lines"] as? Int)?.takeIf { it in 1..10 } ?: invalid()
                    val command: (PrinterInterface) -> Unit = { p -> p.nextLine(lines) }
                    command
                }
                else -> invalid()
            }
        }
    }

    /**
     * Scales the image and centres it on a white strip as wide as the paper:
     * the service ignores setAlignment for bitmaps (observed on the H10).
     */
    private fun centered(png: ByteArray, width: Int, paper: Int): Bitmap {
        val source = BitmapFactory.decodeByteArray(png, 0, png.size) ?: invalid()
        val height = maxOf(1, source.height * width / source.width)
        val output = Bitmap.createBitmap(paper, height, Bitmap.Config.ARGB_8888)
        Canvas(output).apply {
            drawColor(Color.WHITE)
            drawBitmap(Bitmap.createScaledBitmap(source, width, height, true), ((paper - width) / 2).toFloat(), 0f, null)
        }
        source.recycle()
        return output
    }

    private fun string(value: Any?): String {
        val text = value as? String ?: invalid()
        if (text.length > MAX_TEXT || text.contains('\n')) invalid()
        return text
    }

    private fun align(value: Any?): Int = (value as? Int)?.takeIf { it in 0..2 } ?: invalid()

    private fun size(value: Any?): Float =
        ((value as? Number)?.toFloat())?.takeIf { it in 12f..48f } ?: invalid()

    private fun invalid(): Nothing = throw PrinterError("INVALID_RECEIPT", "Ticket invalide : aucun ordre envoyé.")
}
