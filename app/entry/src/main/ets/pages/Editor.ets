/*
 * Aegisub OHOS -- first ArkUI shell.
 *
 * ASS/SSA/SRT editor shell: parse with libaegisub's agi::Time (native
 * ass_lite.cpp), edit events/styles, preview video/audio, export ASS/SRT and
 * export an application log. The old gtest page was removed in v0.1.2.
 */
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import aegisub from 'libaegisubtest.so';

const TAG = 'AegisubEditor';
const APP_VERSION = '0.1.5';

interface AssEvent {
  kind: string;
  fields: string[];
  startMs: number;
  endMs: number;
}

interface AssStyleEntry {
  fields: string[];
}

interface WaveformResult {
  ok: boolean;
  sampleRate?: number;
  channels?: number;
  peaks?: number[];
  error?: string;
}

interface FontListResult {
  ok: boolean;
  fonts?: string[];
  error?: string;
}

interface RenderedFrame {
  width: number;
  height: number;
  pixels: ArrayBuffer;
}

interface EditorSnapshot {
  events: AssEvent[];
  styleEntries: AssStyleEntry[];
  selected: number;
  styleSelected: number;
}

interface AssDoc {
  ok: boolean;
  error?: string;
  header?: string;
  footer?: string;
  eol?: string;
  bom?: boolean;
  format?: string[];
  startIndex?: number;
  endIndex?: number;
  textIndex?: number;
  styles?: string[];
  events?: AssEvent[];
  styleSection?: string;
  stylePrefix?: string;
  styleSuffix?: string;
  styleFormat?: string[];
  styleEntries?: AssStyleEntry[];
}

