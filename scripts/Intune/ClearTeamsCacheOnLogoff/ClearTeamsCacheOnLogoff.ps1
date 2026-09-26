# Example: .\ClearTeamsCacheOnLogoff.ps1
# Variables: $TeamsCacheRoot uses the current user APPDATA path; change it if Teams data is stored elsewhere.
#
$TeamsCacheRoot = Join-Path $env:APPDATA "Microsoft\Teams"
Remove-Item "$TeamsCacheRoot\Logs" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$TeamsCacheRoot\media-stack" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$TeamsCacheRoot\Service Worker\CacheStorage" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$TeamsCacheRoot\Application Cache" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$TeamsCacheRoot\Cache" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$TeamsCacheRoot\GPUCache" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$TeamsCacheRoot\meeting-addin\Cache" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$TeamsCacheRoot\*.txt" -Force -Recurse -ErrorAction SilentlyContinue