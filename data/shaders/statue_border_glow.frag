// ============================================================
// STATUE GLOW SHADER (verde)
// Mesmo efeito do talent_border_glow da skill tree (pulso suave + varredura de
// brilho), em VERDE, aplicado no ICONE do card da estatua (cardImage) enquanto
// a bencao daquele card esta ativa.
//
// Como o efeito funciona: a forma vem do ALFA da textura. Pixel transparente
// perto de pixel opaco = halo verde em volta do desenho; pixel opaco = o
// proprio desenho, que so' ganha um toque de verde + o brilho pulsante (a arte
// do icone NAO e' recolorida - emblema/scroll/potion continuam legiveis).
// ============================================================
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

const vec3 GREEN_COLOR = vec3(0.38, 1.00, 0.45); // Verde brilhante
const vec3 SHINE_COLOR = vec3(0.88, 1.00, 0.88); // Brilho de luz fria
const vec3 GREEN_GLOW  = vec3(0.16, 0.78, 0.26); // Aura verde

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Amostragem de vizinhos para aura externa suave (halo). 2.4/52 da' um
    // brilho mais gordo, que e' o que se le como "glow" num icone de 44px.
    vec2 step = vec2(2.4 / 52.0);
    float neighborA = 0.0;
    neighborA += texture2D(u_Tex0, v_TexCoord + vec2( step.x,  0.0)).a;
    neighborA += texture2D(u_Tex0, v_TexCoord + vec2(-step.x,  0.0)).a;
    neighborA += texture2D(u_Tex0, v_TexCoord + vec2( 0.0,  step.y)).a;
    neighborA += texture2D(u_Tex0, v_TexCoord + vec2( 0.0, -step.y)).a;
    neighborA += texture2D(u_Tex0, v_TexCoord + vec2( step.x,  step.y)).a * 0.7;
    neighborA += texture2D(u_Tex0, v_TexCoord + vec2(-step.x,  step.y)).a * 0.7;
    neighborA += texture2D(u_Tex0, v_TexCoord + vec2( step.x, -step.y)).a * 0.7;
    neighborA += texture2D(u_Tex0, v_TexCoord + vec2(-step.x, -step.y)).a * 0.7;
    neighborA /= 6.8;

    // Pulso suave de respiracao (ciclo de ~2.4s)
    float pulse = sin(u_Time * 2.6) * 0.18 + 0.92;

    // Varredura diagonal de brilho brilhante (sheen)
    float sweepWave = sin((v_TexCoord.x + v_TexCoord.y) * 3.8 - u_Time * 3.2);
    float sheen = pow(clamp(sweepWave, 0.0, 1.0), 5.0);

    // Pixel fora da moldura mas dentro da aura
    if (texColor.a < 0.04) {
        if (neighborA > 0.02) {
            float haloAlpha = clamp((neighborA - texColor.a) * 0.85 * pulse, 0.0, 0.75);
            vec3 haloColor = mix(GREEN_GLOW, GREEN_COLOR, sheen * 0.5);
            gl_FragColor = vec4(haloColor * 1.2, haloAlpha);
            return;
        }
        discard;
    }

    // Pixel do desenho: cor original preservada, so' um toque de verde e o
    // pulso em cima. (Recolorir aqui deixaria o icone verde achatado.)
    vec3 rgb = texColor.rgb * (pulse * 1.10) + (GREEN_COLOR * 0.12 * pulse);

    // Adiciona o brilho cintilante passando pelo desenho
    rgb += SHINE_COLOR * (sheen * 0.45);

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), texColor.a);
}
