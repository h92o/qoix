// -----------------------------------------------------------------------------
// Based on "fractal pyramid" by bradjamesgrant
// https://www.shadertoy.com/view/tsXBzS   (CC BY-NC-SA 3.0)
//
// Fork / modifications by xik (https://www.shadertoy.com/user/xik):
//   - TODO: list your changes here (e.g. new palette, fold count, camera, ...)
//
// Stays under CC BY-NC-SA 3.0: keep this credit, non-commercial use only,
// and share derivatives under the same license.
// -----------------------------------------------------------------------------
//
// HOW TO USE:
//   Preferred: open the original above and click Shadertoy's FORK button, then
//   paste the body below over the forked code and edit. Forking auto-stamps the
//   "Forked from ... by bradjamesgrant" credit. If you instead create a brand-new
//   shader, this header is what keeps the attribution intact — leave it in place.
//   Also copy the credit line into the shader's Description field.
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
    for(int i = 0; i < 8; ++i){
        float t = iTime * 0.2;
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
    ro.xz = rotate(ro.xz, iTime);
    vec3 cf = normalize(-ro);
    vec3 cs = normalize(cross(cf, vec3(0.0, 1.0, 0.0)));
    vec3 cu = normalize(cross(cf, cs));
    vec3 uuv = ro + cf * 3.0 + uv.x * cs + uv.y * cu;
    vec3 rd = normalize(uuv - ro);
    fragColor = rm(ro, rd);
}
