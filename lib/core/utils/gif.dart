import 'dart:typed_data';

/// Animated profile pictures (owner, 29.10.2026): a GIF is uploaded as it
/// is — never resized or cropped, which would keep only its first frame.

/// Same limit as the profile-media bucket (migration 0031).
const kGifMaxBytes = 5 * 1024 * 1024;

/// True for "GIF87a" / "GIF89a" files, whatever the file name or type says.
bool isGifBytes(Uint8List b) =>
    b.length >= 6 &&
    b[0] == 0x47 &&
    b[1] == 0x49 &&
    b[2] == 0x46 &&
    b[3] == 0x38 &&
    (b[4] == 0x37 || b[4] == 0x39) &&
    b[5] == 0x61;
