/*
 * launcher_token.cpp
 * Implementacao da validacao de token AES-256-GCM do launcher.
 */

#include "launcher_token.h"

#include <openssl/evp.h>
#include <openssl/rand.h>

#include <cstring>
#include <ctime>
#include <stdexcept>
#include <algorithm>
#include <filesystem>

// -----------------------------------------------------------------------
//  SECRET KEY — 256 bits (AES-256)
//  NUNCA commitar essa chave no repositorio publico.
//  A mesma chave deve estar no launcher.py (variavel LAUNCHER_SECRET_KEY).
// -----------------------------------------------------------------------
static const uint8_t SECRET_KEY[32] = {
    0x3e, 0x10, 0xb9, 0x8d, 0x70, 0xbd, 0x7f, 0xa3,
    0x69, 0xef, 0xb2, 0xca, 0x3d, 0xfa, 0xa3, 0x57,
    0xc4, 0xd9, 0xfb, 0xfb, 0xc2, 0xad, 0xde, 0x4e,
    0xbe, 0x3d, 0x00, 0x7b, 0x9f, 0xf9, 0x47, 0x4c
};

// Magic number para confirmar autenticidade do plaintext
static const uint32_t TOKEN_MAGIC    = 0xAE54EC11;
// Tempo maximo de vida do token em segundos
static const int64_t  TOKEN_MAX_AGE  = 30;

// AAD (Additional Authenticated Data) — nao precisa ser secreta
static const uint8_t  TOKEN_AAD[]    = "AvatarEclipse";
static const int      TOKEN_AAD_LEN  = sizeof(TOKEN_AAD) - 1;

// -----------------------------------------------------------------------
//  Base64 decode simples (sem dependencias externas)
// -----------------------------------------------------------------------
static const std::string B64_CHARS =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::vector<uint8_t> base64Decode(const std::string& encoded)
{
    std::vector<uint8_t> out;
    int val = 0, bits = -8;
    for (unsigned char c : encoded) {
        if (c == '=' ) { bits -= 6; continue; }
        auto pos = B64_CHARS.find(c);
        if (pos == std::string::npos) continue;
        val = (val << 6) + (int)pos;
        bits += 6;
        if (bits >= 0) {
            out.push_back((val >> bits) & 0xFF);
            bits -= 8;
        }
    }
    return out;
}

// -----------------------------------------------------------------------
//  AES-256-GCM decrypt
//  token_raw layout: iv[12] + tag[16] + ciphertext[...]
// -----------------------------------------------------------------------
static bool aesGcmDecrypt(const std::vector<uint8_t>& raw,
                           std::vector<uint8_t>&       plaintext)
{
    // Minimo: 12 (iv) + 16 (tag) + 12 (plaintext minimo)
    if (raw.size() < 40)
        return false;

    const uint8_t* iv         = raw.data();
    const uint8_t* tag        = raw.data() + 12;
    const uint8_t* ciphertext = raw.data() + 28;
    int            cipher_len = (int)(raw.size() - 28);

    plaintext.resize(cipher_len);
    int plain_len = 0;

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return false;

    bool ok = false;
    do {
        if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) != 1) break;
        if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, nullptr) != 1)        break;
        if (EVP_DecryptInit_ex(ctx, nullptr, nullptr, SECRET_KEY, iv) != 1)             break;

        // AAD
        int dummy = 0;
        if (EVP_DecryptUpdate(ctx, nullptr, &dummy,
                              TOKEN_AAD, TOKEN_AAD_LEN) != 1) break;

        // Decriptografa
        if (EVP_DecryptUpdate(ctx, plaintext.data(), &plain_len,
                              ciphertext, cipher_len) != 1) break;

        // Define a tag esperada
        if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16,
                                 (void*)tag) != 1) break;

        int final_len = 0;
        // Se a tag nao bater, retorna -1 (falha de autenticacao)
        if (EVP_DecryptFinal_ex(ctx, plaintext.data() + plain_len,
                                &final_len) <= 0) break;

        plaintext.resize(plain_len + final_len);
        ok = true;
    } while (false);

    EVP_CIPHER_CTX_free(ctx);
    return ok;
}

// -----------------------------------------------------------------------
//  Interface publica
// -----------------------------------------------------------------------
bool validateLauncherToken(const std::string& tokenBase64)
{
    // 1. Decodifica base64
    auto raw = base64Decode(tokenBase64);

    // 2. Descriptografa AES-256-GCM
    std::vector<uint8_t> plain;
    if (!aesGcmDecrypt(raw, plain))
        return false;

    // 3. Verifica tamanho do plaintext (timestamp:8 + magic:4 = 12 bytes)
    if (plain.size() < 12)
        return false;

    // 4. Verifica magic number
    uint32_t magic = 0;
    std::memcpy(&magic, plain.data() + 8, 4);
    if (magic != TOKEN_MAGIC)
        return false;

    // 5. Verifica timestamp (nao pode ser mais velho que TOKEN_MAX_AGE segundos)
    int64_t token_time = 0;
    std::memcpy(&token_time, plain.data(), 8);

    int64_t now = (int64_t)std::time(nullptr);
    int64_t diff = now - token_time;
    if (diff < 0) diff = -diff; // tolerancia a relogio ligeiramente fora de sync

    if (diff > TOKEN_MAX_AGE)
        return false;

    return true;
}

bool validateLauncherTokenFromArgs(const std::vector<std::string>& args)
{
    // Permite execucao direta local para desenvolvimento se dev.txt existir
    // ou se init.lua for texto puro (desenvolvimento)
    if (std::filesystem::exists("dev.txt")) {
        return true;
    }

    // Ferramentas CLI administrativas para protecao de arquivos
    for (const auto& arg : args) {
        if (arg == "--encrypt" || arg == "--encrypt-sprites" || arg == "--dev") {
            return true;
        }
    }

#ifdef NDEBUG
    // Em release: token e obrigatorio se vier do launcher
    for (size_t i = 0; i + 1 < args.size(); ++i) {
        if (args[i] == "--token") {
            return validateLauncherToken(args[i + 1]);
        }
    }

    // Se nao tiver --token e nem dev.txt, verifica se esta na pasta de dev
    if (std::filesystem::exists("src") && std::filesystem::exists("vc16")) {
        return true;
    }

    // Caso contrario, fecha silenciosamente
    return false;
#else
    // Em debug: pula a validacao para facilitar o desenvolvimento
    (void)args;
    return true;
#endif
}
