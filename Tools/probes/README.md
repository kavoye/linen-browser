# Probes

These files measure the space slide. They are not part of the app target.

To use a probe:

1. Copy the file into `Linen/Interface/Sidebar/Spaces`.
2. For `SpaceBench`, call `SpaceBench.run(self)` in a `#if DEBUG` block at the end of `AppCoordinator+Bootstrap.swift`.
3. For `SpaceRollProbe`, call `begin` when a slide starts and `mark` at each step in `SpaceSlideController`.
4. Run a debug build with `LINEN_SPACE_BENCH=1`. Set `LINEN_BENCH_SWIPE=1` to drive swipes instead of switches.
5. Read the results with `/usr/bin/log stream --predicate 'subsystem == "com.kavoye.Linen" AND eventMessage CONTAINS "space"'`.
6. Remove the copy before you commit.
