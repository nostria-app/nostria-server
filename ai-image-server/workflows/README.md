# ComfyUI workflows

## FLUX.1 img2img basic

`flux1-img2img-basic-api.json` is a ComfyUI API-format workflow for changing an input image with a text prompt. It uses the native FLUX.1 schnell files prepared by `scripts/download-model.sh flux1-schnell`:

- `models/diffusion_models/flux1-schnell.safetensors`
- `models/text_encoders/clip_l.safetensors`
- `models/text_encoders/t5xxl_fp8_e4m3fn.safetensors`
- `models/vae/ae.safetensors`

In ComfyUI, enable API-format workflow loading if needed, then load or paste the JSON. Replace the `LoadImage` image with your uploaded source image and edit both prompt strings in the positive `CLIPTextEncodeFlux` node.

The important control is `KSampler.denoise`:

- `0.25` to `0.45`: subtle edits, source image dominates.
- `0.55` to `0.75`: balanced image-to-image changes.
- `0.80` to `0.95`: prompt dominates, source structure may drift.

For FLUX.1 schnell, keep `cfg` near `1` and use `guidance` around `3.5` to `5.0`. More steps improve prompt following but are slow on CPU.

## Template library entries

The same starter workflows are also packaged under `comfyui-custom-nodes/nostria_templates/example_workflows` so ComfyUI can list them through its workflow template browser after that folder is installed into `custom_nodes` and ComfyUI is restarted.

- `flux1-img2img-basic-api.json`: local native FLUX.1 schnell img2img. This is the currently runnable local template.
- `flux2-img2img-basic-api.json`: FLUX.2 image edit starter using ComfyUI's hosted `Flux2MaxImageNode`; it requires Comfy/Flux API credentials in ComfyUI.
- `z-image-turbo-img2img-basic-api.json`: Z-Image-Turbo local starter using `TextEncodeZImageOmni`. This is included as a graph template, but this ComfyUI stack still needs a working native Z-Image model loader before it can execute locally without the deprecated `DiffusersLoader` failure.