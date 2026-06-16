// -----------------------------------------------------------------------------
// "fractal pyramid — Warm ember"
// Based on "fractal pyramid" by bradjamesgrant
// https://www.shadertoy.com/view/tsXBzS   (CC BY-NC-SA 3.0)
//
// Fork / modifications by xik (https://www.shadertoy.com/user/xik):
//   - Palette retinted to fire: warm orange -> deep red
//   - Fold count raised 8 -> 9, slightly faster fold spin (0.25)
//   - Brighter glow (denominator 300), wider color spread (0.13)
//   - Slightly slower camera orbit (iTime * 0.8)
//
// Stays under CC BY-NC-SA 3.0: keep this credit, non-commercial use only,
// and share derivatives under the same license.
// -----------------------------------------------------------------------------

// Fire palette: warm orange (#ffaa33) -> deep red (#cc1133).
vec3 palette(float d){
    return mix(vec3(1.0, 0.667, 0.2), vec3(0.8, 0.067, 0.2), d);
}

vec2 rotate(vec2 p, float a){
    float c = cos(a);
    float s = sin(a);
    return p * mat2(c, s, -s, c);
}

float map(vec3 p){
    for(int i = 0; i < 9; ++i){            // 9 folds (was 8)
        float t = iTime * 0.25;            // faster fold spin (was 0.2)
        p.xz = rotate(p.xz, t);
        p.xy = rotate(p.xy, t * 1.89);
        p.xz = abs(p.xz);
        p.xz -= 0.5;
    }
    return dot(sign(p), p) / 5.0;
}

vec4 rm(vec3 ro, vec3 rd){
    float t = 0.0;
    vec3 col = vec3(0.0);
    float d;
    for(float i = 0.0; i < 64.0; i++){
        vec3 p = ro + rd * t;
        d = map(p) * 0.5;
        if(d < 0.02) break;
        if(d > 100.0) break;
        col += palette(length(p) * 0.13) / (300.0 * d);  // wider spread, brighter glow
        t += d;
    }
    return vec4(col, 1.0 / (d * 100.0));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = (fragCoord - (iResolution.xy / 2.0)) / iResolution.x;
    vec3 ro = vec3(0.0, 0.0, -50.0);
    ro.xz = rotate(ro.xz, iTime * 0.8);    // slightly slower orbit (was iTime)
    vec3 cf = normalize(-ro);
    vec3 cs = normalize(cross(cf, vec3(0.0, 1.0, 0.0)));
    vec3 cu = normalize(cross(cf, cs));
    vec3 uuv = ro + cf * 3.0 + uv.x * cs + uv.y * cu;
    vec3 rd = normalize(uuv - ro);
    fragColor = rm(ro, rd);
}
