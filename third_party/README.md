# Third-party dependencies

| Package | Version | License | Source |
|---------|---------|---------|--------|
| libsamplerate | 0.2.2 | BSD-2-Clause | https://github.com/libsndfile/libsamplerate |
| libASPL | v3.1.2 | MIT | https://github.com/gavv/libASPL |

Vendored under `third_party/libsamplerate` (git tag `0.2.2`). After clone:

```bash
git submodule update --init third_party/libsamplerate
git submodule update --init third_party/libASPL
```

libASPL is checked out at tag **v3.1.2** for the HAL `APM44Bridge.driver` build.

If the submodule is absent, CMake FetchContent in `cmake/Libsamplerate.cmake` may populate the tree on configure.
