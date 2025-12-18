# INLinterface.Window.psm1
# Functions for managing console window size and position for optimal display.
# This module handles window positioning and sizing operations.

# Add Windows Forms reference for screen dimensions
Add-Type -AssemblyName System.Windows.Forms

<#
	Sets window position and size for optimal display.
	Calculates optimal window dimensions based on screen height, sets buffer and window sizes,
	and attempts to position the window at the top-left corner of the screen. Uses both PowerShell's
	RawUI API and Win32 API calls for maximum compatibility. Errors are handled gracefully to allow
	the script to continue even if window positioning is not supported in the current host.
#>
function Set-WindowPosition {
	try {
		# Get screen dimensions
		$screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
		
		# Use PowerShell's RawUI for resizing and positioning
		$console = $Host.UI.RawUI
		$maxRows = [Math]::Floor($screenHeight / 16) - 2
		
		# Get current buffer size to respect limits
		$currentBuffer = $console.BufferSize
		$maxWidth = $currentBuffer.Width
		$maxHeight = [Math]::Max($currentBuffer.Height, $maxRows)
		
		# Set buffer size first (must be set before window size)
		$console.BufferSize = New-Object System.Management.Automation.Host.Size($maxWidth, $maxHeight)
		
		# Set window size (cannot exceed buffer size)
		$console.WindowSize = New-Object System.Management.Automation.Host.Size($maxWidth, $maxRows)
		
		# Try to set window position to top-left
		try {
			$console.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0)
		} catch {
			# Console positioning not supported in this host
		}
		
		# Additional positioning attempt using Win32 API
		try {
			$code = @'
using System;
using System.Runtime.InteropServices;
public class WindowPos {
	[DllImport("user32.dll")]
	public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
	[DllImport("user32.dll")]
	public static extern IntPtr GetForegroundWindow();
}
'@
			Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
			
			if ("WindowPos" -as [type]) {
				$hwnd = [WindowPos]::GetForegroundWindow()
				if ($hwnd -ne [IntPtr]::Zero) {
					[void][WindowPos]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0001 -bor 0x0004 -bor 0x0040)
				}
			}
		} catch {
			# Silently continue if this method also fails
		}
		
	} catch {
		Write-Warning "Window positioning error: $($_.Exception.Message)"
	}
}

Export-ModuleMember -Function Set-WindowPosition

