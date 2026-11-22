package dev.kousagii.filekit

import org.junit.Assert.assertEquals
import org.junit.Test

class DocumentNamesTest {
    @Test fun uniqueNamesKeepTheirExtensionAndSkipExistingSuffices() {
        val existing = setOf("image.jpg", "image (1).jpg", "image (2).jpg")
        assertEquals("image (3).jpg", DocumentNames.available("image.jpg") { it in existing })
    }
    @Test fun unusedNameIsNotChanged() {
        assertEquals("report.pdf", DocumentNames.available("report.pdf") { false })
    }
    @Test fun dangerousPathCharactersCannotCreateDirectories() {
        assertEquals(".._private_image.png", DocumentNames.sanitize("../private:image.png"))
    }
    @Test fun emptyOrTrailingDotNamesAreSafe() {
        assertEquals("converted", DocumentNames.sanitize(" ... "))
        assertEquals("photo", DocumentNames.sanitize("photo. "))
    }
}
