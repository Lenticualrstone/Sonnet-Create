#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// AI 스피어 플라즈마 셰이더 — fbm(프랙탈 브라운 운동) 노이즈가 구면을 따라 흐르며
// 강조색 주변의 무지갯빛 밴드를 만든다. SwiftUI colorEffect로 원형 마스크 안에 합성.
// (참고: uvolchyk의 SwiftUI+Metal 파티클 글로우, WWDC24 커스텀 비주얼 이펙트)

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return value;
}

// HSV → RGB (무지갯빛 밴드 색상용)
static float3 hsv2rgb(float3 c) {
    float3 rgb = clamp(abs(fmod(c.x * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return c.z * mix(float3(1.0), rgb, c.y);
}

[[ stitchable ]] half4 aiSpherePlasma(
    float2 position,
    half4 currentColor,
    float4 bounds,
    float time,
    float baseHue,
    float thinking,
    float2 hover
) {
    // 정규화 좌표 (-1...1), 원 밖은 투명 — bounds(.boundingRect)로 스케일 안전하게
    float2 uv = ((position - bounds.xy) / bounds.zw) * 2.0 - 1.0;
    // 호버 인터랙션 — 커서 방향으로 노이즈 필드가 살짝 끌려온다
    uv -= hover * 0.12;
    float radius = length(uv);
    if (radius > 1.0) { return half4(0.0); }

    // 구면 감각: z로 살짝 부풀리고, 노이즈 좌표를 구면 방향으로 왜곡
    float z = sqrt(max(0.0, 1.0 - radius * radius));
    float2 sphereUV = uv / (z + 0.35);

    float speed = 1.0 + thinking * 1.8;
    float t = time * 0.35 * speed;

    // 흐르는 fbm 밴드 두 층 — 서로 다른 방향으로 회전
    float band1 = fbm(sphereUV * 2.2 + float2(t * 0.9, -t * 0.6));
    float band2 = fbm(sphereUV * 3.6 - float2(t * 0.5, t * 0.8) + 7.3);
    float bands = band1 * 0.65 + band2 * 0.35;

    // 강조색 주변 ±0.16 회전 무지갯빛 + 코어로 갈수록 백색광.
    // 밝기는 1.0에서 클램프 — 초과분을 채널별로 자르면 색상(hue)이 틀어진다.
    // 화이트 코어는 밝기 대신 채도 감쇠(pow(z))로 만든다.
    float hue = fract(baseHue + (bands - 0.5) * 0.32 + sin(t * 0.4) * 0.03);
    float saturation = mix(0.85, 0.12, pow(z, 2.4));
    float brightness = min(1.0, 0.6 + bands * 0.45 + pow(z, 2.2) * 0.3);
    float3 color = hsv2rgb(float3(hue, saturation, brightness));

    // 림 라이트 — 가장자리가 얇게 발광
    float rim = smoothstep(0.72, 1.0, radius) * (0.45 + 0.25 * sin(t * 2.0 + radius * 9.0));
    color += hsv2rgb(float3(fract(baseHue + 0.08), 0.6, 1.0)) * rim * 0.55;

    // 가장자리 부드러운 알파 (앤티앨리어싱)
    float alpha = smoothstep(1.0, 0.97, radius);
    return half4(half3(color), half(alpha));
}

// 홀로그래픽 스피어 — 진주광택 박막 간섭. 각도+반경 기반 무지개가 실크처럼 흐르고,
// 미세 노이즈 스파클이 포일 질감을 더한다. 파스텔 고명도/저채도라 앤티크 톤과 어울린다.
[[ stitchable ]] half4 aiSphereHolo(
    float2 position,
    half4 currentColor,
    float4 bounds,
    float time,
    float baseHue,
    float thinking,
    float2 hover
) {
    float2 uv = ((position - bounds.xy) / bounds.zw) * 2.0 - 1.0;
    float radius = length(uv);
    if (radius > 1.0) { return half4(0.0); }

    float z = sqrt(max(0.0, 1.0 - radius * radius));
    float speed = 1.0 + thinking * 1.6;
    float t = time * 0.25 * speed;

    // 박막 간섭 위상 — 시야각(z)·표면각·시간·호버 기울기의 합
    float angle = atan2(uv.y, uv.x);
    float tilt = dot(uv, hover) * 0.9; // 커서 방향으로 기울인 만큼 무지개가 미끄러진다
    float phase = angle * 0.6366 + radius * 1.4 - z * 1.2 + t + tilt;

    // 부드러운 실크 밴드 (저주파) + 가는 포일 줄무늬 (고주파)
    float silk = 0.5 + 0.5 * sin(phase * 3.14159);
    float foil = 0.5 + 0.5 * sin(phase * 12.0 + fbm(uv * 3.0 + t) * 4.0);
    float blendBand = silk * 0.7 + foil * 0.3;

    // 파스텔 무지개 — 강조색 hue에서 출발해 전 스펙트럼을 은은히 순환
    float hue = fract(baseHue + blendBand * 0.85);
    float saturation = mix(0.42, 0.16, pow(z, 2.0));
    float brightness = min(1.0, 0.82 + blendBand * 0.14 + pow(z, 2.0) * 0.08);
    float3 color = hsv2rgb(float3(hue, saturation, brightness));

    // 진주 스파클 — 아주 가는 노이즈 하이라이트
    float sparkle = smoothstep(0.78, 1.0, valueNoise(uv * 26.0 + t * 2.0)) * 0.18 * z;
    color += sparkle;

    // 림 — 가장자리가 무지개빛으로 얇게 감돈다
    float rim = smoothstep(0.68, 1.0, radius);
    color = mix(color, hsv2rgb(float3(fract(hue + 0.15), 0.5, 1.0)), rim * 0.35);

    float alpha = smoothstep(1.0, 0.97, radius);
    return half4(half3(color), half(alpha));
}
