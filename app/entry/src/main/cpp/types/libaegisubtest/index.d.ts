/* Aegisub core test harness (libaegisubtest.so) */

/**
 * Runs the full libaegisub gtest suite and returns a JSON summary.
 *
 * @param cacheDir   app cache directory; writable data/ and logs live here
 * @param fixtureDir extracted tests/ directory containing keyframe/, vfr/,
 *                   charset/, options/, lua/ (its parent must contain
 *                   automation/include/)
 */
export const runTests: (cacheDir: string, fixtureDir: string) => Promise<string>;

/** Human-readable build identification. */
export const version: () => string;
