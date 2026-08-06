// Workaround for Xcode 16 / macOS 15 SDK linker issue with libghostty-fat.a
// where ___dso_handle cannot be resolved by the new linker.

void *__dso_handle = 0;
