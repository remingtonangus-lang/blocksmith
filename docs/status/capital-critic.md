# Alabaster blind critic: verified

First round (2026-10-16), gemini-flash-lite (flash ran out of its free daily quota), 11 of 16 shots from capital-shots at 24b07e6. Every defect claim was checked on the 1280x720 PNG:

- Clouds "voxel / blocky / dot-matrix" (7 shots): false. Edges are soft; low clouds near the horizon show faint horizontal striping (minor, real).
- vehicles_spawn "missing hull geometry, buried wheels": false; the white planes are the crawler's side armour, the wheels are hidden in grass.
- capital_noon "ruler-straight seam across the mountain": a road cut seen from 3 km (real geometry, reads as a line).
- capital_dusk "floating cone-shaped smear": the citadel searchlight beam (by design).
- White architecture "flat, unshaded, paper" (most city shots): taste, not a measured defect; stays on the list of look items.

Nothing found that is broken. The raw report follows.

Shots: shots for 24b07e617b

## capital_noon

Composition: 7, Lighting: 4, Materials: 3, Terrain: 4, Scale: 6, Technical: 3

- **Defects:**
  1. Upper left: The mountain range features an unnatural, ruler-straight horizontal seam running across the slope below the snow line.
  2. Upper middle/right: Clouds exhibit severe blocky voxelization/aliasing rather than soft volumetric rendering.
  3. Foreground/Midground: The white architectural surfaces lack ambient occlusion and directional shading, reading as flat, untextured paper rather than monumental white structures.
  4. Left middle: The transition between the grassy base of the mountain and the white ground plane is a harsh, unnatural line.
  5. Background right: The horizon line where the city meets the sea lacks proper atmospheric haze or fog, resulting in a sudden, sharp cutoff.
  6. Throughout the street grid: Roads lack curbs, sidewalks, and contextual details, appearing as simple grey textures stamped onto the white ground.

- **Biggest gap:** Implement physically-based directional lighting, ambient occlusion, and normal mapping on all white architectural surfaces to establish form and depth instead of flat, unshaded geometry.

## capital_dusk

Composition and readability: 5, Lighting and sky: 4, Materials and surfaces: 3, Terrain and vegetation: 4, Scale and atmosphere: 5, Technical artifacts: 2

- **Lower center to right**: A massive horizontal seam cuts across the entire lower portion of the image, sharply separating the city grid from the dark water surface below.
- **Upper center**: The volumetric clouds exhibit severe, heavy stippling and dot-matrix pixelation artifacts instead of smooth gradients.
- **Far left**: A floating, disjointed cone-shaped atmospheric smear or streak hovers in the mid-air between the mountains and the city.
- **Upper left**: The mountain range features hard, flat geometry with untextured, low-poly faces and harsh faceted edges against the sky.
- **Foreground streets**: Street lighting and grid edges suffer from intense, harsh aliasing and stair-stepping along every diagonal and orthogonal line.
- **Center-left background**: A solid, unnaturally dark black silhouette of a landmass or hill abruptly blocks out the base of the mountains without atmospheric perspective.

Biggest gap: Implement proper multi-pass anti-aliasing and depth-based atmospheric haze to eliminate harsh geometric jaggies and the flat black terrain blocking the background.

## capital_night

Composition and readability: 5 | Lighting and sky: 4 | Materials and surfaces: 3 | Terrain and vegetation: 4 | Scale and atmosphere: 5 | Technical artifacts: 4

- Upper left: Snow-capped mountains display harsh, faceted geometry resembling low-poly models rather than realistic, weathered alpine terrain.
- Upper sky: Cloud layers feature heavy, blocky voxel-like texturing and harsh stair-stepping artifacts, violating the physically based atmospheric requirement.
- Foreground to midground: Building facades lack material definition, reading as flat, repetitive grey surfaces without plausible architectural detail or ambient occlusion.
- Foreground roads: Street lighting produces hard-edged, uniform circular pools of light with no smooth falloff or global illumination interaction.
- Left and right foreground edges: Isolated trees appear unnaturally uniform, sparse, and lack realistic ground integration or shadow casting.
- Midground to horizon: The city layout exhibits rigid repetition and a flat, grid-like density distribution lacking organic urban variation.

Biggest gap: Replace the faceted mountain geometry and blocky voxel clouds with high-resolution displacement-mapped terrain and volumetric, physically-based cloud rendering.

## overview

Composition and readability: 6 | Lighting and sky: 5 | Materials and surfaces: 3 | Terrain and vegetation: 4 | Scale and atmosphere: 5 | Technical artifacts: 3

