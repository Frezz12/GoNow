package frezzy.gonow.core

import kotlinx.coroutines.CancellationException

fun Throwable.throwIfCancellation() {
    if (this is CancellationException) throw this
}

inline fun <T> cancellableRunCatching(block: () -> T): Result<T> = try {
    Result.success(block())
} catch (error: Throwable) {
    error.throwIfCancellation()
    Result.failure(error)
}
