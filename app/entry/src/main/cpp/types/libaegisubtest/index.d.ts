/* Aegisub core test harness + ASS reader (libaegisubtest.so) */

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

/** A new v4.00+ document with one default Dialogue line, as JSON. */
export const newAss: () => string;

/** Human-readable build identification. */
export const version: () => string;