function stamp(): string {
  const d = new Date();
  const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-` +
         `${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

@Entry
@Component
struct Editor {
  @State fileName: string = '';
  @State assPath: string = '';
  @State status: string = '打开 .ass/.ssa，或新建一个字幕';
  @State hasDoc: boolean = false;
  @State events: AssEvent[] = [];
  @State format: string[] = [];
  @State styles: string[] = [];
  @State startIndex: number = 1;
  @State endIndex: number = 2;
  @State textIndex: number = 9;
  @State selected: number = -1;
  @State editStart: string = '';
  @State editEnd: string = '';
  @State editStyle: string = '';
  @State editText: string = '';
  @State editKind: string = 'Dialogue';
  @State editLayer: string = '0';
  @State editActor: string = '';
  @State editMarginL: string = '0';
  @State editMarginR: string = '0';
  @State editMarginV: string = '0';
  @State editEffect: string = '';
  @State showAdvanced: boolean = false;
  @State filterText: string = '';
  @State showAudio: boolean = false;
  @State audioName: string = '';
  @State audioPath: string = '';
  @State audioStatus: string = '选择音频做打轴';
  @State audioDuration: number = 0;
  @State audioPlaying: boolean = false;
  @State waveformPeaks: number[] = [];
  @State waveformStatus: string = '';
  @State showStyles: boolean = false;
  @State styleSection: string = '';
  @State stylePrefix: string = '';
  @State styleSuffix: string = '';
  @State styleFormat: string[] = [];
  @State styleEntries: AssStyleEntry[] = [];
  @State styleSelected: number = -1;
  @State editFont: string = '';
  @State editSize: string = '';
  @State editPrimary: string = '';
  @State editOutline: string = '';
  @State editStyleName: string = '';
  @State editBold: string = '0';
  @State editItalic: string = '0';
  @State editAlign: string = '2';
  @State editOutlineWidth: string = '2';
  @State dirty: boolean = false;
  @State canUndo: boolean = false;
  @State canRedo: boolean = false;
  @State showVideo: boolean = false;
  @State videoPath: string = '';
  @State videoUri: string = '';
  @State videoName: string = '';
  @State videoStatus: string = '选择 MP4/MKV/TS 预览字幕';
  @State currentMs: number = 0;
  @State videoDuration: number = 0;
  @State activeText: string = '';
  @State subtitleImage: image.PixelMap | undefined = undefined;
  @State renderStatus: string = '';
  @State autoStyled: boolean = false;
  @State systemFonts: string[] = [];
  @State fontOptions: SelectOption[] = [];
  @State fontSelected: number = -1;
  @State fontListStatus: string = '';

  private header: string = '';
  private fontConfigPath: string = '';
  private logLines: string[] = [];
  private fontsReady: boolean = false;
  private footer: string = '';
  private eol: string = '\n';
  private bom: boolean = false;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private undoStack: EditorSnapshot[] = [];
  private redoStack: EditorSnapshot[] = [];
  private videoController: VideoController = new VideoController();
  private audioPlayer: media.AVPlayer | undefined = undefined;
  private renderBusy: boolean = false;
  private lastAutoRender: number = 0;

  aboutToAppear(): void {
    this.addLog(`app start v${APP_VERSION}`);
    this.newAss();
  }

  private fontFileSize(name: string): number {
    try {
      return fs.statSync(`${this.ctx.cacheDir}/aegisub-fonts/${name}`).size;
    } catch (e) {
      return -1;
    }
  }

  private addLog(msg: string): void {
    const d = new Date();
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    const ts = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
      `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
    this.logLines.push(`[${ts}] ${msg}`);
    if (this.logLines.length > 300) {
      this.logLines.shift();
    }
    hilog.info(0xFF01, TAG, '%{public}s', msg);
  }

  async exportLog(): Promise<void> {
    this.addLog('exportLog requested');
    try {
      const dir = `${this.ctx.filesDir}/logs`;
      try {
        fs.mkdirSync(dir, true);
      } catch (e) {
        // exists
      }
      const path = `${dir}/aegisub-${stamp()}.log`;
      const text = `Aegisub OHOS v${APP_VERSION}\n` +
        `time: ${new Date().toISOString()}\n` +
        `file: ${this.fileName}\npath: ${this.assPath}\n` +
        `hasDoc: ${this.hasDoc}, dirty: ${this.dirty}, ` +
        `events: ${this.events.length}, styles: ${this.styleEntries.length}\n` +
        `video: ${this.videoPath}\naudio: ${this.audioPath}\n` +
        `fontConfig: ${this.fontConfigPath}\n` +
        `fonts: DejaVu=${this.fontFileSize('DejaVuSans.ttf')}, ` +
        `CJK=${this.fontFileSize('DroidSansFallbackFull.ttf')}\n` +
        `status: ${this.status}\n` +
        '---- log ----\n' + this.logLines.join('\n') + '\n';
      this.writeText(path, text);
      const opt = new picker.DocumentSaveOptions();
      opt.newFileNames = [`aegisub-${stamp()}.log`];
      opt.fileSuffixChoices = ['.log', '.txt'];
      const doc = new picker.DocumentViewPicker(this.ctx);
      const uris = await doc.save(opt);
      if (!uris || uris.length === 0) {
        return;
      }
      const n = this.writeToUri(path, uris[0]);
      this.status = `日志已导出：${n} 字节 → ${uris[0]}`;
      promptAction.showToast({ message: '日志已导出', duration: 2000 });
    } catch (e) {
      this.status = `日志导出失败：${JSON.stringify(e)}`;
      this.addLog(`exportLog failed: ${JSON.stringify(e)}`);
    }
  }

  private styleIndex(): number {
    return this.format.findIndex((v: string) => v.toLowerCase() === 'style');
  }

  private cloneEvents(src: AssEvent[]): AssEvent[] {
    const out: AssEvent[] = [];
    for (const e of src) {
      out.push({
        kind: e.kind,
        fields: e.fields.slice(),
        startMs: e.startMs,
        endMs: e.endMs
      });
    }
    return out;
  }

  private cloneStyles(src: AssStyleEntry[]): AssStyleEntry[] {
    const out: AssStyleEntry[] = [];
    for (const st of src) {
      out.push({ fields: st.fields.slice() });
    }
    return out;
  }

  private snapshot(): EditorSnapshot {
    return {
      events: this.cloneEvents(this.events),
      styleEntries: this.cloneStyles(this.styleEntries),
      selected: this.selected,
      styleSelected: this.styleSelected
    };
  }

  private pushUndo(): void {
    this.undoStack.push(this.snapshot());
    if (this.undoStack.length > 50) {
      this.undoStack.shift();
    }
    this.redoStack = [];
    this.canUndo = this.undoStack.length > 0;
    this.canRedo = false;
    this.dirty = true;
  }

  private resetHistory(): void {
    this.undoStack = [];
    this.redoStack = [];
    this.canUndo = false;
    this.canRedo = false;
    this.dirty = false;
  }

  private restoreSnapshot(s: EditorSnapshot): void {
    this.events = this.cloneEvents(s.events);
    this.styleEntries = this.cloneStyles(s.styleEntries);
    this.selected = this.events.length === 0 ? -1 : Math.min(s.selected, this.events.length - 1);
    this.styleSelected = this.styleEntries.length === 0
      ? -1 : Math.min(s.styleSelected, this.styleEntries.length - 1);
    this.loadSelected();
    if (this.styleSelected >= 0) {
      this.selectStyle(this.styleSelected);
    }
  }

  private undo(): void {
    const prev = this.undoStack.pop();
    if (prev === undefined) {
      return;
    }
    this.redoStack.push(this.snapshot());
    this.restoreSnapshot(prev);
    this.canUndo = this.undoStack.length > 0;
    this.canRedo = true;
    this.dirty = true;
  }

  private redo(): void {
    const next = this.redoStack.pop();
    if (next === undefined) {
      return;
    }
    this.undoStack.push(this.snapshot());
    this.restoreSnapshot(next);
    this.canUndo = true;
    this.canRedo = this.redoStack.length > 0;
    this.dirty = true;
  }

  private fieldIndex(name: string): number {
    const target = name.toLowerCase();
    return this.format.findIndex((v: string) => v.toLowerCase() === target);
  }

  private filteredEvents(): AssEvent[] {
    const q = this.filterText.trim().toLowerCase();
    if (q === '') {
      return this.events;
    }
    const out: AssEvent[] = [];
    const ai = this.fieldIndex('Name');
    const si = this.styleIndex();
    for (const e of this.events) {
      const text = this.textIndex >= 0 ? (e.fields[this.textIndex] ?? '') : '';
      const actor = ai >= 0 ? (e.fields[ai] ?? '') : '';
      const style = si >= 0 ? (e.fields[si] ?? '') : '';
      if (text.toLowerCase().includes(q) ||
          actor.toLowerCase().includes(q) ||
          style.toLowerCase().includes(q)) {
        out.push(e);
      }
    }
    return out;
  }

  private styleField(name: string): number {
    const target = name.toLowerCase();
    return this.styleFormat.findIndex((v: string) => v.toLowerCase() === target);
  }

  private styleName(s: AssStyleEntry): string {
    const i = this.styleField('Name');
    return i >= 0 ? (s.fields[i] ?? '') : '';
  }

  private styleOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const name of this.styles) {
      opts.push({ value: name });
    }
    return opts;
  }

  private selectStyle(i: number): void {
    if (i < 0 || i >= this.styleEntries.length) {
      return;
    }
    this.styleSelected = i;
    const f: string[] = this.styleEntries[i].fields;
    this.editFont = this.styleField('Fontname') >= 0
      ? (f[this.styleField('Fontname')] ?? '') : '';
    this.editSize = this.styleField('Fontsize') >= 0
      ? (f[this.styleField('Fontsize')] ?? '') : '';
    this.editPrimary = this.styleField('PrimaryColour') >= 0
      ? (f[this.styleField('PrimaryColour')] ?? '') : '';
    this.editOutline = this.styleField('OutlineColour') >= 0
      ? (f[this.styleField('OutlineColour')] ?? '') : '';
    this.editStyleName = this.styleField('Name') >= 0
      ? (f[this.styleField('Name')] ?? '') : '';
    this.editBold = this.styleField('Bold') >= 0
      ? (f[this.styleField('Bold')] ?? '0') : '0';
    this.editItalic = this.styleField('Italic') >= 0
      ? (f[this.styleField('Italic')] ?? '0') : '0';
    this.editAlign = this.styleField('Alignment') >= 0
      ? (f[this.styleField('Alignment')] ?? '2') : '2';
    this.editOutlineWidth = this.styleField('Outline') >= 0
      ? (f[this.styleField('Outline')] ?? '2') : '2';
    this.fontSelected = this.systemFonts.indexOf(this.editFont);
  }

  private loadFonts(): void {
    try {
      this.ensureFont();
    } catch (e) {
      this.fontListStatus = `字体解压失败：${JSON.stringify(e)}`;
      return;
    }
    const cfg = this.ensureFontConfig();
    if (cfg === '') {
      this.fontListStatus = 'fontconfig 配置不可用';
      return;
    }
    try {
      const raw: string = aegisub.listFonts(cfg);
      const result: FontListResult = JSON.parse(raw) as FontListResult;
      if (!result.ok) {
        this.fontListStatus = `枚举失败：${result.error ?? 'unknown'}`;
        return;
      }
      const fonts: string[] = result.fonts ?? [];
      const opts: SelectOption[] = [];
      for (const f of fonts) {
        opts.push({ value: f });
      }
      this.systemFonts = fonts;
      this.fontOptions = opts;
      this.fontSelected = fonts.indexOf(this.editFont);
      this.fontListStatus = `${fonts.length} 个系统字体`;
    } catch (e) {
      this.fontListStatus = `枚举失败：${JSON.stringify(e)}`;
    }
  }

  private applyStyle(): void {
    if (this.styleSelected < 0 || this.styleSelected >= this.styleEntries.length) {
      return;
    }
    const f: string[] = this.styleEntries[this.styleSelected].fields.slice();
    const set = (name: string, value: string): void => {
      const i = this.styleField(name);
      if (i >= 0 && i < f.length) {
        f[i] = value;
      }
    };
    set('Name', this.editStyleName.trim());
    set('Fontname', this.editFont.trim());
    set('Fontsize', this.editSize.trim());
    set('PrimaryColour', this.editPrimary.trim());
    set('OutlineColour', this.editOutline.trim());
    set('Bold', this.editBold.trim());
    set('Italic', this.editItalic.trim());
    set('Alignment', this.editAlign.trim());
    set('Outline', this.editOutlineWidth.trim());
    const old = this.styleEntries[this.styleSelected].fields;
    let changed = false;
    for (let i = 0; i < f.length; i++) {
      if (f[i] !== old[i]) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      this.status = '样式无改动';
      return;
    }
    this.pushUndo();
    const arr: AssStyleEntry[] = this.styleEntries.slice();
    arr[this.styleSelected] = { fields: f };
    this.styleEntries = arr;
    const names: string[] = [];
    for (const e of arr) {
      names.push(this.styleName(e));
    }
    this.styles = names;
    this.status = '样式已应用（未保存）';
  }

  private addStyle(): void {
    if (this.styleFormat.length === 0) {
      this.status = '该文件没有样式格式，无法新增';
      return;
    }
    let f: string[] = [];
    if (this.styleSelected >= 0 && this.styleSelected < this.styleEntries.length) {
      f = this.styleEntries[this.styleSelected].fields.slice();
    } else {
      for (let i = 0; i < this.styleFormat.length; i++) {
        f.push('');
      }
    }
    const set = (name: string, value: string): void => {
      const i = this.styleField(name);
      if (i >= 0 && i < f.length) {
        f[i] = value;
      }
    };
    let n = this.styleEntries.length + 1;
    let name = `NewStyle${n}`;
    while (this.styleEntries.some((e: AssStyleEntry) => this.styleName(e) === name)) {
      n++;
      name = `NewStyle${n}`;
    }
    set('Name', name);
    if (this.styleField('Fontname') >= 0 && f[this.styleField('Fontname')] === '') {
      set('Fontname', 'Arial');
    }
    if (this.styleField('Fontsize') >= 0 && f[this.styleField('Fontsize')] === '') {
      set('Fontsize', '48');
    }
    if (this.styleField('PrimaryColour') >= 0 && f[this.styleField('PrimaryColour')] === '') {
      set('PrimaryColour', '&H00FFFFFF');
    }
    if (this.styleField('OutlineColour') >= 0 && f[this.styleField('OutlineColour')] === '') {
      set('OutlineColour', '&H00000000');
    }
    this.pushUndo();
    const arr: AssStyleEntry[] = this.styleEntries.slice();
    arr.push({ fields: f });
    this.styleEntries = arr;
    this.styleSelected = arr.length - 1;
    this.selectStyle(this.styleSelected);
    const names: string[] = [];
    for (const e of arr) {
      names.push(this.styleName(e));
    }
    this.styles = names;
    this.status = `已新增样式 ${name}（未保存）`;
  }

  private deleteStyle(): void {
    if (this.styleEntries.length <= 1) {
      this.status = '至少保留一个样式';
      return;
    }
    if (this.styleSelected < 0 || this.styleSelected >= this.styleEntries.length) {
      return;
    }
    const removed = this.styleName(this.styleEntries[this.styleSelected]);
    this.pushUndo();
    const arr: AssStyleEntry[] = this.styleEntries.slice();
    arr.splice(this.styleSelected, 1);
    this.styleEntries = arr;
    this.styleSelected = Math.min(this.styleSelected, arr.length - 1);
    this.selectStyle(this.styleSelected);
    const names: string[] = [];
    for (const e of arr) {
      names.push(this.styleName(e));
    }
    this.styles = names;
    this.status = `已删除样式 ${removed}；引用它的行需手动改样式`;
  }

  private toggleStyles(): void {
    this.showStyles = !this.showStyles;
    if (this.showStyles) {
      this.showVideo = false;
      if (this.styleEntries.length > 0 && this.styleSelected < 0) {
        this.selectStyle(0);
      }
    }
  }

  private toggleVideo(): void {
    this.showVideo = !this.showVideo;
    if (this.showVideo) {
      this.showStyles = false;
      this.showAudio = false;
      this.updateActiveText();
    }
  }

  private updateActiveText(): void {
    let text = '';
    for (const e of this.events) {
      if (e.kind.toLowerCase() !== 'dialogue') {
        continue;
      }
      if (this.currentMs >= e.startMs && this.currentMs < e.endMs) {
        text = this.textIndex >= 0 ? (e.fields[this.textIndex] ?? '') : '';
        break;
      }
    }
    text = text.split('\N').join('\n');
    text = text.split('\n').join('\n');
    this.activeText = text;
  }

  private extractRawFont(asset: string, dest: string): void {
    const bytes: Uint8Array = this.ctx.resourceManager.getRawFileContentSync(asset);
    const length = bytes.byteLength;
    try {
      if (fs.statSync(dest).size === length) {
        return;
      }
    } catch (e) {
      // not extracted yet
    }
    const f = fs.openSync(dest,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < length) {
        const chunk = new ArrayBuffer(length - offset);
        new Uint8Array(chunk).set(bytes.subarray(offset));
        const written: number = fs.writeSync(f.fd, chunk);
        if (written <= 0) {
          throw new Error(`font write stalled at ${offset}/${length}`);
        }
        offset += written;
      }
    } finally {
      fs.closeSync(f);
    }
    if (fs.statSync(dest).size !== length) {
      fs.unlinkSync(dest);
      throw new Error(`font size mismatch: ${dest}`);
    }
  }

  private ensureFont(): string {
    const dir = `${this.ctx.cacheDir}/aegisub-fonts`;
    const dest = `${dir}/DejaVuSans.ttf`;
    if (this.fontsReady) {
      return dest;
    }
    try {
      fs.mkdirSync(dir, true);
    } catch (e) {
      // exists
    }
    this.extractRawFont('fonts/DejaVuSans.ttf', dest);
    // CJK fallback: libass/fontconfig picks this for Chinese glyphs.
    this.extractRawFont('fonts/DroidSansFallbackFull.ttf',
      `${dir}/DroidSansFallbackFull.ttf`);
    this.fontsReady = true;
    return dest;
  }

  private ensureFontConfig(): string {
    if (this.fontConfigPath !== '') {
      return this.fontConfigPath;
    }
    const dir = `${this.ctx.cacheDir}/aegisub-fonts`;
    const path = `${dir}/fonts.conf`;
    try {
      try {
        fs.mkdirSync(dir, true);
      } catch (e) {
        // already exists
      }
      const cache = `${this.ctx.cacheDir}/fc-cache-v012`;
      try {
        fs.mkdirSync(cache, true);
      } catch (e) {
        // exists
      }
      const xml = '<?xml version="1.0"?>\n' +
        '<fontconfig>\n' +
        '  <dir>/system/fonts</dir>\n' +
        `  <dir>${dir}</dir>\n` +
        `  <cachedir>${cache}</cachedir>\n` +
        '</fontconfig>\n';
      this.writeText(path, xml);
      this.fontConfigPath = path;
      return path;
    } catch (e) {
      this.addLog(`ensureFontConfig failed: ${JSON.stringify(e)}`);
      return '';
    }
  }

  async renderStyled(): Promise<void> {
    await this.renderAssFrame(Math.round(this.currentMs), true);
  }

  private async renderAssFrame(timeMs: number, saveFirst: boolean): Promise<void> {
    if (!this.hasDoc || this.assPath === '' || this.renderBusy) {
      return;
    }
    if (saveFirst && !this.saveToSandbox()) {
      return;
    }
    this.renderBusy = true;
    try {
      const font = this.ensureFont();
      const fontConfig = this.ensureFontConfig();
      const frame: RenderedFrame = aegisub.renderAss(
        this.assPath, timeMs, 640, 360, font, fontConfig);
      const opts: image.InitializationOptions = {
        size: { width: frame.width, height: frame.height },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.PREMUL,
        editable: false
      };
      this.subtitleImage = await image.createPixelMap(frame.pixels, opts);
      this.renderStatus = `已渲染 ${frame.width}x${frame.height} @ ` +
        `${(timeMs / 1000).toFixed(2)}s`;
    } catch (e) {
      this.renderStatus = `样式渲染失败：${JSON.stringify(e)}`;
      this.addLog(`renderAss failed: ${JSON.stringify(e)}`);
    } finally {
      this.renderBusy = false;
    }
  }

  private maybeAutoRender(): void {
    if (!this.autoStyled || this.renderBusy || !this.hasDoc) {
      return;
    }
    const now = Date.now();
    if (now - this.lastAutoRender < 400) {
      return;
    }
    this.lastAutoRender = now;
    this.renderAssFrame(Math.round(this.currentMs), false);
  }

  async pickVideo(): Promise<void> {
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.mp4', '.mkv', '.ts', '.m4v'];
      const doc = new picker.DocumentViewPicker(this.ctx);
      const uris = await doc.select(opt);
      if (!uris || uris.length === 0) {
        return;
      }
      let name = uris[0].substring(uris[0].lastIndexOf('/') + 1);
      try {
        name = decodeURIComponent(name);
      } catch (e) {
        // keep raw
      }
      const dir = `${this.ctx.filesDir}/video`;
      try {
        fs.mkdirSync(dir, true);
      } catch (e) {
        // exists
      }
      const dot = name.lastIndexOf('.');
      const ext = dot > 0 ? name.substring(dot) : '.mp4';
      const dest = `${dir}/video-${stamp()}${ext}`;
      this.copyTo(uris[0], dest);
      try {
        this.videoController.stop();
      } catch (e) {
        // not prepared yet
      }
      this.videoPath = dest;
      this.videoUri = fileUri.getUriFromPath(dest);
      this.videoName = name;
      this.currentMs = 0;
      this.subtitleImage = undefined;
      this.autoStyled = false;
      this.videoStatus = '已选择；点播放预览字幕';
      this.addLog(`pickVideo ${name} -> ${dest}`);
      this.updateActiveText();
    } catch (e) {
      this.videoStatus = `选择视频失败：${JSON.stringify(e)}`;
      this.addLog(`pickVideo failed: ${JSON.stringify(e)}`);
    }
  }

  private toggleAudio(): void {
    this.showAudio = !this.showAudio;
    if (this.showAudio) {
      this.showStyles = false;
      this.showVideo = false;
      this.updateActiveText();
    }
  }

  async pickAudio(): Promise<void> {
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg'];
      const doc = new picker.DocumentViewPicker(this.ctx);
      const uris = await doc.select(opt);
      if (!uris || uris.length === 0) {
        return;
      }
      let name = uris[0].substring(uris[0].lastIndexOf('/') + 1);
      try {
        name = decodeURIComponent(name);
      } catch (e) {
        // keep raw
      }
      const dir = `${this.ctx.filesDir}/audio`;
      try {
        fs.mkdirSync(dir, true);
      } catch (e) {
        // exists
      }
      const dot = name.lastIndexOf('.');
      const ext = dot > 0 ? name.substring(dot) : '.mp3';
      const dest = `${dir}/audio-${stamp()}${ext}`;
      this.copyTo(uris[0], dest);
      this.waveformPeaks = [];
      this.waveformStatus = '';
      if (name.toLowerCase().endsWith('.wav')) {
        try {
          const raw: string = aegisub.waveform(dest, 200);
          const result: WaveformResult = JSON.parse(raw) as WaveformResult;
          if (result.ok) {
            this.waveformPeaks = result.peaks ?? [];
            this.waveformStatus = `波形 ${this.waveformPeaks.length} 段`;
          } else {
            this.waveformStatus = `波形解析失败：${result.error ?? 'unknown'}`;
          }
        } catch (we) {
          this.waveformStatus = `波形解析失败：${JSON.stringify(we)}`;
        }
      } else {
        this.waveformStatus = '波形仅支持 WAV；当前格式仍可播放/打轴';
      }
      if (this.audioPlayer !== undefined) {
        try {
          await this.audioPlayer.release();
        } catch (e) {
          // already released
        }
        this.audioPlayer = undefined;
      }
      const player = await media.createAVPlayer();
      this.audioPlayer = player;
      player.url = fileUri.getUriFromPath(dest);
      player.on('timeUpdate', (time: number) => {
        this.currentMs = time;
        this.updateActiveText();
      });
      player.on('durationUpdate', (duration: number) => {
        this.audioDuration = duration;
      });
      player.on('stateChange', (state: media.AVPlayerState) => {
        this.audioPlaying = state === 'playing';
        if (state === 'completed') {
          this.audioPlaying = false;
        }
      });
      player.on('error', (err: BusinessError) => {
        this.audioStatus = `音频错误 ${err.code}`;
      });
      await player.prepare();
      this.audioPath = dest;
      this.audioName = name;
      this.audioStatus = '已加载；播放或用 ±1s 定位';
      this.currentMs = 0;
      this.audioDuration = 0;
      this.addLog(`pickAudio ${name}, waveform ${this.waveformPeaks.length} buckets`);
    } catch (e) {
      this.audioStatus = `选择音频失败：${JSON.stringify(e)}`;
      this.addLog(`pickAudio failed: ${JSON.stringify(e)}`);
    }
  }

  async toggleAudioPlay(): Promise<void> {
    if (this.audioPlayer === undefined) {
      return;
    }
    try {
      if (this.audioPlaying) {
        await this.audioPlayer.pause();
      } else {
        await this.audioPlayer.play();
      }
    } catch (e) {
      this.audioStatus = `播放失败：${JSON.stringify(e)}`;
    }
  }

  private seekAudio(deltaMs: number): void {
    if (this.audioPlayer === undefined) {
      return;
    }
    const target = Math.max(0, Math.min(this.currentMs + deltaMs,
      this.audioDuration > 0 ? this.audioDuration : this.currentMs + deltaMs));
    this.audioPlayer.seek(target);
    this.currentMs = target;
    this.updateActiveText();
  }

  private selectActiveEvent(): void {
    for (let i = 0; i < this.events.length; i++) {
      const e = this.events[i];
      if (e.kind.toLowerCase() === 'dialogue' &&
          this.currentMs >= e.startMs && this.currentMs < e.endMs) {
        this.selected = i;
        this.loadSelected();
        this.showVideo = false;
        this.showStyles = false;
        this.showAudio = false;
        this.status = `已选中当前播放行 #${i + 1}`;
        return;
      }
    }
    this.status = '当前播放位置没有 Dialogue 行';
  }

  private backToVideo(): void {
    if (this.videoUri === '') {
      return;
    }
    this.showVideo = true;
    this.showStyles = false;
    this.showAudio = false;
    if (this.selected >= 0 && this.selected < this.events.length) {
      const e = this.events[this.selected];
      this.currentMs = e.startMs;
      this.updateActiveText();
      try {
        this.videoController.setCurrentTime(e.startMs / 1000);
      } catch (ex) {
        // player not prepared yet
      }
    }
    this.videoStatus = this.selected >= 0
      ? `返回视频，定位到 #${this.selected + 1}` : '返回视频';
  }

  private seekSelected(): void {
    if (this.selected < 0 || this.selected >= this.events.length || this.videoUri === '') {
      return;
    }
    const e = this.events[this.selected];
    try {
      this.videoController.setCurrentTime(e.startMs / 1000);
      this.currentMs = e.startMs;
      this.updateActiveText();
      this.videoStatus = `跳到 ${(e.startMs / 1000).toFixed(2)}s`;
    } catch (ex) {
      this.videoStatus = `跳转失败：${JSON.stringify(ex)}`;
    }
  }

  private buildHeader(): string {
    if (this.styleEntries.length > 0 && this.styleSection !== '') {
      let h = this.stylePrefix;
      if (h.length > 0 && !h.endsWith(this.eol)) {
        h += this.eol;
      }
      h += this.styleSection + this.eol;
      h += 'Format: ' + this.styleFormat.join(', ') + this.eol;
      for (let i = 0; i < this.styleEntries.length; i++) {
        h += 'Style: ' + this.styleEntries[i].fields.join(',') + this.eol;
      }
      h += this.styleSuffix;
      return h;
    }
    return this.header;
  }

  private applyDoc(d: AssDoc): void {
    this.header = d.header ?? '';
    this.footer = d.footer ?? '';
    this.eol = d.eol ?? '\n';
    this.bom = d.bom ?? false;
    this.format = d.format ?? [];
    this.styles = d.styles ?? [];
    this.events = d.events ?? [];
    this.startIndex = d.startIndex ?? 1;
    this.endIndex = d.endIndex ?? 2;
    this.textIndex = d.textIndex ?? 9;
    this.styleSection = d.styleSection ?? '';
    this.stylePrefix = d.stylePrefix ?? '';
    this.styleSuffix = d.styleSuffix ?? '';
    this.styleFormat = d.styleFormat ?? [];
    this.styleEntries = d.styleEntries ?? [];
    this.styleSelected = this.styleEntries.length > 0 ? 0 : -1;
    this.hasDoc = true;
    this.selected = this.events.length > 0 ? 0 : -1;
    this.loadSelected();
    if (this.styleSelected >= 0) {
      this.selectStyle(this.styleSelected);
    }
    this.updateActiveText();
    this.subtitleImage = undefined;
    this.renderStatus = '';
    this.autoStyled = false;
    this.filterText = '';
    this.showAudio = false;
  }

  private loadSelected(): void {
    if (this.selected < 0 || this.selected >= this.events.length) {
      this.editStart = '';
      this.editEnd = '';
      this.editStyle = '';
      this.editText = '';
      return;
    }
    const e: AssEvent = this.events[this.selected];
    this.editKind = e.kind;
    this.editStart = this.startIndex >= 0 ? (e.fields[this.startIndex] ?? '') : '';
    this.editEnd = this.endIndex >= 0 ? (e.fields[this.endIndex] ?? '') : '';
    const si = this.styleIndex();
    this.editStyle = si >= 0 ? (e.fields[si] ?? '') : '';
    this.editText = this.textIndex >= 0 ? (e.fields[this.textIndex] ?? '') : '';
    const li = this.fieldIndex('Layer');
    this.editLayer = li >= 0 ? (e.fields[li] ?? '') : '0';
    const ai = this.fieldIndex('Name');
    this.editActor = ai >= 0 ? (e.fields[ai] ?? '') : '';
    const ml = this.fieldIndex('MarginL');
    this.editMarginL = ml >= 0 ? (e.fields[ml] ?? '') : '0';
    const mr = this.fieldIndex('MarginR');
    this.editMarginR = mr >= 0 ? (e.fields[mr] ?? '') : '0';
    const mv = this.fieldIndex('MarginV');
    this.editMarginV = mv >= 0 ? (e.fields[mv] ?? '') : '0';
    const ef = this.fieldIndex('Effect');
    this.editEffect = ef >= 0 ? (e.fields[ef] ?? '') : '';
  }

  private selectEvent(i: number): void {
    if (this.selected >= 0 && this.selected !== i) {
      this.applyEdit();
    }
    this.selected = i;
    this.loadSelected();
  }

  /** ASS is line-oriented; a real newline in TextArea must become \N. */
  private sanitizeText(t: string): string {
    let out = t.split('\r\n').join('\\N');
    out = out.split('\r').join('\\N');
    out = out.split('\n').join('\\N');
    return out;
  }

  private applyEdit(): void {
    if (this.selected < 0 || this.selected >= this.events.length) {
      return;
    }
    const e: AssEvent = this.events[this.selected];
    const f: string[] = e.fields.slice();
    if (this.startIndex >= 0 && this.startIndex < f.length) {
      this.editStart = aegisub.normalizeTime(this.editStart.trim());
      f[this.startIndex] = this.editStart;
    }
    if (this.endIndex >= 0 && this.endIndex < f.length) {
      this.editEnd = aegisub.normalizeTime(this.editEnd.trim());
      f[this.endIndex] = this.editEnd;
    }
    const si = this.styleIndex();
    if (si >= 0 && si < f.length) {
      f[si] = this.editStyle.trim();
    }
    if (this.textIndex >= 0 && this.textIndex < f.length) {
      this.editText = this.sanitizeText(this.editText);
      f[this.textIndex] = this.editText;
    }
    const li = this.fieldIndex('Layer');
    if (li >= 0 && li < f.length) {
      f[li] = this.editLayer.trim();
    }
    const ai = this.fieldIndex('Name');
    if (ai >= 0 && ai < f.length) {
      f[ai] = this.editActor;
    }
    const ml = this.fieldIndex('MarginL');
    if (ml >= 0 && ml < f.length) {
      f[ml] = this.editMarginL.trim();
    }
    const mr = this.fieldIndex('MarginR');
    if (mr >= 0 && mr < f.length) {
      f[mr] = this.editMarginR.trim();
    }
    const mv = this.fieldIndex('MarginV');
    if (mv >= 0 && mv < f.length) {
      f[mv] = this.editMarginV.trim();
    }
    const ef = this.fieldIndex('Effect');
    if (ef >= 0 && ef < f.length) {
      f[ef] = this.editEffect;
    }
    const newKind = this.editKind === 'Comment' ? 'Comment' : 'Dialogue';
    let changed = newKind !== e.kind;
    for (let i = 0; i < f.length; i++) {
      if (f[i] !== e.fields[i]) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      this.status = '无改动';
      return;
    }
    this.pushUndo();
    const updated: AssEvent = {
      kind: newKind,
      fields: f,
      startMs: this.startIndex >= 0 && this.startIndex < f.length
        ? aegisub.timeToMs(f[this.startIndex]) : e.startMs,
      endMs: this.endIndex >= 0 && this.endIndex < f.length
        ? aegisub.timeToMs(f[this.endIndex]) : e.endMs
    };
    const arr: AssEvent[] = this.events.slice();
    arr[this.selected] = updated;
    this.events = arr;
    this.editKind = newKind;
    this.status = '已应用到内存；点“保存”写入文件';
  }

  private defaultField(name: string): string {
    const n = name.toLowerCase();
    if (n === 'layer') {
      return '0';
    }
    if (n === 'start') {
      return '0:00:00.00';
    }
    if (n === 'end') {
      return '0:00:02.00';
    }
    if (n === 'style') {
      return this.styles.length > 0 ? this.styles[0] : 'Default';
    }
    if (n.indexOf('margin') === 0) {
      return '0';
    }
    if (n === 'text') {
      return 'New line';
    }
    return '';
  }

  private addEvent(): void {
    const fields: string[] = [];
    for (let i = 0; i < this.format.length; i++) {
      fields.push(this.defaultField(this.format[i]));
    }
    const e: AssEvent = { kind: 'Dialogue', fields: fields, startMs: 0, endMs: 2000 };
    this.pushUndo();
    const arr: AssEvent[] = this.events.slice();
    arr.push(e);
    this.events = arr;
    this.selected = arr.length - 1;
    this.loadSelected();
    this.status = '已新增一行；点“保存”写入文件';
  }

  private deleteEvent(): void {
    if (this.selected < 0 || this.selected >= this.events.length) {
      return;
    }
    this.pushUndo();
    const arr: AssEvent[] = this.events.slice();
    arr.splice(this.selected, 1);
    this.events = arr;
    this.selected = arr.length === 0 ? -1 : Math.min(this.selected, arr.length - 1);
    this.loadSelected();
    this.status = '已删除一行；点“保存”写入文件';
  }

  private shiftSelected(deltaMs: number): void {
    if (this.selected < 0 || this.selected >= this.events.length ||
        this.startIndex < 0 || this.endIndex < 0) {
      return;
    }
    this.applyEdit();
    const e = this.events[this.selected];
    const f: string[] = e.fields.slice();
    const s: number = Math.max(0, aegisub.timeToMs(f[this.startIndex]) + deltaMs);
    const en: number = Math.max(s, aegisub.timeToMs(f[this.endIndex]) + deltaMs);
    f[this.startIndex] = aegisub.msToTime(s);
    f[this.endIndex] = aegisub.msToTime(en);
    this.pushUndo();
    const updated: AssEvent = { kind: e.kind, fields: f, startMs: s, endMs: en };
    const arr: AssEvent[] = this.events.slice();
    arr[this.selected] = updated;
    this.events = arr;
    this.editStart = f[this.startIndex];
    this.editEnd = f[this.endIndex];
    this.status = `时间偏移 ${deltaMs > 0 ? '+' : ''}${deltaMs} ms`;
  }

  private shiftAll(deltaMs: number): void {
    if (this.events.length === 0 || this.startIndex < 0 || this.endIndex < 0) {
      return;
    }
    this.applyEdit();
    this.pushUndo();
    const arr: AssEvent[] = [];
    for (const e of this.events) {
      const f: string[] = e.fields.slice();
      let start = e.startMs;
      let end = e.endMs;
      if (this.startIndex < f.length && this.endIndex < f.length) {
        start = Math.max(0, aegisub.timeToMs(f[this.startIndex]) + deltaMs);
        end = Math.max(start, aegisub.timeToMs(f[this.endIndex]) + deltaMs);
        f[this.startIndex] = aegisub.msToTime(start);
        f[this.endIndex] = aegisub.msToTime(end);
      }
      arr.push({ kind: e.kind, fields: f, startMs: start, endMs: end });
    }
    this.events = arr;
    this.loadSelected();
    this.status = `全部事件偏移 ${deltaMs > 0 ? '+' : ''}${deltaMs} ms`;
  }

  private setBoundary(toStart: boolean): void {
    if (this.selected < 0 || this.selected >= this.events.length ||
        this.startIndex < 0 || this.endIndex < 0) {
      return;
    }
    this.applyEdit();
    const e = this.events[this.selected];
    const f: string[] = e.fields.slice();
    const now: number = Math.max(0, Math.round(this.currentMs));
    let s: number = aegisub.timeToMs(f[this.startIndex]);
    let en: number = aegisub.timeToMs(f[this.endIndex]);
    if (toStart) {
      s = now;
      if (en < s) {
        en = s;
      }
    } else {
      en = now;
      if (s > en) {
        s = en;
      }
    }
    f[this.startIndex] = aegisub.msToTime(s);
    f[this.endIndex] = aegisub.msToTime(en);
    this.pushUndo();
    const updated: AssEvent = { kind: e.kind, fields: f, startMs: s, endMs: en };
    const arr: AssEvent[] = this.events.slice();
    arr[this.selected] = updated;
    this.events = arr;
    this.editStart = f[this.startIndex];
    this.editEnd = f[this.endIndex];
    this.status = toStart ? '起点已设为播放位置' : '终点已设为播放位置';
  }

  private duplicateSelected(): void {
    if (this.selected < 0 || this.selected >= this.events.length) {
      return;
    }
    this.applyEdit();
    const e = this.events[this.selected];
    this.pushUndo();
    const copy: AssEvent = {
      kind: e.kind,
      fields: e.fields.slice(),
      startMs: e.startMs,
      endMs: e.endMs
    };
    const arr: AssEvent[] = this.events.slice();
    arr.splice(this.selected + 1, 0, copy);
    this.events = arr;
    this.selected = this.selected + 1;
    this.loadSelected();
    this.status = '已复制选中行';
  }

  private sortEvents(): void {
    if (this.events.length < 2) {
      return;
    }
    this.applyEdit();
    this.pushUndo();
    const arr: AssEvent[] = this.events.slice();
    arr.sort((a: AssEvent, b: AssEvent): number => a.startMs - b.startMs);
    this.events = arr;
    this.selected = 0;
    this.loadSelected();
    this.status = '已按开始时间排序';
  }

  private serialize(): string {
    let out = this.buildHeader();
    if (out.length > 0 && !out.endsWith(this.eol)) {
      out += this.eol;
    }
    out += '[Events]' + this.eol;
    out += 'Format: ' + this.format.join(', ') + this.eol;
    for (let i = 0; i < this.events.length; i++) {
      const e = this.events[i];
      out += e.kind + ': ' + e.fields.join(',') + this.eol;
    }
    out += this.footer;
    if (this.bom) {
      out = '\uFEFF' + out;
    }
    return out;
  }

  private writeText(path: string, text: string): void {
    const f = fs.openSync(path,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const bytes: Uint8Array = new util.TextEncoder().encodeInto(text);
      let offset = 0;
      while (offset < bytes.byteLength) {
        const chunk = new ArrayBuffer(bytes.byteLength - offset);
        new Uint8Array(chunk).set(bytes.subarray(offset));
        const written: number = fs.writeSync(f.fd, chunk);
        if (written <= 0) {
          throw new Error(`write stalled at ${offset}/${bytes.byteLength}`);
        }
        offset += written;
      }
    } finally {
      fs.closeSync(f);
    }
  }

  private saveToSandbox(): boolean {
    if (this.assPath === '') {
      this.status = '没有可保存的文件路径';
      return false;
    }
    if (this.styleSelected >= 0 && this.styleSelected < this.styleEntries.length) {
      this.applyStyle();
    }
    if (this.selected >= 0 && this.selected < this.events.length) {
      this.applyEdit();
    }
    try {
      try {
        fs.copyFileSync(this.assPath, `${this.assPath}.bak`);
      } catch (e) {
        // first save: no previous file
      }
      this.writeText(this.assPath, this.serialize());
      this.dirty = false;
      this.status = `已保存：${this.assPath}（旧版 .bak）`;
      this.addLog(`save ${this.assPath}, ${this.events.length} events`);
      return true;
    } catch (e) {
      this.status = `保存失败：${JSON.stringify(e)}`;
      this.addLog(`save failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  async openAss(): Promise<void> {
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.ass', '.ssa', '.srt'];
      const doc = new picker.DocumentViewPicker(this.ctx);
      const uris = await doc.select(opt);
      if (!uris || uris.length === 0) {
        return;
      }
      let name = uris[0].substring(uris[0].lastIndexOf('/') + 1);
      try {
        name = decodeURIComponent(name);
      } catch (e) {
        // keep raw
      }
      const isSrt = name.toLowerCase().endsWith('.srt');
      const dir = `${this.ctx.filesDir}/ass`;
      try {
        fs.mkdirSync(dir, true);
      } catch (e) {
        // exists
      }
      const dest = `${dir}/current-${stamp()}.ass`;
      this.copyTo(uris[0], dest);
      const raw: string = isSrt ? aegisub.loadSrt(dest) : aegisub.loadAss(dest);
      const d: AssDoc = JSON.parse(raw) as AssDoc;
      if (!d.ok) {
        this.status = `解析失败：${d.error ?? 'unknown'}`;
        this.addLog(`openAss parse failed: ${d.error ?? 'unknown'}`);
        return;
      }
      this.assPath = dest;
      this.fileName = isSrt ? `${name.substring(0, name.length - 4)}.ass` : name;
      this.applyDoc(d);
      this.resetHistory();
      this.status = isSrt
        ? `已导入 SRT ${name}，共 ${this.events.length} 行（转成 ASS）`
        : `已打开 ${name}，共 ${this.events.length} 行`;
      this.addLog(`open ${name} -> ${dest}, ${this.events.length} events`);
    } catch (e) {
      this.status = `打开失败：${JSON.stringify(e)}`;
      this.addLog(`openAss failed: ${JSON.stringify(e)}`);
      hilog.error(0xFF01, TAG, 'openAss failed: %{public}s', `${e}`);
    }
  }

  newAss(): void {
    try {
      const d: AssDoc = JSON.parse(aegisub.newAss()) as AssDoc;
      const dir = `${this.ctx.filesDir}/ass`;
      try {
        fs.mkdirSync(dir, true);
      } catch (e) {
        // exists
      }
      this.assPath = `${dir}/untitled-${stamp()}.ass`;
      this.fileName = 'untitled.ass';
      this.applyDoc(d);
      this.resetHistory();
      this.status = '已新建 v4.00+ 字幕';
      this.addLog(`newAss ${this.assPath}`);
    } catch (e) {
      this.status = `新建失败：${JSON.stringify(e)}`;
      this.addLog(`newAss failed: ${JSON.stringify(e)}`);
    }
  }

  async exportAss(): Promise<void> {
    if (!this.hasDoc) {
      return;
    }
    if (!this.saveToSandbox()) {
      return;
    }
    try {
      const opt = new picker.DocumentSaveOptions();
      opt.newFileNames = [`${this.fileName === '' ? 'subtitle' : this.fileName}`];
      opt.fileSuffixChoices = ['.ass', '.ssa'];
      const doc = new picker.DocumentViewPicker(this.ctx);
      const uris = await doc.save(opt);
      if (!uris || uris.length === 0) {
        return;
      }
      this.writeToUri(this.assPath, uris[0]);
      this.status = `已导出：${uris[0]}`;
      this.addLog(`exportAss ${uris[0]}`);
      promptAction.showToast({ message: '字幕已导出', duration: 2000 });
    } catch (e) {
      this.status = `导出失败：${JSON.stringify(e)}`;
    }
  }

  async exportSrt(): Promise<void> {
    if (!this.hasDoc) {
      return;
    }
    if (!this.saveToSandbox()) {
      return;
    }
    try {
      let out = '';
      let index = 1;
      for (let i = 0; i < this.events.length; i++) {
        const e = this.events[i];
        if (e.kind.toLowerCase() !== 'dialogue') {
          continue;
        }
        const start = this.startIndex >= 0 ? (e.fields[this.startIndex] ?? '') : '';
        const end = this.endIndex >= 0 ? (e.fields[this.endIndex] ?? '') : '';
        let text = this.textIndex >= 0 ? (e.fields[this.textIndex] ?? '') : '';
        text = text.split('\\N').join('\n');
        text = text.split('\\n').join('\n');
        out += `${index}\n${aegisub.srtTime(start)} --> ${aegisub.srtTime(end)}\n${text}\n\n`;
        index++;
      }
      if (index === 1) {
        this.status = '没有 Dialogue 行可导出';
        return;
      }
      const path = `${this.ctx.filesDir}/ass/export-${stamp()}.srt`;
      this.writeText(path, out);
      let base = this.fileName;
      const dot = base.lastIndexOf('.');
      if (dot > 0) {
        base = base.substring(0, dot);
      }
      const opt = new picker.DocumentSaveOptions();
      opt.newFileNames = [`${base}.srt`];
      opt.fileSuffixChoices = ['.srt'];
      const doc = new picker.DocumentViewPicker(this.ctx);
      const uris = await doc.save(opt);
      if (!uris || uris.length === 0) {
        return;
      }
      this.writeToUri(path, uris[0]);
      this.status = `已导出 SRT：${uris[0]}`;
      this.addLog(`exportSrt ${uris[0]}`);
      promptAction.showToast({ message: 'SRT 已导出', duration: 2000 });
    } catch (e) {
      this.status = `SRT 导出失败：${JSON.stringify(e)}`;
    }
  }

  private copyTo(srcUri: string, destPath: string): number {
    const src = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
    const dst = fs.openSync(destPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.copyFileSync(src.fd, dst.fd);
      return fs.statSync(dst.fd).size;
    } finally {
      fs.closeSync(src);
      fs.closeSync(dst);
    }
  }

  private writeToUri(srcPath: string, destUri: string): number {
    const expected = fs.statSync(srcPath).size;
    const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
    const dst = fs.openSync(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.copyFileSync(src.fd, dst.fd);
      const got = fs.statSync(dst.fd).size;
      if (got !== expected) {
        throw new Error(`写入不完整: ${got}/${expected} 字节`);
      }
      return got;
    } finally {
      fs.closeSync(src);
      fs.closeSync(dst);
    }
  }

  onPageHide(): void {
    if (this.hasDoc && this.dirty) {
      this.addLog('onPageHide autosave');
      this.saveToSandbox();
    }
  }

  aboutToDisappear(): void {
    if (this.audioPlayer !== undefined) {
      const player = this.audioPlayer;
      this.audioPlayer = undefined;
      player.release().catch(() => {
        // already released
      });
    }
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('Aegisub OHOS').fontSize(20).fontWeight(FontWeight.Bold)
          Text(`v${APP_VERSION} · ${this.fileName === '' ? '未打开文件'
            : `${this.fileName}${this.dirty ? ' *' : ''}`}`)
            .fontSize(10).fontColor('#888888').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('撤销').width(60).fontSize(11).enabled(this.canUndo)
          .onClick(() => { this.undo(); })
        Button('重做').width(60).fontSize(11).enabled(this.canRedo)
          .onClick(() => { this.redo(); })
      }
      .width('100%')

      Row({ space: 6 }) {
        Button('打开').layoutWeight(1).onClick(() => { this.openAss(); })
        Button('新建').layoutWeight(1).onClick(() => { this.newAss(); })
        Button('保存').layoutWeight(1).enabled(this.hasDoc)
          .onClick(() => { this.saveToSandbox(); })
        Button('ASS').layoutWeight(1).enabled(this.hasDoc)
          .onClick(() => { this.exportAss(); })
        Button('SRT').layoutWeight(1).enabled(this.hasDoc)
          .onClick(() => { this.exportSrt(); })
      }
      .width('100%')

      Row({ space: 6 }) {
        Button('导入视频').layoutWeight(1).fontSize(11).enabled(this.hasDoc)
          .onClick(() => {
            this.showVideo = true;
            this.showStyles = false;
            this.showAudio = false;
            this.pickVideo();
          })
        Button('导入音频').layoutWeight(1).fontSize(11).enabled(this.hasDoc)
          .onClick(() => {
            this.showAudio = true;
            this.showStyles = false;
            this.showVideo = false;
            this.pickAudio();
          })
      }
      .width('100%')

      Row({ space: 6 }) {
        Button('台词')
          .layoutWeight(1)
          .backgroundColor(!this.showStyles && !this.showVideo && !this.showAudio ? '#DCE6FF' : '#F0F0F0')
          .onClick(() => {
            this.showStyles = false;
            this.showVideo = false;
            this.showAudio = false;
          })
        Button('样式')
          .layoutWeight(1)
          .enabled(this.hasDoc)
          .backgroundColor(this.showStyles ? '#DCE6FF' : '#F0F0F0')
          .onClick(() => {
            this.showStyles = true;
            this.showVideo = false;
            this.showAudio = false;
            if (this.styleEntries.length > 0 && this.styleSelected < 0) {
              this.selectStyle(0);
            }
          })
        Button('视频')
          .layoutWeight(1)
          .enabled(this.hasDoc)
          .backgroundColor(this.showVideo ? '#DCE6FF' : '#F0F0F0')
          .onClick(() => { this.toggleVideo(); })
        Button('音频')
          .layoutWeight(1)
          .enabled(this.hasDoc)
          .backgroundColor(this.showAudio ? '#DCE6FF' : '#F0F0F0')
          .onClick(() => { this.toggleAudio(); })
        Button('日志')
          .layoutWeight(1)
          .onClick(() => { this.exportLog(); })
      }
      .width('100%')

      Text(this.status)
        .fontSize(11)
        .fontColor('#555555')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.hasDoc && this.showAudio) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Button('选择音频').fontSize(11)
              .onClick(() => { this.pickAudio(); })
            Text(this.audioName === '' ? '未选择音频' : this.audioName)
              .fontSize(10).fontColor('#666666').layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')

          Text(this.audioStatus).fontSize(10).fontColor('#888888').width('100%')

          if (this.waveformPeaks.length > 0) {
            Row({ space: 0 }) {
              ForEach(this.waveformPeaks, (v: number, i: number) => {
                Column()
                  .width(1.5)
                  .height(Math.max(1, v * 70))
                  .backgroundColor('#4263EB')
              }, (v: number, i: number) => `${i}`)
            }
            .width('100%')
            .height(70)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Bottom)
          }
          if (this.waveformStatus !== '') {
            Text(this.waveformStatus).fontSize(9).fontColor('#999999').width('100%')
          }

          if (this.audioPath !== '') {
            Text(`当前 ${(this.currentMs / 1000).toFixed(2)}s / ${(this.audioDuration / 1000).toFixed(2)}s`)
              .fontSize(11).fontColor('#4263EB').width('100%')
            Row({ space: 6 }) {
              Button(this.audioPlaying ? '暂停' : '播放').layoutWeight(1).fontSize(11)
                .onClick(() => { this.toggleAudioPlay(); })
              Button('-1s').layoutWeight(1).fontSize(11)
                .onClick(() => { this.seekAudio(-1000); })
              Button('+1s').layoutWeight(1).fontSize(11)
                .onClick(() => { this.seekAudio(1000); })
            }
            .width('100%')

            Row({ space: 6 }) {
              Button('设为起点').layoutWeight(1).fontSize(11)
                .enabled(this.selected >= 0)
                .onClick(() => { this.setBoundary(true); })
              Button('设为终点').layoutWeight(1).fontSize(11)
                .enabled(this.selected >= 0)
                .onClick(() => { this.setBoundary(false); })
              Button('选中当前行').layoutWeight(1).fontSize(11)
                .onClick(() => { this.selectActiveEvent(); })
            }
            .width('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
      } else if (this.hasDoc && this.showVideo) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Button('选择视频').fontSize(11)
              .onClick(() => { this.pickVideo(); })
            Text(this.videoName === '' ? '未选择视频' : this.videoName)
              .fontSize(10).fontColor('#666666').layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')

          Row({ space: 6 }) {
            Button('跳到选中行').fontSize(11)
              .enabled(this.selected >= 0 && this.videoUri !== '')
              .onClick(() => { this.seekSelected(); })
            Button('样式渲染').fontSize(11)
              .enabled(this.hasDoc)
              .onClick(() => { this.renderStyled(); })
            Text(`当前 ${(this.currentMs / 1000).toFixed(2)}s / ${this.videoDuration}s`)
              .fontSize(10).fontColor('#666666').layoutWeight(1)
          }
          .width('100%')

          Row({ space: 6 }) {
            Text('自动样式预览').fontSize(10).fontColor('#666666')
            Toggle({ type: ToggleType.Switch, isOn: this.autoStyled })
              .onChange((on: boolean) => {
                this.autoStyled = on;
                if (on) {
                  if (this.saveToSandbox()) {
                    this.renderAssFrame(Math.round(this.currentMs), false);
                  }
                } else {
                  this.subtitleImage = undefined;
                }
              })
            Text(this.renderStatus).fontSize(9).fontColor('#999999').layoutWeight(1)
          }
          .width('100%')

          Row({ space: 6 }) {
            Button('选中当前播放行').fontSize(10)
              .enabled(this.hasDoc)
              .onClick(() => { this.selectActiveEvent(); })
            Text(this.videoStatus).fontSize(9).fontColor('#888888').layoutWeight(1)
          }
          .width('100%')

          if (this.videoUri !== '') {
            Row({ space: 4 }) {
              Column({ space: 2 }) {
                Text('原视频').fontSize(9).fontColor('#888888')
                Stack({ alignContent: Alignment.Bottom }) {
                  Video({ src: this.videoUri, controller: this.videoController })
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Contain)
                    .controls(true)
                    .onPrepared((e: PreparedInfo) => {
                      this.videoDuration = e.duration;
                    })
                    .onUpdate((e: PlaybackInfo) => {
                      this.currentMs = e.time * 1000;
                      this.updateActiveText();
                      if (this.autoStyled) {
                        this.maybeAutoRender();
                      } else {
                        this.subtitleImage = undefined;
                      }
                    })
                    .onError(() => {
                      this.videoStatus = '视频播放失败（格式或解码器不支持）';
                    })
                  Text(this.activeText)
                    .fontSize(15)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#B0000000')
                    .width('100%')
                    .padding(6)
                    .textAlign(TextAlign.Center)
                    .hitTestBehavior(HitTestMode.Transparent)
                }
                .width('100%')
                .aspectRatio(16.0 / 9.0)
                .constraintSize({ maxWidth: 640, maxHeight: 280 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)

              if (this.subtitleImage !== undefined) {
                Column({ space: 2 }) {
                  Text('样式预览').fontSize(9).fontColor('#888888')
                  Image(this.subtitleImage)
                    .width('100%')
                    .aspectRatio(16.0 / 9.0)
                    .constraintSize({ maxWidth: 640, maxHeight: 280 })
                    .objectFit(ImageFit.Contain)
                    .backgroundColor('#202020')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Column() {
              Text('选择 MP4 / MKV / TS 预览字幕').fontSize(12).fontColor('#888888')
            }
            .width('100%')
            .aspectRatio(16.0 / 9.0)
            .constraintSize({ maxWidth: 640, maxHeight: 280 })
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
          }

          if (this.renderStatus !== '') {
            Text(this.renderStatus).fontSize(9).fontColor('#888888').width('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else if (this.hasDoc && this.showStyles) {      } else if (this.hasDoc && this.showStyles) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text('样式').fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)
            Button('新增样式').fontSize(10)
              .onClick(() => { this.addStyle(); })
            Button('删除样式').fontSize(10)
              .enabled(this.styleEntries.length > 1)
              .onClick(() => { this.deleteStyle(); })
          }
          .width('100%')
          if (this.styleEntries.length === 0) {
            Text('该文件没有样式段').fontSize(12).fontColor('#888888')
          } else {
            List({ space: 3 }) {
              ForEach(this.styleEntries, (st: AssStyleEntry, i: number) => {
                ListItem() {
                  Text(this.styleName(st))
                    .fontSize(13)
                    .width('100%')
                    .padding(8)
                    .backgroundColor(this.styleSelected === i ? '#E7F0FF' : '#FFFFFF')
                    .borderRadius(6)
                }
                .onClick(() => { this.selectStyle(i); })
              }, (st: AssStyleEntry, i: number) => `${i}`)
            }
            .layoutWeight(1)
            .width('100%')
            .divider({ strokeWidth: 1, color: '#E5E5E5' })

            Column({ space: 6 }) {
              Row({ space: 5 }) {
                Text('名称').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editStyleName })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editStyleName = v; })
              }
              .width('100%')

              Row({ space: 5 }) {
                Text('字体').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editFont })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editFont = v; })
                Button('系统字体').fontSize(10)
                  .onClick(() => { this.loadFonts(); })
              }
              .width('100%')

              if (this.fontOptions.length > 0) {
                Select(this.fontOptions)
                  .selected(this.fontSelected)
                  .value(this.editFont)
                  .onSelect((index: number, value: string) => {
                    this.fontSelected = index;
                    this.editFont = value;
                  })
              }
              if (this.fontListStatus !== '') {
                Text(this.fontListStatus).fontSize(9).fontColor('#999999').width('100%')
              }

              Row({ space: 5 }) {
                Text('字号').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editSize })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editSize = v; })
                Text('主色').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editPrimary })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editPrimary = v; })
              }
              .width('100%')

              Row({ space: 5 }) {
                Text('描边色').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editOutline })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editOutline = v; })
                Text('描边宽').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editOutlineWidth })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editOutlineWidth = v; })
              }
              .width('100%')

              Row({ space: 5 }) {
                Text('粗体').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editBold })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editBold = v; })
                Text('斜体').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editItalic })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editItalic = v; })
                Text('对齐').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editAlign })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editAlign = v; })
              }
              .width('100%')

              Button('应用样式').fontSize(11)
                .onClick(() => { this.applyStyle(); })
            }
            .padding(8)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .width('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
      } else if (this.hasDoc) {
        Row({ space: 4 }) {
          TextInput({ text: this.filterText, placeholder: '搜索台词 / 角色 / 样式' })
            .layoutWeight(1).fontSize(10)
            .onChange((v: string) => { this.filterText = v; })
          Button('清空').fontSize(10)
            .onClick(() => { this.filterText = ''; })
        }
        .width('100%')

        if (this.videoUri !== '') {
          Row({ space: 6 }) {
            Button('返回视频').fontSize(10)
              .onClick(() => { this.backToVideo(); })
            Text('回到视频并定位到选中行').fontSize(9).fontColor('#999999')
          }
          .width('100%')
        }

        List({ space: 3 }) {
          ForEach(this.filteredEvents(), (e: AssEvent) => {
            ListItem() {
              Column({ space: 2 }) {
                Row({ space: 5 }) {
                  Text(`${this.events.indexOf(e) + 1}`).fontSize(9).fontColor('#999999').width(22)
                  Text(this.startIndex >= 0 ? (e.fields[this.startIndex] ?? '') : '')
                    .fontSize(9).fontColor('#4263EB')
                  Text('→').fontSize(9).fontColor('#999999')
                  Text(this.endIndex >= 0 ? (e.fields[this.endIndex] ?? '') : '')
                    .fontSize(9).fontColor('#4263EB')
                  Text(e.kind).fontSize(8).fontColor('#999999')
                }
                Text(this.textIndex >= 0 ? (e.fields[this.textIndex] ?? '') : '')
                  .fontSize(12)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding(6)
              .backgroundColor(this.selected === this.events.indexOf(e) ? '#E7F0FF' : '#FFFFFF')
              .borderRadius(6)
              .alignItems(HorizontalAlign.Start)
            }
            .onClick(() => { this.selectEvent(this.events.indexOf(e)); })
          }, (e: AssEvent) => `${this.events.indexOf(e)}`)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: '#E5E5E5' })

        Column({ space: 6 }) {
          Row({ space: 5 }) {
            Text('开始').fontSize(10).fontColor('#666666')
            TextInput({ text: this.editStart })
              .layoutWeight(1).fontSize(11)
              .onChange((v: string) => { this.editStart = v; })
            Text('结束').fontSize(10).fontColor('#666666')
            TextInput({ text: this.editEnd })
              .layoutWeight(1).fontSize(11)
              .onChange((v: string) => { this.editEnd = v; })
          }
          .width('100%')

          Row({ space: 5 }) {
            Text('样式').fontSize(10).fontColor('#666666')
            TextInput({ text: this.editStyle })
              .layoutWeight(1).fontSize(11)
              .onChange((v: string) => { this.editStyle = v; })
            Button('应用').fontSize(11).onClick(() => { this.applyEdit(); })
          }
          .width('100%')

          if (this.styles.length > 0) {
            Select(this.styleOptions())
              .selected(Math.max(0, this.styles.indexOf(this.editStyle)))
              .value(this.editStyle)
              .onSelect((index: number, value: string) => {
                this.editStyle = value;
              })
          }

          Row({ space: 4 }) {
            Button(this.editKind).layoutWeight(1).fontSize(10)
              .onClick(() => {
                this.editKind = this.editKind === 'Comment' ? 'Dialogue' : 'Comment';
              })
            Button(this.showAdvanced ? '收起字段' : '更多字段').layoutWeight(1).fontSize(10)
              .onClick(() => { this.showAdvanced = !this.showAdvanced; })
          }
          .width('100%')

          TextArea({ text: this.editText })
            .height(64)
            .fontSize(12)
            .width('100%')
            .onChange((v: string) => { this.editText = v; })

          if (this.showAdvanced) {
            Row({ space: 4 }) {
              Text('层').fontSize(10).fontColor('#666666')
              TextInput({ text: this.editLayer }).layoutWeight(1).fontSize(10)
                .onChange((v: string) => { this.editLayer = v; })
              Text('角色').fontSize(10).fontColor('#666666')
              TextInput({ text: this.editActor }).layoutWeight(1).fontSize(10)
                .onChange((v: string) => { this.editActor = v; })
            }
            .width('100%')

            Row({ space: 4 }) {
              Text('左').fontSize(10).fontColor('#666666')
              TextInput({ text: this.editMarginL }).layoutWeight(1).fontSize(10)
                .onChange((v: string) => { this.editMarginL = v; })
              Text('右').fontSize(10).fontColor('#666666')
              TextInput({ text: this.editMarginR }).layoutWeight(1).fontSize(10)
                .onChange((v: string) => { this.editMarginR = v; })
              Text('垂').fontSize(10).fontColor('#666666')
              TextInput({ text: this.editMarginV }).layoutWeight(1).fontSize(10)
                .onChange((v: string) => { this.editMarginV = v; })
            }
            .width('100%')

            Row({ space: 4 }) {
              Text('特效').fontSize(10).fontColor('#666666')
              TextInput({ text: this.editEffect }).layoutWeight(1).fontSize(10)
                .onChange((v: string) => { this.editEffect = v; })
            }
            .width('100%')
          }

          Row({ space: 4 }) {
            Button('-100ms').layoutWeight(1).fontSize(10)
              .enabled(this.selected >= 0)
              .onClick(() => { this.shiftSelected(-100); })
            Button('+100ms').layoutWeight(1).fontSize(10)
              .enabled(this.selected >= 0)
              .onClick(() => { this.shiftSelected(100); })
            Button('起点=当前').layoutWeight(1).fontSize(10)
              .enabled(this.selected >= 0)
              .onClick(() => { this.setBoundary(true); })
            Button('终点=当前').layoutWeight(1).fontSize(10)
              .enabled(this.selected >= 0)
              .onClick(() => { this.setBoundary(false); })
          }
          .width('100%')

          Row({ space: 4 }) {
            Button('全部-100ms').layoutWeight(1).fontSize(10)
              .enabled(this.events.length > 0)
              .onClick(() => { this.shiftAll(-100); })
            Button('全部+100ms').layoutWeight(1).fontSize(10)
              .enabled(this.events.length > 0)
              .onClick(() => { this.shiftAll(100); })
          }
          .width('100%')

          Row({ space: 4 }) {
            Button('新增行').layoutWeight(1).fontSize(10)
              .onClick(() => { this.addEvent(); })
            Button('复制行').layoutWeight(1).fontSize(10)
              .enabled(this.selected >= 0)
              .onClick(() => { this.duplicateSelected(); })
            Button('删除行').layoutWeight(1).fontSize(10)
              .enabled(this.selected >= 0)
              .onClick(() => { this.deleteEvent(); })
            Button('排序').layoutWeight(1).fontSize(10)
              .enabled(this.events.length > 1)
              .onClick(() => { this.sortEvents(); })
          }
          .width('100%')
        }
        .padding(8)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .width('100%')
      } else {
        Column() {
          Text('打开一个 .ass/.ssa 文件，或点“新建”开始。')
            .fontSize(13)
            .fontColor('#888888')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
  }
}
