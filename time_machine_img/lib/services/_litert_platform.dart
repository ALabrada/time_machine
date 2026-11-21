/// Platform facade for the genuinely platform-specific part of
/// [TimelapseService]: bootstrapping the interpreter that runs the FILM
/// frame-interpolation graph.
///
/// The native and web interpreters cannot share an implementation:
///
/// * native: created from the cached model `File` with an XNNPACK delegate and
///   resized to the requested render resolution;
/// * web: created as a TF.js `GraphModel` from a hosted model.json (weight
///   shards fetched relative to it), which can **not** be resized and keeps
///   the model's own declared input shape (dynamic for FILM, so the caller
///   target is used in practice).
///
/// Both surfaces speak the shared [TimelapseInterpreter] contract — positional
/// float32 byte I/O via `runForMultipleInputs`/`getInputTensors`/
/// `resolveRenderSize`/`close` — so everything else in the timelapse pipeline
/// is platform-agnostic and lives in `timelapse_service.dart`.
library;

export 'timelapse_interpreter.dart' show TimelapseInterpreter, TimelapseTensor;

export '_litert_platform_web.dart'
    if (dart.library.io) '_litert_platform_io.dart'
    show openInterpreter;