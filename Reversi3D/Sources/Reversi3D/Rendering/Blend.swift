import Metal

/// How a pipeline's output combines with what the target holds.
enum Blend {
    case none
    /// Over what is there, by the output's alpha.
    case alpha
    /// Added to what is there.
    case additive

    func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .none:
            attachment.isBlendingEnabled = false
        case .alpha:
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .additive:
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
        }
    }
}
