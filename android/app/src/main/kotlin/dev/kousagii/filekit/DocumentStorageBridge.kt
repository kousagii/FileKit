package dev.kousagii.filekit

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/** Only the selected document tree is accessible. Never converts content URIs to file paths. */
class DocumentStorageBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "dev.kousagii.filekit/documents")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPicker: MethodChannel.Result? = null
    private val resolver get() = activity.contentResolver

    init {
        channel.setMethodCallHandler(this)
        // Share targets can read asynchronously. Retain these caches for at least one day.
        io.execute {
            File(activity.cacheDir, "filekit_share").listFiles()?.forEach { child ->
                if (System.currentTimeMillis() - child.lastModified() > 86400000L) child.deleteRecursively()
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "chooseDirectory" -> chooseDirectory(call, result)
            "validateDirectory" -> background(result) {
                try { writableTree(call.argument<String>("uri")!!).canWrite() } catch (_: Exception) { false }
            }
            "exportFile" -> background(result) { exportFile(call) }
            "openDocument" -> openDocument(call, result)
            "prepareShare" -> background(result) { prepareShare(call) }
            else -> result.notImplemented()
        }
    }

    private fun chooseDirectory(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPicker != null) { result.error("busy", "A folder picker is already open.", null); return }
        pendingPicker = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            call.argument<String>("initialUri")?.let {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(it))
            }
        }
        try { activity.startActivityForResult(intent, REQUEST_DIRECTORY) }
        catch (_: ActivityNotFoundException) {
            pendingPicker = null
            result.error("picker_unavailable", "No system folder picker is available on this device.", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_DIRECTORY) return false
        val result = pendingPicker ?: return true
        pendingPicker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        background(result) {
            val flags = (data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            try { resolver.takePersistableUriPermission(uri, flags) } catch (_: SecurityException) { /* Session access may still work. */ }
            val tree = writableTree(uri.toString())
            val persistent = resolver.persistedUriPermissions.any {
                it.uri == uri && it.isWritePermission && it.isReadPermission
            }
            mapOf("uri" to uri.toString(), "label" to (tree.name ?: "Selected folder"), "persistent" to persistent)
        }
        return true
    }

    private fun writableTree(value: String): DocumentFile {
        val uri = Uri.parse(value)
        require(uri.scheme == "content" && DocumentsContract.isTreeUri(uri)) { "Choose an output folder again." }
        val tree = DocumentFile.fromTreeUri(activity, uri)
            ?: throw IOException("This folder is no longer available. Choose another folder.")
        if (!tree.exists() || !tree.isDirectory || !tree.canWrite()) {
            throw IOException("This folder is unavailable or read-only. Choose another folder.")
        }
        return tree
    }

    private fun exportFile(call: MethodCall): Map<String, Any> {
        val tree = writableTree(call.argument<String>("uri")!!)
        val source = File(call.argument<String>("path")!!).canonicalFile
        val cacheRoot = activity.cacheDir.canonicalFile.path + File.separator
        require(source.path.startsWith(cacheRoot) && source.isFile) { "The converted file is unavailable. Try again." }
        val requested = DocumentNames.sanitize(call.argument<String>("name") ?: "converted")
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        require(mime in setOf("image/jpeg", "image/png", "image/webp", "application/pdf")) { "This output format is not supported." }
        val name = DocumentNames.available(requested) { candidate -> tree.findFile(candidate) != null }
        val document = tree.createFile(mime, name)
            ?: throw IOException("The output file could not be created. Check the selected folder.")
        try {
            val written = resolver.openOutputStream(document.uri, "w")?.use { output ->
                source.inputStream().use { input -> input.copyTo(output, 64 * 1024) }
            } ?: throw IOException("The file could not be written to this folder.")
            if (written != source.length()) throw IOException("The file was not fully saved. Try again.")
            return mapOf("uri" to document.uri.toString(), "name" to (document.name ?: name),
                "mime" to mime, "bytes" to written)
        } catch (error: Exception) {
            // Only the document just created by this call may be removed.
            val removed = try { document.delete() } catch (_: Exception) { false }
            if (!removed) throw IOException("Saving failed. An incomplete file may remain in the selected folder.", error)
            throw error
        }
    }

    private fun openDocument(call: MethodCall, result: MethodChannel.Result) {
        background(result, deliverOnMain = { value ->
            val uri = Uri.parse(value as String)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, call.argument<String>("mime"))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newRawUri("FileKit document", uri)
            }
            try { activity.startActivity(intent); result.success(null) }
            catch (_: ActivityNotFoundException) { result.error("no_viewer", "No app is installed to open this file. You can share it instead.", null) }
            catch (_: Exception) { result.error("unavailable", "This file is no longer available.", null) }
        }) {
            val uri = Uri.parse(call.argument<String>("uri")!!)
            resolver.openAssetFileDescriptor(uri, "r")?.use { } ?: throw IOException("This file is no longer available.")
            uri.toString()
        }
    }

    private fun prepareShare(call: MethodCall): String {
        val uri = Uri.parse(call.argument<String>("uri")!!)
        require(uri.scheme == "content")
        val directory = File(activity.cacheDir, "filekit_share/${System.nanoTime()}")
        if (!directory.mkdirs()) throw IOException("A temporary copy could not be created. Check available storage.")
        val file = File(directory, DocumentNames.sanitize(call.argument<String>("name") ?: "converted"))
        try {
            resolver.openInputStream(uri)?.use { input -> file.outputStream().use { output -> input.copyTo(output) } }
                ?: throw IOException("This file is no longer available.")
        } catch (error: Exception) { file.delete(); directory.delete(); throw error }
        return file.absolutePath
    }

    private fun background(result: MethodChannel.Result, deliverOnMain: ((Any?) -> Unit)? = null, action: () -> Any?) {
        io.execute {
            try {
                val value = action()
                main.post { if (deliverOnMain != null) deliverOnMain(value) else result.success(value) }
            } catch (error: Exception) {
                val message = when (error) {
                    is SecurityException -> "Access to this folder was removed. Choose the folder again."
                    is IOException, is IllegalArgumentException -> error.message ?: "The file operation failed."
                    else -> "The file operation failed. Check the folder and available storage."
                }
                main.post { result.error("document_error", message, null) }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pendingPicker?.error("interrupted", "Folder selection was interrupted. Try again.", null)
        pendingPicker = null
        io.shutdown()
    }

    companion object {
        private const val REQUEST_DIRECTORY = 7321
    }
}
