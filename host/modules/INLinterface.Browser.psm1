# INLinterface.Browser.psm1
# Functions for opening URLs in the default web browser.
# This module handles browser operations for opening reference materials and guides.

<#
	Opens URL in default browser and waits.
	Launches the specified URL in the user's default web browser and waits for a specified delay
	to allow the browser to load before returning control to the script. Used for opening reference
	materials like mapper databases or cleaning guides.
#>
function Open-UrlInDefaultBrowser-AndReturn {
	param(
		[Parameter(Mandatory)][string]$Url,
		[int]$DelayMs = 500
	)

	# Open URL in default browser
	Start-Process $Url

	# Wait for browser to load
	Start-Sleep -Milliseconds $DelayMs
}

Export-ModuleMember -Function 'Open-UrlInDefaultBrowser-AndReturn'

