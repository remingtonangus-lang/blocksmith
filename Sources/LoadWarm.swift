import Foundation

// Store review (Nov 2, callgrind of the frame soak): the per-block-state tables built lazily by string tests over every
// state cost their first user a frame in the middle of play: the first blast built Explosion.valuable (80 ms on the
// host), the first building check Structure.member (65 ms), the crawler's first pass its soft blocks, the first torch
// the ambient emitters. All of them are built at load now, with MobManager.warmTables (Dimension.init).
enum LoadWarm {
    static func tables() {
        _ = Structure.member; _ = Structure.grows
        _ = Game.emitters
        _ = BorealStation.powerOff
        _ = BrandChapterhouse.floor
        _ = CapitalBase.leafTable
        _ = CapitalBase.logTable
        _ = Capital.crawlerSoft
        _ = ShipManager.groundBlock
        _ = ShipManager.rutGround
        _ = ChestJoin.joinable
        _ = Circuit.kinds
        _ = Circuit.woolTable
        _ = Circuit.glazedTable
        _ = DeepSeal.natural
        _ = Explosion.valuable
        _ = Game.hardened
        _ = FarCitadel.tones
        _ = FieldTerrain.loose
        _ = FieldTerrain.gardenSoil
        _ = FreeBuild.wallMaterial
        _ = Greywall.scanKinds
        _ = GroundDrape.seat
        _ = World.restsOnFloor
        _ = GroundSettle.fallSkip
        _ = StructWriter.notGround
        _ = HellGate.keep
        _ = LightHalos.color
        _ = Mesher.detailT
        _ = Mesher.bevelT
        _ = Mesher.iceT
        _ = Mesher.leafT
        _ = Mesher.farPlantT
        _ = Mob.earth
        _ = NaturalCensus.natural
        _ = NaturalCensus.bulkShare
        _ = PathFinder.doorTable
        _ = PathFinder.woodDoorTable
        _ = Railways.clearable
        _ = Roads.natural
        _ = ShapeClass.legacyGround
        _ = ShapeClass.kind
        _ = ShapeClass.family
        _ = ShapeRails.isRail
        _ = ShapeRails.isPowered
        _ = ShapeRails.bedKinds
        _ = ShapeTrunks.axisOf
        _ = ShapeTrunks.isRoot
        _ = ShapeTrunks.isLog
        _ = ShipParts.kinds
        _ = ShipParts.wool
        _ = ShipParts.console
        _ = ShipParts.track
        _ = ShipParts.mass
        _ = ShipParts.natural
        _ = SmoothTerrain.pins
        _ = SmoothTerrain.pinsDetail
        _ = SmoothTerrain.rockSlot
        _ = SmoothTerrain.blend
        _ = Structure.helm
        _ = StructWriter.soilPlant
        _ = StructWriter.soil
        _ = TownLaw.property
        _ = CannonCalibre.boreT
        _ = VillageLife.bedHead
        _ = VillageLife.bedAny
        _ = World.fallingIDs
        _ = World.wetFloor
        _ = WorldGen.isOre
        _ = WorldObjects.candidate
        _ = WorldObjects.isPost
        _ = WorldObjects.isLight
        _ = GameBlocks.sculkIDs
        _ = AudioState.kindTable
    }
}
