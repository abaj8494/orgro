package com.madlonkay.orgro

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val TAG = "OrgroNativeDirectory"

suspend fun handleNativeDirectoryMethod(
    call: MethodCall,
    result: MethodChannel.Result,
    context: Context
) = withContext(Dispatchers.Main) {
    try {
        when (call.method) {
            "listDirectory" -> {
                val dirIdentifier = call.argument<String>("dirIdentifier")
                if (dirIdentifier == null) {
                    result.error(
                        "MissingArg",
                        "Required argument missing",
                        "${call.method} requires 'dirIdentifier'"
                    )
                    return@withContext
                }
                result.success(listDirectory(dirIdentifier, context))
            }
            else -> result.error("UnsupportedMethod", "${call.method} is not supported", null)
        }
    } catch (e: Exception) {
        Log.e(TAG, "Error in ${call.method}", e)
        result.error("ExecutionError", e.toString(), null)
    }
}

/**
 * List the contents of a directory.
 *
 * @param dirIdentifier URI string identifying the directory (SAF tree URI)
 * @param context Android context
 * @return List of maps containing file/directory info
 */
suspend fun listDirectory(
    dirIdentifier: String,
    context: Context
): List<Map<String, Any>> = withContext(Dispatchers.IO) {
    val entries = mutableListOf<Map<String, Any>>()
    val dirUri = Uri.parse(dirIdentifier)

    val parentDocumentId = when {
        DocumentsContract.isDocumentUri(context, dirUri) ->
            DocumentsContract.getDocumentId(dirUri)
        else ->
            DocumentsContract.getTreeDocumentId(dirUri)
    }

    val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(dirUri, parentDocumentId)

    Log.d(TAG, "Listing directory: $dirIdentifier")
    Log.d(TAG, "Children URI: $childrenUri")

    context.contentResolver.query(
        childrenUri,
        arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        ),
        null,
        null,
        null
    )?.use { cursor ->
        val idColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        val nameColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        val mimeColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

        while (cursor.moveToNext()) {
            val documentId = cursor.getString(idColumn)
            val name = cursor.getString(nameColumn)
            val mime = cursor.getString(mimeColumn)
            val isDirectory = DocumentsContract.Document.MIME_TYPE_DIR == mime

            // Build a tree+document URI for this entry
            val uri = DocumentsContract.buildDocumentUriUsingTree(dirUri, documentId)

            Log.d(TAG, "Found: $name (isDir=$isDirectory, mime=$mime)")

            entries.add(
                mapOf(
                    "name" to name,
                    "identifier" to uri.toString(),
                    "uri" to uri.toString(),
                    "isDirectory" to isDirectory
                )
            )
        }
    }

    Log.d(TAG, "Found ${entries.size} entries")
    entries
}
