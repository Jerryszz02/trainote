# Original Trainote body-map asset v1

- Created: 2026-10-03 (Asia/Shanghai).
- Author/source: Trainote contributors, this repository's `BodyMapPreview/generate_asset.py`.
- Source repository: https://github.com/Jerryszz02/trainote
- Acquisition: generated locally from original numerical profiles; no asset download or purchase.
- License: [MIT](LICENSE.txt); free commercial use, modification and redistribution with this notice.
- Included asset: `body-map-v1.json`, 74 named closed muscle/connective volumes, 23,298 bytes.
- SHA-256: `6191358fa3a17a54df1ebed45440203850e173db4d67eca854315e299d9c41e9`.
- Muscle assignment: [mesh-muscle-map.json](mesh-muscle-map.json); each named mesh has one broad training muscle ID, left/right share that ID and score. Neutral head, neck, joints, hands and feet have no score.

The generator defines elliptical cross-section control profiles in metres (+Y up, +Z anterior),
mirrors bilateral geometry, and writes deterministic JSON. `BodyMapGeometry` interpolates those
profiles with Catmull–Rom curves, triangulates closed volumes and calculates area-weighted normals.
There are no textures, rig, remote URLs, runtime downloads, extra frameworks or commercial packages.
Regenerate with `python3 BodyMapPreview/generate_asset.py` from the repository root.

This is a stylized, original volumetric anatomical illustration with separate pectoral, deltoid,
upper-arm, forearm, abdominal, dorsal, gluteal, quadriceps, hamstring and calf structures. It is not
a scan of a person, a clinical anatomy reference, or evidence for recovery-score accuracy. Submeshes
provide recognizable shape, not separate small-muscle or left/right physiological measurements.
The exercise catalog's text license was not used to license this asset.
