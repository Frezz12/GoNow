import CryptoKit
import Foundation

actor MediaDataCache {
    static let shared = MediaDataCache()

    private let memoryCache = NSCache<NSString, NSData>()
    private let directory: URL
    private let maximumAge: TimeInterval
    private let maximumDiskBytes: Int64
    private let pruneInterval: TimeInterval
    private var inFlight: [String: Task<Data, Error>] = [:]
    private var lastPruneAt = Date.distantPast

    init(
        directory: URL? = nil,
        memoryLimit: Int = 48 * 1024 * 1024,
        diskLimit: Int64 = 512 * 1024 * 1024,
        maximumAge: TimeInterval = 60 * 60 * 24 * 7,
        pruneInterval: TimeInterval = 60 * 60 * 6
    ) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? caches.appendingPathComponent("GoNowMediaCache", isDirectory: true)
        self.maximumAge = maximumAge
        maximumDiskBytes = diskLimit
        self.pruneInterval = max(60, pruneInterval)
        memoryCache.totalCostLimit = memoryLimit
        memoryCache.countLimit = 96
        try? FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
    }

    func data(
        for key: String,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        schedulePruneIfNeeded()
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached as Data
        }
        if let cached = await diskData(for: key) {
            memoryCache.setObject(cached as NSData, forKey: key as NSString, cost: cached.count)
            return cached
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task<Data, Error> { try await loader() }
        inFlight[key] = task
        do {
            let data = try await task.value
            inFlight[key] = nil
            guard !data.isEmpty else { return data }
            await store(data, for: key)
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func store(_ data: Data, for key: String) async {
        guard !data.isEmpty else { return }
        memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        let fileURL = fileURL(for: key)
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }.value
    }

    func removeValue(for key: String) async {
        memoryCache.removeObject(forKey: key as NSString)
        inFlight[key]?.cancel()
        inFlight[key] = nil
        let fileURL = fileURL(for: key)
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: fileURL)
        }.value
    }

    func removeAll() async {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        memoryCache.removeAllObjects()
        let directory = directory
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }.value
        lastPruneAt = .distantPast
    }

    private func diskData(for key: String) async -> Data? {
        let fileURL = fileURL(for: key)
        let maximumAge = maximumAge
        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate,
                  Date().timeIntervalSince(modifiedAt) <= maximumAge,
                  let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                  !data.isEmpty else {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
            return data
        }.value
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(digest, isDirectory: false)
    }

    private func schedulePruneIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPruneAt) >= pruneInterval else { return }
        lastPruneAt = now
        let directory = directory
        let maximumAge = maximumAge
        let maximumDiskBytes = maximumDiskBytes
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { return }

            let now = Date()
            var retained: [(url: URL, date: Date, bytes: Int64)] = []
            for file in files {
                guard let values = try? file.resourceValues(forKeys: keys),
                      let date = values.contentModificationDate else {
                    try? fileManager.removeItem(at: file)
                    continue
                }
                if now.timeIntervalSince(date) > maximumAge {
                    try? fileManager.removeItem(at: file)
                    continue
                }
                retained.append((file, date, Int64(values.fileSize ?? 0)))
            }

            var totalBytes = retained.reduce(Int64.zero) { $0 + $1.bytes }
            for file in retained.sorted(by: { $0.date < $1.date }) where totalBytes > maximumDiskBytes {
                try? fileManager.removeItem(at: file.url)
                totalBytes -= file.bytes
            }
        }
    }
}
