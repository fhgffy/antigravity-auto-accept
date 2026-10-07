# 2026-10-07：只替换生产鼠标方法的原生边界，验证真实控制流，不向桌面注入任何输入。
param([string[]]$PowerShellEngines = @('powershell.exe', 'pwsh.exe'), [string]$ScannerSourcePath = '', [switch]$InProcess)

$ErrorActionPreference = 'Stop'
$scannerPath = if ([string]::IsNullOrWhiteSpace($ScannerSourcePath)) { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1')) } else { [IO.Path]::GetFullPath($ScannerSourcePath) }
if (-not $InProcess) {
    $engines = @($PowerShellEngines | ForEach-Object { (Get-Command $_ -ErrorAction Stop).Source } | Select-Object -Unique)
    if ($engines.Count -eq 0) { throw 'No requested PowerShell engine' }
    foreach ($engine in $engines) {
        $testLiteral = $PSCommandPath.Replace("'", "''")
        $scannerLiteral = $scannerPath.Replace("'", "''")
        $command = '$ProgressPreference=''SilentlyContinue''; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); '
        $command += "`$testPath='$testLiteral'; `$tokens=`$null; `$errors=`$null; `$ast=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText(`$testPath,[Text.Encoding]::UTF8),`$testPath,[ref]`$tokens,[ref]`$errors); if (`$errors.Count) { throw 'Mouse test parse errors' }; & `$ast.GetScriptBlock() -InProcess -ScannerSourcePath '$scannerLiteral'"
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $engine
        $start.Arguments = '-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.Encoding]::UTF8
        $start.StandardErrorEncoding = [Text.Encoding]::UTF8
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $start
        [void]$process.Start()
        $pendingOut = $process.StandardOutput.ReadToEndAsync()
        $pendingError = $process.StandardError.ReadToEndAsync()
        try {
            if (-not $process.WaitForExit(30000)) { throw "Mouse test timeout: $engine" }
            $output = $pendingOut.GetAwaiter().GetResult()
            $errorOutput = $pendingError.GetAwaiter().GetResult()
            Write-Output $output.TrimEnd()
            if ($process.ExitCode -ne 0 -or $errorOutput.Length -gt 0 -or $output -notmatch '___MOUSE_HELPER_TEST_DONE___:passed=\d+') { throw "Mouse test failed: engine=$engine exit=$($process.ExitCode) stderr=$errorOutput" }
            Write-Output "PASS mouse helper engine: $engine"
        }
        finally {
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
            $process.Dispose()
        }
    }
    exit 0
}

$source = [IO.File]::ReadAllText($scannerPath, [Text.Encoding]::UTF8)
$match = [regex]::Match($source, '(?s)Add-Type -TypeDefinition @"\r?\n(.*?)\r?\n"@')
if (-not $match.Success -or -not $match.Groups[1].Value.Contains('public class MouseHelper')) { throw 'Production mouse helper not found' }
$csharp = $match.Groups[1].Value
# 2026-10-07：先编译未改动的原生定义，只查询结构和签名，绝不调用其鼠标或键盘 P/Invoke。
Add-Type -TypeDefinition $csharp -ErrorAction Stop
$checks = 1
$failures = @()
$inputType = [MouseHelper].GetNestedType('INPUT')
if ($null -ne $inputType) {
    $expectedSize = if ([IntPtr]::Size -eq 8) { 40 } else { 28 }
    $expectedOffset = if ([IntPtr]::Size -eq 8) { 8 } else { 4 }
    if ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($inputType)) -ne $expectedSize -or [Runtime.InteropServices.Marshal]::OffsetOf($inputType, 'data').ToInt32() -ne $expectedOffset) { throw 'Native INPUT size or union offset mismatch' }
    $mouseInputType = [MouseHelper].GetNestedType('MOUSEINPUT')
    $expectedMouseSize = if ([IntPtr]::Size -eq 8) { 32 } else { 24 }
    if ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($mouseInputType)) -ne $expectedMouseSize -or [Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance([MouseHelper].GetNestedType('INPUTUNION'))) -ne $expectedMouseSize) { throw 'Native MOUSEINPUT or union size mismatch' }
    if ([Runtime.InteropServices.Marshal]::OffsetOf($mouseInputType, 'dwExtraInfo').ToInt32() -ne $(if ([IntPtr]::Size -eq 8) { 24 } else { 20 })) { throw 'Native MOUSEINPUT pointer offset mismatch' }
    if ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance([MouseHelper].GetNestedType('LASTINPUTINFO'))) -ne 8) { throw 'Native LASTINPUTINFO size mismatch' }
    $sendMethod = [MouseHelper].GetMethod('SendInput')
    $import = @($sendMethod.GetCustomAttributes([Runtime.InteropServices.DllImportAttribute], $false))[0]
    if ($import.Value -ne 'user32.dll' -or $sendMethod.ReturnType -ne [uint32]) { throw 'SendInput native signature mismatch' }
    $arrayMarshal = @($sendMethod.GetParameters()[1].GetCustomAttributes([Runtime.InteropServices.MarshalAsAttribute], $false))[0]
    if ($arrayMarshal.Value -ne [Runtime.InteropServices.UnmanagedType]::LPArray -or $arrayMarshal.SizeParamIndex -ne 0) { throw 'SendInput native array marshal mismatch' }
    if ([MouseHelper].GetNestedType('RECT') -eq $null) { $failures += 'Native RECT absent' } elseif ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance([MouseHelper].GetNestedType('RECT'))) -ne 16) { throw 'Native RECT size mismatch' }
    $checks += 5
    Write-Output "PASS production native layout: pointer=$([IntPtr]::Size) INPUT=$expectedSize offset=$expectedOffset"
}
else { $failures += 'Native INPUT and paired SendInput absent'; Write-Output 'FAIL production native layout: paired SendInput absent' }

