/// Hashing of bitboards for position keys and the transposition table.
enum Hashing {
    /// The finalizer of MurmurHash3: every bit of the input moves every bit of the output.
    @inline(__always)
    static func mix(_ value: UInt64) -> UInt64 {
        var x = value
        x ^= x >> 33
        x &*= 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33
        x &*= 0xC4CE_B9FE_1A85_EC53
        x ^= x >> 33
        return x
    }

    /// The key of a pair of bitboards: the side to move's discs and the other side's.
    @inline(__always)
    static func key(player: UInt64, opponent: UInt64) -> UInt64 {
        mix(player) ^ mix(opponent ^ 0x9E37_79B9_7F4A_7C15)
    }
}
