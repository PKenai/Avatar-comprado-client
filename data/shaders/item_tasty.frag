// ============================================================================
// item_tasty - brilho dourado de "comida gostosa" (peixe assado)
// Aplicado pelo Lua em modules/game_shaders/shaders.lua para os client ids
// 18419..18436 (os peixes assados). Nao mexe no item cru.
// Contorno dourado que pulsa + leve tom quente na propria arte.
// ============================================================================
uniform mat4 u_Color;
varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3 GOLD = vec3(1.00, 0.78, 0.30);
const float THICKNESS = 2.2;

void main()
{
    vec2 step = (THICKNESS / 512.0) * vec2(1.0);
    vec2 halfStep = step * 0.5;

    // Contorno por amostragem em anel (mesma tecnica dos tiers).
    float a = 0.0;
    a += texture2D(u_Tex0, v_TexCoord + vec2(-halfStep.x,  0.0)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( halfStep.x,  0.0)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( 0.0, -halfStep.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( 0.0,  halfStep.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2(-halfStep.x, -halfStep.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( halfStep.x, -halfStep.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2(-halfStep.x,  halfStep.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( halfStep.x,  halfStep.y)).a;

    a += texture2D(u_Tex0, v_TexCoord + vec2(-step.x,  0.0)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( step.x,  0.0)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( 0.0, -step.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( 0.0,  step.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2(-step.x, -step.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( step.x, -step.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2(-step.x,  step.y)).a;
    a += texture2D(u_Tex0, v_TexCoord + vec2( step.x,  step.y)).a;

    float outline = min(a, 1.0);
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Pulsacao quente (parece brasa).
    float pulse = sin(u_Time * 3.6) * 0.25 + 0.75;
    float glow = smoothstep(0.0, 0.6, outline) * 0.5;

    // Deixa a propria arte levemente "na brasa".
    vec3 warm = texColor.rgb * vec3(1.06, 1.00, 0.88) + vec3(0.05, 0.02, 0.0);

    vec4 outlineColor = vec4(GOLD * (pulse + glow * 0.5), pulse);

    float outlineAlpha = clamp(outline - texColor.a, 0.0, 1.0);
    outlineAlpha = smoothstep(0.0, 0.85, outlineAlpha);

    gl_FragColor = mix(vec4(warm, texColor.a), outlineColor, outlineAlpha);

    if (gl_FragColor.a < 0.01)
        discard;
}
