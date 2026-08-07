[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$IncludeAllVariableMetadata
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this read-only audit from an elevated PowerShell session.'
    }
}

function Get-VariableAttributeNames([uint32]$Attributes) {
    $known = [ordered]@{
        NonVolatile                    = 0x00000001
        BootServiceAccess              = 0x00000002
        RuntimeAccess                  = 0x00000004
        HardwareErrorRecord            = 0x00000008
        AuthenticatedWriteAccess       = 0x00000010
        TimeBasedAuthenticatedWrite    = 0x00000020
        AppendWrite                    = 0x00000040
        EnhancedAuthenticatedAccess    = 0x00000080
    }
    @($known.GetEnumerator() | Where-Object { ($Attributes -band $_.Value) -ne 0 } | ForEach-Object Key)
}

Assert-Administrator

if (-not ('HeadlessServer.Firmware.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace HeadlessServer.Firmware
{
    public static class NativeMethods
    {
        private const UInt32 TOKEN_ADJUST_PRIVILEGES = 0x0020;
        private const UInt32 TOKEN_QUERY = 0x0008;
        private const UInt32 SE_PRIVILEGE_ENABLED = 0x00000002;

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID
        {
            public UInt32 LowPart;
            public Int32 HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_PRIVILEGES
        {
            public UInt32 PrivilegeCount;
            public LUID Luid;
            public UInt32 Attributes;
        }

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(
            IntPtr ProcessHandle,
            UInt32 DesiredAccess,
            out IntPtr TokenHandle);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool LookupPrivilegeValue(
            string SystemName,
            string Name,
            out LUID Luid);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AdjustTokenPrivileges(
            IntPtr TokenHandle,
            bool DisableAllPrivileges,
            ref TOKEN_PRIVILEGES NewState,
            UInt32 BufferLength,
            IntPtr PreviousState,
            IntPtr ReturnLength);

        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr Handle);

        [DllImport("ntdll.dll")]
        public static extern Int32 NtEnumerateSystemEnvironmentValuesEx(
            UInt32 InformationClass,
            IntPtr Buffer,
            ref UInt32 BufferLength);

        public static void EnableSystemEnvironmentPrivilege()
        {
            IntPtr token;
            if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcessToken failed");

            try
            {
                LUID luid;
                if (!LookupPrivilegeValue(null, "SeSystemEnvironmentPrivilege", out luid))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "LookupPrivilegeValue failed");

                TOKEN_PRIVILEGES privileges = new TOKEN_PRIVILEGES();
                privileges.PrivilegeCount = 1;
                privileges.Luid = luid;
                privileges.Attributes = SE_PRIVILEGE_ENABLED;

                if (!AdjustTokenPrivileges(token, false, ref privileges, 0, IntPtr.Zero, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "AdjustTokenPrivileges failed");

                int error = Marshal.GetLastWin32Error();
                if (error != 0)
                    throw new Win32Exception(error, "SeSystemEnvironmentPrivilege is unavailable");
            }
            finally
            {
                CloseHandle(token);
            }
        }
    }
}
'@
}

[HeadlessServer.Firmware.NativeMethods]::EnableSystemEnvironmentPrivilege()

$statusBufferTooSmall = [Convert]::ToUInt32('C0000023', 16)
$bufferLength = [uint32](1MB)
$buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$bufferLength)
try {
    $nativeStatus = [HeadlessServer.Firmware.NativeMethods]::NtEnumerateSystemEnvironmentValuesEx(2, $buffer, [ref]$bufferLength)
    $status = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$nativeStatus), 0)
    if ($status -eq $statusBufferTooSmall) {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
        $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$bufferLength)
        $nativeStatus = [HeadlessServer.Firmware.NativeMethods]::NtEnumerateSystemEnvironmentValuesEx(2, $buffer, [ref]$bufferLength)
        $status = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$nativeStatus), 0)
    }
    if ($status -ne 0) {
        throw ('NtEnumerateSystemEnvironmentValuesEx failed with NTSTATUS 0x{0:X8}. Windows may restrict runtime UEFI variable enumeration on this platform.' -f $status)
    }

    $candidatePattern = '(?i)(setup|system.?config|power|wake|wol|erp|ac.?loss|after.?g3|state.?after.?g3)'
    $variables = [Collections.Generic.List[object]]::new()
    $offset = 0
    $index = 0
    while (($offset + 32) -le $bufferLength) {
        $entry = [IntPtr]::Add($buffer, $offset)
        $size = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($entry, 0)
        $dataOffset = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($entry, 4)
        $dataSize = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($entry, 8)
        $attributes = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($entry, 12)
        if ($size -eq 0) { break }
        if ($size -lt 32 -or ($offset + $size) -gt $bufferLength -or $dataOffset -lt 32 -or ($dataOffset + $dataSize) -gt $size) {
            throw "Malformed UEFI variable record at buffer offset 0x$($offset.ToString('X'))."
        }

        $guidBytes = [byte[]]::new(16)
        [Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($entry, 16), $guidBytes, 0, 16)
        $guid = [guid]::new($guidBytes).ToString()

        $nameByteLength = [int]$dataOffset - 32
        $nameBytes = [byte[]]::new($nameByteLength)
        [Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($entry, 32), $nameBytes, 0, $nameByteLength)
        $name = [Text.Encoding]::Unicode.GetString($nameBytes).TrimEnd([char]0)

        $data = [byte[]]::new([int]$dataSize)
        if ($dataSize -gt 0) {
            [Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($entry, [int]$dataOffset), $data, 0, [int]$dataSize)
        }
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try { $dataHash = ([BitConverter]::ToString($sha256.ComputeHash($data))).Replace('-', '') } finally { $sha256.Dispose() }

        $isCandidate = $name -match $candidatePattern
        if ($IncludeAllVariableMetadata -or $isCandidate) {
            $variables.Add([pscustomobject][ordered]@{
                Index = $index
                Name = $name
                VendorGuid = $guid
                DataSize = $dataSize
                Attributes = ('0x{0:X8}' -f $attributes)
                AttributeNames = @(Get-VariableAttributeNames $attributes)
                Sha256 = $dataHash
                CandidateSetupOrPowerVariable = $isCandidate
            })
        }
        $offset += [int]$size
        $index++
    }

    $result = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        Method = 'Windows NtEnumerateSystemEnvironmentValuesEx information class 2'
        ReadOnly = $true
        RawVariableDataExported = $false
        TotalVariablesEnumerated = $index
        MetadataRecordsReturned = $variables.Count
        CandidateCount = @($variables | Where-Object CandidateSetupOrPowerVariable).Count
        Variables = @($variables)
    }
    $json = $result | ConvertTo-Json -Depth 6
    if ($OutputPath) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8
    }
    $json
}
finally {
    if ($buffer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
}
