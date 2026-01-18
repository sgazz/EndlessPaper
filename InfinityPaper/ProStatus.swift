import Foundation
import StoreKit
import SwiftUI
import Combine
import os

enum PurchaseOutcome {
    case success
    case cancelled
    case pending
    case productNotFound
    case failed
}

@MainActor
final class ProStatus: ObservableObject {
    @Published private(set) var isPro: Bool = false

    private let proProductId = "infinitypaper.pro"
    private let productIds: Set<String> = ["infinitypaper.pro"]
    private var updatesTask: Task<Void, Never>?
    private var products: [Product] = []
    private let logger = Logger(subsystem: "InfinityPaper", category: "ProStatus")

    init() {
        start()
    }

    deinit {
        updatesTask?.cancel()
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            await loadProducts()
            await refreshEntitlements()
            await finishUnfinishedTransactions()
            await listenForTransactions()
        }
    }

    func refreshEntitlements() async {
        var hasPro = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIds.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            hasPro = true
            break
        }
        isPro = hasPro
    }

    func purchasePro() async -> PurchaseOutcome {
        await loadProducts()
        guard let product = products.first(where: { $0.id == proProductId }) else {
            logger.error("Pro product not found. Check App Store Connect product ID and TestFlight availability.")
            return .productNotFound
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return .failed }
                await handle(transaction: transaction)
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        } catch {
            logger.error("Purchase failed: \(String(describing: error))")
            return .failed
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            // Best-effort restore; ignore errors.
        }
        await refreshEntitlements()
    }

    private func listenForTransactions() async {
        for await result in StoreKit.Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await handle(transaction: transaction)
        }
    }

    private func finishUnfinishedTransactions() async {
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            await handle(transaction: transaction)
        }
    }

    private func handle(transaction: StoreKit.Transaction) async {
        guard productIds.contains(transaction.productID) else { return }
        if transaction.revocationDate != nil {
            isPro = false
            await transaction.finish()
            return
        }
        isPro = true
        await transaction.finish()
    }

    private func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let fetched = try await withTimeout(seconds: 5) {
                try await Product.products(for: Array(self.productIds))
            }
            products = fetched ?? []
            if products.isEmpty {
                logger.error("No StoreKit products returned for \(self.proProductId).")
            }
        } catch {
            logger.error("Failed to load products: \(String(describing: error))")
            products = []
        }
    }

    private func withTimeout<T>(
        seconds: Double,
        operation: @escaping () async throws -> T
    ) async throws -> T? {
        let task = Task { try await operation() }
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil as T?
        }
        let result = await task.result
        timeoutTask.cancel()
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}
