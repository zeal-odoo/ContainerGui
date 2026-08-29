"use strict";

(() => {
  const textEncoder = new TextEncoder();

  function uint32Bytes(value) {
    const bytes = new Uint8Array(4);
    new DataView(bytes.buffer).setUint32(0, value, false);
    return bytes;
  }

  function concatenate(...parts) {
    const output = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
    let offset = 0;
    for (const part of parts) {
      output.set(part, offset);
      offset += part.length;
    }
    return output;
  }

  function sshString(value) {
    const bytes = typeof value === "string" ? textEncoder.encode(value) : value;
    return concatenate(uint32Bytes(bytes.length), bytes);
  }

  function base64URLBytes(value) {
    const base64 = value.replace(/-/g, "+").replace(/_/g, "/")
      .padEnd(Math.ceil(value.length / 4) * 4, "=");
    const binary = atob(base64);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  }

  function sshMPInt(value) {
    let offset = 0;
    while (offset < value.length - 1 && value[offset] === 0) offset += 1;
    let bytes = value.slice(offset);
    if ((bytes[0] & 0x80) !== 0) bytes = concatenate(new Uint8Array([0]), bytes);
    return sshString(bytes);
  }

  function bytesToBase64(value) {
    const chunks = [];
    for (let offset = 0; offset < value.length; offset += 0x8000) {
      chunks.push(String.fromCharCode(...value.subarray(offset, offset + 0x8000)));
    }
    return btoa(chunks.join(""));
  }

  function pem(label, value) {
    const lines = bytesToBase64(value).match(/.{1,64}/g) || [];
    return `-----BEGIN ${label}-----\n${lines.join("\n")}\n-----END ${label}-----\n`;
  }

  async function generateOpenSSHKeyPair() {
    const crypto = globalThis.crypto;
    if (!crypto?.subtle) throw new Error("当前浏览器不支持本地密钥生成");
    const keyPair = await crypto.subtle.generateKey({
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 3072,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256"
    }, true, ["sign", "verify"]);
    const publicJWK = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
    if (!publicJWK.e || !publicJWK.n) throw new Error("无法导出 SSH 公钥");
    const publicBlob = concatenate(
      sshString("ssh-rsa"),
      sshMPInt(base64URLBytes(publicJWK.e)),
      sshMPInt(base64URLBytes(publicJWK.n))
    );
    const privateDER = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keyPair.privateKey));
    const privateKey = pem("PRIVATE KEY", privateDER);
    privateDER.fill(0);
    return Object.freeze({
      algorithm: "RSA-3072",
      publicKey: `ssh-rsa ${bytesToBase64(publicBlob)} container-gui-generated`,
      privateKey
    });
  }

  globalThis.ContainerGUIKeyGenerator = Object.freeze({ generateOpenSSHKeyPair });
})();
