# Planet foundation tests

Run from the project root with Godot 4.6:

```powershell
godot --headless --path . --script res://tests/planet/planet_foundation_test.gd
```

The process exits with code `0` and prints `PLANET_FOUNDATION_TEST_OK` when the face bases, conversions, edge continuity, `PatchId`, topology, patch neighbors and determinism contracts pass.
