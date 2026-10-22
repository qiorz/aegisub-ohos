/*
 * Aegisub core test harness for HarmonyOS.
 *
 * The native module (libaegisubtest.so) recreates tests/setup.sh's data tree in
 * the app cache, runs the full upstream gtest suite, and returns both a JSON
 * summary and the complete stdout/stderr log.  This page never touches the
 * filesystem of other apps: logs stay in the sandbox until the user explicitly
 * exports them through the system save dialog.
 */
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import aegisub from 'libaegisubtest.so';

const TAG = 'AegisubTest';

interface TestResult {
  ok: boolean;
  error?: string;
  total?: number;
  passed?: number;
  failed?: number;
  rc?: number;
  durationMs?: number;
  logPath?: string;
  log?: string;
}

function stamp(): string {
  const d = new Date();
  const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-` +
         `${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

@Entry
@Component
struct Index {
  @State info: string = '初始化…';
  @State status: string = '待运行';
  @State running: boolean = false;
  @State total: number = 0;
  @State passed: number = 0;
  @State failed: number = 0;
  @State durationMs: number = 0;
  @State logPath: string = '';
  @State logText: string = '';

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    try {
      this.info = aegisub.version();
    } catch (e) {
      this.info = '原生模块加载失败';
      this.status = `${e}`;
    }
    const latestLog = `${this.ctx.cacheDir}/aegisub-tests/latest.log`;
    try {
      if (fs.accessSync(latestLog)) {
        this.logPath = latestLog;
      }
    } catch (e) {
      // no previous log
    }
    this.loadPrevious(latestLog);
  }

  /** Show the previous run (including a partial log left by a crash). */
  private loadPrevious(latestLog: string): void {
    try {
      const summaryPath = `${this.ctx.cacheDir}/aegisub-tests/latest.json`;
      const text = fs.readTextSync(summaryPath);
      const r: TestResult = JSON.parse(text) as TestResult;
      if (r && r.ok) {
        this.applyResult(r, false);
        return;
      }
    } catch (e) {
      // no previous summary
    }
    try {
      const text = fs.readTextSync(latestLog);
      if (text.length > 0) {
        this.logPath = latestLog;
        this.logText = text;
        this.status = '已载入上次日志（可能未跑完）';
      }
    } catch (e) {
      // no previous log
    }
  }

  private applyResult(r: TestResult, fresh: boolean): void {
    this.total = r.total ?? 0;
    this.passed = r.passed ?? 0;
    this.failed = r.failed ?? 0;
    this.durationMs = r.durationMs ?? 0;
    if (r.logPath !== undefined && r.logPath !== '') {
      this.logPath = r.logPath;
    }
    this.logText = r.log ?? '';
    if (this.logText === '') {
      try {
        this.logText = fs.readTextSync(this.logPath);
      } catch (e) {
        this.logText = '';
      }
    }
    const prefix = fresh ? '完成' : '上次';
    this.status = `${prefix}：${this.passed}/${this.total} 通过，${this.failed} 失败，` +
      `${this.durationMs} ms`;
  }

  /**
   * Extract rawfile/testdata into the sandbox once.  The fixture tree must look
   * like the upstream tests/ directory: tests/{keyframe,vfr,...} plus a sibling
   * automation/include (Lua automation tests use test_data_dir().parent_path()).
   */
  private ensureFixtures(): string {
    const root = `${this.ctx.cacheDir}/aegisub-tests`;
    const marker = `${root}/.fixtures-ok`;
    const testsDir = `${root}/tests`;
    try {
      if (fs.accessSync(marker) && fs.accessSync(testsDir)) {
        return testsDir;
      }
    } catch (e) {
      // not extracted yet
    }

    this.status = '正在解压测试素材…';
    const manifestBytes: Uint8Array =
      this.ctx.resourceManager.getRawFileContentSync('testdata/manifest.json');
    const text: string = new util.TextDecoder('utf-8').decodeToString(manifestBytes);
    const files: string[] = JSON.parse(text) as string[];

    try {
      fs.mkdirSync(root, true);
    } catch (e) {
      // already exists
    }
    for (const rel of files) {
      const slash = rel.lastIndexOf('/');
      if (slash > 0) {
        try {
          fs.mkdirSync(`${root}/${rel.substring(0, slash)}`, true);
        } catch (e) {
          // already exists
        }
      }
      const bytes: Uint8Array =
        this.ctx.resourceManager.getRawFileContentSync(`testdata/${rel}`);
      const fd = fs.openSync(`${root}/${rel}`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const buffer: ArrayBuffer = bytes.buffer.slice(
          bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
        fs.writeSync(fd.fd, buffer);
      } finally {
        fs.closeSync(fd);
      }
    }

    const markerFd = fs.openSync(marker,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.closeSync(markerFd);
    return testsDir;
  }

  async runTests(): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    this.logText = '';
    try {
      const fixtures: string = this.ensureFixtures();
      this.status = '正在运行全部测试…';
      const raw: string = await aegisub.runTests(this.ctx.cacheDir, fixtures);
      const r: TestResult = JSON.parse(raw) as TestResult;
      if (!r.ok) {
        this.status = `运行失败：${r.error ?? 'unknown'}`;
        if (r.log !== undefined) {
          this.logText = r.log;
        }
        return;
      }
      this.applyResult(r, true);
    } catch (e) {
      this.status = `运行异常：${JSON.stringify(e)}`;
      hilog.error(0xFF01, TAG, 'runTests failed: %{public}s', `${e}`);
    } finally {
      this.running = false;
    }
  }

  /** Export the sandbox log through the system save dialog (user picks path). */
  async exportLog(): Promise<void> {
    if (this.logPath === '') {
      return;
    }
    try {
      const opt = new picker.DocumentSaveOptions();
      opt.newFileNames = [`aegisub-test-${stamp()}.log`];
      opt.fileSuffixChoices = ['.log', '.txt'];
      const doc = new picker.DocumentViewPicker(this.ctx);
      const uris = await doc.save(opt);
      if (!uris || uris.length === 0) {
        return;
      }
      const n = this.writeToUri(this.logPath, uris[0]);
      this.status = `日志已导出：${n} 字节 → ${uris[0]}`;
      promptAction.showToast({ message: '日志已导出', duration: 2000 });
    } catch (e) {
      this.status = `导出失败：${JSON.stringify(e)}`;
      hilog.error(0xFF01, TAG, 'export failed: %{public}s', `${e}`);
    }
  }

  async copyLogPath(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.logPath);
      await pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: '日志路径已复制', duration: 2000 });
    } catch (e) {
      this.status = `复制失败：${JSON.stringify(e)}`;
    }
  }

  /**
   * Write a sandbox file to a URI returned by DocumentViewPicker.
   * fd-to-fd copy first, byte-count verified; sequential fallback otherwise.
   */
  private writeToUri(srcPath: string, destUri: string): number {
    const expected = fs.statSync(srcPath).size;
    if (expected <= 0) {
      throw new Error('日志为空');
    }
    try {
      const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dst.fd);
        const got = fs.statSync(dst.fd).size;
        if (got === expected) {
          return got;
        }
      } finally {
        fs.closeSync(src);
        fs.closeSync(dst);
      }
    } catch (e) {
      hilog.warn(0xFF01, TAG, 'copyFileSync failed, falling back');
    }

    const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
    const dst = fs.openSync(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      const buf = new ArrayBuffer(1 << 20);
      let n = 0;
      while ((n = fs.readSync(src.fd, buf)) > 0) {
        fs.writeSync(dst.fd, buf, { length: n });
      }
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

  @Builder
  metric(label: string, value: number, bad: boolean) {
    Column({ space: 2 }) {
      Text(`${value}`)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(bad && value > 0 ? '#D93025' : '#1A1A1A')
      Text(label).fontSize(10).fontColor('#777777')
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text('Aegisub Core Test')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
          Text(this.info)
            .fontSize(11)
            .fontColor('#666666')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('返回编辑器')
          .fontSize(11)
          .onClick(() => { router.back(); })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.metric('总数', this.total, false)
        this.metric('通过', this.passed, false)
        this.metric('失败', this.failed, true)
      }
      .width('100%')

      Row({ space: 8 }) {
        Button(this.running ? '运行中…' : '运行全部测试')
          .layoutWeight(2)
          .enabled(!this.running)
          .onClick(() => { this.runTests(); })
        Button('导出日志')
          .layoutWeight(1)
          .enabled(this.logPath !== '')
          .onClick(() => { this.exportLog(); })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('复制日志路径')
          .layoutWeight(1)
          .enabled(this.logPath !== '')
          .onClick(() => { this.copyLogPath(); })
        Button('清空显示')
          .layoutWeight(1)
          .onClick(() => { this.logText = ''; })
      }
      .width('100%')

      Text(this.status)
        .fontSize(12)
        .fontColor('#333333')
        .width('100%')
      Text(this.logPath)
        .fontSize(9)
        .fontColor('#888888')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Scroll() {
        Text(this.logText === '' ? '点击“运行全部测试”开始。\n\n'
          + '测试会在应用沙箱 cache/aegisub-tests 下重建 data/，'
          + '运行 371 项 libaegisub 单元测试。' : this.logText)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor('#E8E8E8')
          .width('100%')
          .padding(10)
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#1B1B1B')
      .borderRadius(8)
      .align(Alignment.TopStart)
    }
    .padding(14)
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
  }
}
