/*
 * launcher_token.h
 * Validacao de token AES-256-GCM gerado pelo launcher.
 *
 * O client so inicializa se receber --token <base64> valido
 * gerado pelo launcher oficial com a mesma SECRET_KEY.
 *
 * Token format (plaintext antes do encrypt):
 *   [0..7]  = unix timestamp  (int64_t, little-endian)
 *   [8..11] = magic           (uint32_t: 0xAE54EC11)
 *
 * Ciphertext = AES-256-GCM( plaintext, key=SECRET_KEY, iv=primeiros 12 bytes do token )
 * Token final = base64url( iv[12] + tag[16] + ciphertext[12] ) = 40 bytes -> ~54 chars base64
 */

#ifndef LAUNCHER_TOKEN_H
#define LAUNCHER_TOKEN_H

#include <string>
#include <vector>

// Valida o token passado via --token <base64>
// Retorna true se o token for valido e recente (< TOKEN_MAX_AGE_SECS)
bool validateLauncherToken(const std::string& tokenBase64);

// Extrai o --token <value> dos args e valida.
// Retorna true se encontrar e validar com sucesso.
bool validateLauncherTokenFromArgs(const std::vector<std::string>& args);

#endif // LAUNCHER_TOKEN_H
