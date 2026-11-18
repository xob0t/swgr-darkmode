# Focus the game window and send key presses with SendInput (scan codes, so games that read raw/DirectInput see them).
# Usage: keys.ps1 -Keys "Esc,Enter,Down*3,Q" [-Delay 350]
param([string]$Keys, [int]$Delay = 350, [string]$Proc = "SWGR-Win64-Shipping")
Add-Type @"
using System; using System.Runtime.InteropServices;
public class KB {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static void Key(ushort scan, bool ext, bool up) {
    var i = new INPUT[1]; i[0].type = 1; i[0].ki.wScan = scan;
    i[0].ki.dwFlags = 0x0008u | (ext ? 0x0001u : 0u) | (up ? 0x0002u : 0u);
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@
# scan codes (set 1); E = extended key
$map = @{
  "Esc"=@(0x01,$false); "Enter"=@(0x1C,$false); "Space"=@(0x39,$false); "Tab"=@(0x0F,$false); "Back"=@(0x0E,$false);
  "Up"=@(0x48,$true); "Down"=@(0x50,$true); "Left"=@(0x4B,$true); "Right"=@(0x4D,$true);
  "Q"=@(0x10,$false); "E"=@(0x12,$false); "R"=@(0x13,$false); "C"=@(0x2E,$false); "F"=@(0x21,$false); "X"=@(0x2D,$false);
  "A"=@(0x1E,$false); "D"=@(0x20,$false); "W"=@(0x11,$false); "S"=@(0x1F,$false); "Z"=@(0x2C,$false); "V"=@(0x2F,$false);
  "1"=@(0x02,$false); "2"=@(0x03,$false); "3"=@(0x04,$false); "4"=@(0x05,$false);
  "F1"=@(0x3B,$false); "PgUp"=@(0x49,$true); "PgDn"=@(0x51,$true); "Home"=@(0x47,$true); "End"=@(0x4F,$true)
}
$p = Get-Process $Proc -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
# Alt tap lets SetForegroundWindow succeed from a background process
[KB]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [KB]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
[KB]::ShowWindow($p.MainWindowHandle, 9) | Out-Null
[KB]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 300
foreach ($k in ($Keys -split ",")) {
  $name, $count = $k -split "\*"; if (-not $count) { $count = 1 }
  if (-not $map.ContainsKey($name)) { Write-Error "unknown key $name"; continue }
  for ($n = 0; $n -lt [int]$count; $n++) {
    $sc = $map[$name]
    [KB]::Key([uint16]$sc[0], $sc[1], $false); Start-Sleep -Milliseconds 60
    [KB]::Key([uint16]$sc[0], $sc[1], $true); Start-Sleep -Milliseconds $Delay
  }
}
"sent: $Keys"
