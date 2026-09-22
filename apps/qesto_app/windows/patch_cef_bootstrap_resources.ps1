param(
    [Parameter(Mandatory = $true)]
    [string]$BootstrapPath,

    [Parameter(Mandatory = $true)]
    [string]$ResourceSourcePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$bootstrap = [System.IO.Path]::GetFullPath($BootstrapPath)
$resourceSource = [System.IO.Path]::GetFullPath($ResourceSourcePath)
if (-not [System.IO.File]::Exists($bootstrap)) {
    throw "CEF bootstrap not found: $bootstrap"
}
if (-not [System.IO.File]::Exists($resourceSource)) {
    throw "Qesto resource source not found: $resourceSource"
}

# MSBuild launches the install step with its native LIB search path in the
# environment. Windows PowerShell's legacy Add-Type compiler treats that value
# as a C# reference path and can fail on quoted Visual Studio directories.
# This helper only uses framework assemblies, so an empty LIB is intentional.
$env:LIB = $null

# CMake invokes Windows PowerShell 5.1 (.NET Framework); unlike PowerShell 7,
# its default C# references do not include System.Xml.
$patchCompiler = @{}
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $patchCompiler.ReferencedAssemblies = @('System.dll', 'System.Xml.dll')
}
Add-Type @patchCompiler -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;
using System.Collections.Generic;