1. Upper left: Sky clouds exhibit severe voxelation and low-resolution blocky rasterization artifacts along their edges.
2. Center: The capital city footprint appears as a flat, uniform white disc lacking discernible individual architectural forms, towers, or shadows at this scale.
3. Lower left foreground: The terrain texture displays heavy repeating tiling patterns and harsh pixelation, failing to read as organic ground cover.
4. Upper right horizon: The ocean surface meets the sky with a muddy, uncalibrated color transition and lacks atmospheric haze or depth separation.
5. Center-left: The mountain range features unnaturally sharp, repetitive triangular peaks with flat, unshaded snow caps that look synthetic.
6. Lower left: The river channel is rendered as a flat, bright cyan strip with hard edges that do not blend naturally into the surrounding terrain.

Biggest gap: Replace the flat white city disc and blocky clouds with volumetric geometry and distance-based level-of-detail shading to eliminate voxel artifacts and establish credible architectural scale.

## mountains

Composition: 6 | Lighting: 4 | Materials: 2 | Terrain: 3 | Scale: 5 | Technical: 4

- **Upper right**: Clouds exhibit heavy, pixelated voxel stepping/aliasing along their edges against the sky.
- **Center background**: The mountain range features unnaturally sharp, vertical, wedge-shaped peaks with flat-shaded gray rock faces lacking micro-detail.
- **Midground**: Green-to-tan terrain textures show heavy repeating grid tiling and lack surface normal variation or displacement.
- **Lower center**: The river snakes through the valley with a flat, uniform light-blue emissive strip devoid of water shaders, refraction, or banks.
- **Lower foreground**: Forest coverage is rendered as flat, repetitive billboard patches scattered without density gradients or organic clustering.
- **Upper to lower left**: Terrain slopes display blown-out, unshaded white snow caps terminating in abrupt, straight horizontal lines without blending into the rock.

Biggest gap: Replace procedural low-resolution texturing and flat shading on terrain with PBR height-blended materials, and add a proper water shader to the valley river.

## forest_floor

Composition: 4, Lighting: 3, Materials: 2, Terrain/Vegetation: 2, Scale/Atmosphere: 3, Technical: 3

- Extreme left foreground: Trunk of a large tree is clipped flat by the screen edge, showing a plain dark brown texture without bark relief or shading gradient.
- Lower left: A low bush intersects the ground plane with a hard, unblended cut and lacks contact shadowing at the base.
- Center ground: Grass billboards are rigidly uniform in height and spacing, creating a repeating patterned carpet effect rather than organic growth.
- Mid-ground center: A thin-trunked tree stands completely ungrounded with zero ambient occlusion or grounding shadow where the trunk meets the soil.
- Upper right: Tree canopy foliage features harsh, flat white-to-green sprite cutouts with severe alpha sorting/clipping artifacts.
- Entire mid-to-far distance: Terrain features flat, low-resolution texture tiling with no atmospheric scattering haze to sell kilometre-scale depth.

Biggest gap: Replace flat billboard grass and unshaded sprites with volumetric, wind-affected grass tufts and layered foliage that feature proper terrain contact shadows and distance-based atmospheric haze.

## battle_ground

Composition: 4, Lighting: 3, Materials: 3, Terrain/Vegetation: 2, Scale/Atmosphere: 4, Artifacts: 3

- Upper left: The cloud texture features harsh, jagged pixelation and lacks soft volumetric layering, reading as a flat, distorted overlay.
- Center-right: Two stylized, low-poly palm trees stand out against the surrounding pine-heavy forest, breaking ecological and visual consistency.
- Mid-ground center and right: Multiple soldier figures appear ungrounded and lack distinct contact shadows, making them look like they are floating slightly above the terrain.
- Foreground and mid-ground: The grass blades are uniformly dense and lack variation in scale or distribution, exposing a rigid billboard layout and repetitive stamping.
- Background left ridge: The treeline transitions abruptly into a flat, tiled green texture with visible seams and uniform repetition across the slope.
- Entire image: The overall lighting lacks directional shadow casting and ambient occlusion, resulting in flat, unshaded surfaces that fail to define form.

Biggest gap: Implement per-pixel directional lighting with contact shadows and a robust atmospheric scattering model to give depth and volume to the flat landscape and sky.

## troops_lineup

Composition: 5/10 | Lighting: 4/10 | Materials: 2/10 | Terrain & Vegetation: 3/10 | Scale & Atmosphere: 4/10 | Technical Artifacts: 6/10

