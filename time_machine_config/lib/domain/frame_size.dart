String resolutionPClass(int frameSize) {
  return switch (frameSize) {
    256 => '144p',
    512 => '288p',
    _ => '432p',
  };
}