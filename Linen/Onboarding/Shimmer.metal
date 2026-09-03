// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#include <metal_stdlib>

using namespace metal;

namespace linen {

constant float kBandWidth = 0.48;
constant float kMinStop = 0.14;
constant float kMaxStop = 0.96;

constant float kStripePhase = 0.74;
constant float kSecondaryStripePhase = 1.28;
constant float kPrimaryAmplitude = 0.19;
constant float kSecondaryAmplitude = 0.055;

constant float kIntroStagger = 0.045;
constant float kIntroReveal = 0.84;
constant float kIntroIdleBlend = 0.5;
constant float kIntroStartCenter = 0.96;
constant float kIntroIdleCenter = 0.5;

constant float kPointerFalloff = 2.0;
constant float kPointerPull = 0.65;

constant float kShineBoost = 0.3;

constant float kGrainSize = 180.0;
constant float2 kNoiseHashScale = float2(127.1, 311.7);
constant float kNoiseHashOffset = 43758.5;

inline float clamp01(float value) {
    return clamp(value, 0.0, 1.0);
}

inline float easeOutCubic(float value) {
    float inverse = 1.0 - value;
    return 1.0 - inverse * inverse * inverse;
}

inline float hashNoise(float2 value) {
    return fract(sin(dot(value, kNoiseHashScale)) * kNoiseHashOffset);
}

inline float3 overlayBlend(float3 base, float3 blend) {
    float3 low = 2.0 * base * blend;
    float3 high = 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
    return mix(low, high, step(float3(0.5), base));
}

inline float3 stripeState(
    float index,
    float centerIndex,
    float centerDistance,
    float introElapsed,
    float2 phases
) {
    float revealDelay = max(0.0, abs(index - centerIndex) - centerDistance) * kIntroStagger;
    float elapsed = introElapsed - revealDelay;
    float reveal = easeOutCubic(clamp01(elapsed / kIntroReveal));
    float idleBlend = easeOutCubic(clamp01((elapsed - kIntroReveal) / kIntroIdleBlend));

    float idleCenter = 0.5
        + sin(phases.x - index * kStripePhase) * kPrimaryAmplitude
        + sin(phases.y + index * kSecondaryStripePhase) * kSecondaryAmplitude;
    float introCenter = mix(kIntroStartCenter, kIntroIdleCenter, reveal);

    return float3(mix(introCenter, idleCenter, idleBlend), reveal, idleBlend);
}

inline float highlightAmount(float position, float bandStart, float center, float bandEnd) {
    if (position < bandStart) {
        return 1.0 - clamp01(position / max(bandStart, 0.0001));
    }
    if (position < center) {
        return clamp01((position - bandStart) / max(center - bandStart, 0.0001));
    }
    if (position < bandEnd) {
        return 1.0 - clamp01((position - center) / max(bandEnd - center, 0.0001));
    }
    return 0.0;
}

}

using namespace linen;

[[ stitchable ]] half4 linenShimmer(
    float2 position,
    float2 size,
    float2 stripes,
    float2 phases,
    float2 intro,
    float3 pointer,
    float3 startColor,
    float3 highlightDelta,
    float4 grain
) {
    float stripeWidth = max(stripes.x, 1.0);
    float coordinate = clamp(position.x / stripeWidth, 0.0, stripes.y);
    float lower = floor(coordinate);
    float upper = min(lower + 1.0, stripes.y);
    float blend = smoothstep(0.0, 1.0, coordinate - lower);

    float centerIndex = stripes.y * 0.5;
    float centerDistance = fmod(stripes.y, 2.0) >= 0.5 ? 0.5 : 0.0;
    float3 state = mix(
        linen::stripeState(lower, centerIndex, centerDistance, intro.x, phases),
        linen::stripeState(upper, centerIndex, centerDistance, intro.x, phases),
        blend
    );
    float center = state.x;
    float reveal = state.y;

    float pointerDistance = (position.x - pointer.x) / (stripeWidth * linen::kPointerFalloff);
    float pointerPull = exp(-pointerDistance * pointerDistance) * pointer.z * linen::kPointerPull;
    center = mix(center, clamp01(pointer.y / max(size.y, 1.0)), pointerPull);

    float bandStart = clamp(center - linen::kBandWidth, linen::kMinStop, linen::kMaxStop);
    float bandEnd = clamp(center + linen::kBandWidth, linen::kMinStop, linen::kMaxStop);

    float gradientPosition = clamp01((position.y + size.y * 0.35) / (size.y * 1.7));

    float amount = linen::highlightAmount(gradientPosition, bandStart, center, bandEnd);
    float strength = clamp01(reveal * (1.0 + intro.y * linen::kShineBoost));
    float3 color = startColor + highlightDelta * amount * strength;

    float2 grainPosition = floor(fmod(position, linen::kGrainSize));
    float luminance = grain.z + (linen::hashNoise(grainPosition) - 0.5) * grain.w;
    float3 colorShift = float3(
        linen::hashNoise(grainPosition + float2(17.0, 3.0)) - 0.5,
        linen::hashNoise(grainPosition + float2(7.0, 29.0)) - 0.5,
        linen::hashNoise(grainPosition + float2(31.0, 11.0)) - 0.5
    ) * grain.y;
    float3 speckle = clamp((float3(luminance) + colorShift) / 255.0, 0.0, 1.0);
    color = mix(color, linen::overlayBlend(color, speckle), grain.x);

    float alpha = clamp01(reveal);
    return half4(half3(color * alpha), half(alpha));
}
