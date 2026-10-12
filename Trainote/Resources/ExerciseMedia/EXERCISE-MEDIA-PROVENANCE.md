# Offline exercise sample

The only bundled demonstration is catalog ID `0662`, **push-up / 俯卧撑**.
Other exercises and variants do not inherit this clip. This is an integration
sample, not a complete animated version of the 1,324-entry catalog.

## Source and permissions

- Published GLB: https://assiamahs.github.io/opengym3d/assets/push_up.glb
- Downloaded 2026-10-12; SHA-256:
  `67bfd1bf9c9c679dfd81f34202c661f954ce0ec4b15baac56a5781a372d11326`.
- Upstream repository inspected at
  `ea3a60130fdcfb3c4771e44d09f84ebab4ee9bae`:
  https://github.com/AssiamahS/opengym3d
- Its published manifest identifies this clip as `cc0`, `CC0-1.0`, `pack: true`.
  The asset registry identifies the MakeHuman/MPFB body and Mesh2Motion motion
  as CC0. It does not give that status to every exercise in the repository.
- MakeHuman's asset license: https://static.makehumancommunity.org/about/license.html
- Mesh2Motion's art/animation license: https://github.com/Mesh2Motion/mesh2motion-app
- OpenGym3D's MIT notice is retained in `EXERCISE-MEDIA-LICENSE.txt`.

No Mixamo animation, Gym Visual media, paid media, or remotely fetched media is
included. The app reads the rendered MP4 and poster from its bundle.

## Local processing

`ExerciseMediaPreview/render_sample.py` imports the source in Blender. It drops
an invalid empty morph-weight animation with no corresponding morph targets;
skeletal animation remains. It changes lighting/material contrast, corrects
the whole-body floor alignment to make hand and toe contact visible, and
renders a 3-second, 72-frame loop at 960 × 600. This timing is for display.

`ExerciseMediaPreview/encode_sample.swift` uses macOS AVFoundation to encode
H.264 MP4 without audio. The first rendered frame is the static poster.
The base motion is not an original Trainote motion capture or a professionally
validated coaching asset. Upstream QA and visual inspection are limited evidence;
they are not a substitute for form review before expanding the library.
