import Foundation

// DTO surfaced to the Settings → Pricing editor. Mirrors a row in
// `pricing_catalog` plus the metadata we render (note, official flag,
// LiteLLM provenance).

struct PricingCatalogRow: Sendable, Identifiable, Equatable {
    let modelId: String
    var id: String { modelId }
    let displayName: String
    let inputPrice: Double          // per million tokens, USD
    let cachedInputPrice: Double
    let outputPrice: Double
    let cacheCreationPrice: Double  // Claude-only (5x rate); 0 for OpenAI
    let isOfficial: Bool
    let note: String?
    let sourceUrl: String
    let updatedAt: String

    /// Provenance: 'seed' = bundled defaults, 'litellm' = fetched from
    /// BerriAI/litellm catalog, 'local' = user has hand-edited this row.
    let priceSource: String
    /// ISO-8601 timestamp of the last successful LiteLLM fetch (nil for seed
    /// or freshly-edited rows).
    let fetchedAt: String?
}
