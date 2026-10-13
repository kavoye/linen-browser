// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 linenVoiceOrb(float2 position, float2 size, float time, float energy, float assistant) {
    float2 p = (position - size * 0.5) / (min(size.x, size.y) * 0.5);
    float radius = length(p);
    float angle = atan2(p.y, p.x);
    float t = time * 0.38;
    float boundary = 0.72 + 0.006 * sin(angle * 3.0 + t)
        + 0.004 * sin(angle * 2.0 - t * 0.7) + energy * 0.012;
    float coverage = 1.0 - smoothstep(boundary - 0.015, boundary + 0.015, radius);
    float2 flow = p;
    flow += 0.12 * float2(sin(p.y * 3.4 + t), cos(p.x * 3.1 - t * 0.8));
    float ribbons = sin(flow.x * 4.5 + flow.y * 2.0 + t
                        + sin(flow.y * 3.0 - t) * 1.2);
    float folds = sin(flow.y * 5.0 - flow.x * 2.5 - t * 0.8 + sin(flow.x * 3.0 + t));
    float light = smoothstep(-0.8, 0.95, ribbons * 0.65 + folds * 0.35);
    float filament = pow(max(0.0, 1.0 - abs(ribbons * 0.65 + folds * 0.35)), 5.0);
    float3 deep = mix(float3(0.015, 0.18, 0.40), float3(0.22, 0.035, 0.48), assistant);
    float3 bright = mix(float3(0.10, 0.96, 0.82), float3(0.97, 0.35, 0.66), assistant);
    float3 ice = mix(float3(0.63, 0.98, 1.0), float3(0.71, 0.66, 1.0), assistant);
    float sphere = sqrt(max(0.0, 1.0 - pow(radius / max(boundary, 0.1), 2.0)));
    float3 color = mix(deep, bright, light) * (0.55 + sphere * 0.55);
    color += ice * filament * (0.08 + energy * 0.10);
    float rim = exp(-abs(radius - boundary + 0.015) * 85.0);
    color += ice * rim * 0.25;
    float sheen = exp(-length((p - float2(-0.23, -0.30)) * float2(3.2, 5.0)) * 2.0);
    color += ice * sheen * 0.4;
    float halo = exp(-abs(radius - boundary) * 13.0) * (1.0 - coverage) * (0.12 + energy * 0.13);
    float alpha = coverage + halo;
    return half4(half3(color * coverage + bright * halo), half(alpha));
}
