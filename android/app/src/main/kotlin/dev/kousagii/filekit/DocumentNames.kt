package dev.kousagii.filekit

/** Name rules do not depend on Android and are exercised by JVM tests. */
object DocumentNames {
    fun sanitize(value: String): String = value.replace(Regex("[\\x00-\\x1F<>:\"/\\\\|?*]"), "_")
        .trim().trimEnd('.', ' ').take(160).ifEmpty { "converted" }

    fun available(requested: String, exists: (String) -> Boolean): String {
        if (!exists(requested)) return requested
        val dot = requested.lastIndexOf('.')
        val stem = if (dot > 0) requested.substring(0, dot) else requested
        val extension = if (dot > 0) requested.substring(dot) else ""
        for (index in 1..1000) {
            val name = "$stem ($index)$extension"
            if (!exists(name)) return name
        }
        // A provider is still responsible for choosing the actual created name.
        return "$stem (${System.nanoTime()})$extension"
    }
}
