import sys
import struct
import os
import time
from multiprocessing import Pool, cpu_count

DELTA = 0x9E3779B9

def u32(n):
    return n & 0xFFFFFFFF

def xxtea_encrypt(data, key64):
    key = [u32(key64 >> 32), u32(key64 & 0xFFFFFFFF), 0xDEADDEAD, 0xB00BEEEF]
    n = (len(data) - len(data) % 4) // 4
    if n < 2:
        return data
    v = list(struct.unpack_from('<' + str(n) + 'I', data, 0))
    rounds = 6 + 52 // n
    s = 0
    z = v[n - 1]
    for _ in range(rounds):
        s = u32(s + DELTA)
        e = (s >> 2) & 3
        for p in range(n - 1):
            y = v[p + 1]
            MX = u32(((u32(z >> 5) ^ u32(y << 2)) + (u32(y >> 3) ^ u32(z << 4))) ^ ((u32(s ^ y)) + (key[(p & 3) ^ e] ^ z)))
            v[p] = u32(v[p] + MX)
            z = v[p]
        y = v[0]
        MX = u32(((u32(z >> 5) ^ u32(y << 2)) + (u32(y >> 3) ^ u32(z << 4))) ^ ((u32(s ^ y)) + (key[((n - 1) & 3) ^ e] ^ z)))
        v[n - 1] = u32(v[n - 1] + MX)
        z = v[n - 1]
    result = bytearray(data)
    struct.pack_into('<' + str(n) + 'I', result, 0, *v)
    return result

def shuffle_id(id_, count, encrypt):
    if count <= 1 or id_ == 0 or id_ > count:
        return id_
    x = id_ - 1
    domain = 1
    hb = 1
    while domain < count:
        domain <<= 2
        hb += 1
    hm = (1 << hb) - 1
    while True:
        L = x >> hb
        R = x & hm
        if encrypt:
            for r in range(4):
                rk = ((0x9E3779B9 * (r + 1)) ^ 0x6A09E667) & 0xFFFFFFFF
                F = (((R * 0x85EBCA6B) & 0xFFFFFFFF) ^ (R >> 13) ^ rk) & hm
                L, R = R, (L ^ F) & hm
        else:
            for r in range(3, -1, -1):
                rk = ((0x9E3779B9 * (r + 1)) ^ 0x6A09E667) & 0xFFFFFFFF
                F = (((L * 0x85EBCA6B) & 0xFFFFFFFF) ^ (L >> 13) ^ rk) & hm
                L, R = (R ^ F) & hm, L
        x = (L << hb) | R
        if x < count:
            break
    return x + 1

def crypto_key(sig, id_):
    return ((sig ^ 0xA5F37C29B4E1D08B) + (id_ * 0x517CC1B727220A95)) & 0xFFFFFFFFFFFFFFFF

def _worker_encrypt_chunk(args):
    """Worker function for multiprocessing."""
    slots_chunk, spr_data_dict, sig, count = args
    results = []
    for slot in slots_chunk:
        orig = shuffle_id(slot, count, False)
        raw = spr_data_dict.get(orig)
        if raw is None:
            results.append((slot, b''))
        else:
            # Prepend 1 (hasAlpha=True) and encrypt with XXTEA
            buf = bytearray(b'\x01' + raw)
            enc = xxtea_encrypt(buf, crypto_key(sig, slot))
            results.append((slot, bytes(enc)))
    return results

def encrypt_spr(inp, outp):
    print("================================================================")
    print("        AVATAR ECLIPSE - ENCRYPTADOR DE SPRITES (AVSP)")
    print("================================================================")
    print(f"Entrada: {inp}")
    print(f"Saida  : {outp}")
    
    if not os.path.exists(inp):
        print(f"[ERRO] Arquivo de entrada nao encontrado: {inp}")
        sys.exit(1)
        
    t_start = time.time()
    with open(inp, 'rb') as f:
        data = f.read()
        
    sig = struct.unpack_from('<I', data, 0)[0]
    if sig == int.from_bytes(b'AVSP', 'little'):
        print("[AVISO] O arquivo ja esta no formato AVSP protegido. Nada a fazer.")
        return
        
    count = struct.unpack_from('<I', data, 4)[0]
    soff = 8
    print(f"Assinatura: 0x{sig:08X} | Total de Sprites: {count}")
    print("Lendo tabela de sprites...")

    spr_data_dict = {}
    for i in range(1, count + 1):
        ao = soff + (i - 1) * 4
        if ao + 4 > len(data):
            continue
        addr = struct.unpack_from('<I', data, ao)[0]
        if addr == 0 or addr + 5 > len(data):
            continue
        pos = addr + 3
        if pos + 2 > len(data):
            continue
        sz = struct.unpack_from('<H', data, pos)[0]
        pos += 2
        if sz == 0 or pos + sz > len(data):
            continue
        spr_data_dict[i] = data[pos:pos + sz]

    print(f"Sprites validas carregadas: {len(spr_data_dict)}/{count}")
    del data  # libera memoria

    workers = max(1, min(cpu_count(), 16))
    print(f"Iniciando encriptacao e shuffle paralelo ({workers} threads)...")

    # Divide os slots 1..count em pedacos para os workers
    all_slots = list(range(1, count + 1))
    chunk_size = (count + workers - 1) // workers
    chunks = [all_slots[i:i + chunk_size] for i in range(0, count, chunk_size)]
    tasks = [(chunk, spr_data_dict, sig, count) for chunk in chunks]

    encrypted_results = {}
    with Pool(processes=workers) as pool:
        for chunk_res in pool.imap_unordered(_worker_encrypt_chunk, tasks):
            for slot, enc_buf in chunk_res:
                encrypted_results[slot] = enc_buf
            done = len(encrypted_results)
            pct = done * 100 // count
            sys.stdout.write(f"\rProcessando: {done}/{count} ({pct}%)")
            sys.stdout.flush()

    print("\nGravando arquivo final AVSP...")
    out_dir = os.path.dirname(os.path.abspath(outp))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(outp, 'wb') as out:
        out.write(b'AVSP')
        out.write(struct.pack('<I', sig))
        out.write(struct.pack('<I', count))
        for slot in range(1, count + 1):
            buf = encrypted_results.get(slot, b'')
            out.write(struct.pack('<H', len(buf)))
            if buf:
                out.write(buf)

    elapsed = time.time() - t_start
    final_size_mb = os.path.getsize(outp) / (1024 * 1024)
    print(f"Sucesso! Sprites AVSP geradas em {elapsed:.1f}s ({final_size_mb:.1f} MB)")
    print("================================================================")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Uso: python encrypt_sprites.py <entrada.spr> <saida.spr>")
        sys.exit(1)
    encrypt_spr(sys.argv[1], sys.argv[2])
