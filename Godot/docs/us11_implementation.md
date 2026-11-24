# US11 implementation status

- Owners: Bohdan and Vansh
- Updated: Nov. 24, 2026

The original completion plan is superseded by the living [US11 story](user_stories/US11.md), which records acceptance criteria, implementation evidence, validation results, and remaining work. See the [camera component guide](us8_components.md#camera-observations) for the supported capture contract and the [camera target example](../examples/camera_target/README.md) for Python training and ONNX inference instructions.

The camera target example and training/export pipeline are implemented. The story records a real-camera Python smoke run and inference coverage; this demonstrates pipeline operation, not successful policy learning. A fully trained and evaluated camera policy, pixel conversion performance work, and broader renderer/platform/package validation remain tracked in the story.

US11 retains latest-completed-frame capture for training and inference. Observations can precede the current action, multiple steps can reuse a frame, and reset observations can contain an image from the previous episode. The delay is not guaranteed to be exactly one frame or physics tick. Fresh post-action or post-reset images are not guaranteed by this mode.

An optional render-synchronized lifecycle is deferred beyond US11 to a future user story. Its scope is recorded in [future opportunities](user_stories/remaining.md); it is not a prerequisite for completing US11.
