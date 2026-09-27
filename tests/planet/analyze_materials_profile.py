"""Summarize the identical 840-frame technical/PBR route from materials_profile.gd."""
import json
import math
import sys
from pathlib import Path


def percentile(values, fraction):
    ordered = sorted(float(value) for value in values if math.isfinite(float(value)))
    index = (len(ordered) - 1) * fraction
    lo = math.floor(index)
    hi = math.ceil(index)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (index - lo)


def summarize(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    rows = data["rows"]
    assert len(rows) == 840, (path, len(rows))
    stats = [row["stats"] for row in rows]
    result = {"frames": len(rows), "renderer": data["renderer"],
              "resolution": data["resolution"], "max_depth": data["max_depth"],
              "failed": data["failed"]}
    for key, values in {
        "frame_ms": [row["frame_ms"] for row in rows],
        "update_ms": [row["update_ms"] for row in rows],
        "render_cpu_ms": [row["stats"]["render_cpu_ms"] for row in rows],
        "render_gpu_ms": [row["stats"]["render_gpu_ms"] for row in rows],
        "upload_ms": [row["stats"]["upload_ms"] for row in rows],
        "last_chunk_build_ms": [row["stats"]["build_ms"] for row in rows],
    }.items():
        result[key] = {"p50": percentile(values, 0.5),
                       "p95": percentile(values, 0.95), "max": max(values)}
    result.update({
        "frames_over_50_ms": sum(row["frame_ms"] > 50 for row in rows),
        "max_jobs": max(s["jobs"] for s in stats),
        "max_queue": max(s["queued"] for s in stats),
        "max_uploads_per_frame": max(row["uploads"] for row in rows),
        "max_resident": max(s["resident"] for s in stats),
        "max_cached": max(s["cached"] for s in stats),
        "max_active_vertices": max(s["active_vertices"] for s in stats),
        "max_mesh_payload_mib": max(s["mesh_payload_mib"] for s in stats),
        "max_static_mib": max(s["static_mib"] for s in stats),
        "max_video_mib": max(s["video_mib"] for s in stats),
    })
    return result


if __name__ == "__main__":
    technical, pbr, output = sys.argv[1:4]
    report = {"technical": summarize(technical), "pbr": summarize(pbr)}
    Path(output).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
