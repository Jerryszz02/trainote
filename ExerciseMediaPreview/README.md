# Reproduce the free exercise sample

The shipped sample is only the ordinary push-up, catalog ID `0662`. It is intended
to make the animation interaction reviewable before selecting a full media library.
The app has no network or rendering dependency on this directory.

See [asset provenance](../Trainote/Resources/ExerciseMedia/EXERCISE-MEDIA-PROVENANCE.md)
for the source URL, checksum and licenses. Supply that downloaded GLB locally;
the scripts do not download assets or execute upstream scripts.

With Blender 5.2.1 and the macOS Swift toolchain:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python ExerciseMediaPreview/render_sample.py -- \
  --source /path/to/push_up.glb --output /tmp/trainote-sample
swift ExerciseMediaPreview/encode_sample.swift \
  /tmp/trainote-sample/frames /tmp/trainote-sample/push-up.mp4
```

Use `--preview` to render four sample poses. The encoder expects the full 72-frame
render, writes a new output file, and refuses to overwrite an existing output.
Review the resulting video, including floor contact and loop continuity, before
replacing the app's bundled sample. Copy frame `000.png` as `push-up-poster.png`.
