// zap for Windows — 화면 위에 띄우는 반투명 실측 자 (맥판 Sources/main.swift 이식)
// 빌드: windows/build.sh (또는 Windows에서 dotnet build -c Release)
//
// 좌표 규칙: 자 모델(0점, 길이, 창 위치)은 전부 물리 픽셀. 화면 배율(DPI)은 모니터마다 따로 읽는다.
// 자의 로컬 좌표: u = 0점에서 길이 방향, v = 실측(cm) 모서리에서 안쪽 방향. 화면 y는 아래로 증가.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using WF = System.Windows.Forms;
using SD = System.Drawing;

namespace Zap
{
    // MARK: - Win32

    static class W
    {
        [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct MONITORINFOEX
        {
            public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
        }
        public delegate bool MonitorEnumProc(IntPtr h, IntPtr hdc, ref RECT r, IntPtr data);

        [DllImport("user32")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32")] public static extern bool GetCursorPos(out POINT p);
        [DllImport("user32")] public static extern IntPtr MonitorFromPoint(POINT p, uint flags);
        [DllImport("user32")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
        [DllImport("user32", CharSet = CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr h, ref MONITORINFOEX mi);
        [DllImport("user32")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc cb, IntPtr data);
        [DllImport("gdi32", CharSet = CharSet.Auto)] public static extern IntPtr CreateDC(string drv, string dev, string o, IntPtr init);
        [DllImport("gdi32")] public static extern bool DeleteDC(IntPtr h);
        [DllImport("gdi32")] public static extern int GetDeviceCaps(IntPtr h, int i);
        [DllImport("shcore")] public static extern int GetDpiForMonitor(IntPtr h, int type, out uint x, out uint y);
        [DllImport("user32")] public static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32")] public static extern int SetWindowLong(IntPtr h, int i, int v);
        [DllImport("user32")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);

        public static readonly IntPtr TOPMOST = new IntPtr(-1);
        public const uint NOACTIVATE = 0x10, SHOWWINDOW = 0x40, NOZORDER = 0x4;
        public const int EXSTYLE = -20, EX_TOOLWINDOW = 0x80, EX_TRANSPARENT = 0x20, EX_NOACTIVATE = 0x08000000;

        public static POINT Cursor() { GetCursorPos(out var p); return p; }
        public static IntPtr Handle(Window w) => new WindowInteropHelper(w).EnsureHandle();
        public static void AddExStyle(Window w, int bits)
        {
            var h = Handle(w);
            SetWindowLong(h, EXSTYLE, GetWindowLong(h, EXSTYLE) | bits);
        }
        public static void Place(Window w, int x, int y, int cx, int cy, bool show = false) =>
            SetWindowPos(Handle(w), TOPMOST, x, y, Math.Max(1, cx), Math.Max(1, cy), NOACTIVATE | (show ? SHOWWINDOW : 0));
    }

    // MARK: - 설정 (%APPDATA%\zap\settings.txt, 한 줄에 key=value)

    static class Store
    {
        public static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "zap");
        static readonly string FilePath = Path.Combine(Dir, "settings.txt");
        static readonly Dictionary<string, string> d = Load();

        static Dictionary<string, string> Load()
        {
            var r = new Dictionary<string, string>();
            try
            {
                foreach (var l in File.ReadAllLines(FilePath))
                {
                    int i = l.IndexOf('=');
                    if (i > 0) r[l.Substring(0, i)] = l.Substring(i + 1);
                }
            }
            catch { }
            return r;
        }
        public static string Get(string k) => d.TryGetValue(k, out var v) ? v : null;
        public static void Set(string k, string v)
        {
            if (v == null) d.Remove(k); else d[k] = v;
            try { Directory.CreateDirectory(Dir); File.WriteAllLines(FilePath, d.Select(p => p.Key + "=" + p.Value)); } catch { }
        }
        public static double? Num(string k) =>
            double.TryParse(Get(k), NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : (double?)null;
        public static void SetNum(string k, double v) => Set(k, v.ToString("R", CultureInfo.InvariantCulture));
    }

    static class St
    {
        public static event Action Changed;
        public static void Fire() => Changed?.Invoke();

        public static bool Inch { get => Store.Get("unit") == "inch"; set { Store.Set("unit", value ? "inch" : "metric"); Fire(); } }
        public static double Opacity
        {
            get => Store.Num("opacity") ?? 0.55;
            set { Store.SetNum("opacity", Math.Min(0.95, Math.Max(0.15, value))); Fire(); }
        }
        public static double Thickness
        {
            get => Store.Num("thickness") ?? 80;
            set { Store.SetNum("thickness", Math.Min(160, Math.Max(40, value))); Fire(); }
        }
        public static Color Color { get => Col("color", Color.FromRgb(255, 255, 255)); set => SetCol("color", value); }
        public static Color Color2 { get => Col("color2", Color.FromRgb(158, 199, 255)); set => SetCol("color2", value); }
        static Color Col(string k, Color def)
        {
            var s = Store.Get(k);
            if (s != null && s.Length == 6 && int.TryParse(s, NumberStyles.HexNumber, null, out var v))
                return Color.FromRgb((byte)(v >> 16), (byte)(v >> 8), (byte)v);
            return def;
        }
        static void SetCol(string k, Color c) { Store.Set(k, $"{c.R:X2}{c.G:X2}{c.B:X2}"); Fire(); }
        static bool Flag(string k, bool def) => Store.Get(k) is string s ? s == "1" : def;
        static void SetFlag(string k, bool v) { Store.Set(k, v ? "1" : "0"); Fire(); }
        public static bool Gradient { get => Flag("gradient", false); set => SetFlag("gradient", value); }
        public static bool ShowReal { get => Flag("showReal", true); set => SetFlag("showReal", value); }
        public static bool ShowPx { get => Flag("showPx", true); set => SetFlag("showPx", value); }
        public static bool Snap90 { get => Flag("snap90", true); set => SetFlag("snap90", value); }

        /// 자에 깔 사진 (%APPDATA%\zap 에 복사본 보관)
        public static string ImagePath { get => Store.Get("imagePath"); set { Store.Set("imagePath", value); cached = null; Fire(); } }
        static Tuple<BitmapSource, double> cached;
        /// 사진과 평균 밝기
        public static Tuple<BitmapSource, double> Image
        {
            get
            {
                if (cached != null) return cached;
                var p = ImagePath;
                if (p == null || !File.Exists(p)) return null;
                try
                {
                    var bi = Load(p, 0);
                    var f = new FormatConvertedBitmap(Load(p, 16), PixelFormats.Bgra32, null, 0);
                    int w = f.PixelWidth, h = f.PixelHeight;
                    var px = new byte[w * h * 4];
                    f.CopyPixels(px, w * 4, 0);
                    double sum = 0;
                    for (int i = 0; i < px.Length; i += 4) sum += (0.0722 * px[i] + 0.7152 * px[i + 1] + 0.2126 * px[i + 2]) / 255;
                    cached = Tuple.Create((BitmapSource)bi, sum / (w * h));
                }
                catch { return null; }
                return cached;
            }
        }
        static BitmapImage Load(string p, int decodeWidth)
        {
            var b = new BitmapImage();
            b.BeginInit();
            b.CacheOption = BitmapCacheOption.OnLoad;
            b.UriSource = new Uri(p);
            if (decodeWidth > 0) b.DecodePixelWidth = decodeWidth;
            b.EndInit();
            b.Freeze();
            return b;
        }
        public static void ResetLook()
        {
            foreach (var k in new[] { "imagePath", "opacity", "thickness", "color", "color2", "gradient", "showReal", "showPx", "snap90", "unit" })
                Store.Set(k, null);
            cached = null;
            Fire();
        }
        public static double Lum(Color c) => (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) / 255;
    }

    // MARK: - 화면 물리 크기

    sealed class Mon
    {
        public IntPtr H;
        public string Name;
        public W.RECT Px, Work;
        public double Scale = 1;

        public static Mon From(IntPtr h)
        {
            var mi = new W.MONITORINFOEX { cbSize = Marshal.SizeOf(typeof(W.MONITORINFOEX)) };
            W.GetMonitorInfo(h, ref mi);
            var m = new Mon { H = h, Name = mi.szDevice ?? "DISPLAY", Px = mi.rcMonitor, Work = mi.rcWork };
            try { if (W.GetDpiForMonitor(h, 0, out var dx, out _) == 0 && dx > 0) m.Scale = dx / 96.0; } catch { }
            return m;
        }
        public static Mon At(double x, double y) =>
            From(W.MonitorFromPoint(new W.POINT { X = (int)Math.Round(x), Y = (int)Math.Round(y) }, 2));
        public static Mon AtCursor() { var p = W.Cursor(); return At(p.X, p.Y); }
        public static Mon Of(Window w) => From(W.MonitorFromWindow(W.Handle(w), 2));
        public static List<Mon> All()
        {
            var r = new List<Mon>();
            W.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr h, IntPtr dc, ref W.RECT rc, IntPtr d) => { r.Add(From(h)); return true; }, IntPtr.Zero);
            return r;
        }
        public int Width => Px.R - Px.L;
        public int Height => Px.B - Px.T;
        public bool Contains(double x, double y) => x >= Px.L && x < Px.R && y >= Px.T && y < Px.B;
    }

    static class Disp
    {
        public enum Source { Calibrated, Auto, Guess }

        static string Key(Mon m) => $"cal-{m.Name}-{m.Width}x{m.Height}";

        /// 디스플레이가 알려주는 물리 크기(mm) ÷ 논리 해상도(DIP)
        public static double? AutoMMPerDip(Mon m)
        {
            int mm = 0;
            try
            {
                var dc = W.CreateDC("DISPLAY", m.Name, null, IntPtr.Zero);
                if (dc != IntPtr.Zero) { mm = W.GetDeviceCaps(dc, 4 /* HORZSIZE */); W.DeleteDC(dc); }
            }
            catch { }
            if (mm < 50 || m.Width <= 0) return null;
            double v = mm / (m.Width / m.Scale);
            double ppi = 25.4 / v;
            if (ppi < 40 || ppi > 400) return null;  // TV·프로젝터의 엉터리 EDID 걸러냄
            return v;
        }
        public static double MMPerDip(Mon m) => Store.Num(Key(m)) is double v && v > 0 ? v : AutoMMPerDip(m) ?? 25.4 / 96;
        public static double MMPerPx(Mon m) => MMPerDip(m) / m.Scale;
        public static Source SourceOf(Mon m) =>
            Store.Get(Key(m)) != null ? Source.Calibrated : AutoMMPerDip(m) != null ? Source.Auto : Source.Guess;
        public static void Save(double mmPerDip, Mon m) { Store.SetNum(Key(m), mmPerDip); St.Fire(); }
        public static void Reset(Mon m) { Store.Set(Key(m), null); St.Fire(); }
    }

    // MARK: - 포맷·그리기 도우미

    static class Fmt
    {
        static string F(double v, int d) => v.ToString("F" + d, CultureInfo.InvariantCulture);
        public static string Len(double mm) => St.Inch ? F(mm / 25.4, 2) + " in" : F(mm, 1) + " mm";
        public static string Pair(double a, double b) =>
            St.Inch ? $"{F(a / 25.4, 2)} × {F(b / 25.4, 2)} in" : $"{F(a, 1)} × {F(b, 1)} mm";
        public static string Px(double v) => ((int)Math.Round(v)).ToString(CultureInfo.InvariantCulture);
    }

    static class G
    {
        static readonly FontFamily Family = new FontFamily("Segoe UI");
        public static readonly Color Red = Color.FromRgb(255, 46, 51);

        public static FormattedText Text(string s, double size, Color c, FontWeight w, double pixelsPerDip = 1) =>
            new FormattedText(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                new Typeface(Family, FontStyles.Normal, w, FontStretches.Normal), size, new SolidColorBrush(c), pixelsPerDip);
        public static Color A(Color c, double a) => Color.FromArgb((byte)Math.Round(Math.Max(0, Math.Min(1, a)) * 255), c.R, c.G, c.B);
        public static Color White(double a) => A(Colors.White, a);
        public static Color Black(double a) => A(Colors.Black, a);
        public static Brush B(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
        public static Pen P(Color c, double w) { var p = new Pen(B(c), w); p.Freeze(); return p; }

        /// 어두운 알약 모양 수치 표시. 그린 사각형을 돌려줌.
        public static Rect Pill(DrawingContext dc, IList<FormattedText> lines, Point at, double ax, double ay, Rect? within = null)
        {
            const double padX = 8, padY = 5, gap = 1;
            double w = lines.Max(l => l.WidthIncludingTrailingWhitespace) + padX * 2;
            double h = lines.Sum(l => l.Height) + gap * Math.Max(0, lines.Count - 1) + padY * 2;
            var r = new Rect(at.X - w * ax, at.Y - h * ay, w, h);
            if (within is Rect b)
            {
                r.X = Math.Min(Math.Max(r.X, b.Left + 2), b.Right - w - 2);
                r.Y = Math.Min(Math.Max(r.Y, b.Top + 2), b.Bottom - h - 2);
            }
            dc.DrawRoundedRectangle(B(Color.FromArgb(225, 20, 20, 20)), null, r, 6, 6);
            double y = r.Y + padY;
            foreach (var l in lines) { dc.DrawText(l, new Point(r.X + padX, y)); y += l.Height + gap; }
            return r;
        }
    }

    // MARK: - 자 옆 수치 표시 (클릭은 통과)

    sealed class Readout : Window
    {
        readonly Face face = new Face();
        sealed class Face : FrameworkElement
        {
            public FormattedText Main, Sub;
            protected override void OnRender(DrawingContext dc)
            {
                if (Main == null) return;
                var r = new Rect(0, 0, ActualWidth, ActualHeight);
                dc.DrawRoundedRectangle(G.B(Color.FromArgb(230, 24, 24, 26)), G.P(G.White(0.18), 1), r, r.Height / 2, r.Height / 2);
                double x = 15;
                dc.DrawText(Main, new Point(x, (r.Height - Main.Height) / 2));
                if (Sub != null) dc.DrawText(Sub, new Point(x + Main.WidthIncludingTrailingWhitespace, (r.Height - Sub.Height) / 2 + 1));
            }
        }
        public Readout()
        {
            WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
            Topmost = true; ShowInTaskbar = false; ShowActivated = false; ResizeMode = ResizeMode.NoResize;
            Content = face;
            W.AddExStyle(this, W.EX_TOOLWINDOW | W.EX_TRANSPARENT | W.EX_NOACTIVATE);
        }
        /// 크기(물리 px)를 돌려줌
        public Size SetText(string main, string sub, double scale)
        {
            face.Main = G.Text(main, 15, Colors.White, FontWeights.SemiBold);
            face.Sub = sub == null ? null : G.Text(sub, 12, G.White(0.6), FontWeights.Medium);
            double w = face.Main.WidthIncludingTrailingWhitespace + (face.Sub?.WidthIncludingTrailingWhitespace ?? 0) + 30;
            double h = Math.Max(face.Main.Height, face.Sub?.Height ?? 0) + 14;
            face.InvalidateVisual();
            return new Size(Math.Ceiling(w * scale), Math.Ceiling(h * scale));
        }
    }

    // MARK: - 자

    sealed class Ruler : Window
    {
        /// 0점(실측 모서리 시작), 각도(시계 방향 +), 길이. 전부 물리 px.
        public double OX, OY, Angle, Len = 600;
        public double? MarkU, EndU, HoverU;
        (double?, double?) beforeClick;
        bool rotating;
        enum DragKind { None, Pending, Move, Rotate }
        DragKind drag;
        W.POINT dragStart; double dragOX, dragOY;
        int wx, wy, ww, wh;  // 창 위치 (물리 px)
        readonly Readout readout = new Readout();
        readonly Face face;
        public Action<bool> OnMenu;  // 오른쪽 클릭 메뉴

        public Mon Mon => Mon.At(ScreenPt(Len / 2, T / 2).X, ScreenPt(Len / 2, T / 2).Y);
        public double Sc => Mon.Scale;
        public double T => St.Thickness * Sc;
        double Grip => 22 * Sc;
        public double? LiveEnd => MarkU == null ? null : (EndU ?? HoverU);
        double Cos => Math.Cos(Angle);
        double Sin => Math.Sin(Angle);
        bool AxisAligned => Math.Abs(Math.IEEERemainder(Angle, Math.PI / 2)) < 1e-6;
        int Degrees { get { int d = (int)Math.Round(Angle * 180 / Math.PI) % 360; return d < 0 ? d + 360 : d; } }

        public Point ScreenPt(double u, double v) => new Point(OX + u * Cos - v * Sin, OY + u * Sin + v * Cos);
        public (double u, double v) Local(double x, double y)
        {
            double dx = x - OX, dy = y - OY;
            return (dx * Cos + dy * Sin, -dx * Sin + dy * Cos);
        }
        bool Inside((double u, double v) l) => l.u >= 0 && l.u <= Len && l.v >= 0 && l.v <= T;

        public Ruler()
        {
            WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
            Topmost = true; ShowInTaskbar = false; ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Width = 1; Height = 1;
            face = new Face(this);
            Content = face;
            W.AddExStyle(this, W.EX_TOOLWINDOW);
            St.Changed += Layout;
            DpiChanged += (s, e) => Dispatcher.BeginInvoke(new Action(Layout));
            Deactivated += (s, e) => ClearMark();  // 자 밖(다른 앱 포함)을 누르면 잰 것 지우기
            Closing += (s, e) => { e.Cancel = true; HideRuler(); };
        }

        public void ClearMark()
        {
            if (MarkU == null) return;
            MarkU = null; EndU = null; beforeClick = (null, null);
            face.InvalidateVisual();
            UpdateReadout();
        }

        /// 모델이 바뀌면 창 크기를 다시 맞춤
        public void Layout()
        {
            var c = new[] { ScreenPt(0, 0), ScreenPt(Len, 0), ScreenPt(0, T), ScreenPt(Len, T) };
            wx = (int)Math.Floor(c.Min(p => p.X) - 2); wy = (int)Math.Floor(c.Min(p => p.Y) - 2);
            ww = (int)Math.Ceiling(c.Max(p => p.X) + 2) - wx; wh = (int)Math.Ceiling(c.Max(p => p.Y) + 2) - wy;
            if (IsVisible) W.Place(this, wx, wy, ww, wh);
            face.InvalidateVisual();
            UpdateReadout();
        }

        public void ShowRuler()
        {
            // 마우스가 있는 화면에 자가 없으면 그 화면 가운데로 데려옴
            var m = Mon.AtCursor();
            var mid = ScreenPt(Len / 2, T / 2);
            if (!m.Contains(mid.X, mid.Y)) CenterOn(m);
            Show();
            Layout();
            Activate();
            Focus();
        }
        public void CenterOn(Mon m)
        {
            Len = Math.Min(m.Work.R - m.Work.L - 120 * m.Scale, 200 / Disp.MMPerPx(m));
            Angle = 0;
            OX = Math.Round((m.Work.L + m.Work.R) / 2.0 - Len / 2);
            OY = Math.Round((m.Work.T + m.Work.B) / 2.0 - St.Thickness * m.Scale / 2);
        }
        public void HideRuler() { readout.Hide(); Hide(); }
        public void Toggle() { if (IsVisible) HideRuler(); else ShowRuler(); }

        // 수치 표시
        void UpdateReadout()
        {
            if (!IsVisible) { readout.Hide(); return; }
            double mmpp = Disp.MMPerPx(Mon);
            string main, sub = null;
            double at;
            if (rotating) { main = $"{Degrees}°   {Fmt.Len(Len * mmpp)}"; at = Len; }
            else if (MarkU is double a && LiveEnd is double b)
            {
                double d = Math.Abs(b - a);
                main = Fmt.Len(d * mmpp); sub = $"   {Fmt.Px(d)} px"; at = b;
            }
            else { readout.Hide(); return; }
            var size = readout.SetText(main, sub, Sc);
            double half = Math.Abs(Sin) * size.Width / 2 + Math.Abs(Cos) * size.Height / 2 + 10 * Sc;
            var mon = Mon;
            var c = ScreenPt(at, T + half);
            if (!(c.X - size.Width / 2 >= mon.Work.L && c.X + size.Width / 2 <= mon.Work.R && c.Y - size.Height / 2 >= mon.Work.T && c.Y + size.Height / 2 <= mon.Work.B))
                c = ScreenPt(at, -half);
            double x = Math.Min(Math.Max(c.X - size.Width / 2, mon.Work.L + 4), mon.Work.R - size.Width - 4);
            double y = Math.Min(Math.Max(c.Y - size.Height / 2, mon.Work.T + 4), mon.Work.B - size.Height - 4);
            if (!readout.IsVisible) readout.Show();
            W.Place(readout, (int)Math.Round(x), (int)Math.Round(y), (int)size.Width, (int)size.Height, true);
        }

        void Track()
        {
            var p = W.Cursor();
            var l = Local(p.X, p.Y);
            HoverU = Inside(l) ? Math.Round(l.u) : (double?)null;
            Cursor = !Inside(l) ? Cursors.Arrow : l.u > Len - Grip ? Cursors.Hand : Cursors.Cross;
            face.InvalidateVisual();
            UpdateReadout();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            var m = W.Cursor();
            if (drag == DragKind.Pending)
            {
                if (Math.Sqrt(Math.Pow(m.X - dragStart.X, 2) + Math.Pow(m.Y - dragStart.Y, 2)) <= 3 * Sc) return;
                drag = DragKind.Move;
                Cursor = Cursors.SizeAll;
            }
            switch (drag)
            {
                case DragKind.Move:
                    OX = dragOX + m.X - dragStart.X; OY = dragOY + m.Y - dragStart.Y;
                    Layout();
                    break;
                case DragKind.Rotate:
                    // 0점을 축으로 끝을 마우스에 붙임
                    double dx = m.X - OX, dy = m.Y - OY;
                    double a = Math.Atan2(dy, dx);
                    bool shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
                    double step = shift ? Math.PI / 12 : Math.PI / 2;
                    double nearest = Math.Round(a / step) * step;
                    if (shift || (St.Snap90 && Math.Abs(a - nearest) < 4 * Math.PI / 180)) a = nearest;
                    Angle = a;
                    Len = Math.Max(120 * Sc, dx * Math.Cos(a) + dy * Math.Sin(a) + Grip / 2);
                    HoverU = null;
                    Layout();
                    break;
                default:
                    Track();
                    break;
            }
        }
        protected override void OnMouseLeave(MouseEventArgs e) { if (drag == DragKind.None) { HoverU = null; face.InvalidateVisual(); UpdateReadout(); } }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            var m = W.Cursor();
            var l = Local(m.X, m.Y);
            if (!Inside(l)) { drag = DragKind.None; ClearMark(); return; }
            Activate(); Focus();
            if (e.ClickCount == 2)  // 첫 클릭이 찍은 시작점은 되돌림
            {
                (MarkU, EndU) = beforeClick;
                drag = DragKind.None;
                Rotate(Math.PI / 2);
                return;
            }
            CaptureMouse();
            if (l.u > Len - Grip) { drag = DragKind.Rotate; rotating = true; Cursor = Cursors.SizeAll; UpdateReadout(); }
            else { drag = DragKind.Pending; dragStart = m; dragOX = OX; dragOY = OY; }
        }
        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
        {
            if (drag == DragKind.Pending)  // 움직이지 않은 클릭 = 시작점, 두 번째 = 끝점, 그다음 = 새로 시작
            {
                beforeClick = (MarkU, EndU);
                var p = W.Cursor();
                double u = Math.Round(Local(p.X, p.Y).u);
                if (MarkU == null || EndU != null) { MarkU = u; EndU = null; } else EndU = u;
            }
            drag = DragKind.None;
            rotating = false;
            ReleaseMouseCapture();
            Track();
        }
        protected override void OnMouseRightButtonUp(MouseButtonEventArgs e) { e.Handled = true; OnMenu?.Invoke(true); }

        /// 자 가운데를 축으로 돌림. 90° 배수 근처면 정확히 맞춤.
        public void Rotate(double d)
        {
            var c = ScreenPt(Len / 2, T / 2);
            double a = Angle + d;
            double q = Math.Round(a / (Math.PI / 2)) * (Math.PI / 2);
            if (Math.Abs(a - q) < 1e-3) a = q;
            Angle = Math.Atan2(Math.Sin(a), Math.Cos(a));
            OX = Math.Round(c.X - Cos * Len / 2 + Sin * T / 2);
            OY = Math.Round(c.Y - Sin * Len / 2 - Cos * T / 2);
            HoverU = null;
            Layout();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            bool shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
            double step = shift ? 10 : 1;
            double deg = (shift ? 15 : 1) * Math.PI / 180;
            switch (e.Key)
            {
                case Key.Left: OX -= step; break;
                case Key.Right: OX += step; break;
                case Key.Up: OY -= step; break;
                case Key.Down: OY += step; break;
                case Key.Escape: if (MarkU != null) ClearMark(); else HideRuler(); e.Handled = true; return;
                case Key.R: Rotate(Math.PI / 2); e.Handled = true; return;
                case Key.OemCloseBrackets: Rotate(deg); e.Handled = true; return;
                case Key.OemOpenBrackets: Rotate(-deg); e.Handled = true; return;
                case Key.U: St.Inch = !St.Inch; e.Handled = true; return;
                case Key.OemMinus: case Key.Subtract: St.Opacity -= 0.1; e.Handled = true; return;
                case Key.OemPlus: case Key.Add: St.Opacity += 0.1; e.Handled = true; return;
                default: base.OnKeyDown(e); return;
            }
            e.Handled = true;
            Layout();
        }

        bool BodyIsDark
        {
            get
            {
                if (St.Image is Tuple<BitmapSource, double> img) return img.Item2 < 0.5;
                double lum = St.Gradient ? (St.Lum(St.Color) + St.Lum(St.Color2)) / 2 : St.Lum(St.Color);
                return lum < 0.5;
            }
        }

        sealed class Face : FrameworkElement
        {
            readonly Ruler r;
            public Face(Ruler r) { this.r = r; }

            protected override void OnRender(DrawingContext dc)
            {
                double win = VisualTreeHelper.GetDpi(this).DpiScaleX;  // 이 창이 실제로 그려지는 배율
                double s = r.Sc, L = r.Len, T = r.T;
                var mmpp = Disp.MMPerPx(r.Mon);
                bool inch = St.Inch, dark = r.BodyIsDark;
                var ink = dark ? G.White(0.9) : G.Black(0.9);

                dc.PushTransform(new ScaleTransform(1 / win, 1 / win));
                dc.PushTransform(new TranslateTransform(r.OX - r.wx, r.OY - r.wy));
                dc.PushTransform(new RotateTransform(r.Angle * 180 / Math.PI));

                double R = 9 * s;
                var body = new Rect(0, 0, L, T);
                dc.PushClip(new RectangleGeometry(body, R, R));
                // 유리 대신 깔리는 바탕: 클릭이 통과하지 않도록 아주 옅게라도 칠함
                dc.DrawRectangle(G.B(dark ? G.Black(0.18) : G.White(0.22)), null, body);
                if (St.Image is Tuple<BitmapSource, double> img && img.Item1.PixelWidth > 0 && img.Item1.PixelHeight > 0)
                {
                    // 한 줄로: 높이 = 자 두께, 길이는 cm 단위로 잘라 반복 (2.4cm → 2cm)
                    double cm = 10 / mmpp, iw = img.Item1.PixelWidth, ih = img.Item1.PixelHeight;
                    double n = Math.Max(1, Math.Floor(iw / ih * T / cm + 0.05));
                    double w = n * cm;
                    Int32Rect src;
                    if (iw / ih >= w / T) { int sw = (int)Math.Max(1, ih * w / T); src = new Int32Rect((int)((iw - sw) / 2), 0, sw, (int)ih); }
                    else { int sh = (int)Math.Max(1, iw * T / w); src = new Int32Rect(0, (int)((ih - sh) / 2), (int)iw, sh); }
                    var crop = new CroppedBitmap(img.Item1, src);
                    dc.PushOpacity(St.Opacity);
                    for (double x = 0; x < L; x += w) dc.DrawImage(crop, new Rect(x, 0, w, T));
                    dc.Pop();
                }
                else if (St.Gradient)
                {
                    var gb = new LinearGradientBrush(G.A(St.Color, St.Opacity * 0.7), G.A(St.Color2, St.Opacity * 0.7), new Point(0, 0), new Point(1, 0));
                    dc.DrawRectangle(gb, null, body);
                }
                else dc.DrawRectangle(G.B(G.A(St.Color, St.Opacity * 0.7)), null, body);
                // 유리 광택: 위쪽 반사, 아래쪽 은은한 빛
                dc.DrawRectangle(new LinearGradientBrush(G.White(dark ? 0.22 : 0.5), G.White(0), 90), null, new Rect(0, 0, L, T * 0.45));
                dc.DrawRectangle(new LinearGradientBrush(G.White(0), G.White(dark ? 0.08 : 0.18), 90), null, new Rect(0, T * 0.7, L, T * 0.3));
                dc.Pop();
                // 테두리: 안쪽 밝은 림 + 바깥 얇은 그늘
                var inset = new Rect(0.75 * s, 0.75 * s, L - 1.5 * s, T - 1.5 * s);
                dc.DrawRoundedRectangle(null, G.P(G.White(dark ? 0.35 : 0.85), 1.5 * s), inset, R - 0.75 * s, R - 0.75 * s);
                dc.DrawRoundedRectangle(null, G.P(G.Black(dark ? 0.4 : 0.14), 1), body, R, R);

                if (r.MarkU is double ma && r.LiveEnd is double mb)
                    dc.DrawRectangle(G.B(G.A(G.Red, 0.15)), null, new Rect(Math.Min(ma, mb), 0, Math.Abs(mb - ma), T));

                var ticks = new StreamGeometry();
                bool flip = Math.Cos(r.Angle) < -0.01;  // 거꾸로 서면 글자만 뒤집음
                var labels = new List<(string, double, double, bool)>();
                using (var g = ticks.Open())
                {
                    void Tick(double u, double v0, double v1)
                    {
                        double x = r.AxisAligned ? Math.Floor(u) + 0.5 : u;
                        g.BeginFigure(new Point(x, v0), false, false);
                        g.LineTo(new Point(x, v1), true, false);
                    }
                    // 위 모서리: 실제 길이
                    if (St.ShowReal)
                    {
                        if (inch)
                        {
                            double per = 25.4 / 16 / mmpp;
                            int n = (int)(L / per);
                            for (int i = 0; i <= n; i++)
                            {
                                double h = i % 16 == 0 ? 20 : i % 8 == 0 ? 15 : i % 4 == 0 ? 11 : i % 2 == 0 ? 8 : 5;
                                Tick(i * per, 0, h * s);
                                if (i % 16 == 0 && i > 0) labels.Add(((i / 16).ToString(), i * per, 28 * s, false));
                            }
                        }
                        else
                        {
                            double per = 1 / mmpp;
                            int n = (int)(L / per);
                            for (int i = 0; i <= n; i++)
                            {
                                double h = i % 10 == 0 ? 20 : i % 5 == 0 ? 13 : 7;
                                Tick(i * per, 0, h * s);
                                if (i % 10 == 0 && i > 0) labels.Add(((i / 10).ToString(), i * per, 28 * s, false));
                            }
                        }
                        labels.Add((inch ? "in" : "cm", 12 * s, 28 * s, true));
                    }
                    // 아래 모서리: 화면 px
                    if (St.ShowPx)
                    {
                        for (int i = 0; i <= (int)L; i += 5)
                        {
                            double h = i % 100 == 0 ? 16 : i % 50 == 0 ? 11 : i % 10 == 0 ? 7 : 4;
                            Tick(i, T, T - h * s);
                            if (i % 100 == 0 && i > 0) labels.Add((i.ToString(), i, T - 23 * s, false));
                        }
                        labels.Add(("px", 12 * s, T - 23 * s, true));
                    }
                }
                ticks.Freeze();
                dc.DrawGeometry(null, G.P(ink, 1), ticks);
                foreach (var (str, u, vc, faint) in labels)
                {
                    var ft = faint ? G.Text(str, 9 * s, G.A(ink, 0.5), FontWeights.SemiBold, win) : G.Text(str, 10 * s, ink, FontWeights.Medium, win);
                    dc.PushTransform(new TranslateTransform(u, vc));
                    if (flip) dc.PushTransform(new RotateTransform(180));
                    dc.DrawText(ft, new Point(-ft.Width / 2, -ft.Height / 2));
                    if (flip) dc.Pop();
                    dc.Pop();
                }

                // 끝 손잡이 (드래그 = 돌리기 + 늘이기)
                dc.DrawEllipse(null, G.P(G.A(ink, 0.35), 1.2 * s), new Point(L - r.Grip / 2, T / 2), 5 * s, 5 * s);

                if (r.MarkU is double a) dc.DrawRectangle(G.B(dark ? G.White(0.95) : G.Black(0.95)), null, new Rect(a, 0, 1, T));
                if (r.LiveEnd is double hu) dc.DrawRectangle(G.B(G.Red), null, new Rect(hu, 0, 1, T));

                dc.Pop(); dc.Pop(); dc.Pop();
            }
        }
    }

    // MARK: - 화면에서 재기 (사각형 드래그)

    sealed class MeasureWindow : Window
    {
        readonly Mon mon;
        public Action OnClose;
        Rect? rect;
        Point? mouse;
        enum DragKind { None, New, Move, Edges }
        DragKind drag;
        Point dragA; Rect dragR; double eL, eR, eT, eB;

        public MeasureWindow(Mon m)
        {
            mon = m;
            WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
            Topmost = true; ShowInTaskbar = false; ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Cursor = Cursors.Cross;
            Width = 1; Height = 1;
            W.AddExStyle(this, W.EX_TOOLWINDOW);
            DpiChanged += (s, e) => Dispatcher.BeginInvoke(new Action(Cover));
        }
        public void Cover() => W.Place(this, mon.Px.L, mon.Px.T, mon.Width, mon.Height, true);

        double Dpi => VisualTreeHelper.GetDpi(this).DpiScaleX;
        Point Snap(Point p) { double s = Dpi; return new Point(Math.Round(p.X * s) / s, Math.Round(p.Y * s) / s); }

        protected override void OnRender(DrawingContext dc)
        {
            double s = Dpi;
            var all = new Rect(0, 0, ActualWidth, ActualHeight);
            Geometry dim = new RectangleGeometry(all);
            if (rect is Rect rr) dim = new CombinedGeometry(GeometryCombineMode.Exclude, dim, new RectangleGeometry(rr));
            dc.DrawGeometry(G.B(G.Black(0.22)), null, dim);

            // 십자선
            if (mouse is Point m && drag == DragKind.None)
            {
                double x = (Math.Floor(m.X * s) + 0.5) / s, y = (Math.Floor(m.Y * s) + 0.5) / s;
                var pen = G.P(G.White(0.55), 1 / s);
                dc.DrawLine(pen, new Point(x, 0), new Point(x, all.Height));
                dc.DrawLine(pen, new Point(0, y), new Point(all.Width, y));
            }

            if (rect is Rect r && (r.Width > 0 || r.Height > 0))
            {
                // 바깥쪽에 1px 선 → 안쪽 크기가 곧 측정값
                double o = 1 / s;
                dc.DrawRectangle(G.B(Colors.Black), null, new Rect(r.X - 2 * o, r.Y - 2 * o, r.Width + 4 * o, r.Height + 4 * o));
                dc.DrawRectangle(G.B(Colors.White), null, new Rect(r.X - o, r.Y - o, r.Width + 2 * o, r.Height + 2 * o));
                dc.DrawRectangle(G.B(Color.FromArgb(3, 0, 0, 0)), null, r);  // 완전 투명이면 클릭이 뒤로 빠짐
                foreach (var c in new[] { r.TopLeft, r.TopRight, r.BottomLeft, r.BottomRight })
                    dc.DrawEllipse(G.B(Colors.White), G.P(Colors.Black, 1), c, 3, 3);

                double mm = Disp.MMPerDip(mon);
                var lines = new[]
                {
                    G.Text(Fmt.Pair(r.Width * mm, r.Height * mm), 14, Colors.White, FontWeights.SemiBold, s),
                    G.Text($"{Fmt.Px(r.Width * s)} × {Fmt.Px(r.Height * s)} px", 10.5, G.White(0.7), FontWeights.Medium, s),
                };
                bool below = r.Bottom < all.Height - 60;
                G.Pill(dc, lines, new Point(r.Left, below ? r.Bottom + 8 : r.Top - 8), 0, below ? 0 : 1, all);
            }

            const string help = "Drag to measure  ·  Drag edges/corners to adjust  ·  ← → ↑ ↓ move 1px (Alt resize, Shift ×10)  ·  Ctrl+C copy  ·  Esc close";
            G.Pill(dc, new[] { G.Text(help, 11, G.White(0.85), FontWeights.Medium, s) }, new Point(all.Width / 2, 44), 0.5, 0);
            if (Disp.SourceOf(mon) == Disp.Source.Guess)
                G.Pill(dc, new[] { G.Text("This display doesn't report its physical size, so mm values are estimates. Tray icon → Calibrate Display", 11, Colors.White, FontWeights.Medium, s) },
                    new Point(all.Width / 2, 72), 0.5, 0);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            var p = e.GetPosition(this);
            if (drag != DragKind.None && e.LeftButton == MouseButtonState.Pressed)
            {
                switch (drag)
                {
                    case DragKind.New:
                        var b = Snap(p);
                        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))  // 정사각형
                        {
                            double side = Math.Max(Math.Abs(b.X - dragA.X), Math.Abs(b.Y - dragA.Y));
                            b = new Point(dragA.X + (b.X >= dragA.X ? side : -side), dragA.Y + (b.Y >= dragA.Y ? side : -side));
                        }
                        rect = new Rect(dragA, b);
                        break;
                    case DragKind.Move:
                        var d = Snap(new Point(p.X - dragA.X, p.Y - dragA.Y));
                        rect = new Rect(dragR.X + d.X, dragR.Y + d.Y, dragR.Width, dragR.Height);
                        break;
                    case DragKind.Edges:
                        var e2 = Snap(new Point(p.X - dragA.X, p.Y - dragA.Y));
                        double minX = dragR.Left + e2.X * eL, maxX = dragR.Right + e2.X * eR;
                        double minY = dragR.Top + e2.Y * eT, maxY = dragR.Bottom + e2.Y * eB;
                        rect = new Rect(new Point(minX, minY), new Point(maxX, maxY));
                        break;
                }
            }
            mouse = p;
            InvalidateVisual();
        }
        protected override void OnMouseLeave(MouseEventArgs e) { mouse = null; InvalidateVisual(); }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            Activate(); Focus();
            var p = e.GetPosition(this);
            CaptureMouse();
            if (rect is Rect r)
            {
                const double tol = 6;
                var near = new Rect(r.X - tol, r.Y - tol, r.Width + 2 * tol, r.Height + 2 * tol).Contains(p);
                eL = Math.Abs(p.X - r.Left) < tol ? 1 : 0; eR = Math.Abs(p.X - r.Right) < tol ? 1 : 0;
                eT = Math.Abs(p.Y - r.Top) < tol ? 1 : 0; eB = Math.Abs(p.Y - r.Bottom) < tol ? 1 : 0;
                if (near && eL + eR + eT + eB > 0) { drag = DragKind.Edges; dragA = p; dragR = r; return; }
                if (r.Contains(p)) { drag = DragKind.Move; dragA = p; dragR = r; return; }
            }
            dragA = Snap(p);
            drag = DragKind.New;
            rect = new Rect(dragA, new Size(0, 0));
            InvalidateVisual();
        }
        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e) { drag = DragKind.None; ReleaseMouseCapture(); InvalidateVisual(); }
        protected override void OnMouseRightButtonUp(MouseButtonEventArgs e) { e.Handled = true; OnClose?.Invoke(); }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            var mods = Keyboard.Modifiers;
            e.Handled = true;
            if (key == Key.Escape) { OnClose?.Invoke(); return; }
            if (mods.HasFlag(ModifierKeys.Control) && key == Key.C && rect is Rect cr)
            {
                double mm = Disp.MMPerDip(mon), s = Dpi;
                try { Clipboard.SetText($"{Fmt.Pair(cr.Width * mm, cr.Height * mm)} ({Fmt.Px(cr.Width * s)} × {Fmt.Px(cr.Height * s)} px)"); } catch { }
                return;
            }
            if (!(rect is Rect r)) return;
            double step = (mods.HasFlag(ModifierKeys.Shift) ? 10 : 1) / Dpi;
            bool resize = mods.HasFlag(ModifierKeys.Alt);
            switch (key)
            {
                case Key.Left: if (resize) r.Width = Math.Max(0, r.Width - step); else r.X -= step; break;
                case Key.Right: if (resize) r.Width += step; else r.X += step; break;
                case Key.Up: if (resize) r.Height = Math.Max(0, r.Height - step); else r.Y -= step; break;
                case Key.Down: if (resize) r.Height += step; else r.Y += step; break;
                default: e.Handled = false; return;
            }
            rect = r;
            InvalidateVisual();
        }
    }

    sealed class Measure
    {
        readonly List<MeasureWindow> windows = new List<MeasureWindow>();
        public bool IsOpen => windows.Count > 0;

        public void Show()
        {
            Close();
            var cur = W.Cursor();
            foreach (var m in Mon.All())
            {
                var w = new MeasureWindow(m) { OnClose = Close };
                w.Show();
                w.Cover();
                windows.Add(w);
                if (m.Contains(cur.X, cur.Y)) { w.Activate(); w.Focus(); }
            }
        }
        public void Close()
        {
            foreach (var w in windows) w.Close();
            windows.Clear();
        }
        public void Toggle() { if (IsOpen) Close(); else Show(); }
    }

    // MARK: - 화면 보정 (카드 맞추기)

    sealed class CalibrationWindow : Window
    {
        const double CardW = 85.60, CardH = 53.98;  // ISO/IEC 7810 ID-1 (신용·교통카드)
        double cardW;
        double? dragX0, dragW0;
        readonly Face face;

        public CalibrationWindow()
        {
            Title = "Calibrate Display";
            Width = 760; Height = 560;
            ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Topmost = true;
            face = new Face(this);
            var save = new Button { Content = "Save", Width = 90, Height = 30, IsDefault = true, Margin = new Thickness(8, 0, 0, 0) };
            var reset = new Button { Content = "Revert to Auto", Width = 150, Height = 30 };
            save.Click += (s, e) => { Disp.Save(CardW / cardW, Mon.Of(this)); Close(); };
            reset.Click += (s, e) => { Disp.Reset(Mon.Of(this)); ResetFromScreen(); };
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 30, 24) };
            buttons.Children.Add(reset); buttons.Children.Add(save);
            var grid = new Grid();
            grid.Children.Add(face); grid.Children.Add(buttons);
            Content = grid;
            Loaded += (s, e) => ResetFromScreen();
            DpiChanged += (s, e) => ResetFromScreen();
            LocationChanged += (s, e) => face.InvalidateVisual();
        }
        void ResetFromScreen() { cardW = CardW / Disp.MMPerDip(Mon.Of(this)); face.InvalidateVisual(); }

        protected override void OnPreviewKeyDown(KeyEventArgs e)
        {
            double step = (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) ? 10 : 1) / VisualTreeHelper.GetDpi(this).DpiScaleX;
            switch (e.Key)
            {
                case Key.Left: cardW = Math.Max(100, cardW - step); break;
                case Key.Right: cardW += step; break;
                case Key.Escape: Close(); return;
                default: return;
            }
            e.Handled = true;
            face.InvalidateVisual();
        }

        sealed class Face : FrameworkElement
        {
            readonly CalibrationWindow w;
            public Face(CalibrationWindow w)
            {
                this.w = w;
                MouseLeftButtonDown += (s, e) => { w.dragX0 = W.Cursor().X; w.dragW0 = w.cardW; CaptureMouse(); };
                MouseMove += (s, e) =>
                {
                    if (w.dragX0 is double x0 && w.dragW0 is double w0)
                    {
                        w.cardW = Math.Max(100, w0 + (W.Cursor().X - x0) / VisualTreeHelper.GetDpi(this).DpiScaleX);
                        InvalidateVisual();
                    }
                };
                MouseLeftButtonUp += (s, e) => { w.dragX0 = null; ReleaseMouseCapture(); };
            }
            protected override void OnRender(DrawingContext dc)
            {
                double s = VisualTreeHelper.GetDpi(this).DpiScaleX;
                dc.DrawRectangle(G.B(Color.FromRgb(246, 246, 246)), null, new Rect(0, 0, ActualWidth, ActualHeight));
                double cw = w.cardW, ch = cw * CardH / CardW;
                var r = new Rect(40, 110, cw, ch);
                double radius = cw * 3.18 / 85.6;
                dc.DrawRoundedRectangle(G.B(G.Black(0.07)), G.P(Colors.Black, 1 / s), r, radius, radius);
                dc.DrawRectangle(G.B(G.Red), null, new Rect(r.Right - 1.5, r.Top, 3, r.Height));  // 오른쪽 손잡이

                dc.DrawText(G.Text("Hold a credit card against the screen and drag the red line to match the card's width.", 13, Colors.Black, FontWeights.SemiBold, s), new Point(40, 30));
                dc.DrawText(G.Text("← →  adjust 1px · hold Shift for 10px · height follows automatically", 12, Color.FromRgb(110, 110, 110), FontWeights.Normal, s), new Point(40, 52));
                var m = Mon.Of(w);
                var src = Disp.SourceOf(m) == Disp.Source.Calibrated ? "Using calibrated value"
                    : Disp.SourceOf(m) == Disp.Source.Auto ? "Using auto-detected value"
                    : "No size info from this display, using an estimate (calibration recommended)";
                double ppi = 25.4 / (CardW / cw);
                var info = $"{m.Name.TrimStart('\\', '.')} · {src} · now {ppi.ToString("F1", CultureInfo.InvariantCulture)} DIP/inch";
                if (Disp.AutoMMPerDip(m) is double a) info += $" · auto-detected screen width {(a * m.Width / m.Scale).ToString("F0", CultureInfo.InvariantCulture)} mm";
                dc.DrawText(G.Text(info, 12, Color.FromRgb(110, 110, 110), FontWeights.Normal, s), new Point(40, ActualHeight - 90));
            }
        }
    }

    // MARK: - 자 설정 창

    sealed class SettingsWindow : Window
    {
        bool syncing;
        readonly Button color1 = Swatch(), color2 = Swatch(), removeImage = new Button { Content = "Remove", Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(6, 0, 0, 0) };
        readonly CheckBox gradient = new CheckBox { Content = "Horizontal gradient", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
        readonly Slider opacity = new Slider { Minimum = 15, Maximum = 95, Width = 240 }, thickness = new Slider { Minimum = 40, Maximum = 160, Width = 240 };
        readonly RadioButton metric = new RadioButton { Content = "mm · cm", Margin = new Thickness(0, 0, 14, 0) }, inch = new RadioButton { Content = "inch" };
        readonly CheckBox showReal = new CheckBox { Content = "cm (physical length)", Margin = new Thickness(0, 0, 14, 0) }, showPx = new CheckBox { Content = "px (screen)" };
        readonly CheckBox snap = new CheckBox { Content = "Snap to 90°" };

        static Button Swatch() => new Button { Width = 44, Height = 24, Margin = new Thickness(0, 0, 8, 0) };

        public SettingsWindow()
        {
            Title = "Ruler Settings";
            SizeToContent = SizeToContent.WidthAndHeight;
            ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Topmost = true;
            FontFamily = new FontFamily("Segoe UI"); FontSize = 13;

            var rows = new StackPanel { Margin = new Thickness(20, 16, 20, 16) };
            void Row(string title, params UIElement[] els)
            {
                var p = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 6) };
                p.Children.Add(new TextBlock { Text = title, Width = 80, FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center });
                foreach (var e in els) p.Children.Add(e);
                rows.Children.Add(p);
            }
            var choose = new Button { Content = "Choose Photo…", Padding = new Thickness(10, 3, 10, 3) };
            Row("Color", color1, color2, gradient);
            Row("Photo", choose, removeImage);
            Row("Opacity", opacity);
            Row("Thickness", thickness);
            Row("Units", metric, inch);
            Row("Ticks", showReal, showPx);
            Row("Angle", snap);
            var bottom = new DockPanel { Margin = new Thickness(0, 12, 0, 0), LastChildFill = false };
            var hint = new TextBlock { Text = "Drag end handle to rotate · Shift 15°", FontSize = 11, Foreground = Brushes.Gray, VerticalAlignment = VerticalAlignment.Center };
            var reset = new Button { Content = "Restore Defaults", Padding = new Thickness(10, 3, 10, 3) };
            DockPanel.SetDock(hint, Dock.Left); DockPanel.SetDock(reset, Dock.Right);
            bottom.Children.Add(hint); bottom.Children.Add(reset);
            rows.Children.Add(bottom);
            Content = rows;

            color1.Click += (s, e) => { if (Pick(St.Color) is Color c) St.Color = c; };
            color2.Click += (s, e) => { if (Pick(St.Color2) is Color c) St.Color2 = c; };
            gradient.Click += (s, e) => St.Gradient = gradient.IsChecked == true;
            choose.Click += (s, e) => PickImage();
            removeImage.Click += (s, e) => { DeleteImage(); St.ImagePath = null; };
            opacity.ValueChanged += (s, e) => { if (!syncing) St.Opacity = opacity.Value / 100; };
            thickness.ValueChanged += (s, e) => { if (!syncing) St.Thickness = Math.Round(thickness.Value); };
            metric.Checked += (s, e) => { if (!syncing) St.Inch = false; };
            inch.Checked += (s, e) => { if (!syncing) St.Inch = true; };
            showReal.Click += (s, e) => St.ShowReal = showReal.IsChecked == true;
            showPx.Click += (s, e) => St.ShowPx = showPx.IsChecked == true;
            snap.Click += (s, e) => St.Snap90 = snap.IsChecked == true;
            reset.Click += (s, e) => St.ResetLook();

            St.Changed += Sync;
            Closed += (s, e) => St.Changed -= Sync;
            Sync();
        }

        void Sync()
        {
            syncing = true;
            color1.Background = G.B(St.Color);
            color2.Background = G.B(St.Color2);
            color2.IsEnabled = St.Gradient;
            gradient.IsChecked = St.Gradient;
            opacity.Value = St.Opacity * 100;
            thickness.Value = St.Thickness;
            metric.IsChecked = !St.Inch; inch.IsChecked = St.Inch;
            showReal.IsChecked = St.ShowReal; showPx.IsChecked = St.ShowPx;
            snap.IsChecked = St.Snap90;
            removeImage.IsEnabled = St.ImagePath != null;
            syncing = false;
        }

        static Color? Pick(Color c)
        {
            using (var d = new WF.ColorDialog { Color = SD.Color.FromArgb(c.R, c.G, c.B), FullOpen = true })
                return d.ShowDialog() == WF.DialogResult.OK ? Color.FromRgb(d.Color.R, d.Color.G, d.Color.B) : (Color?)null;
        }
        void PickImage()
        {
            var d = new OpenFileDialog { Title = "Choose a photo for the ruler", Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff|All files|*.*" };
            if (d.ShowDialog(this) != true) return;
            try
            {
                Directory.CreateDirectory(Store.Dir);
                DeleteImage();
                var dst = Path.Combine(Store.Dir, $"ruler-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}{Path.GetExtension(d.FileName)}");
                File.Copy(d.FileName, dst, true);
                St.ImagePath = dst;
                if (St.Image == null) { DeleteImage(); St.ImagePath = null; }
            }
            catch { }
        }
        static void DeleteImage() { try { if (St.ImagePath is string p) File.Delete(p); } catch { } }
    }

    // MARK: - 앱

    sealed class App
    {
        readonly Ruler ruler = new Ruler();
        readonly Measure measure = new Measure();
        readonly WF.NotifyIcon tray = new WF.NotifyIcon();
        SettingsWindow settings;
        CalibrationWindow calibration;
        HwndSource hotkeys;
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        public void Start()
        {
            ruler.CenterOn(Mon.AtCursor());
            ruler.OnMenu = c => ShowMenu(c);

            tray.Icon = SD.Icon.ExtractAssociatedIcon(System.Reflection.Assembly.GetExecutingAssembly().Location);
            tray.Text = "zap";
            tray.Visible = true;
            // 왼쪽 클릭도 메뉴. NotifyIcon 내부 메서드를 써야 바깥을 눌렀을 때 메뉴가 닫힌다.
            tray.MouseUp += (s, e) =>
            {
                if (e.Button == WF.MouseButtons.Left)
                    typeof(WF.NotifyIcon).GetMethod("ShowContextMenu", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)?.Invoke(tray, null);
            };
            tray.ContextMenuStrip = new WF.ContextMenuStrip();
            tray.ContextMenuStrip.Opening += (s, e) => Fill(tray.ContextMenuStrip, false);

            // 전역 단축키: Ctrl+Alt+R 자, Ctrl+Alt+M 화면 재기
            hotkeys = new HwndSource(new HwndSourceParameters("zap-hotkeys") { Width = 0, Height = 0, WindowStyle = 0, ParentWindow = new IntPtr(-3) });
            hotkeys.AddHook((IntPtr h, int msg, IntPtr wp, IntPtr lp, ref bool handled) =>
            {
                if (msg == 0x0312) { if (wp.ToInt32() == 1) ruler.Toggle(); else if (wp.ToInt32() == 2) measure.Toggle(); handled = true; }
                return IntPtr.Zero;
            });
            const uint ctrlAlt = 0x1 | 0x2 | 0x4000;  // MOD_ALT | MOD_CONTROL | MOD_NOREPEAT
            W.RegisterHotKey(hotkeys.Handle, 1, ctrlAlt, 0x52);  // R
            W.RegisterHotKey(hotkeys.Handle, 2, ctrlAlt, 0x4D);  // M

            ruler.ShowRuler();
            if (Store.Get("welcomed") == null)
            {
                Store.Set("welcomed", "1");
                tray.ShowBalloonTip(4000, "zap", "zap lives in the tray (^ next to the clock). Ctrl+Alt+R toggles the ruler.", WF.ToolTipIcon.None);
            }
        }

        /// GitHub Actions의 Windows 서버에서 돌리는 점검: 창 상태를 기록하고 화면을 캡처한 뒤 종료
        public void RunSelfTest(Action<int> done)
        {
            int step = 0;
            var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            t.Tick += (s, e) =>
            {
                try
                {
                    switch (step++)
                    {
                        case 0:
                            Program.Log($"ruler visible={ruler.IsVisible} pos=({ruler.Left},{ruler.Top}) size=({ruler.ActualWidth}x{ruler.ActualHeight}) origin=({ruler.OX},{ruler.OY}) len={ruler.Len} T={ruler.T} scale={ruler.Sc}");
                            foreach (var m in Mon.All()) Program.Log($"monitor {m.Name} {m.Width}x{m.Height} scale={m.Scale} mmPerDip={Disp.MMPerDip(m)} src={Disp.SourceOf(m)}");
                            Snap("1-ruler.png");
                            ruler.Rotate(Math.PI / 6);
                            break;
                        case 1:
                            Snap("2-rotated.png");
                            OpenSettings();
                            break;
                        case 2:
                            Snap("3-settings.png");
                            settings?.Close();
                            measure.Show();
                            break;
                        case 3:
                            Snap("4-measure.png");
                            measure.Close();
                            OpenCalibration();
                            break;
                        case 4:
                            Snap("5-calibration.png");
                            calibration?.Close();
                            t.Stop();
                            Program.Log("selftest ok");
                            done(0);
                            break;
                    }
                }
                catch (Exception ex) { t.Stop(); Program.Log("selftest FAIL " + ex); done(2); }
            };
            t.Start();
        }
        static void Snap(string name)
        {
            var b = WF.SystemInformation.VirtualScreen;
            using (var bmp = new SD.Bitmap(b.Width, b.Height))
            {
                using (var g = SD.Graphics.FromImage(bmp)) g.CopyFromScreen(b.Left, b.Top, 0, 0, bmp.Size);
                bmp.Save(Path.Combine(Store.Dir, name), SD.Imaging.ImageFormat.Png);
            }
            Program.Log("snap " + name);
        }

        void ShowMenu(bool contextual)
        {
            var m = new WF.ContextMenuStrip();
            Fill(m, contextual);
            m.Closed += (s, e) => m.Dispose();
            m.Show(WF.Cursor.Position);
        }

        void Fill(WF.ContextMenuStrip m, bool contextual)
        {
            m.Items.Clear();
            WF.ToolStripMenuItem Add(WF.ToolStripItemCollection to, string title, Action a, string keys = null, bool check = false)
            {
                var it = new WF.ToolStripMenuItem(title) { ShortcutKeyDisplayString = keys, Checked = check };
                if (a != null) it.Click += (s, e) => a();
                to.Add(it);
                return it;
            }
            var items = m.Items;
            Add(items, ruler.IsVisible ? "Hide Ruler" : "Show Ruler", ruler.Toggle, "Ctrl+Alt+R");
            Add(items, "Rotate Ruler 90°", () => { if (!ruler.IsVisible) ruler.ShowRuler(); ruler.Rotate(Math.PI / 2); });
            Add(items, "Measure Screen", measure.Show, "Ctrl+Alt+M");
            items.Add(new WF.ToolStripSeparator());

            var unit = Add(items, "Units", null);
            Add(unit.DropDownItems, "mm · cm", () => St.Inch = false, null, !St.Inch);
            Add(unit.DropDownItems, "inch", () => St.Inch = true, null, St.Inch);
            var op = Add(items, "Ruler Opacity", null);
            foreach (var v in new[] { 0.3, 0.45, 0.55, 0.7, 0.85 })
                Add(op.DropDownItems, $"{(int)Math.Round(v * 100)}%", () => St.Opacity = v, null, Math.Abs(St.Opacity - v) < 0.051);

            items.Add(new WF.ToolStripSeparator());
            Add(items, "Ruler Settings…", OpenSettings);
            Add(items, "Calibrate Display…", OpenCalibration);
            if (!contextual)
            {
                items.Add(new WF.ToolStripSeparator());
                Add(items, "Start with Windows", ToggleLogin, null, LoginEnabled);
                Add(items, "Quit zap", Quit);
                items.Add(new WF.ToolStripSeparator());
                items.Add(new WF.ToolStripLabel("Standing Studio") { ForeColor = SD.Color.Gray, Font = new SD.Font("Segoe UI", 7.5f) });
            }
        }

        void OpenSettings()
        {
            if (settings == null) { settings = new SettingsWindow(); settings.Closed += (s, e) => settings = null; settings.Show(); }
            settings.Activate();
        }
        void OpenCalibration()
        {
            if (calibration == null) { calibration = new CalibrationWindow(); calibration.Closed += (s, e) => calibration = null; calibration.Show(); }
            calibration.Activate();
        }

        static bool LoginEnabled
        {
            get { using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k?.GetValue("zap") != null; }
        }
        static void ToggleLogin()
        {
            using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (k.GetValue("zap") != null) k.DeleteValue("zap", false);
                else k.SetValue("zap", "\"" + System.Reflection.Assembly.GetExecutingAssembly().Location + "\"");
            }
        }

        void Quit()
        {
            tray.Visible = false;
            tray.Dispose();
            Application.Current.Shutdown();
        }
    }

    static class Program
    {
        static readonly string LogPath = Path.Combine(Store.Dir, "zap.log");
        public static void Log(string msg)
        {
            try { Directory.CreateDirectory(Store.Dir); File.AppendAllText(LogPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {msg}\r\n"); } catch { }
            Console.WriteLine(msg);
        }
        static void Crash(object e)
        {
            Log("CRASH " + e);
            if (!SelfTest) MessageBox.Show("zap ran into a problem and has to close.\n\n" + e + "\n\nLog: " + LogPath, "zap", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        public static bool SelfTest;

        [STAThread]
        static int Main(string[] args)
        {
            SelfTest = args.Contains("--selftest");
            AppDomain.CurrentDomain.UnhandledException += (s, e) => { Crash(e.ExceptionObject); Environment.Exit(1); };
            using (var single = new Mutex(true, "studio.standing.zap", out bool first))
            {
                if (!first) { Log("already running"); return 0; }
                Log($"start {Environment.OSVersion} clr {Environment.Version} 64bit={Environment.Is64BitProcess}");
                var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                app.DispatcherUnhandledException += (s, e) => { Crash(e.Exception); e.Handled = true; app.Shutdown(1); };
                int code = 0;
                app.Startup += (s, e) =>
                {
                    var a = new App();
                    a.Start();
                    Log("started");
                    if (SelfTest) a.RunSelfTest(c => { code = c; app.Shutdown(c); });
                };
                app.Run();
                return code;
            }
        }
    }
}
