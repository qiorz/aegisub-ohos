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

/** Render one ASS frame with libass into RGBA8. */
export const renderAss: (assPath: string, timeMs: number, width: number,
                         height: number, fontPath: string) => RenderedFrame;

export const version: () => string;
