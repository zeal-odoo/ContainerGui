# Quickstart: Verify Material 3 Motion

## Automated tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter Material3MotionAssetTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
node --test Tests/Frontend/*.mjs
git diff --check
```

## Browser acceptance

1. Open `http://127.0.0.1:8787/#main`.
2. Open and cancel Create, Pull and a non-mutating confirmation dialog; verify enter and exit motion.
3. Press Escape in Create/Pull and verify the same exit motion.
4. Open and close a container detail; collapse and expand local images.
5. Verify rapid repeated clicks do not leave a blocking backdrop.
6. Emulate reduced motion and repeat dialog/collapse checks.
7. Confirm console has no errors or warnings and no real mutation was submitted.
