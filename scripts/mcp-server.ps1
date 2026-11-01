$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
try {
    $node = Resolve-QuotaNode
    & $node (Join-Path $script:PackageRoot 'src\mcp-server.mjs')
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine('Codex Quota Rings needs the complete Windows release or Node.js 22.5+ on PATH.')
    exit 1
}
