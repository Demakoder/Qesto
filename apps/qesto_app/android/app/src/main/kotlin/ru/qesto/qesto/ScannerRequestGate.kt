package ru.qesto.qesto

import java.util.concurrent.atomic.AtomicInteger

/** Single-flight native request ownership. Callbacks capture their own lease,
 * never read another request's Result. Release BEFORE delivering a terminal
 * result, so retries/reentrant callers are safe. No Android/financial state. */
internal class ScannerRequestGate<T> {
    class Request<T> internal constructor(val id: Int, internal val result: T)

    var current: Request<T>? = null
        private set
    var closed = false
        private set

    @Synchronized
    fun begin(result: T): Request<T>? {
        if (closed || current != null) return null
        // Unique within the process, including recreated Activities. Android's
        // legacy activity results allow 16-bit codes; don't reuse an old code.
        val id = nextId.getAndIncrement()
        if (id > 65535) {
            closed = true
            return null
        }
        return Request(id, result).also { current = it }
    }

    @Synchronized
    fun owns(request: Request<T>): Boolean = !closed && current === request

    fun complete(request: Request<T>, deliver: (T) -> Unit): Boolean {
        val result = synchronized(this) {
            if (closed || current !== request) return false
            current = null
            request.result
        }
        deliver(result)
        return true
    }

    fun close(deliver: (T) -> Unit) {
        val result = synchronized(this) {
            if (closed) return
            closed = true
            current?.result.also { current = null }
        }
        if (result != null) deliver(result)
    }

    private companion object {
        val nextId = AtomicInteger(5000)
    }
}