- Foreground (lower half): Grass blades appear as rigid, flat geometric cards with harsh, unshaded edges that lack any ground interaction or ambient occlusion.
- Center-left (midground, roadway): The flat grey road strip is completely untextured and lacks any surface detail, shoulder markings, or blending with the surrounding terrain.
- Center-right (fore-to-midground): The line of soldier models exhibits low-poly geometric rigidity and unshaded, flat-colored materials that fail to read as realistic military gear.
- Midground to background (center and left hills): The distant forest canopy features repetitive, low-detail billboard trees that lack volume or individual silhouette variation.
- Upper right (sky): Diagonal glowing trace lines terminate abruptly mid-air without context, smoke trails, or impact sources.
- Background horizon (upper left/center): The transition between the rolling hills and the sky lacks atmospheric perspective, showing uniform contrast and saturation at a distance.

Biggest gap: Replace the flat-colored, low-poly soldier models and rigid grass cards with PBR-shaded assets featuring realistic tactical gear, detailed textures, and proper ground contact shadows.

## vehicles_spawn

Composition: 4, Lighting: 4, Materials: 2, Terrain/Vegetation: 3, Scale/Atmosphere: 4, Technical: 2

- **Defects:**
  - Lower center: The foreground military vehicle has missing polygonal geometry, showing large horizontal white planes instead of a solid hull.
  - Lower center: The front wheels and undercarriage of the spawned vehicle are clipping into or buried within the flat terrain.
  - Mid-ground left to center: The white architectural towers feature harsh, unshaded flat white textures lacking proper ambient occlusion and form shading.
  - Lower center and right: The grass blades lack contact shadows, making the entire field look pasted onto the ground plane.
  - Far left and mid-ground: Trees on top of the mountain ridge and near the base of the towers are floating or penetrating geometry incorrectly.
  - Mid-ground right: A cluster of white angular structures on the runway-like area exhibits heavy aliasing and jagged geometry edges.

Biggest gap: Implement proper PBR surface shaders, ambient occlusion, and normal-mapped detailing on all white architectural assets to eliminate the flat, unshaded paper look.

## frigate_deck

Composition and readability: 4 | Lighting and sky: 5 | Materials and surfaces: 2 | Terrain and vegetation: 4 | Scale and atmosphere: 5 | Technical artifacts: 2

- **Defects:**
  - Center/upper-center: Frigate superstructure features severe clipping, overlapping geometry, and misaligned floating deck sections.
  - Right foreground: White hull panels and curved dome structure lack proper shading, ambient occlusion, and material depth, reading as flat, untextured geometry.
  - Center mast: The top of the mast and crossarm show jagged geometry and raw polygon edges without proper smoothing or detail.
  - Left mid-ground: Distant mountain terrain exhibits visible tiling, low-resolution textures, and a lack of coherent atmospheric perspective.
  - Lower center: Flight deck surface lacks runway markings, skid textures, or PBR material properties, appearing as blank unshaded grey polygons.
  - Upper sky: Cloud geometry features harsh, blocky volumetric silhouettes instead of soft, organic light-scattering.

- **Biggest gap:** Implement complete PBR shaders with normal maps, ambient occlusion, and proper lighting models on all frigate surfaces to replace the current unshaded flat-polygon aesthetic.

## coast

Composition and readability: 6 | Lighting and sky: 4 | Materials and surfaces: 3 | Terrain and vegetation: 4 | Scale and atmosphere: 5 | Technical artifacts: 3

- Heavy, blocky voxel-style stair-stepping visible along the edges of the cloud formations, upper left and upper right.
- Water surface texture in the foreground uses a repeating, high-contrast tile pattern that lacks natural wave scale transition into the distance.
- Extreme blown-out highlight glare on the left horizon where the sun meets the water and coastline.
- Distant mountain range in the upper right background lacks atmospheric perspective, appearing too sharp and dark against the haze.
- The Capital city silhouette in the mid-ground center reads as a flat, low-detail extrusion without distinct architectural form or shading.
- Harsh white jagged peaks on the mountains stand out as abrupt, unconvincing geometry against the dark slopes.

Biggest gap: Implement volumetric cloud smoothing and a coherent water shader with proper wave-scale attenuation and foam blending to remove the visible voxel artifacts and repeating tile patterns.

## road_bridge

Composition and readability: 5, Lighting and sky: 4, Materials and surfaces: 3, Terrain and vegetation: 4, Scale and atmosphere: 4, Technical artifacts: 3

1. Severe z-fighting and texture shimmering on the water surface in the center-left bay and bottom edge.
2. Hard, unnatural grid-like repetition and lack of blending on the flat green terrain textures in the middle ground.
3. Blocky, low-poly geometric mountains in the background lacking realistic organic contouring and high-frequency surface detail.
4. Unshaded, flat, low-poly tree assets scattered sparsely across the field on the right.
5. Severe screen-edge clamping and aliasing artifacts along the bottom boundary of the water plane.
6. Abrupt, harsh angle transition where the white bridge connects to the asphalt road on the right shore.

Biggest gap: Implement a water shader with surface normals, depth falloff, and anti-aliased shoreline blending to eliminate the current heavy texture swimming and flickering.

