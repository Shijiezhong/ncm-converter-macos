# Compatibility audit — v2.0.2

## Confirmed conversion blockers fixed

These inputs failed in v2.0.1 and now restore the original audio bytes:

1. MP3 with a valid trailing APEv2 tag, including the optional header and combined ID3v1 tags.
2. FLAC with an explicit 32-bit frame-header bit-depth code.
3. FLAC with a STREAMINFO sample rate above 655350 Hz, within the format's 20-bit range.
4. Source filenames near the filesystem name-length limit: the FLAC extension or collision suffix used to exceed it. Output names are shortened by UTF-8 code point without modifying sources.
5. MP3 without an ID3 header after extra container data. Recovery now recognizes a plausible pair of MPEG frames, then validates the entire stream.

Recognizable audio that fails integrity checks is not scanned again to silently discard its damaged beginning. MP3 tag sizes remain bounded; unknown trailing garbage is rejected.

## Validation performed

- **42 dependency-free checks** in `ConverterTest.java`; run `bash test.sh`.
- **52 independent libsndfile-encoded files**: 42 FLAC combinations covering 8/16/24-bit, mono/stereo and 8–192 kHz; 10 MP3 combinations covering mono/stereo and 8–48 kHz. All restore byte-for-byte without a regression.
- Three further edge fixtures (32-bit FLAC, 768 kHz FLAC, and a real encoder's MP3 plus APE tag) restore byte-for-byte: **55 compatibility files total**.
- Three privately held complete NCM music samples were converted and the results fully decoded by an independent decoder. No music or private filenames are included in this repository.
- A previously problematic private sample remains rejected rather than producing a misleading successful output.

The independent decoder used for this audit does not implement 32-bit FLAC. The 32-bit fixture is tested against the FLAC format layout, frame CRC and exact restored bytes; it has not been independently rendered to PCM. These results are evidence of the tested cases, not a guarantee for every possible NCM variant.

## Format references

- [RFC 9639 — FLAC](https://www.rfc-editor.org/rfc/rfc9639.html), especially STREAMINFO and frame bit-depth codes.
- [ID3v2.4 structure](https://id3.org/id3v2.4.0-structure).
- [TagLib APE footer implementation](https://github.com/taglib/taglib/blob/master/taglib/ape/apefooter.cpp) as a reference for APE tag layout. No TagLib code is included.
