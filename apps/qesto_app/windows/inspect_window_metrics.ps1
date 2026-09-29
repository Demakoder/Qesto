param([string]$ExeDirectory=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs/Qesto'))
# Read-only diagnostics: reports window geometry/DPI and manifests, never bank data.
# This script does not resize, activate, open or close application windows.
$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class QestoMetricsProbe {
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr w,out Rect r);
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr w,out Rect r);
 [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr w);
 [DllImport("user32.dll")] static extern IntPtr GetWindowDpiAwarenessContext(IntPtr w);
 [DllImport("user32.dll")] static extern int GetAwarenessFromDpiAwarenessContext(IntPtr c);
 [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr w);
 [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr w,StringBuilder s,int n);
 delegate bool EnumCallback(IntPtr w,IntPtr data);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr w,EnumCallback callback,IntPtr data);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr LoadLibraryEx(string p,IntPtr f,uint flags);
 [DllImport("kernel32.dll")] static extern IntPtr FindResource(IntPtr m,IntPtr name,IntPtr type);
 [DllImport("kernel32.dll")] static extern uint SizeofResource(IntPtr m,IntPtr r);
 [DllImport("kernel32.dll")] static extern IntPtr LoadResource(IntPtr m,IntPtr r);
 [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr r);
 [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr m);
 public static string Metrics(IntPtr w) {
  // Change only the diagnostic thread, not the target app; avoid virtualized rectangles.
  var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
  try {
  Rect c,r; GetClientRect(w,out c); GetWindowRect(w,out r);
  var s=new StringBuilder(256); GetClassName(w,s,256);
  return String.Format("class={0} client={1}x{2} rect={3},{4},{5},{6} dpi={7} awareness={8} maximized={9}",s,c.Right-c.Left,c.Bottom-c.Top,r.Left,r.Top,r.Right,r.Bottom,GetDpiForWindow(w),GetAwarenessFromDpiAwarenessContext(GetWindowDpiAwarenessContext(w)),IsZoomed(w));
  } finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
 }
 public static void Children(IntPtr w) { EnumChildWindows(w,(c,p)=>{Console.WriteLine(Metrics(c));return true;},IntPtr.Zero); }
 public static string Manifest(string path,int id) {
  var m=LoadLibraryEx(path,IntPtr.Zero,2); if(m==IntPtr.Zero)return "load failed";
  try {var r=FindResource(m,new IntPtr(id),new IntPtr(24));if(r==IntPtr.Zero)return "no manifest";var n=SizeofResource(m,r);var p=LockResource(LoadResource(m,r));var b=new byte[n];Marshal.Copy(p,b,0,(int)n);return Encoding.UTF8.GetString(b);} finally {FreeLibrary(m);}
 }
}
'@
Get-Process qesto -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | ForEach-Object {
 Write-Output "PID=$($_.Id)"
 [QestoMetricsProbe]::Metrics($_.MainWindowHandle)
 [QestoMetricsProbe]::Children($_.MainWindowHandle)
}
Write-Output 'EXE manifest:'
[QestoMetricsProbe]::Manifest((Join-Path $ExeDirectory 'qesto.exe'),1)
Write-Output 'DLL manifest:'
[QestoMetricsProbe]::Manifest((Join-Path $ExeDirectory 'qesto.dll'),2)
