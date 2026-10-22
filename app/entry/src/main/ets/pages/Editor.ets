/*
 * Aegisub OHOS -- first ArkUI shell.
 *
 * MVP scope: open an .ass/.ssa file through the system picker, parse its
 * [Events] table with libaegisub's agi::Time (native ass_lite.cpp), edit the
 * start/end/style/text of a line, and save/export.  Styling, video and audio
 * are intentionally not part of this page yet; the gtest harness remains on
 * pages/Index for diagnostics.
 */
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import aegisub from 'libaegisubtest.so';

const TAG = 'AegisubEditor';

interface AssEvent {
  kind: string;
  fields: string[];
  startMs: number;
  endMs: number;
}

interface AssStyleEntry {
  fields: string[];
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

  private header: string = '';
  private footer: string = '';
  private eol: string = '\n';
  private bom: boolean = false;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private undoStack: EditorSnapshot[] = [];
  private redoStack: EditorSnapshot[] = [];
  private videoController: VideoController = new VideoController();

  aboutToAppear(): void {
    this.newAss();
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

  private styleField(name: string): number {
    const target = name.toLowerCase();
    return this.styleFormat.findIndex((v: string) => v.toLowerCase() === target);
  }

  private styleName(s: AssStyleEntry): string {
    const i = this.styleField('Name');
    return i >= 0 ? (s.fields[i] ?? '') : '';
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
    set('Fontname', this.editFont.trim());
    set('Fontsize', this.editSize.trim());
    set('PrimaryColour', this.editPrimary.trim());
    set('OutlineColour', this.editOutline.trim());
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
      this.videoStatus = '已选择；点播放预览字幕';
      this.updateActiveText();
    } catch (e) {
      this.videoStatus = `选择视频失败：${JSON.stringify(e)}`;
    }
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
    this.editStart = this.startIndex >= 0 ? (e.fields[this.startIndex] ?? '') : '';
    this.editEnd = this.endIndex >= 0 ? (e.fields[this.endIndex] ?? '') : '';
    const si = this.styleIndex();
    this.editStyle = si >= 0 ? (e.fields[si] ?? '') : '';
    this.editText = this.textIndex >= 0 ? (e.fields[this.textIndex] ?? '') : '';
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
    let changed = false;
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
      kind: e.kind,
      fields: f,
      startMs: this.startIndex >= 0 && this.startIndex < f.length
        ? aegisub.timeToMs(f[this.startIndex]) : e.startMs,
      endMs: this.endIndex >= 0 && this.endIndex < f.length
        ? aegisub.timeToMs(f[this.endIndex]) : e.endMs
    };
    const arr: AssEvent[] = this.events.slice();
    arr[this.selected] = updated;
    this.events = arr;
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
      fs.writeSync(f.fd, text);
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
      this.writeText(this.assPath, this.serialize());
      this.dirty = false;
      this.status = `已保存：${this.assPath}`;
      return true;
    } catch (e) {
      this.status = `保存失败：${JSON.stringify(e)}`;
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
        return;
      }
      this.assPath = dest;
      this.fileName = isSrt ? `${name.substring(0, name.length - 4)}.ass` : name;
      this.applyDoc(d);
      this.resetHistory();
      this.status = isSrt
        ? `已导入 SRT ${name}，共 ${this.events.length} 行（转成 ASS）`
        : `已打开 ${name}，共 ${this.events.length} 行`;
    } catch (e) {
      this.status = `打开失败：${JSON.stringify(e)}`;
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
    } catch (e) {
      this.status = `新建失败：${JSON.stringify(e)}`;
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

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('Aegisub OHOS').fontSize(22).fontWeight(FontWeight.Bold)
          Text(this.fileName === '' ? '未打开文件'
            : `${this.fileName}${this.dirty ? ' *' : ''}`)
            .fontSize(10).fontColor('#888888').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('↶').width(38).fontSize(12).enabled(this.canUndo)
          .onClick(() => { this.undo(); })
        Button('↷').width(38).fontSize(12).enabled(this.canRedo)
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
        Button('台词')
          .layoutWeight(1)
          .backgroundColor(!this.showStyles && !this.showVideo ? '#DCE6FF' : '#F0F0F0')
          .onClick(() => { this.showStyles = false; this.showVideo = false; })
        Button('样式')
          .layoutWeight(1)
          .enabled(this.hasDoc)
          .backgroundColor(this.showStyles ? '#DCE6FF' : '#F0F0F0')
          .onClick(() => {
            this.showStyles = true;
            this.showVideo = false;
            if (this.styleEntries.length > 0 && this.styleSelected < 0) {
              this.selectStyle(0);
            }
          })
        Button('视频')
          .layoutWeight(1)
          .enabled(this.hasDoc)
          .backgroundColor(this.showVideo ? '#DCE6FF' : '#F0F0F0')
          .onClick(() => { this.toggleVideo(); })
        Button('测试')
          .layoutWeight(1)
          .onClick(() => { router.pushUrl({ url: 'pages/Index' }); })
      }
      .width('100%')

      Text(this.status)
        .fontSize(11)
        .fontColor('#555555')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.hasDoc && this.showVideo) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Button('选择视频').fontSize(11)
              .onClick(() => { this.pickVideo(); })
            Text(this.videoName === '' ? '未选择视频' : this.videoName)
              .fontSize(10).fontColor('#666666').layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')

          if (this.videoUri !== '') {
            Stack({ alignContent: Alignment.Bottom }) {
              Video({ src: this.videoUri, controller: this.videoController })
                .width('100%')
                .height(220)
                .controls(true)
                .onPrepared((e: PreparedInfo) => {
                  this.videoDuration = e.duration;
                })
                .onUpdate((e: PlaybackInfo) => {
                  this.currentMs = e.time * 1000;
                  this.updateActiveText();
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
            }
            .width('100%')
            .height(220)
          } else {
            Column() {
              Text('选择 MP4 / MKV / TS 预览字幕').fontSize(12).fontColor('#888888')
            }
            .width('100%')
            .height(220)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
          }

          Row({ space: 6 }) {
            Button('跳到选中行').fontSize(11)
              .enabled(this.selected >= 0 && this.videoUri !== '')
              .onClick(() => { this.seekSelected(); })
            Text(`当前 ${(this.currentMs / 1000).toFixed(2)}s / ${this.videoDuration}s`)
              .fontSize(10).fontColor('#666666').layoutWeight(1)
          }
          .width('100%')

          Text(this.videoStatus).fontSize(10).fontColor('#888888').width('100%')
        }
        .layoutWeight(1)
        .width('100%')
      } else if (this.hasDoc && this.showStyles) {
        Column({ space: 6 }) {
          Text('样式').fontSize(16).fontWeight(FontWeight.Bold).width('100%')
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
                Text('字体').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editFont })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editFont = v; })
              }
              .width('100%')

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
                Text('描边').fontSize(10).fontColor('#666666')
                TextInput({ text: this.editOutline })
                  .layoutWeight(1).fontSize(11)
                  .onChange((v: string) => { this.editOutline = v; })
                Button('应用样式').fontSize(11)
                  .onClick(() => { this.applyStyle(); })
              }
              .width('100%')
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
        List({ space: 3 }) {
          ForEach(this.events, (e: AssEvent, i: number) => {
            ListItem() {
              Column({ space: 2 }) {
                Row({ space: 5 }) {
                  Text(`${i + 1}`).fontSize(9).fontColor('#999999').width(22)
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
              .backgroundColor(this.selected === i ? '#E7F0FF' : '#FFFFFF')
              .borderRadius(6)
              .alignItems(HorizontalAlign.Start)
            }
            .onClick(() => { this.selectEvent(i); })
          }, (e: AssEvent, i: number) => `${i}`)
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

          TextArea({ text: this.editText })
            .height(64)
            .fontSize(12)
            .width('100%')
            .onChange((v: string) => { this.editText = v; })

          Row({ space: 6 }) {
            Button('新增行').layoutWeight(1).fontSize(11)
              .onClick(() => { this.addEvent(); })
            Button('删除行').layoutWeight(1).fontSize(11)
              .enabled(this.selected >= 0)
              .onClick(() => { this.deleteEvent(); })
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
