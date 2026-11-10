#version 440
// Solo Leveling screensaver: pixel rain builds each scene from coarse
// blocks, the blocks resolve to full detail, then re-pixelate and rain away.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewportSize;
    float imageAspect;
    float rain;     // 0 → 1: falling columns lay the pixelated scene down
    float sharpen;  // 0 → 1: coarse blocks resolve to full detail
    float drain;    // 0 → 1: columns rain the scene away
    float time;     // seconds, advanced only while pixels are moving
    float seed;
};
layout(binding = 1) uniform sampler2D source;

const float CELL = 24.0;     // rain cell and coarsest pixel block, in px
const float TRAIL = 16.0;    // glowing rows behind each falling head
const vec3 HEAD = vec3(0.957, 0.937, 1.000);   // moonlit white #F4EFFF
const vec3 GLOW = vec3(0.608, 0.482, 1.000);   // shadow violet #9B7BFF
const vec3 MIST = vec3(0.549, 0.784, 0.949);   // mana blue #8CC8F2

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 19.19) * 43758.5453);
}

vec2 cover(vec2 uv, vec2 size) {
    // PreserveAspectCrop without relying on the source Image's geometry.
    float screenAspect = size.x / size.y;
    if (screenAspect > imageAspect) uv.y = (uv.y - 0.5) * imageAspect / screenAspect + 0.5;
    else uv.x = (uv.x - 0.5) * screenAspect / imageAspect + 0.5;
    return uv;
}

// Row position of a column's falling head for a 0 → 1 phase.
float headRow(float column, float phase, float rows, float salt) {
    float delay = hash(vec2(column, salt)) * 0.45;
    float pace = mix(0.6, 1.0, hash(vec2(salt, column)));
    float progress = clamp((phase - delay) / (0.55 * pace), 0.0, 1.0);
    return progress * (rows + TRAIL) - 1.0;
}

// Faint free-falling streaks over empty cells, like background code rain.
float ambient(vec2 cell, float rows) {
    float speed = mix(5.0, 11.0, hash(vec2(cell.x, 7.0)));
    float head = fract(time * speed / (rows + 24.0) + hash(vec2(cell.x, 3.0))) * (rows + 24.0) - 8.0;
    float behind = head - cell.y;
    if (behind < 0.0 || behind > 10.0) return 0.0;
    return (1.0 - behind / 10.0) * step(0.35, hash(vec2(cell.x, 11.0)));
}

void main() {
    vec2 size = max(viewportSize, vec2(1.0));
    vec2 pixel = qt_TexCoord0 * size;
    vec2 cell = floor(pixel / CELL);
    float rows = ceil(size.y / CELL);

    // Pixelation: rain lays down CELL-sized blocks; sharpening shrinks them.
    float block = mix(CELL, 1.0, pow(clamp(sharpen, 0.0, 1.0), 1.6));
    vec2 uv = (floor(pixel / block) + 0.5) * block / size;
    uv = mix(uv, qt_TexCoord0, smoothstep(0.92, 1.0, sharpen));
    vec3 image = texture(source, cover(uv, size)).rgb;

    // LED-style gaps between coarse pixels, closing as the image sharpens.
    vec2 local = fract(pixel / CELL);
    float gap = step(0.06, local.x) * step(local.x, 0.94) * step(0.06, local.y) * step(local.y, 0.94);
    image *= mix(gap, 1.0, smoothstep(0.0, 0.35, sharpen));

    // Glyph flicker: each cell shimmers while it is part of a falling trail.
    float flicker = mix(0.7, 1.15, hash(cell + floor(time * 14.0)));

    // Arrival: cells behind the head keep the scene; the trail glows violet.
    float arrive = cell.y <= headRow(cell.x, rain, rows, 1.0) ? 1.0 : 0.0;
    float behindArrive = headRow(cell.x, rain, rows, 1.0) - cell.y;
    // Departure: cells above the draining head fall away to black.
    float behindDrain = headRow(cell.x, drain, rows, 2.0) - cell.y;
    float stay = drain > 0.0 ? step(behindDrain, 0.0) : 1.0;

    vec3 color = vec3(0.0);
    float lit = arrive * stay;
    if (lit > 0.0) {
        color = image;
        float glow = 1.0 - clamp(behindArrive / TRAIL, 0.0, 1.0);
        color = mix(color, GLOW * 1.6 * flicker * gap, glow * glow * 0.75);
        if (behindArrive < 1.0) color = HEAD * gap;
    }

    // Departing trail: the pixels that just left glow as they fall.
    if (drain > 0.0 && behindDrain >= 0.0 && behindDrain < TRAIL) {
        float fade = 1.0 - behindDrain / TRAIL;
        vec3 falling = mix(image, GLOW * 1.6 * flicker, 0.55) * gap;
        color = mix(color, falling, fade * fade);
        if (behindDrain < 1.0) color = MIST * gap;
    }

    // Background rain over cells the scene does not cover yet (or anymore).
    if (lit == 0.0 && (rain < 1.0 || drain > 0.0)) {
        float streak = ambient(cell, rows);
        color = max(color, GLOW * streak * 0.55 * flicker * gap);
    }

    fragColor = vec4(color, 1.0) * qt_Opacity;
}
