param(
    # 2026-10-05：扫描间隔限定为有效范围，宿主信息由扩展传入以锁定进程归属。
    [ValidateRange(50, 60000)][int]$PollMs = 500,
    [ValidateRange(0, 60000)][int]$CooldownMs = 1500,
    [string]$RestoreCursor = 'true',
    [string]$HostExecutablePath = '',
    [ValidateRange(0, 2147483647)][int]$ParentProcessId = 0,
    [switch]$SelfTest
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MouseHelper {
    // 2026-07-28 物理点击前记录鼠标位置，回退点击后尽量不打断用户操作
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }
    // 2026-10-07：原生指针对齐保持 32/64 位兼容，移动、按下、释放和恢复由同一批次连续提交。
    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION {
        [FieldOffset(0)]
        public MOUSEINPUT mi;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public INPUTUNION data;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetPhysicalCursorPos(out POINT lpPoint);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint count, [In, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] INPUT[] inputs, int size);
    [DllImport("user32.dll")]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")]
    public static extern int GetSystemMetricsForDpi(int index, uint dpi);
    [DllImport("user32.dll")]
    public static extern bool GetClipCursor(out RECT rectangle);
    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromPoint(POINT point, uint flags);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int virtualKey);
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("kernel32.dll")]
    public static extern uint GetTickCount();
    // 2026-10-05：物理回退只接受目标顶层窗口内的坐标，遮挡或失效时跳过。
    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    // 2026-10-07：按窗口 PID 查询完整映像，避免轮询枚举全系统进程和跨位数 MainModule 读取。
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    public static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, System.Text.StringBuilder imagePath, ref uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);
    public static string GetProcessImagePath(uint processId) {
        if (processId == 0) { return null; }
        IntPtr process = OpenProcess(0x101000, false, processId);
        if (process == IntPtr.Zero) { return null; }
        try {
            // 2026-10-07：同一句柄在查询前后均须未退出，退出码 259 也不能当作进程存活。
            if (WaitForSingleObject(process, 0) != 258) { return null; }
            System.Text.StringBuilder imagePath = new System.Text.StringBuilder(512);
            uint size = (uint)imagePath.Capacity;
            if (!QueryFullProcessImageNameW(process, 0, imagePath, ref size)) {
                if (Marshal.GetLastWin32Error() != 122) { return null; }
                // 2026-10-07：仅缓冲不足时扩容一次，普通路径不按最长路径分配。
                imagePath = new System.Text.StringBuilder(32768);
                size = (uint)imagePath.Capacity;
                if (!QueryFullProcessImageNameW(process, 0, imagePath, ref size)) { return null; }
            }
            if (WaitForSingleObject(process, 0) != 258) { return null; }
            return imagePath.ToString();
        }
        finally { CloseHandle(process); }
    }
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    // 2026-10-07：不接管用户正在按住的鼠标键、修饰键或系统快捷键。
    private static readonly int[] inputKeys = { 1, 2, 4, 5, 6, 16, 17, 18, 91, 92 };
    public static bool IsHitTargetWindow(IntPtr target, IntPtr root, bool exists, bool visible,
                                        bool enabled, bool iconic, uint actualProcessId, uint expectedProcessId) {
        return target != IntPtr.Zero && root == target && exists && visible && enabled && !iconic &&
               expectedProcessId != 0 && actualProcessId == expectedProcessId;
    }
    public static bool IsPointOwnedByWindow(int x, int y, IntPtr target, uint expectedProcessId) {
        POINT point = new POINT { X = x, Y = y };
        IntPtr hit = WindowFromPoint(point);
        IntPtr root = GetAncestor(hit, 2);
        uint actualProcessId;
        GetWindowThreadProcessId(target, out actualProcessId);
        return IsHitTargetWindow(target, root, IsWindow(target), IsWindowVisible(target),
                                 IsWindowEnabled(target), IsIconic(target), actualProcessId, expectedProcessId);
    }
    // 2026-10-07：最后输入戳只用于发现变化，不当作递增计数或输入事件身份。
    private static bool TryGetInputTime(out uint inputTime) {
        LASTINPUTINFO info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO)) };
        inputTime = 0;
        if (!GetLastInputInfo(ref info)) { return false; }
        inputTime = info.dwTime;
        return true;
    }
    private static bool AreInputKeysReleased() {
        foreach (int key in inputKeys) {
            if ((GetAsyncKeyState(key) & 0x8000) != 0) { return false; }
        }
        return true;
    }
    private static bool IsInputUnchanged(uint expectedTime) {
        uint currentTime;
        return AreInputKeysReleased() && TryGetInputTime(out currentTime) && currentTime == expectedTime;
    }
    private static bool IsTargetCurrent(Func<bool> validateTarget) {
        try { return validateTarget != null && validateTarget(); }
        catch { return false; }
    }
    // 2026-10-09：会聚焦的界面操作仅限当前前台且输入空闲；只读重查不激活窗口或恢复用户焦点。
    public static bool CanUseForegroundUi(IntPtr target) {
        try {
            if (target == IntPtr.Zero || GetForegroundWindow() != target) { return false; }
            // 2026-10-09：普通键首轮重复可能延迟，不能只靠输入年龄或鼠标、修饰键判断长按。
            for (int key = 1; key < 256; key++) {
                if ((GetAsyncKeyState(key) & 0x8000) != 0) { return false; }
            }
            uint inputTime;
            if (!TryGetInputTime(out inputTime)) { return false; }
            uint age = unchecked(GetTickCount() - inputTime);
            if (age < 500 || age > Int32.MaxValue) { return false; }
            for (int key = 1; key < 256; key++) {
                if ((GetAsyncKeyState(key) & 0x8000) != 0) { return false; }
            }
            return IsInputUnchanged(inputTime) && GetForegroundWindow() == target;
        }
        catch { return false; }
    }
    // 2026-10-07：归一化到像素中心，使用长整数避免负屏幕原点、边缘像素和乘法溢出。
    private static bool TryNormalizePoint(POINT point, int left, int top, int width, int height, RECT clip,
                                          out int normalizedX, out int normalizedY) {
        normalizedX = normalizedY = 0;
        long offsetX = (long)point.X - left, offsetY = (long)point.Y - top;
        if (width <= 0 || height <= 0 || width > 65536 || height > 65536 ||
            offsetX < 0 || offsetX >= width || offsetY < 0 || offsetY >= height ||
            point.X < clip.Left || point.X >= clip.Right || point.Y < clip.Top || point.Y >= clip.Bottom) { return false; }
        // 2026-10-07：从像素对应的可表示区间取中点，65535 像素的宽屏也不能向左偏移一像素。
        long firstX = (offsetX * 65536L + width - 1) / width;
        long lastX = ((offsetX + 1) * 65536L + width - 1) / width - 1;
        long firstY = (offsetY * 65536L + height - 1) / height;
        long lastY = ((offsetY + 1) * 65536L + height - 1) / height - 1;
        normalizedX = (int)((firstX + lastX) / 2);
        normalizedY = (int)((firstY + lastY) / 2);
        return true;
    }
    // 2026-10-07：提交前只做只读核验；同一 SendInput 批次没有鼠标停留，也不在用户输入后单独拉回。
    public static bool Click(int x, int y, bool restoreCursor, IntPtr target, uint expectedProcessId, Func<bool> validateTarget) {
        IntPtr originalDpi = IntPtr.Zero;
        try {
            // 2026-10-07：UIA 使用物理坐标，只临时切换本线程 DPI 上下文，退出时恢复原上下文。
            originalDpi = SetThreadDpiAwarenessContext(new IntPtr(-4));
            if (originalDpi == IntPtr.Zero || !AreInputKeysReleased()) { return false; }
            uint inputTime;
            if (!TryGetInputTime(out inputTime)) { return false; }
            uint inputAge = unchecked(GetTickCount() - inputTime);
            if (inputAge < 500 || inputAge > Int32.MaxValue) { return false; }
            POINT oldPoint;
            if (!GetPhysicalCursorPos(out oldPoint)) { return false; }
            int left = GetSystemMetricsForDpi(76, 96), top = GetSystemMetricsForDpi(77, 96);
            int width = GetSystemMetricsForDpi(78, 96), height = GetSystemMetricsForDpi(79, 96);
            RECT clip;
            if (!GetClipCursor(out clip)) { return false; }
            int targetX, targetY, restoreX, restoreY;
            if (!TryNormalizePoint(new POINT { X = x, Y = y }, left, top, width, height, clip, out targetX, out targetY) ||
                !TryNormalizePoint(oldPoint, left, top, width, height, clip, out restoreX, out restoreY)) { return false; }
            INPUT[] inputs = new INPUT[restoreCursor ? 4 : 3];
            inputs[0].data.mi.dx = targetX;
            inputs[0].data.mi.dy = targetY;
            inputs[0].data.mi.dwFlags = 0x0001 | 0x8000 | 0x4000;
            inputs[1].data.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
            inputs[2].data.mi.dwFlags = MOUSEEVENTF_LEFTUP;
            if (restoreCursor) {
                inputs[3].data.mi.dx = restoreX;
                inputs[3].data.mi.dy = restoreY;
                inputs[3].data.mi.dwFlags = inputs[0].data.mi.dwFlags;
            }
            int inputSize = Marshal.SizeOf(typeof(INPUT));
            if (!IsTargetCurrent(validateTarget)) { return false; }
            RECT currentClip;
            if (GetSystemMetricsForDpi(76, 96) != left || GetSystemMetricsForDpi(77, 96) != top ||
                GetSystemMetricsForDpi(78, 96) != width || GetSystemMetricsForDpi(79, 96) != height ||
                !GetClipCursor(out currentClip) || currentClip.Left != clip.Left || currentClip.Top != clip.Top ||
                currentClip.Right != clip.Right || currentClip.Bottom != clip.Bottom) { return false; }
            // 2026-10-07：虚拟屏幕可能含显示器空隙，屏幕查询后最后核验窗口归属和前台。
            if (MonitorFromPoint(new POINT { X = x, Y = y }, 0) == IntPtr.Zero || MonitorFromPoint(oldPoint, 0) == IntPtr.Zero) { return false; }
            if (!IsPointOwnedByWindow(x, y, target, expectedProcessId)) { return false; }
            if (GetForegroundWindow() != target) { return false; }
            POINT currentPoint;
            if (!IsInputUnchanged(inputTime) || !GetPhysicalCursorPos(out currentPoint) ||
                currentPoint.X != oldPoint.X || currentPoint.Y != oldPoint.Y) { return false; }
            uint inserted = SendInput((uint)inputs.Length, inputs, inputSize);
            // 2026-10-07：只插入移动和按下时尽力补释放；不追加移动或重新批准，补偿被拒绝仍返回失败。
            if (inserted == 2) { SendInput(1, new INPUT[] { inputs[2] }, inputSize); }
            return inserted >= 3 && inserted <= inputs.Length;
        }
        catch { return false; }
        finally {
            if (originalDpi != IntPtr.Zero) { SetThreadDpiAwarenessContext(originalDpi); }
        }
    }
}
// 2026-10-07：原生 UIA 契约按完整 SDK vtable 声明，只调用已绑定窗口中的 Legacy 默认动作。
// SDK 快照 SHA256：66B00453430CC6884482352EBC0DDF6DB3916E38BF5684CABA79D6E86AA1F038。
// 来源：https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/um/UIAutomationClient.h
// 未使用的原生接口/缓冲区保留 IntPtr 声明；使用时必须另行满足指针和释放契约。
namespace AntigravityUia
{
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [Flags] public enum TreeScope { None = 0, Element = 1, Children = 2, Descendants = 4, Parent = 8, Ancestors = 16, Subtree = 7 }
    [Flags] public enum PropertyConditionFlags { None = 0, IgnoreCase = 1, MatchSubstring = 2 }
    public enum OrientationType { None = 0, Horizontal = 1, Vertical = 2 }

