// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// `SplitMix64` is a pseudo-random generator that answers the same numbers for the same seed on every machine, in every run and with every toolchain.
///
/// It exists for property cases, whose sequences of events have to be drawn rather than written out and still be reproducible: a failure then names the seed that brings it back exactly, which a generator seeded by the system cannot offer.
/// It is Sebastiano Vigna's SplitMix64, chosen because it is a few lines long and spreads even consecutive small seeds over unrelated sequences.
/// It deliberately does not conform to `RandomNumberGenerator`, so no standard library algorithm, whose way of drawing from a range may change between releases, stands between a seed and the numbers it yields.
///
struct SplitMix64 {
    ///
    /// `state` is the counter each draw advances by the golden-ratio increment before mixing it into the number answered.
    ///
    private var state: UInt64

    ///
    /// `init(seed:)` starts the sequence `seed` stands for.
    ///
    init(seed: UInt64) {
        state = seed
    }

    ///
    /// `next()` answers the next number of the sequence, spread over the whole range of `UInt64`.
    ///
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15

        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB

        return mixed ^ (mixed >> 31)
    }

    ///
    /// `next(below:)` answers the next number of the sequence reduced to `0 ..< bound`, which has to be positive.
    ///
    /// The reduction is a plain remainder, whose bias towards smaller numbers is immeasurably small for bounds this far below 2⁶⁴.
    ///
    mutating func next(below bound: Int) -> Int {
        precondition(bound > 0, "A bound has to be positive.")

        return Int(next() % UInt64(bound))
    }
}
