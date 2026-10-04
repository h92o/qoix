// -----------------------------------------------------------------------------
// "octagram pyramid" — a mashup of two Shadertoy shaders
//
// Combines:
//   1) "fractal pyramid" by bradjamesgrant
//      https://www.shadertoy.com/view/tsXBzS        (CC BY-NC-SA 3.0)
//        -> the space-folding SDF (rotate / abs / offset loop)
//   2) "Octagrams" by whisky_shusuky
//      https://www.shadertoy.com/view/tlVGDt        (CC BY-NC-SA 3.0)
//        -> the flying-tunnel camera + exp() volumetric glow accumulation
//
// Mashup by xik (https://www.shadertoy.com/user/xik): each repeated tunnel cell
// is folded through the pyramid SDF, the two distance fields are combined with a
// selectable blend mode, and the glow is tinted with the pyramid palette.
//
// Both sources are CC BY-NC-SA 3.0, so this derivative is too: keep both credits,
// non-commercial use only, and share alike.
// -----------------------------------------------------------------------------

// BLEND: 0 = union (min)       -> both structures coexist  (default, boldest)
//        1 = intersection      -> only where both overlap (sparse, ghostly)
//        2 = subtract pyramid   -> carve the pyramid out of the octagrams (moody)
//        3 = average (mix)      -> soft morph between the two (bloomy)
#define BLEND 0

float gTime = 0.0;

mat2 rot(float a){ float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }

// ---- Octagrams primitives (whisky_shusuky) --------------------------------
float sdBox(vec3 p, vec3 b){
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
// (the original box() mutates pos after computing base but returns only -base,
//  so the trailing transforms are no-ops; kept faithful but simplified here)
float box(vec3 pos, float scale){
    return -sdBox(pos * scale, vec3(0.4, 0.4, 0.1)) / 1.5;
}
float box_set(vec3 pos){
    vec3 o = pos;
    float s = sin(gTime * 0.4);
    float sc = 2.0 - abs(s) * 1.5;
    pos = o; pos.y += s * 2.5; pos.xy *= rot(0.8); float b1 = box(pos, sc);
    pos = o; pos.y -= s * 2.5; pos.xy *= rot(0.8); float b2 = box(pos, sc);
    pos = o; pos.x += s * 2.5; pos.xy *= rot(0.8); float b3 = box(pos, sc);
    pos = o; pos.x -= s * 2.5; pos.xy *= rot(0.8); float b4 = box(pos, sc);
    pos = o; pos.xy *= rot(0.8);                   float b5 = box(pos, 0.5) * 6.0;
    pos = o;                                        float b6 = box(pos, 0.5) * 6.0;
    return max(max(max(max(max(b1, b2), b3), b4), b5), b6);
}

// ---- fractal pyramid fold (bradjamesgrant) --------------------------------
float pyramid(vec3 p){
    for(int i = 0; i < 8; ++i){
        float t = iTime * 0.2;
        p.xz *= rot(t);
        p.xy *= rot(t * 1.89);
        p.xz = abs(p.xz);
        p.xz -= 0.5;
    }
    return dot(sign(p), p) / 5.0;
}

vec3 palette(float d){
    return mix(vec3(0.2, 0.7, 0.9), vec3(1.0, 0.0, 1.0), d);
}

// combine the two signed distances per the chosen blend mode
float combine(float dO, float dP){
#if BLEND == 0
    return min(dO, dP);
#elif BLEND == 1
    return max(dO, dP);
#elif BLEND == 2
    return max(dO, -dP);
#else
    return mix(dO, dP, 0.5);
#endif
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    // Octagrams camera: fly forward through a modulo-repeated tunnel.
    vec2 p = (fragCoord.xy * 2.0 - iResolution.xy) / min(iResolution.x, iResolution.y);
    vec3 ro = vec3(0.0, -0.2, iTime * 4.0);
    vec3 ray = normalize(vec3(p, 1.5));
    ray.xy *= rot(sin(iTime * 0.03) * 5.0);
    ray.yz *= rot(sin(iTime * 0.05) * 0.2);

    float t = 0.1;
    float ac = 0.0;   // accumulated glow
    for(int i = 0; i < 99; i++){
        vec3 pos = ro + ray * t;
        pos = mod(pos - 2.0, 4.0) - 2.0;      // repeat space into cells
        gTime = iTime - float(i) * 0.01;

        float dO = box_set(pos);              // octagram field
        float dP = pyramid(pos);              // pyramid fold field
        float d  = combine(dO, dP);           // add / subtract / mix

        d = max(abs(d), 0.01);
        ac += exp(-d * 23.0);                 // volumetric glow
        t += d * 0.55;
    }

    // Pyramid palette tints the octagram glow; add a subtle animated pulse.
    vec3 col = palette(clamp(ac * 0.03, 0.0, 1.0)) * ac * 0.02;
    col += vec3(0.0, 0.15 * abs(sin(iTime)), 0.4 + 0.2 * sin(iTime)) * ac * 0.015;

    fragColor = vec4(col, 1.0 - t * (0.02 + 0.02 * sin(iTime)));
}

/** SHADERDATA
{
    "title": "octagram pyramid",
    "description": "Mashup of 'fractal pyramid' (bradjamesgrant) and 'Octagrams' (whisky_shusuky): octagram tunnel cells folded through the pyramid SDF with a selectable blend mode.",
    "model": "person"
}
*/
