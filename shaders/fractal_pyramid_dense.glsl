// -----------------------------------------------------------------------------
// "fractal pyramid — Dense & slow"
// Based on "fractal pyramid" by bradjamesgrant
// https://www.shadertoy.com/view/tsXBzS   (CC BY-NC-SA 3.0)
//
// Fork / modifications by xik (https://www.shadertoy.com/user/xik):
//   - Fold count raised 8 -> 12 (more intricate structure)
//   - Slower camera orbit (iTime * 0.4) and calmer fold spin (0.12)
//   - Original cyan -> magenta palette kept
//
// Stays under CC BY-NC-SA 3.0: keep this credit, non-commercial use only,
// and share derivatives under the same license.
// -----------------------------------------------------------------------------

vec3 palette(float d){
    return mix(vec3(0.2, 0.7, 0.9), vec3(1.0, 0.0, 1.0), d);
}

vec2 rotate(vec2 p, float a){
    float c = cos(a);
    float s = sin(a);
    return p * mat2(c, s, -s, c);
}

float map(vec3 p){
    for(int i = 0; i < 12; ++i){           // 12 folds (was 8)
        float t = iTime * 0.12;            // calmer fold spin (was 0.2)
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
        col += palette(length(p) * 0.1) / (400.0 * d);
        t += d;
    }
    return vec4(col, 1.0 / (d * 100.0));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = (fragCoord - (iResolution.xy / 2.0)) / iResolution.x;
    vec3 ro = vec3(0.0, 0.0, -50.0);
    ro.xz = rotate(ro.xz, iTime * 0.4);    // slower orbit (was iTime)
    vec3 cf = normalize(-ro);
    vec3 cs = normalize(cross(cf, vec3(0.0, 1.0, 0.0)));
    vec3 cu = normalize(cross(cf, cs));
    vec3 uuv = ro + cf * 3.0 + uv.x * cs + uv.y * cu;
    vec3 rd = normalize(uuv - ro);
    fragColor = rm(ro, rd);
}
