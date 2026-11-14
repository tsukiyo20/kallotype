package com.kallo.app

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Size
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * The Kallo folder in MediaStore.
 *
 * The app owns `Pictures/Kallo`: it inserts marked PNG/JPEG files there, lists
 * that folder, and opens a content URI only when a marker has to be read or a
 * thumbnail has to be drawn. Android owns the pictures; the catalog owns the
 * records.
 */
class KalloMediaStore(
    private val activity: Activity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.kallo.app/library"
        private const val RELATIVE = "Pictures/Kallo"
        private const val RELATIVE_SLASH = "Pictures/Kallo/"
        private const val PICK_REQUEST = 0x4b41
        private const val MEDIA_REQUEST = 0x4b42
        private const val PICK_IMAGES_ACTION = "android.provider.action.PICK_IMAGES"
        private const val PICK_IMAGES_MAX = "android.provider.extra.PICK_IMAGES_MAX"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pendingPick: MethodChannel.Result? = null
    private var pendingOpen: MethodChannel.Result? = null

    fun attach() {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> open(result)
            "list" -> background(result) { list() }
            "save" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                if (path == null || name == null) {
                    result.error("bad_arguments", "save needs a path and a name", null)
                    return
                }
                background(result) { save(File(path), name) }
            }
            "materialize" -> {
                val locator = call.argument<String>("locator")
                if (locator == null) {
                    result.error("bad_arguments", "materialize needs a locator", null)
                    return
                }
                background(result) { materialize(Uri.parse(locator)) }
            }
            "thumbnail" -> {
                val locator = call.argument<String>("locator")
                val width = call.argument<Int>("width") ?: 512
                if (locator == null) {
                    result.error("bad_arguments", "thumbnail needs a locator", null)
                    return
                }
                background(result) { image(Uri.parse(locator), width) }
            }
            "image" -> {
                val locator = call.argument<String>("locator")
                val width = call.argument<Int>("width")
                if (locator == null) {
                    result.error("bad_arguments", "image needs a locator", null)
                    return
                }
                background(result) { image(Uri.parse(locator), width) }
            }
            "delete" -> {
                val locator = call.argument<String>("locator")
                if (locator == null) {
                    result.error("bad_arguments", "delete needs a locator", null)
                    return
                }
                background(result) {
                    activity.contentResolver.delete(Uri.parse(locator), null, null)
                    null
                }
            }
            "pick" -> pick(call.argument<Int>("limit") ?: 0, result)
            else -> result.notImplemented()
        }
    }

    private fun open(result: MethodChannel.Result) {
        if (hasMediaAccess()) {
            result.success(openPayload())
            return
        }
        if (pendingOpen != null) {
            result.error("busy", "the library is already opening", null)
            return
        }
        pendingOpen = result
        try {
            activity.requestPermissions(mediaPermissions(), MEDIA_REQUEST)
        } catch (error: Exception) {
            pendingOpen = null
            result.error("permission_failed", error.message, null)
        }
    }

    /// The folder belongs to the person, not only to Kallo: a picture another
    /// app puts in `Pictures/Kallo` is part of the library too. Reading it needs
    /// the platform's media permission; without it the app still imports and
    /// saves, but only sees the files it owns.
    private fun hasMediaAccess(): Boolean = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
            granted(Manifest.permission.READ_MEDIA_IMAGES) ||
                granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            granted(Manifest.permission.READ_MEDIA_IMAGES)
        else -> granted(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    private fun canListAll(): Boolean = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            granted(Manifest.permission.READ_MEDIA_IMAGES)
        else -> granted(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    private fun granted(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun mediaPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        )
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != MEDIA_REQUEST) return false
        val result = pendingOpen ?: return true
        pendingOpen = null
        result.success(openPayload())
        return true
    }

    private fun openPayload(): Map<String, Any> = mapOf(
        "root" to RELATIVE,
        "displayName" to RELATIVE,
        "supportPath" to activity.filesDir.absolutePath,
        "temporaryPath" to activity.cacheDir.absolutePath,
        "available" to true,
        "canListAll" to canListAll(),
    )

    private fun list(): List<Map<String, Any>> {
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_MODIFIED,
        )
        val selection =
            "(${MediaStore.Images.Media.RELATIVE_PATH} = ? OR " +
                "${MediaStore.Images.Media.RELATIVE_PATH} = ?)"
        val rows = mutableListOf<Map<String, Any>>()
        activity.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            arrayOf(RELATIVE_SLASH, RELATIVE),
            "${MediaStore.Images.Media.DATE_ADDED} ASC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val addedColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val uri = ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    id,
                )
                val width = cursor.getInt(widthColumn)
                val height = cursor.getInt(heightColumn)
                rows.add(
                    mapOf(
                        "locator" to uri.toString(),
                        "name" to (cursor.getString(nameColumn) ?: "print-$id.jpg"),
                        "width" to width,
                        "height" to height,
                        "size" to cursor.getLong(sizeColumn),
                        "created" to cursor.getLong(addedColumn) * 1000L,
                        "modified" to cursor.getLong(modifiedColumn) * 1000L,
                    ),
                )
            }
        }
        return rows
    }

    private fun save(file: File, name: String): String {
        if (!file.exists()) {
            throw IllegalArgumentException("the print is no longer there")
        }
        val mime = when (file.extension.lowercase()) {
            "png" -> "image/png"
            else -> "image/jpeg"
        }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(MediaStore.Images.Media.RELATIVE_PATH, RELATIVE)
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = activity.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore did not give the print a place")
        try {
            resolver.openOutputStream(uri)?.use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("MediaStore did not open the print")
            val ready = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            resolver.update(uri, ready, null, null)
            return uri.toString()
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun materialize(uri: Uri): String {
        val resolver = activity.contentResolver
        val mime = resolver.getType(uri)
        val ext = extensionFor(mime, uri)
        val target = File(activity.cacheDir, "kallo-${UUID.randomUUID()}.$ext")
        resolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("the print could not be read")
        return target.absolutePath
    }

    private fun image(uri: Uri, width: Int?): ByteArray {
        val resolver = activity.contentResolver
        if (width != null && width in 1..512) {
            try {
                val thumbnail = resolver.loadThumbnail(uri, Size(width, width), null)
                val bytes = thumbnail.compressBytes()
                thumbnail.recycle()
                if (bytes != null) return bytes
            } catch (_: Exception) {
                // Fall through to a decoder; some providers do not implement it.
            }
        }
        val source = ImageDecoder.createSource(resolver, uri)
        val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
            if (width != null && width > 0 && info.size.width > width) {
                decoder.setTargetSampleSize(maxOf(1, info.size.width / width))
            }
        }
        val bytes = bitmap.compressBytes()
        bitmap.recycle()
        return bytes ?: throw IllegalStateException("the print could not be rendered")
    }

    private fun Bitmap.compressBytes(): ByteArray? {
        val output = java.io.ByteArrayOutputStream()
        return if (compress(Bitmap.CompressFormat.JPEG, 90, output)) {
            output.toByteArray()
        } else {
            null
        }
    }

    private fun extensionFor(mime: String?, uri: Uri): String = when (mime) {
        "image/png" -> "png"
        "image/jpeg" -> "jpg"
        "image/webp" -> "webp"
        "image/heic", "image/heif" -> "heic"
        else -> uri.lastPathSegment?.substringAfterLast('.', "img") ?: "img"
    }

    // MARK: - The system picker

    private fun pick(limit: Int, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "the picker is already open", null)
            return
        }
        val picker = Intent(pickImagesAction()).apply {
            type = "image/*"
            if (limit <= 0 || limit > 1) {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        val multiple = limit != 1
        if (picker.action == PICK_IMAGES_ACTION) {
            val max = if (limit > 0) {
                limit
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                MediaStore.getPickImagesMaxLimit()
            } else {
                Int.MAX_VALUE
            }
            picker.putExtra(PICK_IMAGES_MAX, max)
        } else {
            picker.addCategory(Intent.CATEGORY_OPENABLE)
            if (multiple) {
                picker.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
        }
        pendingPick = result
        try {
            activity.startActivityForResult(picker, PICK_REQUEST)
        } catch (error: Exception) {
            pendingPick = null
            result.error("no_picker", error.message, null)
        }
    }

    private fun pickImagesAction(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return MediaStore.ACTION_PICK_IMAGES
        }
        val intent = Intent(PICK_IMAGES_ACTION).apply { type = "image/*" }
        return if (intent.resolveActivity(activity.packageManager) != null) {
            PICK_IMAGES_ACTION
        } else {
            Intent.ACTION_OPEN_DOCUMENT
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return true
        }
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let { uris.add(it) }
            }
        } else {
            data.data?.let { uris.add(it) }
        }
        background(result) {
            uris.mapNotNull { uri ->
                try {
                    copyPick(uri)
                } catch (_: Exception) {
                    null
                }
            }
        }
        return true
    }

    private fun copyPick(uri: Uri): String? {
        val resolver = activity.contentResolver
        val mime = resolver.getType(uri)
        // Keep the name the person knows. The copy lives in its own folder so
        // two pictures called `IMG_0001` never overwrite each other; the title
        // the catalog reads is the file's stem.
        val directory = File(activity.cacheDir, "kallo-pick-${UUID.randomUUID()}")
        if (!directory.mkdirs()) return null
        val name = pickName(uri, mime)
        if (mime == "image/png" || mime == "image/jpeg") {
            val target = File(directory, name)
            resolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            return target.absolutePath
        }
        val source = ImageDecoder.createSource(resolver, uri)
        val bitmap = ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
        }
        val jpeg = File(directory, "${name.substringBeforeLast('.')}.jpg")
        jpeg.outputStream().use { output ->
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 95, output)) {
                bitmap.recycle()
                return null
            }
        }
        bitmap.recycle()
        return jpeg.absolutePath
    }

    private fun pickName(uri: Uri, mime: String?): String {
        val display = runCatching {
            activity.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull()
        val stem = sanitizeStem(display?.substringBeforeLast('.'))
        val extension = if (mime == "image/png") "png" else "jpg"
        return "$stem.$extension"
    }

    private fun sanitizeStem(value: String?): String {
        val cleaned = value.orEmpty()
            .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "-")
            .trim()
            .trim('.')
            .take(80)
            .trim()
        return cleaned.ifBlank { "print" }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("library_error", error.message ?: "the library failed", null)
                }
            }
        }.start()
    }
}
