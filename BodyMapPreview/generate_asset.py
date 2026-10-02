#!/usr/bin/env python3
"""Original Trainote body-map v1 profiles. No external geometry, textures or datasets.

Coordinates in metres: +Y up, +Z anterior; neutral A-pose; bilateral scores share a muscle ID.
Run from any directory to reproduce the JSON and its mesh-muscle map byte for byte.
The asset and this generator are licensed under the adjacent BodyMap/LICENSE.txt (MIT).
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Trainote/Resources/BodyMap"
meshes = []


def profile(name, muscle, values, facing=None, mirror=False):
    """Each tuple is (y, x, z, transverse radius, depth radius), bottom to top."""
    for side, sign in (("left", -1), ("right", 1)) if mirror else (("center", 1),):
        meshes.append({
            "name": f"{name}.{side}", "muscle": muscle, "facing": facing,
            "rings": [{"center": [round(x * sign, 5), y, z], "radius": [rx, rz]}
                      for y, x, z, rx, rz in values],
        })


# Neutral connective silhouette, head, hands and feet remain neutral at every score.
profile("neutral.torso", None, [
    (.85, 0, -.01, .095, .065), (.94, 0, 0, .172, .108),
    (1.06, 0, 0, .133, .084), (1.19, 0, -.005, .160, .092),
    (1.34, 0, 0, .226, .111), (1.44, 0, 0, .245, .102),
    (1.49, 0, 0, .212, .075), (1.53, 0, 0, .07, .057)])
profile("neutral.neck", None, [
    (1.48, 0, 0, .063, .049), (1.54, 0, 0, .053, .053),
    (1.61, 0, .004, .045, .049), (1.65, 0, .006, .054, .051)])
profile("neutral.head", None, [
    (1.613, 0, .025, .019, .023), (1.637, 0, .016, .054, .059),
    (1.678, 0, .005, .073, .075), (1.738, 0, 0, .081, .083),
    (1.803, 0, -.003, .076, .080), (1.845, 0, -.008, .053, .061),
    (1.862, 0, -.008, .002, .002)])
profile("neutral.nose", None, [
    (1.693, 0, .073, .011, .006), (1.708, 0, .083, .015, .024),
    (1.736, 0, .083, .008, .013), (1.766, 0, .074, .002, .002)])
profile("neutral.ear", None, [
    (1.681, .079, -.006, .004, .011), (1.711, .084, -.004, .011, .019),
    (1.739, .080, -.008, .004, .010)], mirror=True)
profile("neutral.upperArm", None, [
    (1.12, .363, 0, .037, .038), (1.20, .345, 0, .043, .043),
    (1.35, .299, 0, .056, .055), (1.45, .266, -.004, .048, .050)], mirror=True)
profile("neutral.forearm", None, [
    (.885, .438, .006, .024, .025), (.97, .414, .004, .030, .031),
    (1.07, .385, 0, .038, .041), (1.14, .362, 0, .036, .036)], mirror=True)
profile("neutral.palm", None, [
    (.805, .467, .005, .030, .016), (.834, .457, .005, .037, .021),
    (.877, .443, .005, .029, .024), (.91, .430, .005, .021, .024)], mirror=True)
for i in range(4):
    x = .442 + i * .016
    low = .747 + abs(1 - i) * .009
    profile(f"neutral.finger{i}", None, [
        (low, x + .024, .006, .004, .006), (low + .014, x + .020, .006, .008, .008),
        (.820, x, .005, .008, .009)], mirror=True)
profile("neutral.thumb", None, [
    (.803, .420, .031, .006, .006), (.828, .420, .025, .011, .011),
    (.858, .432, .015, .012, .014)], mirror=True)
profile("neutral.thigh", None, [
    (.495, .141, 0, .043, .045), (.58, .139, 0, .056, .060),
    (.74, .120, -.006, .075, .073), (.88, .095, -.003, .087, .078),
    (.99, .09, -.007, .072, .067)], mirror=True)
profile("neutral.lowerLeg", None, [
    (.08, .156, -.012, .025, .03), (.18, .153, -.01, .03, .032),
    (.32, .15, 0, .039, .042), (.44, .147, .005, .043, .045),
    (.525, .14, .006, .041, .043)], mirror=True)
profile("neutral.foot", None, [
    (.018, .158, .037, .038, .093), (.04, .158, .038, .046, .107),
    (.068, .157, .014, .038, .081), (.115, .155, -.015, .025, .034)], mirror=True)

# Anterior muscle volumes, shaped by distinct anatomical landmarks and insertions.
profile("chest.pectoralis", "chest", [
    (1.287, .082, .081, .024, .013), (1.322, .116, .102, .108, .045),
    (1.39, .125, .112, .122, .058), (1.443, .127, .097, .111, .042),
    (1.469, .177, .057, .054, .012)], facing=1, mirror=True)
profile("shoulders.deltoid", "shoulders", [
    (1.317, .299, .009, .018, .025), (1.368, .298, .011, .058, .069),
    (1.425, .282, .003, .072, .081), (1.475, .262, -.006, .055, .054),
    (1.49, .253, -.012, .018, .02)], facing=1, mirror=True)
profile("biceps.brachii", "biceps", [
    (1.146, .355, .027, .012, .012), (1.199, .344, .042, .032, .035),
    (1.263, .326, .046, .043, .043), (1.323, .307, .043, .037, .035),
    (1.382, .283, .032, .010, .012)], facing=1, mirror=True)
profile("triceps.brachii", "triceps", [
    (1.125, .363, -.023, .015, .015), (1.186, .347, -.042, .038, .034),
    (1.266, .325, -.051, .046, .038), (1.337, .304, -.045, .037, .035),
    (1.390, .283, -.026, .011, .014)], facing=-1, mirror=True)
profile("forearms.flexors", "forearms", [
    (.90, .430, .018, .010, .009), (.984, .412, .028, .025, .022),
    (1.057, .388, .034, .032, .028), (1.104, .374, .027, .024, .020),
    (1.13, .371, .019, .009, .010)], facing=1, mirror=True)
profile("forearms.extensors", "forearms", [
    (.901, .437, -.013, .009, .009), (.978, .422, -.024, .025, .020),
    (1.048, .398, -.032, .036, .024), (1.098, .375, -.028, .028, .021),
    (1.130, .363, -.020, .009, .010)], facing=-1, mirror=True)
for i, (bottom, top, x, width, z) in enumerate([
    (1.208, 1.308, .047, .040, .097), (1.110, 1.208, .042, .036, .089),
    (1.015, 1.110, .038, .033, .082), (.937, 1.015, .030, .025, .091),
]):
    profile(f"core.rectus{i}", "core", [
        (bottom, x, z, width * .55, .008),
        (bottom + (top - bottom) * .28, x, z, width, .022),
        (bottom + (top - bottom) * .72, x, z, width, .025),
        (top, x, z, width * .65, .009)], facing=1, mirror=True)
profile("core.oblique", "core", [
    (.95, .102, .063, .015, .012), (1.025, .111, .062, .032, .028),
    (1.12, .124, .059, .033, .032), (1.212, .156, .051, .038, .037),
    (1.289, .190, .036, .020, .021)], facing=1, mirror=True)
profile("quads.rectus", "quads", [
    (.527, .136, .030, .018, .014), (.610, .128, .049, .047, .039),
    (.743, .111, .054, .057, .047), (.876, .089, .052, .047, .036),
    (.951, .075, .031, .013, .013)], facing=1, mirror=True)
profile("quads.vastusLateralis", "quads", [
    (.551, .167, .02, .012, .014), (.650, .178, .019, .036, .059),
    (.785, .168, .015, .046, .070), (.899, .140, .022, .032, .048),
    (.956, .119, .017, .011, .014)], facing=1, mirror=True)
profile("quads.vastusMedialis", "quads", [
    (.517, .110, .031, .009, .009), (.567, .100, .049, .025, .034),
    (.632, .093, .049, .030, .039), (.722, .083, .036, .021, .026),
    (.788, .076, .017, .006, .008)], facing=1, mirror=True)

# Posterior volumes; all belong to the same eleven broad training groups, not separate scores.
profile("back.trapezius", "back", [
    (1.193, .024, -.093, .008, .01), (1.301, .065, -.103, .053, .028),
    (1.403, .112, -.097, .091, .036), (1.472, .122, -.069, .107, .031),
    (1.538, .050, -.043, .027, .020), (1.596, .029, -.041, .011, .009)],
    facing=-1, mirror=True)
profile("back.latissimus", "back", [
    (1.025, .056, -.054, .019, .011), (1.118, .108, -.073, .055, .032),
    (1.234, .146, -.087, .070, .039), (1.336, .170, -.090, .065, .041),
    (1.391, .195, -.074, .018, .014)], facing=-1, mirror=True)
profile("back.erector", "back", [
    (.98, .025, -.095, .011, .012), (1.065, .033, -.084, .020, .022),
    (1.18, .035, -.097, .023, .022), (1.294, .029, -.113, .009, .011)],
    facing=-1, mirror=True)
profile("glutes.maximus", "glutes", [
    (.798, .094, -.057, .026, .019), (.839, .099, -.075, .083, .069),
    (.904, .092, -.078, .095, .082), (.977, .088, -.071, .085, .065),
    (1.026, .072, -.047, .037, .019)], facing=-1, mirror=True)
profile("hamstrings.bicepsFemoris", "hamstrings", [
    (.502, .163, -.022, .011, .011), (.600, .163, -.051, .032, .033),
    (.728, .145, -.061, .047, .040), (.841, .123, -.059, .039, .030),
    (.886, .115, -.044, .014, .012)], facing=-1, mirror=True)
profile("hamstrings.semitendinosus", "hamstrings", [
    (.501, .111, -.028, .009, .011), (.631, .095, -.055, .024, .032),
    (.757, .076, -.060, .033, .032), (.837, .064, -.056, .026, .024),
    (.882, .069, -.04, .008, .009)], facing=-1, mirror=True)
profile("calves.gastrocnemiusMedial", "calves", [
    (.156, .151, -.020, .010, .010), (.253, .132, -.041, .024, .029),
    (.345, .125, -.044, .033, .042), (.428, .127, -.028, .030, .029),
    (.489, .132, -.016, .010, .01)], facing=-1, mirror=True)
profile("calves.gastrocnemiusLateral", "calves", [
    (.170, .16, -.013, .008, .010), (.280, .172, -.033, .023, .032),
    (.357, .179, -.038, .027, .035), (.424, .172, -.022, .024, .027),
    (.482, .162, -.011, .008, .01)], facing=-1, mirror=True)
profile("calves.soleus", "calves", [
    (.13, .164, -.008, .009, .013), (.232, .179, -.009, .020, .029),
    (.33, .188, -.009, .017, .038), (.393, .185, -.006, .008, .019)],
    facing=1, mirror=True)

OUT.mkdir(parents=True, exist_ok=True)
asset = OUT / "body-map-v1.json"
asset.write_text(json.dumps({"version": 1, "meshes": meshes}, ensure_ascii=False, separators=(",", ":")) + "\n")
mapping = {key: [m["name"] for m in meshes if m["muscle"] == key]
           for key in sorted({m["muscle"] for m in meshes if m["muscle"]})}
(OUT / "mesh-muscle-map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
print(f"{len(meshes)} meshes, {asset.stat().st_size} bytes, SHA256 {hashlib.sha256(asset.read_bytes()).hexdigest()}")
