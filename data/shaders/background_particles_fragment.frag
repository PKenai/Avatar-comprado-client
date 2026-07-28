uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    vec2 uv = v_TexCoord;
    
    vec3 particlesColor = vec3(0.0);
    
    // Criamos 40 partículas individuais
    for(int i = 0; i < 40; i++) {
        float id = float(i);
        
        // Posição inicial baseada no ID
        vec2 pos = vec2(hash(vec2(id, 1.1)), hash(vec2(id, 2.2)));
        
        // Movimento flutuante
        pos.x = fract(pos.x + u_Time * 0.01 * (0.5 + hash(vec2(id, 3.3))));
        pos.y = fract(pos.y + u_Time * 0.02 * (0.5 + hash(vec2(id, 4.4))));
        
        // Adiciona um balanço lateral
        pos.x += sin(u_Time * 0.5 + id) * 0.01;
        
        float dist = length(uv - pos);
        
        // Brilho da partícula (Glow) - aumentado um pouco
        float glow = 0.0020 / (dist + 0.0001);
        
        // Cintilação
        glow *= 0.3 + 0.7 * sin(u_Time * 2.0 + id * 123.4);
        
        // Fade out nas bordas
        float alpha = smoothstep(0.0, 0.1, pos.x) * smoothstep(1.0, 0.9, pos.x) *
                      smoothstep(0.0, 0.1, pos.y) * smoothstep(1.0, 0.9, pos.y);
        
        // Definir cor individual: mistura entre Azul Bebê e Branco
        vec3 babyBlue = vec3(0.6, 0.85, 1.0);
        vec3 white = vec3(1.0, 1.0, 1.0);
        vec3 col = mix(babyBlue, white, hash(vec2(id, 5.5)));
        
        particlesColor += col * glow * alpha;
    }
    
    // Limita o brilho máximo para não estourar muito o branco
    particlesColor = clamp(particlesColor, 0.0, 1.2);
    
    // Somamos a cor original da imagem com o brilho das partículas
    gl_FragColor = vec4(texColor.rgb + particlesColor, texColor.a);
}
