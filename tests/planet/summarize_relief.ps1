param([Parameter(Mandatory=$true)][string]$Evidence)
$ErrorActionPreference = 'Stop'
function Measure-Values($Values) {
    $sorted = @($Values | Sort-Object)
    return @{p50=$sorted[[math]::Ceiling($sorted.Count*0.5)-1];p95=$sorted[[math]::Ceiling($sorted.Count*0.95)-1];max=$sorted[-1]}
}
$results = @()
foreach ($file in Get-ChildItem -LiteralPath $Evidence -Recurse -Filter profile.json) {
    $r = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $rows = @($r.rows)
    $phases = @{}
    foreach ($group in ($rows | Group-Object phase)) {
        $phases[$group.Name] = Measure-Values $group.Group.frame_ms
    }
    $results += [ordered]@{
        case=$file.Directory.Name; samples=$r.resolution; depth=$r.max_depth; failed=$r.failed
        frame_ms=(Measure-Values $rows.frame_ms); update_ms=(Measure-Values $rows.update_ms)
        render_cpu_ms=(Measure-Values $rows.stats.render_cpu_ms); render_gpu_ms=(Measure-Values $rows.stats.render_gpu_ms)
        last_chunk_ms=(Measure-Values $rows.stats.build_ms); upload_ms=(Measure-Values $rows.stats.upload_ms)
        queued_max=($rows.stats.queued|Measure-Object -Maximum).Maximum
        jobs_max=($rows.stats.jobs|Measure-Object -Maximum).Maximum
        uploads_max=($rows.uploads|Measure-Object -Maximum).Maximum
        resident_max=($rows.stats.resident|Measure-Object -Maximum).Maximum
        cached_max=($rows.stats.cached|Measure-Object -Maximum).Maximum
        vertices_max=($rows.stats.active_vertices|Measure-Object -Maximum).Maximum
        payload_mib_max=($rows.stats.mesh_payload_mib|Measure-Object -Maximum).Maximum
        static_mib_max=($rows.stats.static_mib|Measure-Object -Maximum).Maximum
        video_mib_max=($rows.stats.video_mib|Measure-Object -Maximum).Maximum
        frames_over_50ms=@($rows|Where-Object frame_ms -gt 50).Count
        phases=$phases; captures=$r.captures
    }
}
$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Evidence 'summary.json') -Encoding utf8
$results | ForEach-Object { [pscustomobject]@{case=$_.case;p50=$_.frame_ms.p50;p95=$_.frame_ms.p95;max=$_.frame_ms.max;cpu95=$_.update_ms.p95;gpu95=$_.render_gpu_ms.p95;vertices=$_.vertices_max;videoMiB=$_.video_mib_max;frames50=$_.frames_over_50ms} } | Format-Table
