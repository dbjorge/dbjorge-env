Set-StrictMode -Version Latest
$script:ErrorActionPreference = 'Stop'

Add-Type @"
    namespace WindowUIModule {
        using System;
        using System.Runtime.InteropServices;

        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        public class Win32 {
            [DllImport("user32.dll", SetLastError=true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
            [DllImport("user32.dll", SetLastError=true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
            [DllImport("user32.dll", SetLastError=true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
        }
    }
"@

function Get-Window {
    [CmdletBinding(DefaultParameterSetName='ByWindowTitle')]
    Param(
        [Parameter(ParameterSetName='ByProcess', Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [System.Diagnostics.Process[]]$Process,
        [Parameter(ParameterSetName='ByProcessId', Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [int[]]$ProcessId,
        [Parameter(ParameterSetName='ByWindowTitle', Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [string[]]$WindowTitle # Accepts globs
    )

    PROCESS {
        switch ($PSCmdlet.ParameterSetName) {
            'ByProcess' { $procs = $Process }
            'ByProcessId' { $procs = Get-Process -Id $ProcessId }
            'ByWindowTitle' { $procs = Get-Process | Where-Object MainWindowTitle -like $WindowTitle }
        }

        foreach ($proc in $procs) {  
            $windowRect = New-Object WindowUIModule.RECT;
            $clientRect = New-Object WindowUIModule.RECT;
            if (-not [WindowUIModule.Win32]::GetWindowRect($proc.MainWindowHandle, [ref]$windowRect)) {
                throw 'GetWindowRect failed'
            }
            if (-not [WindowUIModule.Win32]::GetClientRect($proc.MainWindowHandle, [ref]$clientRect)) {
                throw 'GetClientRect failed'
            }

            New-Object PSObject @{
                Title = $proc.MainWindowTitle;
                Handle = $proc.MainWindowHandle;
                Process = $proc;
                WindowRect = $windowRect;
                ClientRect = $clientRect;
            }
        }
    }
}

function Move-Window {
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSObject[]]$Window,
        [Parameter(Mandatory=$true, Position=0)]
        [int]$X,
        [Parameter(Mandatory=$true, Position=1)]
        [int]$Y,
        [switch]$Relative,
        [switch]$PassThru
    )
    PROCESS {
        foreach ($win in $Window) {
            $absLeft = $X;
            $absTop = $Y;
            if ($Relative) {
                $absLeft += $win.WindowRect.Left
                $absTop += $win.WindowRect.Top
            }

            [WindowUIModule.Win32]::Movewindow($win.Handle, $absLeft, $absTop, $win.WindowRect.Right - $win.WindowRect.Left, $win.WindowRect.Bottom - $win.WindowRect.Top, $true);
            
            if ($PassThru) { $win }
        }
    }
}

function Resize-Window {
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSObject[]]$Window,
        [Parameter(Mandatory=$true, Position=0)]
        [int]$Width,
        [Parameter(Mandatory=$true, Position=1)]
        [int]$Height,
        [switch]$PassThru
    )
    PROCESS {
        foreach ($win in $Window) {
            [WindowUIModule.Win32]::Movewindow($win.Handle, $win.WindowRect.Left, $win.WindowRect.Top, $Width, $Height, $true);

            if ($PassThru) { $win }
        }
    }
}

Export-ModuleMember -Function @(
    'Get-Window'
    'Move-Window'
    'Resize-Window'
)