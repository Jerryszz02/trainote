# Native anatomy illustrations and masks

Source: https://github.com/crmapache/js-rich-body-highlighter
Pinned revision: `107dafe86f91298d66a41ff1c7b7251b073983d8`
License: MIT, full upstream text in `ANATOMY-LICENSE.txt`.

`anatomy-front.png` and `anatomy-back.png` are unchanged source illustrations from
`assets-src/01_male_front_white_transparent.png` and
`assets-src/02_male_back_white_transparent.png` respectively.

`anatomy-masks.json` is generated from male entries in `src/data/muscles/front.ts`
and `back.ts`. SVG relative and smooth cubic commands are converted to absolute
native path commands; offset pixels are converted at 25.4/96 viewBox units.
`abs`/`obliques` map to core; `lats`/`upper_back`/`lower_back` map to back.
The illustration viewBox is 361.15625 × 541.8666667.
Run `python3 BodyMapPreview/import_anatomy.py` to reproduce the import.

Runtime uses bundled PNG files and native Core Graphics paths, with no JavaScript,
WebView, network dependency, or inference of recovery scores. Unknown areas retain
neutral artwork, supplied recovery values tint masks, restrictions have an amber
dashed outline, and selection has a solid outline. The original 3D asset and its
license remain unchanged for the optional rotation mode.
