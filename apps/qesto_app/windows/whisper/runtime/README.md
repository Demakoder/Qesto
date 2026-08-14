# Qesto offline speech runtime

This directory is populated by `../setup_runtime.ps1` with whisper.cpp 1.9.2
and the multilingual `small-q5_1` model. The downloaded binaries and model are
not committed to Git, but CMake bundles them into Windows builds when present.

Recognition runs locally. Recorded speech is not sent to a remote service.
