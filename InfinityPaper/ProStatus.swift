import Foundation
import StoreKit
import SwiftUI
import Combine

@MainActor
final class ProStatus: ObservableObject {
    @Published private(set) var isPro: Bool = false

    private let proProductId = "infinitypaper.pro"
    private var updatesTask: Task<Void, Never>?
    private var products: [Product] = []

    init() {
        updatesTask = Task {
            await fetchProducts()
            await refreshEntitlements()
            await listenForTransactions()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refreshEntitlements() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == proProductId else { continue }
            guard transaction.revocationDate == nil else { continue }
            hasPro = true
            break
        }
        isPro = hasPro
    }

    func purchasePro() async -> Bool {
        await fetchProducts()
        guard let product = products.first(where: { $0.id == proProductId }) else { return false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return false }
                await transaction.finish()
                isPro = transaction.revocationDate == nil
                return isPro
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
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
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == proProductId else { continue }
            guard transaction.revocationDate == nil else {
                isPro = false
                continue
            }
            isPro = true
        }
    }

    private func fetchProducts() async {
        if products.isEmpty {
            do {
                products = try await Product.products(for: [proProductId])
            } catch {
                products = []
            }
        }
    }
}
