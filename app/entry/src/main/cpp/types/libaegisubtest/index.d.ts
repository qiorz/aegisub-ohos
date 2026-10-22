/* Aegisub core test harness + ASS/SRT reader (libaegisubtest.so) */

/**
 * Runs the full libaegisub gtest suite and returns a JSON summary.
 *
 * @param cacheDir   app cache directory; writable data/ and logs live here
 * @param fixtureDir extracted tests/ directory containing keyframe/, vfr/,
 *                   charset/, options/, lua/ (its parent must contain
 *                   automation/include/)
 */
export const runTests: (cacheDir: string, fixtureDir: string) => Promise<string>;

/**
 * Parse an ASS/SSA file and return a JSON document. Header/footer text is
 * preserved verbatim; the [Events] table is parsed using its Format line.
 */
export const loadAss: (path: string) => string;

/** Parse an SRT file into the same JSON document shape (import as ASS). */
export const loadSrt: (path: string) => string;

/** A new v4.00+ document with one default Dialogue line, as JSON. */
export const newAss: () => string;

/** Canonicalize a user-entered ASS time (e.g. "1:02.5" -> "0:00:01.02"). */
export const normalizeTime: (text: string) => string;

/** Format a time as SRT (e.g. "0:00:01.00" -> "00:00:01,000"). */
export const srtTime: (text: string) => string;

/** Convert an ASS time to milliseconds (for preview sync). */
export const timeToMs: (text: string) => number;

/** Human-readable build identification. */
export const version: () => string;