public static class QestoVersionResourcePatch {
    private const uint LoadLibraryAsDataFile = 0x00000002;
    private static readonly IntPtr RtVersion = new IntPtr(16);
    private static readonly IntPtr VersionResourceId = new IntPtr(1);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryExW(
        string fileName,
        IntPtr file,
        uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr module);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr FindResourceW(
        IntPtr module,
        IntPtr name,
        IntPtr type);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LockResource(IntPtr resourceData);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(IntPtr module, IntPtr resource);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr BeginUpdateResourceW(
        string fileName,
        bool deleteExistingResources);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool UpdateResourceW(
        IntPtr update,
        IntPtr type,
        IntPtr name,
        ushort language,
        byte[] data,
        uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EndUpdateResourceW(IntPtr update, bool discard);

    private delegate bool ResourceLanguageCallback(IntPtr module, IntPtr type,
        IntPtr name, ushort language, IntPtr parameter);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EnumResourceLanguagesW(IntPtr module, IntPtr type,
        IntPtr name, ResourceLanguageCallback callback, IntPtr parameter);

    private static byte[] ReadResource(IntPtr module, int type, int id) {
        IntPtr resource = FindResourceW(module, new IntPtr(id), new IntPtr(type));
        if (resource == IntPtr.Zero) throw Error("FindResourceW");
        uint size = SizeofResource(module, resource);
        IntPtr data = LockResource(LoadResource(module, resource));
        if (size == 0 || data == IntPtr.Zero) throw Error("ReadResource");
        byte[] bytes = new byte[size];
        Marshal.Copy(data, bytes, 0, checked((int)size));
        return bytes;
    }

    public static void MergeDpiManifest(string sourcePath, string targetPath) {
        // A DLL manifest does not establish the executable's process DPI mode.
        // Preserve the official bootstrap's trust, Common Controls and sandbox
        // compatibility entries; merge only our Windows DPI declarations.
        var source = LoadLibraryExW(sourcePath, IntPtr.Zero, LoadLibraryAsDataFile);
        var target = LoadLibraryExW(targetPath, IntPtr.Zero, LoadLibraryAsDataFile);
        if (source == IntPtr.Zero || target == IntPtr.Zero) {
            var failure = Error("Load manifest module");
            if (source != IntPtr.Zero) FreeLibrary(source);
            if (target != IntPtr.Zero) FreeLibrary(target);
            throw failure;
        }
        var languages = new List<ushort>();
        byte[] merged;
        try {
            var src = new XmlDocument();
            src.LoadXml(Encoding.UTF8.GetString(ReadResource(source, 24, 2)).TrimStart('\uFEFF'));
            var dst = new XmlDocument();
            dst.LoadXml(Encoding.UTF8.GetString(ReadResource(target, 24, 1)).TrimStart('\uFEFF'));
            const string v3 = "urn:schemas-microsoft-com:asm.v3";
            var application = dst.DocumentElement.SelectSingleNode("*[local-name()='application' and namespace-uri()='" + v3 + "']");
            if (application == null) application = dst.DocumentElement.AppendChild(dst.CreateElement("application", v3));
            var settings = application.SelectSingleNode("*[local-name()='windowsSettings']");
            if (settings == null) settings = application.AppendChild(dst.CreateElement("windowsSettings", v3));
            foreach (XmlNode node in src.SelectNodes("//*[local-name()='windowsSettings']/*")) {
                if (node.LocalName != "dpiAwareness" && node.LocalName != "dpiAware") continue;
                var previous = settings.SelectSingleNode("*[local-name()='" + node.LocalName + "']");
                if (previous != null) settings.RemoveChild(previous);
                settings.AppendChild(dst.ImportNode(node, true));
            }
            var mode = settings.SelectSingleNode("*[local-name()='dpiAwareness']");
            if (mode == null || mode.InnerText != "PerMonitorV2") throw new Exception("Missing PerMonitorV2 declaration");
            merged = new UTF8Encoding(false).GetBytes(dst.OuterXml);
            ResourceLanguageCallback callback = (m,t,n,l,p) => { languages.Add(l); return true; };
            if (!EnumResourceLanguagesW(target, new IntPtr(24), new IntPtr(1), callback, IntPtr.Zero)) throw Error("Manifest languages");
            GC.KeepAlive(callback);
        } finally {
            if (source != IntPtr.Zero) FreeLibrary(source);
            if (target != IntPtr.Zero) FreeLibrary(target);
        }
        IntPtr update = BeginUpdateResourceW(targetPath, false);
        if (update == IntPtr.Zero) throw Error("BeginUpdateResourceW(manifest)");
        bool committed = false;
        try {
            foreach (ushort language in languages) {
                if (!UpdateResourceW(update, new IntPtr(24), new IntPtr(1), language, merged, (uint)merged.Length)) throw Error("Update manifest");
            }
            if (!EndUpdateResourceW(update, false)) throw Error("Commit manifest");
            committed = true;
        } finally { if (!committed) EndUpdateResourceW(update, true); }
        var verify = LoadLibraryExW(targetPath, IntPtr.Zero, LoadLibraryAsDataFile);
        if (verify == IntPtr.Zero) throw Error("Load manifest verification module");
        try {
            var xml = new XmlDocument();
            xml.LoadXml(Encoding.UTF8.GetString(ReadResource(verify, 24, 1)).TrimStart('\uFEFF'));
            if (xml.SelectSingleNode("//*[local-name()='dpiAwareness']").InnerText != "PerMonitorV2") throw new Exception("DPI manifest verification failed");
        } finally { FreeLibrary(verify); }
    }

    private static Win32Exception Error(string operation) {
        return new Win32Exception(Marshal.GetLastWin32Error(), operation);
    }

    public static void CopyVersion(string sourcePath, string targetPath) {
        IntPtr module = LoadLibraryExW(sourcePath, IntPtr.Zero, LoadLibraryAsDataFile);
        if (module == IntPtr.Zero) throw Error("LoadLibraryExW");
        try {
            IntPtr resource = FindResourceW(module, VersionResourceId, RtVersion);
            if (resource == IntPtr.Zero) throw Error("FindResourceW(RT_VERSION)");
            uint size = SizeofResource(module, resource);
            if (size == 0) throw Error("SizeofResource(RT_VERSION)");
            IntPtr loaded = LoadResource(module, resource);
            if (loaded == IntPtr.Zero) throw Error("LoadResource(RT_VERSION)");
            IntPtr dataPointer = LockResource(loaded);
            if (dataPointer == IntPtr.Zero) throw Error("LockResource(RT_VERSION)");
            byte[] data = new byte[size];
            Marshal.Copy(dataPointer, data, 0, checked((int)size));

            IntPtr update = BeginUpdateResourceW(targetPath, false);
            if (update == IntPtr.Zero) throw Error("BeginUpdateResourceW");
            bool committed = false;
            try {
                // Runner.rc uses English (United States), code page 1252.
                if (!UpdateResourceW(
                        update, RtVersion, VersionResourceId, 0x0409, data, size)) {
                    throw Error("UpdateResourceW(RT_VERSION)");
                }
                if (!EndUpdateResourceW(update, false)) {
                    throw Error("EndUpdateResourceW");
                }
                committed = true;
            } finally {
                if (!committed) EndUpdateResourceW(update, true);
            }
        } finally {
            FreeLibrary(module);
        }
    }
}
'@

[QestoVersionResourcePatch]::CopyVersion($resourceSource, $bootstrap)
[QestoVersionResourcePatch]::MergeDpiManifest($resourceSource, $bootstrap)
$version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($bootstrap)
if ($version.ProductName -ne 'Qesto' -or $version.CompanyName -ne 'ru.qesto') {
    throw "CEF bootstrap identity patch verification failed: '$($version.CompanyName)' / '$($version.ProductName)'"
}

Write-Output "Patched CEF bootstrap identity and PerMonitorV2 manifest: $($version.CompanyName) / $($version.ProductName)"