    [ComImport, Guid("34723aff-0c9d-49d0-9896-7ab52df8cd8a"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IUIAutomation2
    {
        [PreserveSig] int CompareElements([MarshalAs(UnmanagedType.Interface)] IUIAutomationElement el1, [MarshalAs(UnmanagedType.Interface)] IUIAutomationElement el2, [MarshalAs(UnmanagedType.Bool)] out bool areSame);
        [PreserveSig] int CompareRuntimeIds([MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] int[] runtimeId1, [MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] int[] runtimeId2, [MarshalAs(UnmanagedType.Bool)] out bool areSame);
        [PreserveSig] int GetRootElement([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement root);
        [PreserveSig] int ElementFromHandle(IntPtr hwnd, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
        [PreserveSig] int ElementFromPoint(POINT pt, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
        [PreserveSig] int GetFocusedElement([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
        [PreserveSig] int GetRootElementBuildCache(IntPtr cacheRequest, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement root);
        [PreserveSig] int ElementFromHandleBuildCache(IntPtr hwnd, IntPtr cacheRequest, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
        [PreserveSig] int ElementFromPointBuildCache(POINT pt, IntPtr cacheRequest, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
        [PreserveSig] int GetFocusedElementBuildCache(IntPtr cacheRequest, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
        [PreserveSig] int CreateTreeWalker([MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition pCondition, out IntPtr walker);
        [PreserveSig] int get_ControlViewWalker(out IntPtr walker);
        [PreserveSig] int get_ContentViewWalker(out IntPtr walker);
        [PreserveSig] int get_RawViewWalker(out IntPtr walker);
        [PreserveSig] int get_RawViewCondition([MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition condition);
        [PreserveSig] int get_ControlViewCondition([MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition condition);
        [PreserveSig] int get_ContentViewCondition([MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition condition);
        [PreserveSig] int CreateCacheRequest(out IntPtr cacheRequest);
        [PreserveSig] int CreateTrueCondition([MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreateFalseCondition([MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreatePropertyCondition(int propertyId, [MarshalAs(UnmanagedType.Struct)] object @value, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreatePropertyConditionEx(int propertyId, [MarshalAs(UnmanagedType.Struct)] object @value, PropertyConditionFlags flags, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreateAndCondition([MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition1, [MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition2, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreateAndConditionFromArray([MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_UNKNOWN)] object[] conditions, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreateAndConditionFromNativeArray(IntPtr conditions, int conditionCount, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreateOrCondition([MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition1, [MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition2, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreateOrConditionFromArray([MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_UNKNOWN)] object[] conditions, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreateOrConditionFromNativeArray(IntPtr conditions, int conditionCount, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int CreateNotCondition([MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationCondition newCondition);
        [PreserveSig] int AddAutomationEventHandler(int eventId, [MarshalAs(UnmanagedType.Interface)] IUIAutomationElement element, TreeScope scope, IntPtr cacheRequest, IntPtr handler);
        [PreserveSig] int RemoveAutomationEventHandler(int eventId, [MarshalAs(UnmanagedType.Interface)] IUIAutomationElement element, IntPtr handler);
        [PreserveSig] int AddPropertyChangedEventHandlerNativeArray([MarshalAs(UnmanagedType.Interface)] IUIAutomationElement element, TreeScope scope, IntPtr cacheRequest, IntPtr handler, IntPtr propertyArray, int propertyCount);
        [PreserveSig] int AddPropertyChangedEventHandler([MarshalAs(UnmanagedType.Interface)] IUIAutomationElement element, TreeScope scope, IntPtr cacheRequest, IntPtr handler, [MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] int[] propertyArray);
        [PreserveSig] int RemovePropertyChangedEventHandler([MarshalAs(UnmanagedType.Interface)] IUIAutomationElement element, IntPtr handler);
        [PreserveSig] int AddStructureChangedEventHandler([MarshalAs(UnmanagedType.Interface)] IUIAutomationElement element, TreeScope scope, IntPtr cacheRequest, IntPtr handler);
        [PreserveSig] int RemoveStructureChangedEventHandler([MarshalAs(UnmanagedType.Interface)] IUIAutomationElement element, IntPtr handler);
        [PreserveSig] int AddFocusChangedEventHandler(IntPtr cacheRequest, IntPtr handler);
        [PreserveSig] int RemoveFocusChangedEventHandler(IntPtr handler);
        [PreserveSig] int RemoveAllEventHandlers();
        [PreserveSig] int IntNativeArrayToSafeArray(IntPtr array, int arrayCount, [MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] out int[] safeArray);
        [PreserveSig] int IntSafeArrayToNativeArray([MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] int[] intArray, out IntPtr array, out int arrayCount);
        [PreserveSig] int RectToVariant(RECT rc, [MarshalAs(UnmanagedType.Struct)] out object var);
        [PreserveSig] int VariantToRect([MarshalAs(UnmanagedType.Struct)] object var, out RECT rc);
        [PreserveSig] int SafeArrayToRectNativeArray([MarshalAs(UnmanagedType.SafeArray)] Array rects, out IntPtr rectArray, out int rectArrayCount);
        [PreserveSig] int CreateProxyFactoryEntry(IntPtr factory, out IntPtr factoryEntry);
        [PreserveSig] int get_ProxyFactoryMapping(out IntPtr factoryMapping);
        [PreserveSig] int GetPropertyProgrammaticName(int property, [MarshalAs(UnmanagedType.BStr)] out string name);
        [PreserveSig] int GetPatternProgrammaticName(int pattern, [MarshalAs(UnmanagedType.BStr)] out string name);
        [PreserveSig] int PollForPotentialSupportedPatterns([MarshalAs(UnmanagedType.Interface)] IUIAutomationElement pElement, [MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] out int[] patternIds, [MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_BSTR)] out string[] patternNames);
        [PreserveSig] int PollForPotentialSupportedProperties([MarshalAs(UnmanagedType.Interface)] IUIAutomationElement pElement, [MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] out int[] propertyIds, [MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_BSTR)] out string[] propertyNames);
        [PreserveSig] int CheckNotSupported([MarshalAs(UnmanagedType.Struct)] object @value, [MarshalAs(UnmanagedType.Bool)] out bool isNotSupported);
        [PreserveSig] int get_ReservedNotSupportedValue([MarshalAs(UnmanagedType.IUnknown)] out object notSupportedValue);
        [PreserveSig] int get_ReservedMixedAttributeValue([MarshalAs(UnmanagedType.IUnknown)] out object mixedAttributeValue);
        [PreserveSig] int ElementFromIAccessible(IntPtr accessible, int childId, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
        [PreserveSig] int ElementFromIAccessibleBuildCache(IntPtr accessible, int childId, IntPtr cacheRequest, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
        [PreserveSig] int get_AutoSetFocus([MarshalAs(UnmanagedType.Bool)] out bool autoSetFocus);
        [PreserveSig] int put_AutoSetFocus([MarshalAs(UnmanagedType.Bool)] bool autoSetFocus);
        [PreserveSig] int get_ConnectionTimeout(out uint timeout);
        [PreserveSig] int put_ConnectionTimeout(uint timeout);
        [PreserveSig] int get_TransactionTimeout(out uint timeout);
        [PreserveSig] int put_TransactionTimeout(uint timeout);
    }

    [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IUIAutomationElement
    {
        [PreserveSig] int SetFocus();
        [PreserveSig] int GetRuntimeId([MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] out int[] runtimeId);
        [PreserveSig] int FindFirst(TreeScope scope, [MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement found);
        [PreserveSig] int FindAll(TreeScope scope, [MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray found);
        [PreserveSig] int FindFirstBuildCache(TreeScope scope, [MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition, IntPtr cacheRequest, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement found);
        [PreserveSig] int FindAllBuildCache(TreeScope scope, [MarshalAs(UnmanagedType.Interface)] IUIAutomationCondition condition, IntPtr cacheRequest, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray found);
        [PreserveSig] int BuildUpdatedCache(IntPtr cacheRequest, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement updatedElement);
        [PreserveSig] int GetCurrentPropertyValue(int propertyId, [MarshalAs(UnmanagedType.Struct)] out object retVal);
        [PreserveSig] int GetCurrentPropertyValueEx(int propertyId, [MarshalAs(UnmanagedType.Bool)] bool ignoreDefaultValue, [MarshalAs(UnmanagedType.Struct)] out object retVal);
        [PreserveSig] int GetCachedPropertyValue(int propertyId, [MarshalAs(UnmanagedType.Struct)] out object retVal);
        [PreserveSig] int GetCachedPropertyValueEx(int propertyId, [MarshalAs(UnmanagedType.Bool)] bool ignoreDefaultValue, [MarshalAs(UnmanagedType.Struct)] out object retVal);
        [PreserveSig] int GetCurrentPatternAs(int patternId, ref Guid riid, out IntPtr patternObject);
        [PreserveSig] int GetCachedPatternAs(int patternId, ref Guid riid, out IntPtr patternObject);
        [PreserveSig] int GetCurrentPattern(int patternId, [MarshalAs(UnmanagedType.IUnknown)] out object patternObject);
        [PreserveSig] int GetCachedPattern(int patternId, [MarshalAs(UnmanagedType.IUnknown)] out object patternObject);
        [PreserveSig] int GetCachedParent([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement parent);
        [PreserveSig] int GetCachedChildren([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray children);
        [PreserveSig] int get_CurrentProcessId(out int retVal);
        [PreserveSig] int get_CurrentControlType(out int retVal);
        [PreserveSig] int get_CurrentLocalizedControlType([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentName([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentAcceleratorKey([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentAccessKey([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentHasKeyboardFocus([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentIsKeyboardFocusable([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentIsEnabled([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentAutomationId([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentClassName([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentHelpText([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentCulture(out int retVal);
        [PreserveSig] int get_CurrentIsControlElement([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentIsContentElement([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentIsPassword([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentNativeWindowHandle(out IntPtr retVal);
        [PreserveSig] int get_CurrentItemType([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentIsOffscreen([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentOrientation(out OrientationType retVal);
        [PreserveSig] int get_CurrentFrameworkId([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentIsRequiredForForm([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentItemStatus([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentBoundingRectangle(out RECT retVal);
        [PreserveSig] int get_CurrentLabeledBy([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement retVal);
        [PreserveSig] int get_CurrentAriaRole([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentAriaProperties([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CurrentIsDataValidForForm([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CurrentControllerFor([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray retVal);
        [PreserveSig] int get_CurrentDescribedBy([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray retVal);
        [PreserveSig] int get_CurrentFlowsTo([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray retVal);
        [PreserveSig] int get_CurrentProviderDescription([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedProcessId(out int retVal);
        [PreserveSig] int get_CachedControlType(out int retVal);
        [PreserveSig] int get_CachedLocalizedControlType([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedName([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedAcceleratorKey([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedAccessKey([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedHasKeyboardFocus([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedIsKeyboardFocusable([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedIsEnabled([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedAutomationId([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedClassName([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedHelpText([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedCulture(out int retVal);
        [PreserveSig] int get_CachedIsControlElement([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedIsContentElement([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedIsPassword([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedNativeWindowHandle(out IntPtr retVal);
        [PreserveSig] int get_CachedItemType([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedIsOffscreen([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedOrientation(out OrientationType retVal);
        [PreserveSig] int get_CachedFrameworkId([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedIsRequiredForForm([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedItemStatus([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedBoundingRectangle(out RECT retVal);
        [PreserveSig] int get_CachedLabeledBy([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement retVal);
        [PreserveSig] int get_CachedAriaRole([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedAriaProperties([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int get_CachedIsDataValidForForm([MarshalAs(UnmanagedType.Bool)] out bool retVal);
        [PreserveSig] int get_CachedControllerFor([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray retVal);
        [PreserveSig] int get_CachedDescribedBy([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray retVal);
        [PreserveSig] int get_CachedFlowsTo([MarshalAs(UnmanagedType.Interface)] out IUIAutomationElementArray retVal);
        [PreserveSig] int get_CachedProviderDescription([MarshalAs(UnmanagedType.BStr)] out string retVal);
        [PreserveSig] int GetClickablePoint(out POINT clickable, [MarshalAs(UnmanagedType.Bool)] out bool gotClickable);
    }

    [ComImport, Guid("14314595-b4bc-4055-95f2-58f2e42c9855"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IUIAutomationElementArray
    {
        [PreserveSig] int get_Length(out int length);
        [PreserveSig] int GetElement(int index, [MarshalAs(UnmanagedType.Interface)] out IUIAutomationElement element);
    }

    [ComImport, Guid("352ffba8-0973-437c-a61f-f64cafd81df9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IUIAutomationCondition
    {
    }

    [ComImport, Guid("e22ad333-b25f-460c-83d0-0581107395c9"), ClassInterface(ClassInterfaceType.None)]
    public class CUIAutomation8 { }

    [ComImport, Guid("828055ad-355b-4435-86d5-3b51c14a9b1b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IUIAutomationLegacyIAccessiblePattern
    {
        [PreserveSig] int Select(int flagsSelect);
        [PreserveSig] int DoDefaultAction();
        [PreserveSig] int SetValue([MarshalAs(UnmanagedType.LPWStr)] string value);
        [PreserveSig] int get_CurrentChildId(out int childId);
        [PreserveSig] int get_CurrentName([MarshalAs(UnmanagedType.BStr)] out string name);
        [PreserveSig] int get_CurrentValue([MarshalAs(UnmanagedType.BStr)] out string value);
        [PreserveSig] int get_CurrentDescription([MarshalAs(UnmanagedType.BStr)] out string description);
        [PreserveSig] int get_CurrentRole(out uint role);
        [PreserveSig] int get_CurrentState(out uint state);
        [PreserveSig] int get_CurrentHelp([MarshalAs(UnmanagedType.BStr)] out string help);
        [PreserveSig] int get_CurrentKeyboardShortcut([MarshalAs(UnmanagedType.BStr)] out string shortcut);
        [PreserveSig] int GetCurrentSelection(out IntPtr selection);
        [PreserveSig] int get_CurrentDefaultAction([MarshalAs(UnmanagedType.BStr)] out string action);
        [PreserveSig] int get_CachedChildId(out int childId);
        [PreserveSig] int get_CachedName([MarshalAs(UnmanagedType.BStr)] out string name);
        [PreserveSig] int get_CachedValue([MarshalAs(UnmanagedType.BStr)] out string value);
        [PreserveSig] int get_CachedDescription([MarshalAs(UnmanagedType.BStr)] out string description);
        [PreserveSig] int get_CachedRole(out uint role);
        [PreserveSig] int get_CachedState(out uint state);
        [PreserveSig] int get_CachedHelp([MarshalAs(UnmanagedType.BStr)] out string help);
        [PreserveSig] int get_CachedKeyboardShortcut([MarshalAs(UnmanagedType.BStr)] out string shortcut);
        [PreserveSig] int GetCachedSelection(out IntPtr selection);
        [PreserveSig] int get_CachedDefaultAction([MarshalAs(UnmanagedType.BStr)] out string action);
        [PreserveSig] int GetIAccessible(out IntPtr accessible);
    }

    // 2026-10-07：复用禁用自动焦点的同一个客户端，准备动作与最后审批检查分开。
    public sealed class BackgroundClient : IDisposable
    {
        private IUIAutomation2 client;
        public BackgroundClient()
        {
            client = (IUIAutomation2)new CUIAutomation8();
            try
            {
                Marshal.ThrowExceptionForHR(client.put_AutoSetFocus(false));
                if (AutoSetFocus) { throw new InvalidOperationException("AutoSetFocus did not disable"); }
            }
            catch { Dispose(); throw; }
        }
        public bool AutoSetFocus
        {
            get
            {
                if (client == null) { throw new ObjectDisposedException("BackgroundClient"); }
                bool enabled;
                Marshal.ThrowExceptionForHR(client.get_AutoSetFocus(out enabled));
                return enabled;
            }
        }
        public BackgroundInvoke Prepare(IntPtr hwnd, int[] expectedRuntimeId)
        {
            if (hwnd == IntPtr.Zero) { throw new ArgumentException("Missing window handle", "hwnd"); }
            if (expectedRuntimeId == null || expectedRuntimeId.Length == 0) { throw new ArgumentException("Missing RuntimeId", "expectedRuntimeId"); }
            if (client == null) { throw new ObjectDisposedException("BackgroundClient"); }
            IUIAutomationElement root = null;
            IUIAutomationElement target = null;
            IUIAutomationCondition condition = null;
            object acquiredPattern = null;
            try
            {
                Marshal.ThrowExceptionForHR(client.ElementFromHandle(hwnd, out root));
                if (root == null) { throw new InvalidOperationException("Window element missing"); }
                Marshal.ThrowExceptionForHR(client.CreatePropertyCondition(30000, expectedRuntimeId, out condition));
                Marshal.ThrowExceptionForHR(root.FindFirst(TreeScope.Descendants, condition, out target));
                if (target == null) { throw new InvalidOperationException("RuntimeId target missing"); }
                int[] actualRuntimeId;
                Marshal.ThrowExceptionForHR(target.GetRuntimeId(out actualRuntimeId));
                bool same;
                Marshal.ThrowExceptionForHR(client.CompareRuntimeIds(expectedRuntimeId, actualRuntimeId, out same));
                if (!same) { throw new InvalidOperationException("RuntimeId binding changed"); }
                Marshal.ThrowExceptionForHR(target.GetCurrentPattern(10018, out acquiredPattern));
                if (acquiredPattern == null) { throw new InvalidOperationException("Legacy default-action pattern missing"); }
                if (AutoSetFocus) { throw new InvalidOperationException("AutoSetFocus changed after binding"); }
                var prepared = new BackgroundInvoke((IUIAutomationLegacyIAccessiblePattern)acquiredPattern);
                acquiredPattern = null;
                return prepared;
            }
            finally
            {
                ReleaseOwned(acquiredPattern);
                ReleaseOwned(condition);
                ReleaseOwned(target);
                ReleaseOwned(root);
            }
        }
        // 2026-10-07：自己的 COM 引用清理不遮盖审批异常，也不跳过其余引用；不清空共享 RCW。
        internal static void ReleaseOwned(object owned)
        {
            try
            {
                if (owned != null && Marshal.IsComObject(owned)) { Marshal.ReleaseComObject(owned); }
            }
            catch (InvalidComObjectException) { }
            catch (COMException) { }
            catch (ArgumentException) { }
        }
        public void Dispose()
        {
            IUIAutomation2 owned = client;
            client = null;
            ReleaseOwned(owned);
        }
    }
    public sealed class BackgroundInvoke : IDisposable
    {
        private IUIAutomationLegacyIAccessiblePattern pattern;
        internal BackgroundInvoke(IUIAutomationLegacyIAccessiblePattern pattern) { this.pattern = pattern; }
        // 2026-10-07：最终调用只执行默认动作，全部绑定查询先于调用方最后检查。
        public void Invoke()
        {
            if (pattern == null) { throw new ObjectDisposedException("BackgroundInvoke"); }
            Marshal.ThrowExceptionForHR(pattern.DoDefaultAction());
        }
        public void Dispose()
        {
            IUIAutomationLegacyIAccessiblePattern owned = pattern;
            pattern = null;
            BackgroundClient.ReleaseOwned(owned);
        }
    }
}
"@

Add-Type -AssemblyName UIAutomationClient

$automation = [System.Windows.Automation.AutomationElement]::RootElement
$winCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
)
$btnCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button
)
# 2026-10-05：新版权限卡片位于会话区域，审批单选项与权限目标需成组识别。
$conversationCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'conversation'
)
$radioCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::RadioButton
)
$editCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit
)
# 2026-10-06：浏览器权限在宽栏是按钮、窄栏是弹出菜单项，分别读取实际控件类型。
$textCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text
)
$menuCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Menu
)
$menuItemCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem
)

# 2026-10-05：只匹配审批动作及其中文标签，普通保存、确认、重试按钮不参与自动同意。
$targetPrefixes = @('Run', 'Accept', 'Allow', 'Execute', 'Approve', '运行', '接受', '允许', '同意', '批准', '执行')
$excludeExact = @('Run and Debug', 'Run Task', 'Run Build Task', 'Run File', 'Always run', 'Run Extension', 'Run Selection')
$exactOnly = @('全部接受', '全部同意', '全部允许', '全部批准')

# 2026-07-28 前缀匹配必须有边界，避免 Application/Continuous 这类普通按钮被误点
function Test-PrefixBoundary([string]$Rest) {
    if ($Rest.Length -eq 0) { return $true }
    if ($Rest[0] -eq ' ' -or $Rest[0] -eq '(' -or $Rest[0] -eq '[' -or $Rest[0] -eq '+' -or $Rest[0] -eq ':' -or $Rest[0] -eq '-') { return $true }
    if ($Rest -match '^(Alt|Ctrl|Shift|Enter|Cmd|Win)\b') { return $true }
    return $false
}

function Test-ButtonMatch([string]$Name) {
    # 2026-10-05：拒绝、取消和停止动作优先排除，中文审批仅允许常见审批后缀。
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $n = $Name.Trim()
    if ($n -match '\b(Reject|Deny|Denied|Cancel|Stop|Abort)\b|拒绝|取消|停止|中止') { return $false }
    # 2026-10-06：本次允许专属于已核验的浏览器卡片，不能由全窗普通按钮回退绕过作用域。
    if ($n -eq 'Allow Once') { return $false }
    # 2026-10-05：执行后的工具标题也会以 Run 开头，仅静态审批标签和快捷键后缀可点击。
    if ($n -match '^(Run|Execute|Approve|运行|执行|批准)') {
        return $n -match '^(Run|Execute|Approve|Run command|Execute command|Approve command|运行|执行|批准|运行命令|执行命令|批准命令)(\s*[\(\[]?(Alt|Ctrl|Shift|Enter|Cmd|Win)(\s*\+\s*(Alt|Ctrl|Shift|Enter|Cmd|Win|[A-Za-z0-9]))*[\)\]]?)?$'
    }

    foreach ($ex in $excludeExact) {
        if ($n -eq $ex) { return $false }
        if ($n -like "$ex *") { return $false }
    }

    foreach ($em in $exactOnly) {
        if ($n -eq $em) { return $true }
    }

    foreach ($p in $targetPrefixes) {
        if ($n -eq $p) { return $true }
        if ($n.Length -gt $p.Length) {
            $start = $n.Substring(0, $p.Length)
            if ($start -eq $p) {
                $rest = $n.Substring($p.Length)
                if (Test-PrefixBoundary $rest) { return $true }
                if ($p -match '[\u4e00-\u9fff]' -and $rest -match '^(全部|所有|一次|本次|此次|此|该|运行|执行|命令|更改|修改|编辑|操作|会话|终端|文件|访问|网络|目录)') { return $true }
            }
        }
    }
    return $false
}

# 2026-10-05：按完整可执行文件路径锁定窗口，独立运行兼容新旧 Antigravity 进程名。
function Test-HostProcessPath([string]$ExecutablePath, [string]$ExpectedPath) {
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath($ExecutablePath)
        if ([IO.Path]::GetFileName($fullPath) -notin @('Antigravity.exe', 'Antigravity IDE.exe')) { return $false }
        if ([string]::IsNullOrWhiteSpace($ExpectedPath)) { return $true }
        return [string]::Equals($fullPath, [IO.Path]::GetFullPath($ExpectedPath), [StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

# 2026-10-05：进程路径不可读取时跳过，不使用可能被其他应用仿造的窗口标题。
function Get-TargetProcessIds {
    param([int]$ProcessId)
    # 2026-10-07：只核对当前窗口进程，每次重新查询完整路径，不缓存可被复用的 PID。
    $targetIds = @{}
    if ($ProcessId -le 0) { return $targetIds }
    try {
        $imagePath = [MouseHelper]::GetProcessImagePath([uint32]$ProcessId)
        if (Test-HostProcessPath $imagePath $HostExecutablePath) { $targetIds[$ProcessId] = $true }
    }
    catch { }
    return $targetIds
}

# 2026-10-05：按按钮最新矩形计算坐标，负坐标保留以支持主屏左侧或上方的副屏。
function Get-ButtonCenter($Rectangle) {
    if ($null -eq $Rectangle -or $Rectangle.Width -le 0 -or $Rectangle.Height -le 0) { return $null }
    $x = $Rectangle.X + $Rectangle.Width / 2
    $y = $Rectangle.Y + $Rectangle.Height / 2
    if ([double]::IsNaN($x) -or [double]::IsInfinity($x) -or [double]::IsNaN($y) -or [double]::IsInfinity($y)) { return $null }
    if ($x -lt [int]::MinValue -or $x -gt [int]::MaxValue -or $y -lt [int]::MinValue -or $y -gt [int]::MaxValue) { return $null }
    return @{ X = [int]$x; Y = [int]$y }
}

# 2026-10-05：保留启动时的父进程对象，宿主退出后等待者及扫描者均退出。
function Test-ParentAlive {
    if ($ParentProcessId -eq 0) { return $true }
    if ($null -eq $script:parentProcess) { return $false }
    try {
        $script:parentProcess.Refresh()
        return -not $script:parentProcess.HasExited
    }
    catch { return $false }
}

# 2026-10-05：仅允许明确的本次审批，始终允许和拒绝选项不参与自动选择。
function Test-OneTimeApprovalName([string]$Name) {
    return $Name.Trim() -in @('1 Yes, allow this time', 'Yes, allow this time', '1 是，仅本次允许', '是，仅本次允许', '1 是，允许本次', '是，允许本次', '1 仅允许本次', '仅允许本次')
}

# 2026-10-05：权限目标编辑框与同问题的本次、始终、拒绝选项必须在同一卡片内。
function Test-ApprovalCardShape($EditNames, $OptionIds, $OptionNames, $SubmitNames) {
    if (@($EditNames | Where-Object { $_ -eq 'Edit permission target' }).Count -ne 1) { return $false }
    if ($OptionIds.Count -lt 3 -or $OptionIds.Count -ne $OptionNames.Count) { return $false }
    $oneTimeIndex = -1
    for ($i = 0; $i -lt $OptionIds.Count; $i++) {
        if ($OptionIds[$i] -match '^ask-opt-(.+)-1$' -and (Test-OneTimeApprovalName $OptionNames[$i])) {
            if ($oneTimeIndex -ge 0) { return $false }
            $oneTimeIndex = $i
        }
    }
    if ($oneTimeIndex -lt 0) { return $false }
    $questionPrefix = $OptionIds[$oneTimeIndex].Substring(0, $OptionIds[$oneTimeIndex].Length - 1)
    foreach ($id in $OptionIds) {
        if (-not $id.StartsWith($questionPrefix, [StringComparison]::Ordinal)) { return $false }
    }
    if (@($OptionNames | Where-Object { $_ -match '\balways allow\b|始终允许|总是允许|始终同意|总是同意' }).Count -eq 0) { return $false }
    if (@($OptionNames | Where-Object { $_ -match '^(\d+\s+)?No\b|拒绝|不同意|不允许' }).Count -eq 0) { return $false }
    return @($SubmitNames | Where-Object { $_ -match '^(Submit|提交)(\s*[↵⏎])?$' }).Count -eq 1
}

# 2026-10-05：用实际选中状态确认本次允许，无法读取选中状态时不提交表单。
function Test-ApprovalOptionSelected($Option) {
    try {
        $selection = $Option.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        return $selection.Current.IsSelected
    }
    # 2026-10-07：托管 UIA 不提供 LegacyIAccessiblePattern，读不到真实选中状态时保持不提交。
    catch { return $false }
}

# 2026-10-05：读取审批卡片的实时控件特征，普通问答表单和全局提交按钮不会命中。
function Test-LiveApprovalCard($Card, $ExpectedTarget = $null) {
    $edits = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCondition)
    $radios = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $radioCondition)
    $buttons = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
    # 2026-10-06：滚动和宿主查询后同时验证目标控件身份与原始值，命令变化时不能沿用旧批准。
    if (-not (Test-ApprovalCardShape @($edits | ForEach-Object { $_.Current.Name }) @($radios | ForEach-Object { $_.Current.AutomationId }) @($radios | ForEach-Object { $_.Current.Name }) @($buttons | ForEach-Object { $_.Current.Name }))) { return $false }
    if ($null -ne $ExpectedTarget) {
        $target = @($edits | Where-Object { $_.Current.Name -eq 'Edit permission target' })[0]
        if (($target.GetRuntimeId() -join '.') -ne $ExpectedTarget.Id) { return $false }
        $value = $target.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if (-not [string]::Equals($value, $ExpectedTarget.Value, [StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

# 2026-10-06：审批卡片的诊断最多每十秒输出一次，便于排查宿主 UI 变化且避免刷屏。
$script:lastApprovalDiagnosticTime = [DateTime]::MinValue
$script:approvalDiagnosticTimes = @{}
# 2026-10-06：候选、控件模式和动作结果分别节流，候选结构不能永久压住后续失败证据。
function Write-ApprovalDiagnostic([string]$Message, [string]$Category = 'approval') {
    $now = [DateTime]::Now
    if ($Category -eq 'browser-candidate') {
        if (($now - $script:lastApprovalDiagnosticTime).TotalSeconds -lt 10) { return }
        $script:lastApprovalDiagnosticTime = $now
    }
    else {
        if ($script:approvalDiagnosticTimes.ContainsKey($Category) -and ($now - $script:approvalDiagnosticTimes[$Category]).TotalSeconds -lt 10) { return }
        $script:approvalDiagnosticTimes[$Category] = $now
    }
    [Console]::WriteLine("___SCANNER_DIAGNOSTIC___:$Message")
}

# 2026-10-06：浏览器权限文案必须包含真实主机名，不把普通消息或网址正文当作审批。
function Test-BrowserPermissionText([string]$Name) {
    if ($Name -notmatch '^Agent needs permission to act on (\S+)$') { return $false }
    return [Uri]::CheckHostName($Matches[1]) -ne [UriHostNameType]::Unknown
}

# 2026-10-06：同一卡片必须同时有权限文案、配置、拒绝和始终允许，批准仍只选择本次。
function Test-BrowserPermissionCardShape($TextNames, $ButtonNames) {
    if (@($TextNames | Where-Object { Test-BrowserPermissionText $_ }).Count -ne 1) { return $false }
    foreach ($required in @('Configure', 'Deny', 'Always Allow')) {
        if (@($ButtonNames | Where-Object { $_ -eq $required }).Count -ne 1) { return $false }
    }
    $onceCount = @($ButtonNames | Where-Object { $_ -eq 'Allow Once' }).Count
    if ($onceCount -eq 1) { return $true }
    return $onceCount -eq 0 -and @($ButtonNames | Where-Object { $_ -eq 'More actions' }).Count -eq 1
}

# 2026-10-06：只检查当前卡片的直属控件，不能从整段会话拼凑不相关按钮。
function Test-LiveBrowserPermissionCard($Card, $ExpectedTarget = $null, $Action = $null) { # 2026-10-07
    $texts = $Card.FindAll([System.Windows.Automation.TreeScope]::Children, $textCondition)
    $buttons = $Card.FindAll([System.Windows.Automation.TreeScope]::Children, $btnCondition)
    # 2026-10-07：实时目标必须仍是原卡片和原文案，动作按钮不能从原卡片脱离或被同名控件替换。
    if (-not (Test-BrowserPermissionCardShape @($texts | ForEach-Object { $_.Current.Name }) @($buttons | ForEach-Object { $_.Current.Name }))) { return $false }
    if ($null -ne $ExpectedTarget) {
        if ($null -eq $Action -or ($Action.GetRuntimeId() -join '.') -ne $ExpectedTarget.ActionId) { return $false }
        $actionParent = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($Action)
        if ($null -eq $actionParent -or ($actionParent.GetRuntimeId() -join '.') -ne $ExpectedTarget.CardId) { return $false }
        if (@($buttons | Where-Object { ($_.GetRuntimeId() -join '.') -eq $ExpectedTarget.ActionId }).Count -ne 1) { return $false }
        # 2026-10-07：动作和父链查询完成后最后重读当前目标，不能用查询前已比较过的文案继续批准。
        $targets = @($Card.FindAll([System.Windows.Automation.TreeScope]::Children, $textCondition) | Where-Object { Test-BrowserPermissionText $_.Current.Name })
        if ($targets.Count -ne 1) { return $false }
        $target = $targets[0]
        if (($Card.GetRuntimeId() -join '.') -ne $ExpectedTarget.CardId -or ($target.GetRuntimeId() -join '.') -ne $ExpectedTarget.Id) { return $false }
        if (-not [string]::Equals($target.Current.Name, $ExpectedTarget.Name, [StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

# 2026-10-06：门户菜单必须靠近此次触发按钮，负坐标副屏沿用同一几何判断。
function Test-BrowserMenuAnchor($MenuRectangle, $ButtonRectangle) {
    if ($null -eq (Get-ButtonCenter $MenuRectangle) -or $null -eq (Get-ButtonCenter $ButtonRectangle)) { return $false }
    $horizontal = $MenuRectangle.X -le ($ButtonRectangle.X + $ButtonRectangle.Width + 16) -and ($MenuRectangle.X + $MenuRectangle.Width) -ge ($ButtonRectangle.X - 16)
    $below = [Math]::Abs($MenuRectangle.Y - ($ButtonRectangle.Y + $ButtonRectangle.Height))
    $above = [Math]::Abs(($MenuRectangle.Y + $MenuRectangle.Height) - $ButtonRectangle.Y)
    return $horizontal -and [Math]::Min($below, $above) -le 32
}

# 2026-10-06：菜单限定为目标宿主窗口内可见的菜单，隐藏或其他进程的菜单不参与差分。
function Get-VisibleBrowserMenus($Window, [int]$WindowProcessId) {
    foreach ($menu in $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuCondition)) {
        if ($menu.Current.ProcessId -eq $WindowProcessId -and -not $menu.Current.IsOffscreen -and $menu.Current.IsEnabled -and $null -ne (Get-ButtonCenter $menu.Current.BoundingRectangle)) { $menu }
    }
}

# 2026-10-06：仅输出候选控件结构和固定批准标签，不记录域名、消息或窗口标题。
function Write-BrowserCandidateDiagnostic($CandidateButtons, [int]$WindowProcessId) {
    if (([DateTime]::Now - $script:lastApprovalDiagnosticTime).TotalSeconds -lt 10) { return }
    $candidates = @($CandidateButtons | Where-Object { $_.Current.Name -in @('Allow Once', 'More actions') })
    $structures = @()
    foreach ($allow in $candidates) {
        try {
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($allow)
            $parentType = 'none'
            $texts = @()
            $buttons = @()
            if ($null -ne $card) {
                $parentType = $card.Current.ControlType.ProgrammaticName
                $texts = @($card.FindAll([System.Windows.Automation.TreeScope]::Children, $textCondition))
                $buttons = @($card.FindAll([System.Windows.Automation.TreeScope]::Children, $btnCondition))
            }
            $fixedLabels = @($buttons | ForEach-Object { $_.Current.Name } | Where-Object { $_ -in @('Configure', 'Deny', 'Always Allow', 'Allow Once', 'More actions') }) -join ','
            $shape = Test-BrowserPermissionCardShape @($texts | ForEach-Object { $_.Current.Name }) @($buttons | ForEach-Object { $_.Current.Name })
            # 2026-10-06：离屏控件也只读报告支持模式，为后续受控滚动提供实际证据。
            $patternSummary = 'patterns=unavailable'
            try {
                $supportsInvoke = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty)
                $supportsScrollItem = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty)
                $supportsExpand = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsExpandCollapsePatternAvailableProperty)
                $patternSummary = "invoke=$supportsInvoke scrollitem=$supportsScrollItem expand=$supportsExpand"
            }
            catch { }
            $structures += "[$($allow.Current.Name) enabled=$($allow.Current.IsEnabled) offscreen=$($allow.Current.IsOffscreen) parent=$parentType texts=$($texts.Count) buttons=$($buttons.Count) labels=$fixedLabels shape=$shape $patternSummary]"
        }
        catch { $structures += '[candidate structure unavailable]' }
    }
    $summary = @($structures | Sort-Object -Unique) -join ' '
    Write-ApprovalDiagnostic "browser candidates pid=$WindowProcessId buttons=$($CandidateButtons.Count) candidates=$($candidates.Count) $summary" 'browser-candidate'
}

# 2026-10-07：仅准备原生默认动作；原宿主、控件身份和一次允许检查仍在准备完成后执行。
function Get-BackgroundInvoke($Element, [IntPtr]$WindowHandle) {
    if ($null -eq $script:backgroundClient) { $script:backgroundClient = [AntigravityUia.BackgroundClient]::new() }
    return $script:backgroundClient.Prepare($WindowHandle, [int[]]$Element.GetRuntimeId())
}

# 2026-10-06：宽栏直接允许本次，窄栏展开已核验卡片的菜单，只允许此次新出现的本次菜单项。
function Invoke-BrowserPermissionCards($Window, [int]$WindowProcessId, [IntPtr]$WindowHandle) {
    # 2026-10-09：每个窗口只保留本轮已核验的新菜单续办身份，句柄相同仍必须复核 PID 和全部控件身份。
    if ($null -eq $script:deferredBrowserMenus) { $script:deferredBrowserMenus = @{} }
    $deferredWindowKey = $WindowHandle.ToInt64().ToString([Globalization.CultureInfo]::InvariantCulture)
    $conversation = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $conversationCondition)
    if ($null -eq $conversation) {
        Write-ApprovalDiagnostic "browser conversation missing pid=$WindowProcessId" 'browser-candidate'
        return $false
    }
    $conversationButtons = @($conversation.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition))
    Write-BrowserCandidateDiagnostic $conversationButtons $WindowProcessId
    foreach ($allow in $conversationButtons) {
        $stage = 'candidate'
        $backgroundPatterns = [Collections.Generic.List[object]]::new() # 2026-10-07：所有退出路径统一释放本候选准备的原生模式。
        try {
            $actionName = $allow.Current.Name
            if ($actionName -notin @('Allow Once', 'More actions') -or -not $allow.Current.IsEnabled) { continue }
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($allow)
            if ($null -eq $card -or -not (Test-LiveBrowserPermissionCard $card)) { continue }
            # 2026-10-07：把首次看到的卡片、权限文案和动作身份作为后续宿主查询与滚动的审批快照。
            $targets = @($card.FindAll([System.Windows.Automation.TreeScope]::Children, $textCondition) | Where-Object { Test-BrowserPermissionText $_.Current.Name })
            if ($targets.Count -ne 1) { continue }
            $expectedTarget = @{ CardId = ($card.GetRuntimeId() -join '.'); Id = ($targets[0].GetRuntimeId() -join '.'); Name = $targets[0].Current.Name; ActionId = ($allow.GetRuntimeId() -join '.') }
            if ($actionName -eq 'More actions') {
                # 2026-10-09：窄菜单可能激活 IDE，后台或输入繁忙时暂缓，回到前台后由下一轮自动处理。
                if (-not [MouseHelper]::CanUseForegroundUi($WindowHandle)) {
                    Write-ApprovalDiagnostic 'browser menu deferred until IDE foreground and input idle' 'browser-deferred'
                    continue
                }
                $cardButtons = $card.FindAll([System.Windows.Automation.TreeScope]::Children, $btnCondition)
                if (@($cardButtons | Where-Object { $_.Current.Name -eq 'Allow Once' }).Count -gt 0) { continue }
            }
            # 2026-10-06：只记录固定模式布尔值，区分控件不支持调用与调用后菜单没有出现。
            $stage = 'pattern'
            $invokeAvailable = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty)
            $scrollItemAvailable = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty)
            $expandAvailable = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsExpandCollapsePatternAvailableProperty)
            Write-ApprovalDiagnostic "browser pattern action=$actionName invoke=$invokeAvailable scrollitem=$scrollItemAvailable expand=$expandAvailable" 'browser-pattern'
            # 2026-10-06：离屏的已核验窄卡片仅通过自身滚动模式带出，滚动前后复核宿主和当前卡片。
            if ($allow.Current.IsOffscreen) {
                if ($actionName -ne 'More actions' -or -not $scrollItemAvailable) { continue }
                $stage = 'scroll-pattern'
                $scrollItem = $allow.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
                if (-not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                # 2026-10-06：宿主查询可能改变卡片状态，滚动前后的界面复核统一放在查询之后。
                if (-not (Test-LiveBrowserPermissionCard $card $expectedTarget $allow) -or $allow.Current.Name -ne 'More actions' -or -not $allow.Current.IsEnabled) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                # 2026-10-09：模式和身份查询期间切走或开始输入时，不再滚动窄卡片。
                if (-not [MouseHelper]::CanUseForegroundUi($WindowHandle)) { continue }
                $stage = 'scroll'
                $scrollItem.ScrollIntoView()
                if (-not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                if (-not (Test-LiveBrowserPermissionCard $card $expectedTarget $allow) -or $allow.Current.Name -ne 'More actions' -or -not $allow.Current.IsEnabled -or $allow.Current.IsOffscreen) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                Write-ApprovalDiagnostic 'browser scroll returned=True visible=True' 'browser-scroll'
            }
            # 2026-10-06：实机窄按钮没有 Invoke，优先使用展开模式避免切换菜单；宽栏本次按钮继续 Invoke。
            $stage = 'action-pattern'
            $method = 'invoke'
            if ($actionName -eq 'More actions' -and $expandAvailable) {
                $actionPattern = $allow.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
                $method = 'expand'
            }
            elseif ($invokeAvailable) { $actionPattern = Get-BackgroundInvoke $allow $WindowHandle; $backgroundPatterns.Add($actionPattern) } # 2026-10-07
            else { continue }
            $stage = 'before-menus'
            $beforeMenus = @{}
            $existingMenuId = $null
            $resumedDeferredMenu = $null # 2026-10-09：无标签旧菜单只有完整自有记录命中才允许续办。
            if ($actionName -eq 'More actions') {
                $beforeVisibleMenus = @(Get-VisibleBrowserMenus $Window $WindowProcessId)
                foreach ($menu in $beforeVisibleMenus) { $beforeMenus[($menu.GetRuntimeId() -join '.')] = $true }
                # 2026-10-07：唯一精确标识当前触发器且贴近按钮的已打开菜单可以接管，不沿用未标识的旧菜单。
                $linkedMenus = @($beforeVisibleMenus | Where-Object {
                    $label = $_.Current.LabeledBy
                    $null -ne $label -and ($label.GetRuntimeId() -join '.') -eq $expectedTarget.ActionId -and (Test-BrowserMenuAnchor $_.Current.BoundingRectangle $allow.Current.BoundingRectangle)
                })
                $deferredMenu = $script:deferredBrowserMenus[$deferredWindowKey]
                if ($null -ne $deferredMenu -and @($beforeVisibleMenus | Where-Object { ($_.GetRuntimeId() -join '.') -eq $deferredMenu.MenuId }).Count -eq 0) {
                    [void]$script:deferredBrowserMenus.Remove($deferredWindowKey)
                    $deferredMenu = $null
                }
                if ($linkedMenus.Count -eq 1) { $existingMenuId = ($linkedMenus[0].GetRuntimeId() -join '.'); $method = 'existing-menu' }
                elseif ($null -ne $deferredMenu -and $deferredMenu.ProcessId -eq $WindowProcessId -and
                    $deferredMenu.Target.CardId -eq $expectedTarget.CardId -and $deferredMenu.Target.Id -eq $expectedTarget.Id -and
                    [string]::Equals($deferredMenu.Target.Name, $expectedTarget.Name, [StringComparison]::Ordinal) -and $deferredMenu.Target.ActionId -eq $expectedTarget.ActionId) { # 2026-10-09：文案必须逐字相同。
                    $ownedMenus = @($beforeVisibleMenus | Where-Object { ($_.GetRuntimeId() -join '.') -eq $deferredMenu.MenuId })
                    if ($ownedMenus.Count -ne 1) { continue }
                    $existingMenuId = $deferredMenu.MenuId
                    $resumedDeferredMenu = $deferredMenu
                    $method = 'existing-menu'
                }
                elseif ($beforeVisibleMenus.Count -gt 0) { continue } # 2026-10-09：不展开或批准未精确关联的用户旧菜单。
            }
            $stage = 'host'
            if (-not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
            if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
            # 2026-10-06：最后一次宿主查询后重读卡片和动作按钮，不沿用查询前的批准状态。
            $stage = 'final-card'
            if (-not (Test-LiveBrowserPermissionCard $card $expectedTarget $allow) -or $allow.Current.Name -ne $actionName -or -not $allow.Current.IsEnabled -or $allow.Current.IsOffscreen) { continue }
            if (-not (Test-ParentAlive)) { return $false }
            # 2026-10-09：紧邻窄菜单动作重查前台和输入；宽栏一次允许仍使用原后台默认动作。
            if ($actionName -eq 'More actions' -and -not [MouseHelper]::CanUseForegroundUi($WindowHandle)) { continue }
            $stage = $method
            if ($method -eq 'expand') { $actionPattern.Expand() }
            elseif ($method -eq 'invoke') { $actionPattern.Invoke() } # 2026-10-07：已打开的精确关联菜单无需再次展开。
            if ($actionName -eq 'Allow Once') {
                [Console]::WriteLine('___CLICK_INVOKE___:Allow Once (browser domain permission)')
                return $true
            }
            $stage = 'menu-query'
            $menuCount = 0
            $newMenuCount = 0
            $itemCount = 0
            for ($attempt = 0; $attempt -lt 3; $attempt++) {
                Start-Sleep -Milliseconds 100
                if (-not (Test-ParentAlive)) { return $false }
                $visibleMenus = @(Get-VisibleBrowserMenus $Window $WindowProcessId)
                $menuCount = $visibleMenus.Count
                $newMenus = @($visibleMenus | Where-Object { -not $beforeMenus.ContainsKey(($_.GetRuntimeId() -join '.')) -or ($_.GetRuntimeId() -join '.') -eq $existingMenuId }) # 2026-10-07
                $newMenuCount = $newMenus.Count
                if ($newMenus.Count -ne 1) { continue }
                $menu = $newMenus[0]
                if (-not (Test-BrowserMenuAnchor $menu.Current.BoundingRectangle $allow.Current.BoundingRectangle)) { continue }
                $label = $menu.Current.LabeledBy
                if ($null -ne $label -and ($label.GetRuntimeId() -join '.') -ne ($allow.GetRuntimeId() -join '.')) { continue }
                $items = @($menu.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCondition) | Where-Object { $_.Current.Name -eq 'Allow Once' })
                $itemCount = $items.Count
                if ($items.Count -ne 1) { continue }
                $item = $items[0]
                $menuId = ($menu.GetRuntimeId() -join '.'); $itemId = ($item.GetRuntimeId() -join '.') # 2026-10-07：保留取模式之前的菜单及菜单项身份。
                # 2026-10-09：续办必须仍是原菜单中的原本次项，换项即丢弃记录，后续原归属复核照常执行。
                if ($null -ne $resumedDeferredMenu -and ($menuId -ne $resumedDeferredMenu.MenuId -or $itemId -ne $resumedDeferredMenu.ItemId)) {
                    [void]$script:deferredBrowserMenus.Remove($deferredWindowKey)
                    continue
                }
                $stage = 'item-pattern' # 2026-10-06：菜单项模式异常单独标明阶段，便于实机定位。
                $itemInvoke = Get-BackgroundInvoke $item $WindowHandle # 2026-10-07
                $backgroundPatterns.Add($itemInvoke)
                if (-not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                # 2026-10-06：宿主查询完成后复核卡片、菜单和本次菜单项，关联触发器仍保持最后复核。
                $stage = 'item-final'
                # 2026-10-07：先完成会重读卡片树的关联复核，再核菜单项身份与当前父链，避免后续卡片查询使旧项失效。
                if (-not (Test-LiveBrowserPermissionCard $card $expectedTarget $allow) -or $allow.Current.Name -ne 'More actions' -or -not $allow.Current.IsEnabled -or $allow.Current.IsOffscreen) { continue }
                # 2026-10-07：取模式和宿主查询后重新枚举实际菜单项，再沿当前父链确认原项仍属于唯一原菜单。
                $currentMenus = @(Get-VisibleBrowserMenus $Window $WindowProcessId | Where-Object { -not $beforeMenus.ContainsKey(($_.GetRuntimeId() -join '.')) -or ($_.GetRuntimeId() -join '.') -eq $existingMenuId })
                if ($currentMenus.Count -ne 1 -or ($currentMenus[0].GetRuntimeId() -join '.') -ne $menuId) { continue }
                $currentItems = @($menu.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCondition) | Where-Object { $_.Current.Name -eq 'Allow Once' })
                if ($currentItems.Count -ne 1 -or ($currentItems[0].GetRuntimeId() -join '.') -ne $itemId) { continue }
                $itemParent = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($item)
                while ($null -ne $itemParent -and ($itemParent.GetRuntimeId() -join '.') -ne $menuId) { $itemParent = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($itemParent) }
                if ($null -eq $itemParent) { continue }
                if ($menu.Current.ProcessId -ne $WindowProcessId -or $menu.Current.IsOffscreen -or -not $menu.Current.IsEnabled -or -not (Test-BrowserMenuAnchor $menu.Current.BoundingRectangle $allow.Current.BoundingRectangle)) { continue }
                if ($item.Current.Name -ne 'Allow Once' -or -not $item.Current.IsEnabled -or $item.Current.IsOffscreen) { continue }
                # 2026-10-06：菜单项取模式和宿主查询后复核关联触发器，菜单改属其他卡片时不批准。
                $label = $menu.Current.LabeledBy
                if ($null -ne $existingMenuId -and $null -eq $label -and $null -eq $resumedDeferredMenu) { continue } # 2026-10-09：无标签菜单仅限已完整核验的自有续办记录。
                if ($null -ne $label -and ($label.GetRuntimeId() -join '.') -ne ($allow.GetRuntimeId() -join '.')) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                # 2026-10-09：展开后用户切走或开始输入时保留待批菜单，不继续提交。
                if (-not [MouseHelper]::CanUseForegroundUi($WindowHandle)) {
                    $script:deferredBrowserMenus[$deferredWindowKey] = @{ ProcessId = $WindowProcessId; Target = $expectedTarget; MenuId = $menuId; ItemId = $itemId }
                    continue
                }
                [void]$script:deferredBrowserMenus.Remove($deferredWindowKey)
                $stage = 'item-invoke' # 2026-10-06：明确唯一新菜单本次批准的实际调用阶段。
                $itemInvoke.Invoke()
                [Console]::WriteLine('___CLICK_INVOKE___:Allow Once (browser domain permission)')
                return $true
            }
            Write-ApprovalDiagnostic "browser menu method=$method action-returned=True before=$($beforeMenus.Count) visible=$menuCount new=$newMenuCount once-items=$itemCount" 'browser-menu'
        }
        catch {
            Write-ApprovalDiagnostic "browser error stage=$stage type=$($_.Exception.GetType().Name)" 'browser-error'
            # 2026-10-07：最终批准已尝试但结果未知时占用本轮，展开或滚动失败仍可继续其它候选。
            if (($stage -eq 'invoke' -and $actionName -eq 'Allow Once') -or $stage -eq 'item-invoke') { return $true }
        }
        finally { foreach ($preparedPattern in $backgroundPatterns) { $preparedPattern.Dispose() } } # 2026-10-07
    }
    return $false
}

# 2026-10-05：新版卡片只选本次允许并提交同一卡片，不修改终端或权限的持久设置。
function Invoke-ApprovalCards($Window, [int]$WindowProcessId, [IntPtr]$WindowHandle) {
    # 2026-10-06：专用权限表单也会位于会话兄弟输入区，候选来自宿主窗口，批准仍限定同一个真实表单。
    $options = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $radioCondition)
    foreach ($option in $options) {
        $stage = 'candidate'
        $backgroundPatterns = [Collections.Generic.List[object]]::new() # 2026-10-07：所有退出路径统一释放本候选准备的原生模式。
        try {
            if ($option.Current.AutomationId -notmatch '^ask-opt-.+-1$' -or -not (Test-OneTimeApprovalName $option.Current.Name)) { continue }
            if (-not $option.Current.IsEnabled) { continue }
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
            if ($null -eq $card) { continue }
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($card)
            if ($null -eq $card -or -not (Test-LiveApprovalCard $card)) {
                Write-ApprovalDiagnostic 'permission-card shape mismatch'
                continue
            }
            # 2026-10-06：保存当前表单归属，滚动导致控件移到其他表单时不能继续选择或提交。
            $cardId = $card.GetRuntimeId() -join '.'
            $stage = 'target-pattern'
            $target = @($card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCondition) | Where-Object { $_.Current.Name -eq 'Edit permission target' })[0]
            try {
                $valueAvailable = $target.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsValuePatternAvailableProperty)
                Write-ApprovalDiagnostic "permission target value-pattern=$valueAvailable" 'permission-target-pattern'
            }
            catch { }
            $expectedTarget = @{ Id = ($target.GetRuntimeId() -join '.'); Value = $target.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
            # 2026-10-06：仅对已核验表单报告固定模式布尔值，候选日志不抢占滚动和错误诊断。
            try {
                $selectionAvailable = $option.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsSelectionItemPatternAvailableProperty)
                $scrollAvailable = $option.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty)
                Write-ApprovalDiagnostic "permission option enabled=$($option.Current.IsEnabled) offscreen=$($option.Current.IsOffscreen) selection=$selectionAvailable scrollitem=$scrollAvailable" 'permission-candidate'
            }
            catch { }
            if ($option.Current.IsOffscreen) {
                $stage = 'option-scroll-pattern'
                $scroll = $option.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
                if (-not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                $optionGroup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
                $optionCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)
                if ($null -eq $optionCard -or ($optionCard.GetRuntimeId() -join '.') -ne $cardId -or -not (Test-LiveApprovalCard $card $expectedTarget) -or -not $option.Current.IsEnabled -or -not (Test-OneTimeApprovalName $option.Current.Name)) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                $stage = 'option-scroll'
                $scroll.ScrollIntoView()
                Write-ApprovalDiagnostic "permission option-scroll returned=True visible=$(-not $option.Current.IsOffscreen)" 'permission-option-scroll'
            }
            if ($option.Current.IsOffscreen) { continue }
            if (-not (Test-ApprovalOptionSelected $option)) {
                # 2026-10-06：只在取得模式后再次核验同表单、可见性和宿主，模式降级不重复执行选择动作。
                $stage = 'selection-pattern'
                $selectionMethod = 'select'
                try { $selection = $option.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern) }
                # 2026-10-07：仅降级到托管 UIA 实际支持的调用模式，选中状态仍由 SelectionItem 复核。
                catch {
                    $selection = Get-BackgroundInvoke $option $WindowHandle # 2026-10-07
                    $backgroundPatterns.Add($selection)
                    $selectionMethod = 'invoke'
                }
                if (-not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                $optionGroup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
                $optionCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)
                if ($null -eq $optionCard -or ($optionCard.GetRuntimeId() -join '.') -ne $cardId -or -not (Test-LiveApprovalCard $card $expectedTarget) -or -not $option.Current.IsEnabled -or $option.Current.IsOffscreen -or $option.Current.AutomationId -notmatch '^ask-opt-.+-1$' -or -not (Test-OneTimeApprovalName $option.Current.Name)) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                $stage = 'selection'
                if ($selectionMethod -eq 'select') { $selection.Select() }
                else { $selection.Invoke() } # 2026-10-07：已取得调用模式后只执行一次选择动作。
            }
            if (-not (Test-ApprovalOptionSelected $option) -or -not (Test-LiveApprovalCard $card $expectedTarget)) {
                Write-ApprovalDiagnostic 'permission-card one-time selection unavailable'
                continue
            }
            if (-not (Test-ParentAlive) -or -not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
            if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
            $buttons = $card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
            foreach ($submit in $buttons) {
                if ($submit.Current.Name -notmatch '^(Submit|提交)(\s*[↵⏎])?$') { continue }
                if (-not $submit.Current.IsEnabled) { continue }
                try {
                    $invokeAvailable = $submit.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty)
                    $scrollAvailable = $submit.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty)
                    Write-ApprovalDiagnostic "permission submit enabled=$($submit.Current.IsEnabled) offscreen=$($submit.Current.IsOffscreen) invoke=$invokeAvailable scrollitem=$scrollAvailable" 'permission-submit-pattern'
                }
                catch { }
                # 2026-10-06：长表单只滚动同表单 Submit；顶部一次允许因本次滚动离屏时仍读取选中状态。
                $submitScrolled = $false
                if ($submit.Current.IsOffscreen) {
                    $stage = 'submit-scroll-pattern'
                    $scroll = $submit.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
                    if (-not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
                    if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                    $optionGroup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
                    $optionCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)
                    $submitCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($submit)
                    if ($null -eq $optionCard -or $null -eq $submitCard -or ($optionCard.GetRuntimeId() -join '.') -ne $cardId -or ($submitCard.GetRuntimeId() -join '.') -ne $cardId -or -not (Test-LiveApprovalCard $card $expectedTarget) -or -not $submit.Current.IsEnabled -or $submit.Current.Name -notmatch '^(Submit|提交)(\s*[↵⏎])?$' -or -not $option.Current.IsEnabled -or $option.Current.IsOffscreen -or -not (Test-ApprovalOptionSelected $option)) { continue }
                    if (-not (Test-ParentAlive)) { return $false }
                    $stage = 'submit-scroll'
                    $scroll.ScrollIntoView()
                    $submitScrolled = $true
                    Write-ApprovalDiagnostic "permission submit-scroll returned=True visible=$(-not $submit.Current.IsOffscreen)" 'permission-submit-scroll'
                }
                $stage = 'submit-pattern'
                $invoke = Get-BackgroundInvoke $submit $WindowHandle # 2026-10-07
                $backgroundPatterns.Add($invoke)
                # 2026-10-06：模式和宿主查询完成后，再核验最终按钮状态及两端控件仍归属原权限表单。
                if (-not (Get-TargetProcessIds $WindowProcessId).ContainsKey($WindowProcessId)) { continue } # 2026-10-07
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                $optionGroup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
                $optionCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)
                $submitCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($submit)
                if ($null -eq $optionCard -or $null -eq $submitCard -or ($optionCard.GetRuntimeId() -join '.') -ne $cardId -or ($submitCard.GetRuntimeId() -join '.') -ne $cardId) { continue }
                if (-not $submit.Current.IsEnabled -or $submit.Current.IsOffscreen -or $submit.Current.Name -notmatch '^(Submit|提交)(\s*[↵⏎])?$') { continue }
                # 2026-10-05：提交前最后复核本次允许，避免宿主检查期间选项变成始终允许或拒绝。
                if (-not $option.Current.IsEnabled -or ($option.Current.IsOffscreen -and -not $submitScrolled) -or $option.Current.AutomationId -notmatch '^ask-opt-.+-1$' -or -not (Test-OneTimeApprovalName $option.Current.Name) -or -not (Test-LiveApprovalCard $card $expectedTarget) -or -not (Test-ApprovalOptionSelected $option)) { continue }
                # 2026-10-05：所有控件查询结束后最后检查父宿主，退出期间不提交权限卡片。
                if (-not (Test-ParentAlive)) { return $false }
                $stage = 'submit-invoke' # 2026-10-07：最终批准阶段紧邻调用，选中、模式及只读查询失败不能误计为批准尝试。
                $invoke.Invoke()
                [Console]::WriteLine('___CLICK_INVOKE___:Submit (one-time permission)')
                return $true
            }
        }
        catch {
            Write-ApprovalDiagnostic "permission-card error stage=$stage type=$($_.Exception.GetType().Name)" 'permission-error'
            # 2026-10-07：提交调用已开始即消耗本轮，异常不能导致同轮继续批准其它窗口。
            if ($stage -eq 'submit-invoke') { return $true }
        } # 2026-10-06：错误日志只含固定阶段和类型，不输出命令正文。
        finally { foreach ($preparedPattern in $backgroundPatterns) { $preparedPattern.Dispose() } } # 2026-10-07
    }
    return $false
}

# 2026-07-28 自测只验证匹配规则，不进入无限扫描循环，方便打包前快速回归
function Invoke-SelfTest {
    # 2026-10-05：同时覆盖中文审批、普通按钮排除、窗口归属及负坐标，所有分支均不点击。
    $cases = @(
        @{ Name = 'Run'; Expected = $true },
        @{ Name = 'RunAlt+Enter'; Expected = $true },
        @{ Name = 'Run and Debug'; Expected = $false },
        @{ Name = 'Accept (1)'; Expected = $true },
        @{ Name = 'Accept All'; Expected = $true },
        @{ Name = 'Allow this conversation'; Expected = $true },
        @{ Name = 'Apply Changes'; Expected = $false },
        @{ Name = 'Application Settings'; Expected = $false },
        @{ Name = 'Continue'; Expected = $false },
        @{ Name = 'Continuous Integration'; Expected = $false },
        @{ Name = 'Yes'; Expected = $false },
        @{ Name = 'Ok'; Expected = $false },
        @{ Name = 'Always run'; Expected = $false },
        @{ Name = 'Run (Alt+Enter)'; Expected = $true },
        @{ Name = 'Run command'; Expected = $true },
        @{ Name = 'Run Task (Ctrl+Shift+P)'; Expected = $false },
        @{ Name = 'Runnable'; Expected = $false },
        @{ Name = 'Allow once'; Expected = $false },
        @{ Name = 'Allow this workspace'; Expected = $true },
        @{ Name = 'Accept all'; Expected = $true },
        @{ Name = 'Accept All Changes'; Expected = $true },
        @{ Name = 'Acceptance criteria'; Expected = $false },
        @{ Name = 'Approve'; Expected = $true },
        @{ Name = 'Execute'; Expected = $true },
        @{ Name = 'Retry'; Expected = $false },
        @{ Name = 'Save'; Expected = $false },
        @{ Name = 'Save All'; Expected = $false },
        @{ Name = 'Confirm'; Expected = $false },
        @{ Name = 'Overwrite'; Expected = $false },
        @{ Name = 'OK'; Expected = $false },
        @{ Name = 'Reject'; Expected = $false },
        @{ Name = 'Accept or Reject'; Expected = $false },
        @{ Name = 'Run / Stop'; Expected = $false },
        @{ Name = 'Allow - Cancel'; Expected = $false },
        @{ Name = '运行'; Expected = $true },
        @{ Name = '运行命令'; Expected = $true },
        @{ Name = '运行 (Alt+Enter)'; Expected = $true },
        @{ Name = '执行'; Expected = $true },
        @{ Name = '接受'; Expected = $true },
        @{ Name = '接受全部'; Expected = $true },
        @{ Name = '接受所有更改'; Expected = $true },
        @{ Name = '全部接受'; Expected = $true },
        @{ Name = '允许'; Expected = $true },
        @{ Name = '允许运行一次'; Expected = $true },
        @{ Name = '允许本次会话'; Expected = $true },
        @{ Name = '同意'; Expected = $true },
        @{ Name = '同意全部'; Expected = $true },
        @{ Name = '全部同意'; Expected = $true },
        @{ Name = '批准'; Expected = $true },
        @{ Name = '允许 / 拒绝'; Expected = $false },
        @{ Name = '运行 / 停止'; Expected = $false },
        @{ Name = '允许取消'; Expected = $false },
        @{ Name = '接受度设置'; Expected = $false },
        @{ Name = '运行状态'; Expected = $false },
        @{ Name = '保存'; Expected = $false },
        @{ Name = '确定'; Expected = $false },
        @{ Name = '是'; Expected = $false },
        @{ Name = '继续'; Expected = $false },
        @{ Name = ''; Expected = $false },
        @{ Name = '   '; Expected = $false }
        @{ Name = 'Run Write-Output test?'; Expected = $false },
        @{ Name = 'Run command？'; Expected = $false },
        @{ Name = 'Submit'; Expected = $false },
        @{ Name = 'Submit ↵'; Expected = $false },
        @{ Name = 'Run Write-Output ANTIGRAVITY_AA_SMOKE_V53'; Expected = $false },
        @{ Name = 'Run npm test'; Expected = $false },
        @{ Name = 'Run git status'; Expected = $false },
        @{ Name = 'Execute npm test'; Expected = $false },
        @{ Name = 'Approve npm test'; Expected = $false },
        @{ Name = 'Run (1)'; Expected = $false },
        @{ Name = 'Run command (Alt+Enter)'; Expected = $true },
        # 2026-10-06：浏览器专用批准由卡片分支处理，普通按钮匹配不得放行。
        @{ Name = 'Allow Once'; Expected = $false },
        @{ Name = 'Always Allow'; Expected = $false }
    )

    $failed = 0
    foreach ($case in $cases) {
        $actual = Test-ButtonMatch $case.Name
        if ($actual -ne $case.Expected) {
            [Console]::WriteLine("___SELFTEST_FAIL___:$($case.Name): expected=$($case.Expected), actual=$actual")
            $failed++
        }
    }

    $stateCases = @(
        @{ Root = 42; Exists = $true; Visible = $true; Enabled = $true; Iconic = $false; Process = 10; Expected = $true },
        @{ Root = 43; Exists = $true; Visible = $true; Enabled = $true; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 0; Exists = $true; Visible = $true; Enabled = $true; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $false; Visible = $true; Enabled = $true; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $true; Visible = $false; Enabled = $true; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $true; Visible = $true; Enabled = $false; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $true; Visible = $true; Enabled = $true; Iconic = $true; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $true; Visible = $true; Enabled = $true; Iconic = $false; Process = 11; Expected = $false }
    )
    foreach ($case in $stateCases) {
        $actual = [MouseHelper]::IsHitTargetWindow([IntPtr]42, [IntPtr]$case.Root, $case.Exists, $case.Visible, $case.Enabled, $case.Iconic, [uint32]$case.Process, [uint32]10)
        if ($actual -ne $case.Expected) {
            [Console]::WriteLine('___SELFTEST_FAIL___:window ownership')
            $failed++
        }
    }

    $pathCases = @(
        @{ Path = 'C:\Apps\Antigravity IDE.exe'; Host = 'c:\apps\ANTIGRAVITY IDE.EXE'; Expected = $true },
        @{ Path = 'C:\Apps\Antigravity.exe'; Host = ''; Expected = $true },
        @{ Path = 'C:\Other\Antigravity IDE.exe'; Host = 'C:\Apps\Antigravity IDE.exe'; Expected = $false },
        @{ Path = 'C:\Apps\Code.exe'; Host = ''; Expected = $false },
        @{ Path = ''; Host = ''; Expected = $false }
    )
    foreach ($case in $pathCases) {
        if ((Test-HostProcessPath $case.Path $case.Host) -ne $case.Expected) {
            [Console]::WriteLine('___SELFTEST_FAIL___:host executable path')
            $failed++
        }
    }

    $center = Get-ButtonCenter @{ X = -1920; Y = -1000; Width = 100; Height = 40 }
    if ($null -eq $center -or $center.X -ne -1870 -or $center.Y -ne -980) {
        [Console]::WriteLine('___SELFTEST_FAIL___:negative monitor coordinates')
        $failed++
    }
    if ($null -ne (Get-ButtonCenter @{ X = 0; Y = 0; Width = 0; Height = 40 })) {
        [Console]::WriteLine('___SELFTEST_FAIL___:invalid rectangle')
        $failed++
    }

    $cardCases = @(
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '4 No (tell the agent what to do instead)'); Submit = @('Skip', 'Submit ↵'); Expected = $true },
        @{ Edits = @('Other question'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '4 No'); Submit = @('Submit ↵'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-32-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '4 No'); Submit = @('Submit'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, and always allow command', '2 Yes, and always allow command', '4 No'); Submit = @('Submit'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-3'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '3 Other'); Submit = @('Submit'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Other', '4 No'); Submit = @('Submit'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '4 No'); Submit = @('Save'); Expected = $false }
    )
    foreach ($case in $cardCases) {
        if ((Test-ApprovalCardShape $case.Edits $case.Ids $case.Names $case.Submit) -ne $case.Expected) {
            [Console]::WriteLine('___SELFTEST_FAIL___:permission card scope')
            $failed++
        }
    }

    if ($failed -gt 0) {
        [Console]::WriteLine("___SELFTEST_DONE___:failed=$failed")
        exit 1
    }

    [Console]::WriteLine("___SELFTEST_DONE___:passed=$($cases.Count + $stateCases.Count + $pathCases.Count + $cardCases.Count + 2)")
    exit 0
}

if ($SelfTest) {
    Invoke-SelfTest
}

# 2026-07-28 扩展进程传入的是字符串，这里统一转成布尔值，避免 PowerShell 参数绑定失败
$restoreCursorEnabled = $RestoreCursor -notmatch '^(false|0|no)$'

# 2026-07-28 多个 Antigravity 窗口只允许一个全局扫描器，避免重复点击同一权限按钮
# 2026-10-05：等待现有扫描器释放后接管，父宿主退出时释放互斥并结束子进程。
$script:backgroundClient = $null # 2026-10-07：客户端仅在实际准备审批时创建。
$script:parentProcess = $null
if ($ParentProcessId -gt 0) {
    try { $script:parentProcess = Get-Process -Id $ParentProcessId -ErrorAction Stop }
    catch { exit 0 }
}
$scannerMutex = New-Object System.Threading.Mutex($false, 'Local\AntigravityAutoAcceptScanner')
$mutexOwned = $false
$waitingReported = $false
try {
    while (-not $mutexOwned -and (Test-ParentAlive)) {
        try { $mutexOwned = $scannerMutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $mutexOwned = $true }
        if (-not $mutexOwned) {
            if (-not $waitingReported) {
                [Console]::WriteLine('___SCANNER_WAITING___')
                $waitingReported = $true
            }
            Start-Sleep -Milliseconds $PollMs
        }
    }
    if (-not $mutexOwned -or -not (Test-ParentAlive)) { exit 0 }
    [Console]::WriteLine('___AUTOCLICK_READY___')
    $lastClickTime = [DateTime]::MinValue
    $lastServedWindowHandle = [IntPtr]::Zero # 2026-10-07：最终批准尝试后从下一窗口开始，持续审批的首窗不能饿死其余窗口。

    while (Test-ParentAlive) {
        Start-Sleep -Milliseconds $PollMs
        if (-not (Test-ParentAlive)) { break }
        $elapsed = ([DateTime]::Now - $lastClickTime).TotalMilliseconds
        if ($elapsed -lt $CooldownMs) { continue }

        try {
            $windows = @($automation.FindAll([System.Windows.Automation.TreeScope]::Children, $winCondition))
            # 2026-10-09：窗口离开本轮快照就丢弃其纯身份记录，不把已关闭窗口的菜单延续到新窗口。
            if ($null -ne $script:deferredBrowserMenus) {
                $liveMenuWindowKeys = @{}
                foreach ($menuWindow in $windows) {
                    try { $liveMenuWindowKeys[([long]$menuWindow.Current.NativeWindowHandle).ToString([Globalization.CultureInfo]::InvariantCulture)] = $true }
                    catch { }
                }
                foreach ($pendingWindowKey in @($script:deferredBrowserMenus.Keys)) {
                    if (-not $liveMenuWindowKeys.ContainsKey($pendingWindowKey)) { [void]$script:deferredBrowserMenus.Remove($pendingWindowKey) }
                }
            }
            $didClick = $false
            # 2026-10-07：每轮保留窗口快照并按上次动作窗口轮转，失效句柄只跳过自身。
            $windowStart = 0
            for ($index = 0; $index -lt $windows.Count; $index++) {
                try {
                    if ([IntPtr]$windows[$index].Current.NativeWindowHandle -eq $lastServedWindowHandle) {
                        $windowStart = ($index + 1) % $windows.Count
                        break
                    }
                }
                catch { }
            }

            for ($offset = 0; $offset -lt $windows.Count; $offset++) {
                if ($didClick) { break }
                $win = $windows[($windowStart + $offset) % $windows.Count]
                # 2026-10-07：单窗控件树在扫描时关闭或失效，不阻断同轮其它窗口。
                try {
                    # 2026-10-05：窗口仅按已验证路径的进程 ID 归属，窗口标题不影响识别。
                    $windowProcessId = $win.Current.ProcessId
                    # 2026-10-07：从本轮窗口读取 PID 后只查询该进程，其它应用不触发全系统进程枚举。
                    if (-not (Get-TargetProcessIds $windowProcessId).ContainsKey($windowProcessId)) { continue } # 2026-10-07
                    $windowHandle = [IntPtr]$win.Current.NativeWindowHandle
                    if ($windowHandle -eq [IntPtr]::Zero) { continue }

                    # 2026-10-05：新版本次审批卡片优先处理，完成后统一进入原点击冷却。
                    # 2026-10-06：浏览器域名卡片使用同卡片本次允许，窄栏菜单不能交给普通按钮匹配。
                    if (Invoke-BrowserPermissionCards $win $windowProcessId $windowHandle) {
                        $didClick = $true
                        $lastClickTime = [DateTime]::Now
                        $lastServedWindowHandle = $windowHandle # 2026-10-07：两类卡片均参与窗口轮转。
                        break
                    }
                    if (Invoke-ApprovalCards $win $windowProcessId $windowHandle) {
                        $didClick = $true
                        $lastClickTime = [DateTime]::Now
                        $lastServedWindowHandle = $windowHandle # 2026-10-07：终端提交尝试后优先服务其它窗口。
                        break
                    }

                    $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
                    foreach ($btn in $buttons) {
                        if ($didClick) { break }
                        # 2026-10-07：单个按钮失效或调用报错仅跳过该按钮，调用后报错不能再物理重试。
                        $ip = $null # 2026-10-07：早期跳过也不能沿用上一按钮的已释放模式。
                        try {
                            # 2026-10-07：先按名称排除普通按钮，避免无关控件的跨进程状态及几何查询。
                            $btnName = $btn.Current.Name
                            if (-not (Test-ButtonMatch $btnName)) { continue }
                            if (-not $btn.Current.IsEnabled) { continue }
                            if ($btn.Current.IsOffscreen) { continue }
                            $rect = $btn.Current.BoundingRectangle
                            if ($null -eq (Get-ButtonCenter $rect)) { continue }
                            $ip = $null
                            try { $ip = Get-BackgroundInvoke $btn $windowHandle } # 2026-10-07
                            catch { }
                            if ($null -ne $ip) {
                                # 2026-10-05：调用前重读按钮并复核宿主归属，扫描期间父进程退出时不执行动作。
                                # 2026-10-07：宿主查询放在最终按钮复核前，查询期间变化的名称及可见性不会沿用。
                                if (-not (Get-TargetProcessIds $windowProcessId).ContainsKey($windowProcessId)) { continue } # 2026-10-07
                                if ($win.Current.NativeWindowHandle -ne $windowHandle.ToInt64() -or $win.Current.ProcessId -ne $windowProcessId) { continue }
                                $btnName = $btn.Current.Name
                                if (-not $btn.Current.IsEnabled -or $btn.Current.IsOffscreen -or -not (Test-ButtonMatch $btnName)) { continue }
                                if (-not (Test-ParentAlive)) { break }
                                # 2026-10-07：提供者可能在动作后抛错，先占用本轮和窗口轮换；慢调用的冷却从结束时计时。
                                $didClick = $true
                                $lastServedWindowHandle = $windowHandle
                                try {
                                    $ip.Invoke()
                                    [Console]::WriteLine("___CLICK_INVOKE___:$btnName")
                                }
                                finally { $lastClickTime = [DateTime]::Now }
                            }
                            else {
                                # 2026-10-05：回退前重读按钮与窗口，坐标被遮挡、宿主退出或按钮失效均不点击。
                                # 2026-10-07：只有未取得调用模式才物理回退，最后坐标及状态查询后再检查父宿主。
                                if (-not (Get-TargetProcessIds $windowProcessId).ContainsKey($windowProcessId)) { continue } # 2026-10-07
                                if ($win.Current.NativeWindowHandle -ne $windowHandle.ToInt64() -or $win.Current.ProcessId -ne $windowProcessId) { continue }
                                $center = Get-ButtonCenter $btn.Current.BoundingRectangle
                                if ($null -eq $center) { continue }
                                $btnName = $btn.Current.Name
                                if (-not $btn.Current.IsEnabled -or $btn.Current.IsOffscreen -or -not (Test-ButtonMatch $btnName)) { continue }
                                if (-not (Test-ParentAlive)) { break }
                                # 2026-10-07：移动前保存原按钮身份，回退时从实际像素命中沿父链核对同一按钮。
                                $physicalButtonId = $btn.GetRuntimeId() -join '.'
                                $physicalButtonName = $btnName
                                $physicalValidator = [Func[bool]] {
                                    try {
                                        if (-not (Get-TargetProcessIds $windowProcessId).ContainsKey($windowProcessId)) { return $false } # 2026-10-07
                                        if ($win.Current.NativeWindowHandle -ne $windowHandle.ToInt64() -or $win.Current.ProcessId -ne $windowProcessId) { return $false }
                                        $pointed = [System.Windows.Automation.AutomationElement]::FromPoint([System.Windows.Point]::new($center.X, $center.Y))
                                        $pointedMatches = $false
                                        for ($depth = 0; $null -ne $pointed -and $depth -lt 8; $depth++) {
                                            if (($pointed.GetRuntimeId() -join '.') -eq $physicalButtonId) { $pointedMatches = $true; break }
                                            $pointed = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($pointed)
                                        }
                                        if (-not $pointedMatches -or ($btn.GetRuntimeId() -join '.') -ne $physicalButtonId) { return $false }
                                        $currentRectangle = $btn.Current.BoundingRectangle
                                        if ($null -eq (Get-ButtonCenter $currentRectangle) -or $center.X -lt $currentRectangle.X -or $center.Y -lt $currentRectangle.Y -or $center.X -ge ($currentRectangle.X + $currentRectangle.Width) -or $center.Y -ge ($currentRectangle.Y + $currentRectangle.Height)) { return $false }
                                        if (-not $btn.Current.IsEnabled -or $btn.Current.IsOffscreen -or $btn.Current.Name -ne $physicalButtonName -or -not (Test-ButtonMatch $btn.Current.Name)) { return $false }
                                        return Test-ParentAlive
                                    }
                                    catch { return $false }
                                }
                                # 2026-10-07：物理回退同样只尝试一次，失败或动作后抛错都从动作结束时开始冷却。
                                $didClick = $true
                                $lastServedWindowHandle = $windowHandle
                                try {
                                    if ([MouseHelper]::Click($center.X, $center.Y, $restoreCursorEnabled, $windowHandle, [uint32]$windowProcessId, $physicalValidator)) {
                                        [Console]::WriteLine("___CLICK_PHYSICAL___:$btnName at ($($center.X),$($center.Y))")
                                    }
                                }
                                finally { $lastClickTime = [DateTime]::Now }
                            }
                        }
                        catch { Write-ApprovalDiagnostic "button scan failed type=$($_.Exception.GetType().Name)" 'button-error' }
                        finally { if ($null -ne $ip) { $ip.Dispose() } } # 2026-10-07
                    }
                }
                catch { Write-ApprovalDiagnostic "window scan failed type=$($_.Exception.GetType().Name)" 'window-error' }
            }
        }
        catch {
            if ($_.Exception.Message -notlike '*Operation is not valid*') {
                [Console]::WriteLine("___ERROR___:$($_.Exception.Message)")
            }
        }
    }
}
# 2026-10-05：正常退出和异常退出均释放已持有的单实例锁，等待者可继续接管。
finally {
    if ($null -ne $script:backgroundClient) { $script:backgroundClient.Dispose(); $script:backgroundClient = $null } # 2026-10-07
    if ($mutexOwned) { $scannerMutex.ReleaseMutex() }
    $scannerMutex.Dispose()
    if ($null -ne $script:parentProcess) { $script:parentProcess.Dispose() }
}
