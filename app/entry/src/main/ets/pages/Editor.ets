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
import { fileIo as fs, picker } from '@kit.CoreFileKit';
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

  private header: string = '';
  private footer: string = '';
  private eol: string = '\n';
  private bom: boolean = false;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.newAss();
  }

  private styleIndex(): number {
    return this.format.findIndex((v: string) => v.toLowerCase() === 'style');
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
    this.hasDoc = true;
    this.selected = this.events.length > 0 ? 0 : -1;
    this.loadSelected();
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
    this.selected = i;
    this.loadSelected();
  }

  private applyEdit(): void {
    if (this.selected < 0 || this.selected >= this.events.length) {
      return;
    }
    const e: AssEvent = this.events[this.selected];
    const f: string[] = e.fields.slice();
    if (this.startIndex >= 0 && this.startIndex < f.length) {
      f[this.startIndex] = this.editStart.trim();
    }
    if (this.endIndex >= 0 && this.endIndex < f.length) {
      f[this.endIndex] = this.editEnd.trim();
    }
    const si = this.styleIndex();
    if (si >= 0 && si < f.length) {
      f[si] = this.editStyle.trim();
    }
    if (this.textIndex >= 0 && this.textIndex < f.length) {
      f[this.textIndex] = this.editText;
    }
    const updated: AssEvent = {
      kind: e.kind,
      fields: f,
      startMs: e.startMs,
      endMs: e.endMs
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
    const arr: AssEvent[] = this.events.slice();
    arr.splice(this.selected, 1);
    this.events = arr;
    this.selected = arr.length === 0 ? -1 : Math.min(this.selected, arr.length - 1);
    this.loadSelected();
    this.status = '已删除一行；点“保存”写入文件';
  }

  private serialize(): string {
    let out = this.header;
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
    try {
      this.writeText(this.assPath, this.serialize());
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
      opt.fileSuffixFilters = ['.ass', '.ssa'];
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
      const dir = `${this.ctx.filesDir}/ass`;
      try {
        fs.mkdirSync(dir, true);
      } catch (e) {
        // exists
      }
      const dest = `${dir}/current-${stamp()}.ass`;
      this.copyTo(uris[0], dest);
      const d: AssDoc = JSON.parse(aegisub.loadAss(dest)) as AssDoc;
      if (!d.ok) {
        this.status = `解析失败：${d.error ?? 'unknown'}`;
        return;
      }
      this.assPath = dest;
      this.fileName = name;
      this.applyDoc(d);
      this.status = `已打开 ${name}，共 ${this.events.length} 行`;
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
          Text(this.fileName === '' ? '未打开文件' : this.fileName)
            .fontSize(10).fontColor('#888888').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('测试')
          .onClick(() => { router.pushUrl({ url: 'pages/Index' }); })
      }
      .width('100%')

      Row({ space: 6 }) {
        Button('打开').layoutWeight(1).onClick(() => { this.openAss(); })
        Button('新建').layoutWeight(1).onClick(() => { this.newAss(); })
        Button('保存').layoutWeight(1).enabled(this.hasDoc)
          .onClick(() => { this.saveToSandbox(); })
        Button('导出').layoutWeight(1).enabled(this.hasDoc)
          .onClick(() => { this.exportAss(); })
      }
      .width('100%')

      Text(this.status)
        .fontSize(11)
        .fontColor('#555555')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.hasDoc) {
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
