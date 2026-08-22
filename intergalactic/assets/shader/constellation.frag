#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec4 uBaseColor;
uniform vec4 uAccentColor;
uniform vec4 uGlowColor;
out vec4 fragColor;

float softBand(vec2 uv, float angle, float phase, float width) {
    float c = cos(angle);
    float s = sin(angle);
    vec2 p = mat2(c, -s, s, c) * uv;
    float wave = sin((p.x * 2.6) + phase) * 0.035;
    return smoothstep(width, 0.0, abs(p.y + wave));
}

float cellValue(vec2 cell) {
    vec2 p = fract(cell * vec2(0.3183099, 0.3678794));
    p += dot(p, p.yx + vec2(0.17, 0.43));
    return fract((p.x + p.y) * 37.0);
}

float nodeLayer(vec2 uv, float scale, float drift) {
    vec2 grid = uv * scale;
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    float seed = cellValue(cell);
    vec2 offset = vec2(
        sin(seed * 6.2831 + drift),
        cos(seed * 5.1138 - drift)
    ) * 0.18;
    float node = smoothstep(0.055, 0.0, length(local - offset));
    float visible = step(0.58, seed);
    return node * visible;
}

float signalMesh(vec2 uv) {
    float phase = uTime * 0.22;
    float mesh = 0.0;

    mesh += softBand(uv, 0.56, phase, 0.018);
    mesh += softBand(uv, -0.72, phase * 0.7 + 1.8, 0.012) * 0.7;
    mesh += softBand(uv + vec2(0.12, -0.08), 1.42, phase * 0.5, 0.01) * 0.5;

    for (int i = 0; i < 4; i++) {
        float layer = float(i);
        float scale = 5.0 + layer * 2.0;
        float drift = phase + layer * 0.9;
        mesh += nodeLayer(uv + vec2(layer * 0.07, -layer * 0.04), scale, drift)
            * (0.18 + layer * 0.05);
    }

    return mesh;
}

void main(void) {
    vec2 fragCoord = FlutterFragCoord();
    vec2 uv = (fragCoord.xy - (uSize.xy * 0.5)) / max(uSize.y, 1.0);
    vec2 wideUv = uv * vec2(uSize.x / max(uSize.y, 1.0), 1.0);

    float vignette = smoothstep(1.45, 0.12, length(wideUv * vec2(0.82, 1.05)));
    float horizon = smoothstep(-0.7, 0.9, uv.y);
    float pulse = 0.5 + 0.5 * sin(uTime * 0.36);
    float mesh = signalMesh(wideUv);

    vec3 base = uBaseColor.rgb;
    vec3 accent = uAccentColor.rgb;
    vec3 glow = uGlowColor.rgb;

    vec3 color = mix(base * 0.55, base, vignette);
    color = mix(color, accent, (0.08 + 0.04 * pulse) * horizon);
    color += glow * mesh * (0.42 + 0.18 * pulse);
    color += accent * smoothstep(0.9, 0.0, length(wideUv - vec2(0.45, -0.2))) * 0.1;
    color *= 0.72 + 0.28 * vignette;

    fragColor = vec4(color, 1.0);
}