# 2026-10-07：所有原生方法替换成内存状态；生产 Click、核验和批次控制流原样执行。
$nativeBodies = @{
    GetPhysicalCursorPos = 'FakeCursorCalls++; if (FakeCase == "final-cursor-change" && FakeCursorCalls > 1) { UserMove(); } lpPoint = new POINT { X = FakeX, Y = FakeY }; return FakeCase != "cursor-unreadable";'
    GetCursorPos = 'lpPoint = new POINT { X = FakeX, Y = FakeY }; return FakeCase != "cursor-unreadable";'
    SetCursorPos = 'FakeSetCalls++; FakeX = X; FakeY = Y; if (FakeCase == "own-move-time") { FakeInputTime = ++FakeTick; } return true;'
    mouse_event = 'RecordInput(new MOUSEINPUT { dwFlags = dwFlags });'
    WindowFromPoint = 'return new IntPtr(FakeCovered || FakeCase == "covered" ? 43 : 42);'
    GetAncestor = 'return hwnd;'
    IsWindow = 'return FakeCase != "window-gone";'
    IsWindowVisible = 'return true;'
    IsWindowEnabled = 'return true;'
    IsIconic = 'return false;'
    GetWindowThreadProcessId = 'processId = 123; if (FakeCase == "validation-move" && FakeCursorCalls > 0 && !FakeMoved) { UserMove(); } return 1;'
    GetForegroundWindow = 'return new IntPtr(FakeBackground || FakeCase == "background" ? 43 : 42);'
    GetAsyncKeyState = 'return FakeKeys.Contains(virtualKey) ? unchecked((short)0x8000) : (short)0;'
    GetLastInputInfo = 'info.dwTime = FakeInputTime; return FakeCase != "input-unreadable";'
    GetTickCount = 'return FakeTick;'
    SetThreadDpiAwarenessContext = 'FakeDpiCalls++; if (FakeCase == "dpi-unsupported") { throw new EntryPointNotFoundException(); } if (FakeCase == "dpi-failed") { return IntPtr.Zero; } IntPtr prior = new IntPtr(FakeDpi); FakeDpi = context.ToInt32(); return prior;'
    GetSystemMetricsForDpi = 'FakeNativeDpiValid = FakeNativeDpiValid && dpi == 96 && FakeDpi == -4; if (FakeCase == "metrics-change" && FakeValidatorCalls > 0) { return index == 78 ? FakeWidth - 1 : Metric(index); } return Metric(index);'
    GetClipCursor = 'FakeClipCalls++; rectangle = new RECT { Left = FakeClipLeft, Top = FakeClipTop, Right = FakeClipRight, Bottom = FakeClipBottom }; if (FakeCase == "clip-change" && FakeClipCalls > 1) { rectangle.Right--; } if (FakeClipCalls > 1 && FakeCase == "clip-foreground") { FakeBackground = true; } if (FakeClipCalls > 1 && FakeCase == "clip-covered") { FakeCovered = true; } return FakeCase != "clip-unreadable";'
    MonitorFromPoint = 'return new IntPtr((FakeCase == "target-gap" && point.X == 50) || (FakeCase == "restore-gap" && point.X == 5) ? 0 : 1);'
    SendInput = 'return SendMemoryInputs(count, inputs);'
}
$shadow = $csharp.Replace('public class MouseHelper', 'public class MouseHelperMemory')
$nativePattern = '(?m)^    \[DllImport\([^\r\n]+\)\]\r?\n    public static extern [^\r\n]+;'
$declarations = [regex]::Matches($shadow, $nativePattern)
if ($declarations.Count -lt 10) { throw 'Native replacement declarations incomplete' }
foreach ($declaration in $declarations) {
    $signature = ($declaration.Value -split '\r?\n')[-1].Trim()
    $methodMatch = [regex]::Match($signature, 'public static extern \S+ (\w+)\(')
    $methodName = $methodMatch.Groups[1].Value
    if (-not $nativeBodies.ContainsKey($methodName)) { throw "Unhandled native boundary: $methodName" }
    $replacement = '    ' + ($signature -replace '\bextern\s+', '').TrimEnd(';') + ' { ' + $nativeBodies[$methodName] + ' }'
    $shadow = $shadow.Replace($declaration.Value, $replacement)
}
if ($shadow.Contains('[DllImport(')) { throw 'A native boundary remains in memory test' }
$shadow = $shadow.Replace('System.Threading.Thread.Sleep(', 'MemorySleep(')
$stateCode = @'
    // 2026-10-07：时序只改变内存，按绝对坐标像素映射记录整个批次，不向桌面注入事件。
    public static string FakeCase;
    public static int FakeX, FakeY, FakeSetCalls, FakeDown, FakeUp, FakeDownX, FakeUpX, FakeDownY, FakeUpY, FakeSendCalls, FakeCursorCalls;
    public static int FakeValidatorCalls, FakeDpiCalls, FakeDpi, FakeLeft, FakeTop, FakeWidth, FakeHeight, FakeClipCalls;
    public static int FakeClipLeft, FakeClipTop, FakeClipRight, FakeClipBottom;
    public static uint FakeInputTime, FakeTick;
    public static bool FakeMoved, FakeTargetMatches, FakeCovered, FakeBackground, FakeNativeDpiValid;
    public static System.Collections.Generic.HashSet<int> FakeKeys = new System.Collections.Generic.HashSet<int>();
    public static System.Collections.Generic.List<uint> FakeRequested = new System.Collections.Generic.List<uint>();
    public static System.Collections.Generic.List<uint> FakeFlags = new System.Collections.Generic.List<uint>();
    public static void Reset(string name) {
        FakeCase = name; FakeX = 5; FakeY = 6; FakeSetCalls = 0; FakeDown = 0; FakeUp = 0;
        FakeDownX = 0; FakeUpX = 0; FakeDownY = 0; FakeUpY = 0; FakeSendCalls = 0; FakeCursorCalls = 0; FakeValidatorCalls = 0; FakeClipCalls = 0;
        FakeDpiCalls = 0; FakeDpi = -2; FakeNativeDpiValid = true; FakeTick = 10000; FakeInputTime = 9000;
        FakeLeft = 0; FakeTop = 0; FakeWidth = 1920; FakeHeight = 1080;
        FakeMoved = false; FakeTargetMatches = true; FakeCovered = false; FakeBackground = false;
        FakeKeys.Clear(); FakeRequested.Clear(); FakeFlags.Clear();
        if (name == "left-held") { FakeKeys.Add(1); } if (name == "right-held") { FakeKeys.Add(2); }
        if (name == "middle-held") { FakeKeys.Add(4); } if (name == "xbutton-held") { FakeKeys.Add(5); }
        if (name == "shift-held") { FakeKeys.Add(16); } if (name == "control-held") { FakeKeys.Add(17); }
        if (name == "alt-held") { FakeKeys.Add(18); } if (name == "windows-held") { FakeKeys.Add(91); }
        if (name == "recent-input") { FakeInputTime = 9900; }
        if (name == "tick-wrap") { FakeTick = 1000; FakeInputTime = UInt32.MaxValue - 1000; }
        if (name.StartsWith("negative-")) { FakeLeft = -1920; FakeTop = -1080; FakeWidth = 3840; FakeHeight = 2160; }
        if (name == "invalid-metrics") { FakeWidth = 0; } if (name == "too-wide") { FakeWidth = 65537; }
        if (name == "tiny-desktop") { FakeWidth = 1; FakeHeight = 1; FakeX = FakeY = 0; }
        if (name == "largest-desktop") { FakeWidth = 65536; FakeHeight = 65536; }
        if (name == "rounding-desktop" || name == "negative-rounding") { FakeWidth = 65535; FakeHeight = 65535; }
        if (name == "overflow-origin") { FakeLeft = Int32.MinValue; FakeTop = Int32.MinValue; FakeX = FakeLeft + 5; FakeY = FakeTop + 6; }
        FakeClipLeft = FakeLeft; FakeClipTop = FakeTop; FakeClipRight = FakeLeft + FakeWidth; FakeClipBottom = FakeTop + FakeHeight;
        if (name == "target-clipped") { FakeClipRight = 40; } if (name == "restore-clipped") { FakeClipLeft = 20; }
    }
    public static int Metric(int index) {
        if (index == 76) { return FakeLeft; } if (index == 77) { return FakeTop; }
        if (index == 78) { return FakeWidth; } if (index == 79) { return FakeHeight; }
        throw new InvalidOperationException("Unexpected screen metric");
    }
    public static void UserMove() { FakeMoved = true; FakeX = 888; FakeY = 777; FakeInputTime = ++FakeTick; }
    public static void RecordInput(MOUSEINPUT input) {
        FakeFlags.Add(input.dwFlags);
        if ((input.dwFlags & 1) != 0) {
            if ((input.dwFlags & 0xc000) != 0xc000 || input.dx < 0 || input.dx > 65535 || input.dy < 0 || input.dy > 65535) { throw new InvalidOperationException("Invalid absolute move"); }
            FakeX = FakeLeft + (int)((long)input.dx * FakeWidth / 65536); FakeY = FakeTop + (int)((long)input.dy * FakeHeight / 65536);
        }
        if ((input.dwFlags & 2) != 0) { FakeDown++; FakeDownX = FakeX; FakeDownY = FakeY; FakeKeys.Add(1); }
        if ((input.dwFlags & 4) != 0) { FakeUp++; FakeUpX = FakeX; FakeUpY = FakeY; FakeKeys.Remove(1); }
        FakeInputTime = input.time == 0 ? ++FakeTick : input.time;
    }
    public static uint SendMemoryInputs(uint count, INPUT[] inputs) {
        FakeSendCalls++; FakeRequested.Add(count); uint inserted = count;
        if (FakeSendCalls == 1) {
            if (FakeCase == "send-zero") { inserted = 0; } if (FakeCase == "send-one") { inserted = 1; }
            if (FakeCase == "send-two" || FakeCase == "send-two-up-blocked") { inserted = 2; }
            if (FakeCase == "send-three") { inserted = 3; }
        }
        else if (FakeCase == "send-two-up-blocked") { inserted = 0; }
        if (inserted > count) { inserted = count; }
        for (int index = 0; index < inserted; index++) { RecordInput(inputs[index].data.mi); }
        if (FakeCase == "post-batch-move" || FakeCase == "post-batch-input") { UserMove(); }
        return inserted;
    }
    public static void MemorySleep(int milliseconds) { if (milliseconds == 30 && FakeCase == "own-move-time") { FakeInputTime = ++FakeTick; } }
    public static bool ValidateTarget() {
        FakeValidatorCalls++;
        if (FakeCase == "callback-input") { FakeInputTime = ++FakeTick; } if (FakeCase == "callback-input-backwards") { FakeInputTime = 8000; }
        if (FakeCase == "callback-key") { FakeKeys.Add(16); }
        if (FakeCase == "callback-move" || FakeCase == "callback-same-tick-move") { uint savedTime = FakeInputTime; UserMove(); if (FakeCase == "callback-same-tick-move") { FakeInputTime = savedTime; } }
        if (FakeCase == "callback-foreground") { FakeBackground = true; } if (FakeCase == "callback-covered") { FakeCovered = true; }
        if (FakeCase == "layout-change") { FakeTargetMatches = false; }
        return FakeTargetMatches;
    }
