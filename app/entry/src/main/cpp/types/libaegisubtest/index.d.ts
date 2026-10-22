/* Aegisub core test harness + ASS/SRT reader + libass renderer */

export interface RenderedFrame {
  width: number;
  height: number;
  /** RGBA8, width*height*4 bytes. */
  pixels: ArrayBuffer;
}

export const runTests: (cacheDir: string, fixtureDir: string) => Promise<string>;
export const loadAss: (path: string) => string;
export const loadSrt: (path: string) => string;
export const newAss: () => string;
export const normalizeTime: (text: string) => string;
export const srtTime: (text: string) => string;
export const timeToMs: (text: string) => number;

/** Convert milliseconds to ASS time. */
export const msToTime: (ms: number) => string;

export interface FontListResult {
  ok: boolean;
  fonts?: string[];
  error?: string;
}

export interface WaveformResult {
  ok: boolean;
  sampleRate?: number;
  channels?: number;
  peaks?: number[];
  error?: string;
}

/** Compute PCM WAV peak buckets (0..1) for a waveform display. */
export const waveform: (path: string, buckets?: number) => string;

/** Enumerate font families via fontconfig. */
export const listFonts: (fontConfigPath: string) => string;

/** Render one ASS frame with libass into RGBA8. */
export const renderAss: (assPath: string, timeMs: number, width: number,
                         height: number, fontPath: string,
                         fontConfigPath: string) => RenderedFrame;

export const version: () => string;
