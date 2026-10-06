# Surroundings streaming

At regional altitude the streamer samples the camera's terrain-aware view rays, pads the geographic footprint, and requests the whole visible rectangle. Longitude seam crops are split. The worker joins NASA Trek CTX tiles into one PNG before resampling, so internal WMTS tile edges are not rendered as rectangles. The atlas is installed alongside the bundled Viking base and is cross-faded while previous imagery remains available.

The surrounding source is `CTX_beta01_uncontrolled_5m_Caltech`, a preliminary visible mosaic. Its WMTS preparation is an imagery product only: it is not a height source, and its baked illumination and source calibration limitations are kept in the dataset metadata. Elevation continues to come from MOLA and verified regional products. Runtime imagery is cached under the existing 2 GiB disk cap and participates in the 512 MiB decoded budget.

Verification at Jezero (1920×1080) loaded eight source tiles into a padded `4.11° × 2.21°` footprint in 1.8 s from the warm cache, with a 238 m prepared pixel spacing. The same capture was written at 1600×900 and 1366×768. Cold online timings vary with NASA service latency; unavailable or partial coverage retains the prior imagery and reports that state in the HUD.

The same Jezero atlas is now bundled in `assets/terrain/ctx_jezero_view.png`, so the demonstration remains useful with `--planet-offline`. The offline verification loads it in about 1.3 s, without starting the worker.
