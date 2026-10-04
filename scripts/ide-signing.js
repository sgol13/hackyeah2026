/*
 * Makes the system-app signing material from scripts/sign.ps1 usable by hvigor
 * itself, so builds started from DevEco Studio (Run button) are signed too.
 *
 * hvigor only accepts signing passwords encrypted with a local "material"
 * directory next to the keystore (see hvigor-ohos-plugin src/utils/decipher-util.js):
 *   material/fd/{3 dirs, each with one 16-byte file}, material/ac/{salt}, material/ce/{encrypted work key}
 *   rootKey = pbkdf2(xor(fd[0], fd[1], fd[2], COMPONENT).toString(), salt, 10000, 16, sha256)
 *   workKey = aesGcmDecrypt(rootKey, ce);  password = aesGcmDecrypt(workKey, hex)
 *   blob = [u32 BE len(ciphertext + tag)][iv][ciphertext][16-byte tag]
 * This script creates such material (once) in the signing directory and writes
 * ide-signing.json, which the project hvigorfile.ts injects as signingConfig.
 *
 * usage: node ide-signing.js <signingDir> <password> <keyAlias>
 * The password is the PUBLIC default of the OpenHarmony test keystore.
 */
'use strict';
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const COMPONENT = Buffer.from(new Int8Array([49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119]));
const IV_LEN = 12;

function xorAll(buffers) {
  const out = Buffer.alloc(16);
  for (const b of buffers) {
    for (let i = 0; i < 16; i++) {
      out[i] ^= b[i];
    }
  }
  return out;
}

function encrypt(key, plain) {
  const iv = crypto.randomBytes(IV_LEN);
  const cipher = crypto.createCipheriv('aes-128-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(plain), cipher.final()]);
  const tag = cipher.getAuthTag();
  const header = Buffer.alloc(4);
  header.writeUInt32BE(ct.length + tag.length);
  return Buffer.concat([header, iv, ct, tag]);
}

function decrypt(key, blob) {
  const len = blob.readUInt32BE(0);
  const ivLen = blob.length - 4 - len;
  const iv = blob.subarray(4, 4 + ivLen);
  const decipher = crypto.createDecipheriv('aes-128-gcm', key, iv);
  decipher.setAuthTag(blob.subarray(blob.length - 16));
  return Buffer.concat([decipher.update(blob.subarray(4 + ivLen, blob.length - 16)), decipher.final()]);
}

function readSingle(dir) {
  const files = fs.readdirSync(dir);
  return fs.readFileSync(path.join(dir, files[0]));
}

function rootKey(materialDir) {
  const fdDir = path.join(materialDir, 'fd');
  const parts = fs.readdirSync(fdDir).map((d) => readSingle(path.join(fdDir, d)));
  const xored = xorAll(parts.concat([COMPONENT]));
  const salt = readSingle(path.join(materialDir, 'ac'));
  return crypto.pbkdf2Sync(xored.toString(), salt, 10000, 16, 'sha256');
}

function ensureMaterial(materialDir) {
  if (fs.existsSync(path.join(materialDir, 'ce'))) {
    return;
  }
  for (const d of ['fd', 'ac', 'ce']) {
    fs.mkdirSync(path.join(materialDir, d), { recursive: true });
  }
  for (let i = 0; i < 3; i++) {
    const part = path.join(materialDir, 'fd', String(i));
    fs.mkdirSync(part, { recursive: true });
    fs.writeFileSync(path.join(part, '0'), crypto.randomBytes(16));
  }
  fs.writeFileSync(path.join(materialDir, 'ac', '0'), crypto.randomBytes(16));
  const workKey = crypto.randomBytes(16);
  fs.writeFileSync(path.join(materialDir, 'ce', '0'), encrypt(rootKey(materialDir), workKey));
}

function main() {
  const [signingDir, password, keyAlias] = process.argv.slice(2);
  if (!signingDir || !password || !keyAlias) {
    console.error('usage: node ide-signing.js <signingDir> <password> <keyAlias>');
    process.exit(2);
  }
  const dir = path.resolve(signingDir);
  const materialDir = path.join(dir, 'material');
  ensureMaterial(materialDir);
  const workKey = decrypt(rootKey(materialDir), readSingle(path.join(materialDir, 'ce')));
  const encPwd = encrypt(workKey, Buffer.from(password, 'utf-8')).toString('hex');
  // self-check: decrypts back the same way hvigor does
  if (decrypt(workKey, Buffer.from(encPwd, 'hex')).toString('utf-8') !== password) {
    throw new Error('material self-check failed');
  }
  const config = {
    storeFile: path.join(dir, 'keystore.p12'),
    storePassword: encPwd,
    keyAlias: keyAlias,
    keyPassword: encPwd,
    profile: path.join(dir, 'profile.p7b'),
    certpath: path.join(dir, 'app-chain.pem'),
    signAlg: 'SHA256withECDSA'
  };
  fs.writeFileSync(path.join(dir, 'ide-signing.json'), JSON.stringify(config, null, 2));
  console.log(`IDE signing config written: ${path.join(dir, 'ide-signing.json')}`);
}

main();
