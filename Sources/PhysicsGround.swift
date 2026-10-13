import simd

// Realistic world, layer 3 (docs/design/realistic-world.md): what debris pieces and ragdolls collide with. The game
// implements it over the drawn surface (smooth ground where the world is smooth, the block boxes elsewhere); tests
// implement it with planes and boxes.
protocol PhysicsGround {
    // Contact of a point with the world's solid: nil in open space, else how deep the point is inside (blocks, >= 0)
    // and the unit outward surface normal there (the direction that pushes it out by the shortest way).
    func contact(_ p: SIMD3<Float>) -> (depth: Float, normal: SIMD3<Float>)?
}