'@
if (-not $csharp.Contains('public struct RECT')) { $shadow = $shadow.Replace('public class MouseHelperMemory {', 'public class MouseHelperMemory { public struct RECT { public int Left, Top, Right, Bottom; }'); }
$closingIndex = $shadow.LastIndexOf('}', [StringComparison]::Ordinal)
$shadow = $shadow.Insert($closingIndex, $stateCode + "`r`n")
Add-Type -TypeDefinition $shadow -ErrorAction Stop
$method = [MouseHelperMemory].GetMethod('Click')
function Test-MemoryTargetCurrent { return [MouseHelperMemory]::ValidateTarget() } # 2026-10-07：委托保留当前脚本函数作用域，直接在生产调用线程执行。
foreach ($name in @('good', 'no-restore', 'covered', 'window-gone', 'background', 'cursor-unreadable', 'input-unreadable', 'left-held', 'right-held', 'middle-held', 'xbutton-held', 'shift-held', 'control-held', 'alt-held', 'windows-held', 'recent-input', 'validation-move', 'layout-change', 'callback-input', 'callback-input-backwards', 'callback-key', 'callback-move', 'callback-same-tick-move', 'callback-foreground', 'callback-covered', 'final-cursor-change', 'validator-null', 'send-zero', 'send-one', 'send-two', 'send-two-up-blocked', 'send-three', 'post-batch-move', 'post-batch-input', 'own-move-time', 'tick-wrap', 'negative-origin', 'negative-min', 'negative-max', 'target-offscreen', 'target-gap', 'restore-gap', 'target-clipped', 'restore-clipped', 'clip-unreadable', 'clip-change', 'clip-foreground', 'clip-covered', 'metrics-change', 'invalid-metrics', 'too-wide', 'tiny-desktop', 'largest-desktop', 'rounding-desktop', 'negative-rounding', 'overflow-origin', 'dpi-failed', 'dpi-unsupported')) {
    [MouseHelperMemory]::Reset($name)
    $restore = $name -ne 'no-restore'
    $originalX = [MouseHelperMemory]::FakeX
    $originalY = [MouseHelperMemory]::FakeY
    $targetX = 50
    $targetY = 20
    switch ($name) {
        'negative-origin' { $targetX = -1850; $targetY = -1040 }
        'negative-min' { $targetX = -1920; $targetY = -1080 }
        'negative-max' { $targetX = 1919; $targetY = 1079 }
        'target-offscreen' { $targetX = 1920 }
        'tiny-desktop' { $targetX = 0; $targetY = 0 }
        'largest-desktop' { $targetX = 65535; $targetY = 65535 }
        'rounding-desktop' { $targetX = 1; $targetY = 1 }
        'negative-rounding' { $targetX = -1919; $targetY = -1079 }
        'overflow-origin' { $targetX = [int]::MinValue + 50; $targetY = [int]::MinValue + 20 }
    }
    $arguments = @([int]$targetX, [int]$targetY, [bool]$restore, [IntPtr]42, [uint32]123)
    if ($method.GetParameters().Count -eq 6) { $arguments += $(if ($name -eq 'validator-null') { $null } else { [Func[bool]]{ return Test-MemoryTargetCurrent } }) }
    $actual = [bool]$method.Invoke($null, $arguments)
    $expected = $name -in @('good', 'no-restore', 'send-three', 'post-batch-move', 'post-batch-input', 'own-move-time', 'tick-wrap', 'negative-origin', 'negative-min', 'negative-max', 'tiny-desktop', 'largest-desktop', 'rounding-desktop', 'negative-rounding', 'overflow-origin')
    $passed = $actual -eq $expected -and [MouseHelperMemory]::FakeSetCalls -eq 0 -and [MouseHelperMemory]::FakeDpi -eq -2
    if ($expected) {
        $passed = $passed -and [MouseHelperMemory]::FakeDown -eq 1 -and [MouseHelperMemory]::FakeUp -eq 1 -and [MouseHelperMemory]::FakeDownX -eq $targetX -and [MouseHelperMemory]::FakeUpX -eq $targetX -and [MouseHelperMemory]::FakeDownY -eq $targetY -and [MouseHelperMemory]::FakeUpY -eq $targetY
        $passed = $passed -and [MouseHelperMemory]::FakeSendCalls -eq 1 -and [MouseHelperMemory]::FakeRequested[0] -eq $(if ($restore) { 4 } else { 3 }) -and [MouseHelperMemory]::FakeNativeDpiValid
        $passed = $passed -and [MouseHelperMemory]::FakeFlags[0] -eq 49153 -and [MouseHelperMemory]::FakeFlags[1] -eq 2 -and [MouseHelperMemory]::FakeFlags[2] -eq 4
        if ($name -in @('post-batch-move', 'post-batch-input')) { $passed = $passed -and [MouseHelperMemory]::FakeX -eq 888 -and [MouseHelperMemory]::FakeY -eq 777 }
        elseif ($name -in @('no-restore', 'send-three')) { $passed = $passed -and [MouseHelperMemory]::FakeX -eq $targetX -and [MouseHelperMemory]::FakeY -eq $targetY }
        else { $passed = $passed -and [MouseHelperMemory]::FakeX -eq $originalX -and [MouseHelperMemory]::FakeY -eq $originalY -and [MouseHelperMemory]::FakeFlags[3] -eq 49153 }
    }
    elseif ($name -in @('send-two', 'send-two-up-blocked')) {
        $expectedUp = if ($name -eq 'send-two') { 1 } else { 0 }
        $passed = $passed -and [MouseHelperMemory]::FakeDown -eq 1 -and [MouseHelperMemory]::FakeUp -eq $expectedUp -and [MouseHelperMemory]::FakeSendCalls -eq 2 -and [MouseHelperMemory]::FakeRequested[1] -eq 1
        $passed = $passed -and [MouseHelperMemory]::FakeX -eq $targetX -and [MouseHelperMemory]::FakeY -eq $targetY
    }
    else {
        $passed = $passed -and [MouseHelperMemory]::FakeDown -eq 0 -and [MouseHelperMemory]::FakeUp -eq 0
        $passed = $passed -and [MouseHelperMemory]::FakeSendCalls -eq $(if ($name -in @('send-zero', 'send-one')) { 1 } else { 0 })
        if ($name -eq 'send-one') { $passed = $passed -and [MouseHelperMemory]::FakeX -eq $targetX -and [MouseHelperMemory]::FakeY -eq $targetY }
        elseif ($name -in @('callback-move', 'callback-same-tick-move', 'validation-move', 'final-cursor-change')) { $passed = $passed -and [MouseHelperMemory]::FakeX -eq 888 -and [MouseHelperMemory]::FakeY -eq 777 }
        else { $passed = $passed -and [MouseHelperMemory]::FakeX -eq $originalX -and [MouseHelperMemory]::FakeY -eq $originalY }
    }
    if ($name -eq 'left-held') { $passed = $passed -and [MouseHelperMemory]::FakeKeys.Contains(1) }
    $description = "case=$name result=$actual down=$([MouseHelperMemory]::FakeDown) up=$([MouseHelperMemory]::FakeUp) down-point=$([MouseHelperMemory]::FakeDownX),$([MouseHelperMemory]::FakeDownY) up-point=$([MouseHelperMemory]::FakeUpX),$([MouseHelperMemory]::FakeUpY) cursor=$([MouseHelperMemory]::FakeX),$([MouseHelperMemory]::FakeY) send-calls=$([MouseHelperMemory]::FakeSendCalls)"
    if (-not $passed) { $failures += $description; Write-Output "FAIL mouse helper: $description" }
    else { Write-Output "PASS mouse helper: $description" }
    $checks++
}
# 2026-10-07：真实 PowerShell 身份回调只替换像素命中和父节点查询，在生产 C# 委托调用中执行。
$tokens = $null
$parseErrors = $null
$sourceAst = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Physical validator source parse errors' }
$validatorAssignment = @($sourceAst.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq 'physicalValidator' }, $true))
if ($validatorAssignment.Count -eq 1) {
    foreach ($name in @('targetPrefixes', 'excludeExact', 'exactOnly')) {
        $assignment = @($sourceAst.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq $name }, $true))
        if ($assignment.Count -ne 1) { throw "Physical matcher table missing: $name" }
        . ([scriptblock]::Create($assignment[0].Extent.Text))
    }
    foreach ($name in @('Test-PrefixBoundary', 'Test-ButtonMatch', 'Get-ButtonCenter')) {
        $definition = @($sourceAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
        if ($definition.Count -ne 1) { throw "Physical validator function missing: $name" }
        . ([scriptblock]::Create($definition[0].Extent.Text))
    }
    $validatorText = $validatorAssignment[0].Extent.Text
    $pointQuery = '[System.Windows.Automation.AutomationElement]::FromPoint([System.Windows.Point]::new($center.X, $center.Y))'
    $parentQuery = '[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($pointed)'
    if (-not $validatorText.Contains($pointQuery) -or -not $validatorText.Contains($parentQuery)) { throw 'Physical validator native boundary changed' }
    $validatorText = $validatorText.Replace($pointQuery, '(Get-MemoryPhysicalPoint)').Replace($parentQuery, '(Get-MemoryPhysicalParent $pointed)')
    function Test-ParentAlive { return $script:memoryParentAlive }
    function Get-TargetProcessIds {
        [MouseHelperMemory]::FakeValidatorCalls++
        if ($script:memoryValidatorCase -eq 'host-changed') { $script:memoryWindow.Current.ProcessId = 999 }
        if ($script:memoryValidatorCase -eq 'parent-exit') { $script:memoryParentAlive = $false }
        if ($script:memoryValidatorCase -eq 'input-during-query') { [MouseHelperMemory]::UserMove() }
        return @{ 123 = $true }
    }
    function Get-MemoryPhysicalPoint {
        if ($script:memoryValidatorCase -eq 'query-error') { throw 'Pixel query unavailable in test' }
        switch ($script:memoryValidatorCase) {
            'changed-name' { $script:memoryButton.Current.Name = 'Reject' }
            'replaced-button' { $script:memoryButton.Key = 1002 }
            'moved-button' { $script:memoryButton.Current.BoundingRectangle.X = 200 }
            'disabled' { $script:memoryButton.Current.IsEnabled = $false }
            'offscreen' { $script:memoryButton.Current.IsOffscreen = $true }
        }
        return $script:memoryPixelLeaf
    }
    function Get-MemoryPhysicalParent($Node) { return $Node.Parent }
    $checks++
    foreach ($case in @('button-leaf', 'text-child', 'wrong-button', 'changed-name', 'replaced-button', 'moved-button', 'host-changed', 'parent-exit', 'parent-chain-missing', 'disabled', 'offscreen', 'query-error', 'input-during-query')) {
        [MouseHelperMemory]::Reset('validator-case')
        $script:memoryValidatorCase = $case
        $script:memoryParentAlive = $true
        $btn = [pscustomobject]@{ Key = 1001; Parent = $null; Current = [pscustomobject]@{ Name = 'Run'; IsEnabled = $true; IsOffscreen = $false; BoundingRectangle = @{ X = 0; Y = 0; Width = 100; Height = 40 } } }
        $btn | Add-Member ScriptMethod GetRuntimeId { return @($this.Key) }
        $win = [pscustomobject]@{ Current = [pscustomobject]@{ ProcessId = 123; NativeWindowHandle = 42 } }
        $leaf = [pscustomobject]@{ Key = 2001; Parent = $btn }
        $leaf | Add-Member ScriptMethod GetRuntimeId { return @($this.Key) }
        if ($case -eq 'wrong-button') {
            $otherButton = [pscustomobject]@{ Key = 1002; Parent = $null }
            $otherButton | Add-Member ScriptMethod GetRuntimeId { return @($this.Key) }
            $leaf.Parent = $otherButton
        }
        if ($case -eq 'parent-chain-missing') { $leaf.Parent = $null }
        $script:memoryButton = $btn
        $script:memoryWindow = $win
        $script:memoryPixelLeaf = if ($case -eq 'button-leaf') { $btn } else { $leaf }
        $windowProcessId = 123
        $windowHandle = [IntPtr]42
        $center = @{ X = 50; Y = 20 }
        $physicalButtonId = $btn.GetRuntimeId() -join '.'
        $physicalButtonName = 'Run'
        . ([scriptblock]::Create($validatorText))
        $actual = [bool]$method.Invoke($null, @([int]50, [int]20, [bool]$true, [IntPtr]42, [uint32]123, $physicalValidator))
        $expected = $case -in @('button-leaf', 'text-child')
        $eventCount = [MouseHelperMemory]::FakeDown + [MouseHelperMemory]::FakeUp
        $passed = $actual -eq $expected -and $eventCount -eq $(if ($expected) { 2 } else { 0 })
        if ($case -eq 'input-during-query') { $passed = $passed -and [MouseHelperMemory]::FakeX -eq 888 -and [MouseHelperMemory]::FakeY -eq 777 }
        $description = "case=$case result=$actual events=$eventCount cursor=$([MouseHelperMemory]::FakeX),$([MouseHelperMemory]::FakeY)"
        if (-not $passed) { $failures += $description; Write-Output "FAIL production physical validator: $description" }
        else { Write-Output "PASS production physical validator: $description" }
        $checks++
    }
}
else { $failures += 'Production physical identity validator absent'; Write-Output 'FAIL production physical validator: absent' }

if ($csharp.Contains('mouse_event(') -or $csharp.Contains('SetCursorPos(') -or $csharp.Contains('Thread.Sleep(')) { $failures += 'Split cursor or mouse events remain'; Write-Output 'FAIL mouse event pairing: split input or cursor dwell remains' }
else { $checks++; Write-Output 'PASS mouse event pairing: one move-click-restore SendInput batch' }
foreach ($path in @($scannerPath, $PSCommandPath)) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $body = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if (($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) -or $body -match '(?<!\r)\n|\r(?!\n)') { throw "Mouse test encoding changed: $path" }
    $checks++
}
if ($failures.Count -gt 0) { throw "Mouse helper failures ($($failures.Count)): $($failures -join '; ')" }
Write-Output "___MOUSE_HELPER_TEST_DONE___:passed=$checks"
