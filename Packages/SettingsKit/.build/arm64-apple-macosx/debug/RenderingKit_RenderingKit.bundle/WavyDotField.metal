#include <metal_stdlib>
using namespace metal;

// Wavy Dot Field — 도트 격자가 물결치는 시그니처 배경.
// SwiftUI colorEffect 셰이더: 각 픽셀에서 가장 가까운 격자 도트까지의 거리로 부드러운 원을 그린다.
[[ stitchable ]] half4 wavyDotField(
    float2 position,
    half4 currentColor,
    float4 bounds,
    float time,
    float density,
    float amplitude,
    half4 tint,
    float vignette,
    float dotScale,
    float pitch
) {
    float2 size = bounds.zw;
    if (size.x < 1.0 || size.y < 1.0) { return half4(0.0);
    }

    // 시점 각도: y축 압축으로 기울어진 평면 느낌 (1.0 = 정면)
    float2 warped = float2(position.x, position.y / max(pitch, 0.3));

    float cell = max(size.x, size.y) / max(density, 4.0);
    float2 grid = warped / cell;
    float2 cellIndex = floor(grid);

    half4 accumulated = half4(0.0);

    // 이웃 셀까지 포함해 도트 오프셋이 셀 경계를 넘어도 잘리지 않게 한다.
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 index = cellIndex + float2(dx, dy);
            float2 center = (index + 0.5) * cell;

            // 두 방향의 진행파 결합 — 물결
            float phase = time;
            float waveA = sin(index.x * 0.55 + index.y * 0.35 + phase);
            float waveB = cos(index.x * 0.32 - index.y * 0.47 + phase * 0.8);
            float lift = sin((index.x + index.y) * 0.4 + phase * 1.25);

            float2 offset = float2(waveA, waveB) * cell * 0.22 * amplitude;
            float radius = cell * (0.085 + 0.055 * (0.5 + 0.5 * lift) * amplitude) * max(dotScale, 0.2);

            float dist = distance(warped, center + offset);
            float alpha = 1.0 - smoothstep(radius * 0.45, radius, dist);

            // 물결 마루에서 살짝 밝아진다
            float brightness = 0.55 + 0.45 * (0.5 + 0.5 * lift);
            accumulated += half4(tint.rgb, tint.a) * half(alpha * brightness);
        }
    }

    // 비네트
    float2 uv = position / size - 0.5;
    float vig = 1.0 - smoothstep(0.30, 0.72, length(uv)) * vignette;

    accumulated *= half(vig);
    accumulated.a = min(accumulated.a, half(1.0));
    return accumulated;
}
