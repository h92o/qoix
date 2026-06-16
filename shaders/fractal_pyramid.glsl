// fractal pyramid
// -----------------------------------------------------------------------------
// A raymarched, space-folding fractal lit with a cheap volumetric "glow".
// An orbiting camera circles a recursive, pyramid-like shape built by folding
// space 8 times per sample; near-misses to the surface accumulate a depth-tinted
// cyan -> magenta halo, giving a slowly breathing neon look.
//
// Author : xik  (https://www.shadertoy.com/user/xik)
// Shader : https://www.shadertoy.com/view/XXXXXX   (TODO: paste URL after publishing)
// License: GPL-3.0 (see repository LICENSE)
//
// Paste the body below into a new Shadertoy "Image" buffer; it relies on the
// built-in iTime and iResolution uniforms. For a standalone, no-account version
// with live sliders see fractal_pyramid.html in this folder.
// -----------------------------------------------------------------------------

// Color ramp: blends cyan-blue -> magenta as d goes 0 -> 1.
// Used to tint the fractal by how far the sample point is from the origin.
vec3 palette(float d){
    return mix(vec3(0.2, 0.7, 0.9), vec3(1.0, 0.0, 1.0), d);
}

// Standard 2D rotation by angle a (radians) via a rotation matrix.
vec2 rotate(vec2 p, float a){
    float c = cos(a);
    float s = sin(a);
    return p * mat2(c, s, -s, c);
}

// Signed-distance estimate for the fractal.
// The shape is built by "folding" space 8 times: each pass rotates the point,
// mirrors it into one quadrant (abs), then offsets it. Repeating this produces
// the self-similar, pyramid-like recursive structure.
float map(vec3 p){
    for(int i = 0; i < 8; ++i){
        float t = iTime * 0.2;          // animate the folds over time
        p.xz = rotate(p.xz, t);         // spin on the XZ plane
        p.xy = rotate(p.xy, t * 1.89);  // spin on XY at a different rate
        p.xz = abs(p.xz);               // mirror into one quadrant -> self-similarity
        p.xz -= 0.5;                    // offset each folded copy
    }
    // dot(sign(p), p) == |p.x| + |p.y| + |p.z|  (an octahedral / L1 distance).
    // The /5 is a fudge factor that keeps the (approximate) DE from overshooting.
    return dot(sign(p), p) / 5.0;
}

// Raymarcher (sphere tracing) that also accumulates a glow.
vec4 rm(vec3 ro, vec3 rd){
    float t = 0.0;             // distance travelled along the ray
    vec3 col = vec3(0.0);      // accumulated color
    float d;                   // last step's distance estimate
    for(float i = 0.0; i < 64.0; i++){
        vec3 p = ro + rd * t;       // current sample position
        d = map(p) * 0.5;           // *0.5 = extra safety since the DE is approximate
        if(d < 0.02) break;         // close enough -> treat as a hit
        if(d > 100.0) break;        // ray escaped to infinity
        // Glow trick: add color every step, weighted by 1/d. Near-misses (small d)
        // contribute a lot, giving the soft neon halo around the surface.
        col += palette(length(p) * 0.1) / (400.0 * d);
        t += d;                     // advance by the safe distance
    }
    // alpha encodes how close the final step got (used as a vignette-ish term).
    return vec4(col, 1.0 / (d * 100.0));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    // Centered, aspect-correct UV roughly in [-0.5, 0.5].
    vec2 uv = (fragCoord - (iResolution.xy / 2.0)) / iResolution.x;

    // Camera 50 units back, orbiting the origin over time.
    vec3 ro = vec3(0.0, 0.0, -50.0);
    ro.xz = rotate(ro.xz, iTime);

    // Build a camera basis that always looks at the origin.
    vec3 cf = normalize(-ro);                       // forward
    vec3 cs = normalize(cross(cf, vec3(0.0, 1.0, 0.0))); // right
    vec3 cu = normalize(cross(cf, cs));             // up

    // Point on the virtual image plane; cf*3.0 acts as the focal length / FOV.
    vec3 uuv = ro + cf * 3.0 + uv.x * cs + uv.y * cu;

    // Ray direction through this pixel.
    vec3 rd = normalize(uuv - ro);

    fragColor = rm(ro, rd);
}

/** SHADERDATA
{
    "title": "fractal pyramid",
    "description": "Raymarched space-folding fractal with an orbiting camera and a cheap volumetric cyan-to-magenta glow.",
    "model": "car"
}
*/