## fort_lumen

Composition and readability: 5, Lighting and sky: 4, Materials and surfaces: 3, Terrain and vegetation: 4, Scale and atmosphere: 5, Technical artifacts: 4

- Foreground (lower center to right): Individual tree trunks are stark vertical white cylinders lacking bark texture or proper ground contact shadows, appearing disconnected from the canopy and terrain.
- Midground center (Fort complex): The white exterior walls and structures lack ambient occlusion, normal detail, or micro-surface texture, making them read as flat unshaded clay or paper.
- Midground left (Meadow): Several small, isolated white patches float disconnected near the fort, resembling untextured or misplaced geometry.
- Background (Distant mountains): The mountain ridges feature harsh, repetitive high-frequency snow/rock textures with visible tiling and a lack of atmospheric scattering/haze to sell kilometre scale.
- Upper sky (Top center): The cloud layer exhibits low-resolution voxelated artifacts and abrupt hard-edged transitions rather than volumetric, soft-lit formations.
- Midground center-left (Road): The asphalt highway leading to the fort lacks shoulder detailing, line markings, or surface roughness, appearing as a flat grey ribbon pasted onto the terrain.

Biggest gap: Implement physically based material shaders with albedo, roughness, and normal maps on all architectural and terrain surfaces, replacing the flat unshaded white look with readable form through ambient occlusion and directional lighting.

## radar_night

Composition: 6 | Lighting: 3 | Materials: 2 | Terrain: 3 | Scale: 4 | Artifacts: 2

- **Upper background**: A harsh, unnatural horizontal orange-yellow band of light clips across the horizon between the dark mountains and night sky.
- **Center plateau**: The military installation floor and structures are rendered in flat, unshaded gray material with no surface detail, ambient occlusion, or texture maps.
- **Foreground right**: A massive glowing searchlight cone cuts through the air, but the source geometry near the base has missing contact shadows and looks pasted onto the mountain.
- **Center background**: The searchlight beams from the radar station point straight up into the sky as uniform gray semi-transparent capsules with zero volumetric light scattering or falloff.
- **Surrounding mountains**: The mountain ridges exhibit severe stair-stepping and low-poly faceted geometry without micro-relief, normal maps, or believable rock strata.
- **Lower right foreground**: The massive cliff edge lacks any atmospheric perspective, haze, or textural variation, resulting in a flat, ungrounded cut-out.

Biggest gap: Implement physically based lighting with volumetric fog, dynamic shadows, and textured material shaders across terrain and structures to eliminate the flat-shaded, ungrounded look.

## snow_peaks

Composition and readability: 5, Lighting and sky: 3, Materials and surfaces: 2, Terrain and vegetation: 3, Scale and atmosphere: 3, Technical artifacts: 3

- Flat paper appearance with no discernible subsurface scattering, specular glints, or crystalline texture across the entire snow surface.
- Blown highlights and lack of form-defining shadow gradients on the main summit ridge (upper center).
- Undefined, flat grey sky lacking volume, atmospheric perspective, or any believable meteorological cloud structure (upper left and background).
- Muddy, low-resolution procedural noise patches resembling dithering rather than realistic snow drift or rock outcrops (mid right face).
- Severe lack of scale cues; without contextual reference objects, the mountain reads as a small clay or plaster model.
- Sparse, poorly integrated dark vegetation sprites appearing as isolated blemishes rather than a coherent tree line (mid left slope).

Biggest gap: Implement a physically based snow material with micro-facet sparkle, proper ambient occlusion in crevices, and directional sunlight interaction to eliminate the flat plaster look.

## weapon_view

Composition and readability: 5, Lighting and sky: 4, Materials and surfaces: 2, Terrain and vegetation: 3, Scale and atmosphere: 3, Technical artifacts: 2.

1. Lower right: The first-person weapon model lacks textures, specular response, and normal details, reading as unshaded primitive geometry.
2. Foreground (bottom-left to center): The landing pad surface is completely flat and white with missing ambient occlusion and material definition.
3. Mid-ground (center): The six-wheeled crawler lacks ground contact shadows, making it appear to float slightly above the tarmac.
4. Mid-ground (right): The white architectural walls feature harsh, flat lighting without ambient occlusion or facade depth, violating the "never as flat paper" spec.
5. Horizon (mid-ground center): The segmented prefabricated walls exhibit visible gaps and disjointed intersections where individual modules meet.
6. Background (left): The sparse trees and green terrain slope transition lack atmospheric perspective and feature harsh, unblended asset placement.

Biggest gap: Implement physically based rendering materials, ambient occlusion, and directional shadow maps to replace the unshaded flat geometry and missing contact shadows across all surfaces.

