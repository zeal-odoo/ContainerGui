import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

if (!globalThis.crypto?.subtle) {
  Object.defineProperty(globalThis, "crypto", { value: webcrypto, configurable: true });
}

const testDirectory = dirname(fileURLToPath(import.meta.url));
const generatorPath = resolve(
  testDirectory,
  "../../Sources/ContainerGUI/Resources/Public/ssh-key-generator.js"
);
await import(pathToFileURL(generatorPath).href);

test("browser-generated RSA key pair is accepted by OpenSSH", (context) => {
  const temporaryDirectory = mkdtempSync(join(tmpdir(), "container-gui-key-"));
  context.after(() => rmSync(temporaryDirectory, { recursive: true, force: true }));

  return globalThis.ContainerGUIKeyGenerator.generateOpenSSHKeyPair().then((pair) => {
    assert.equal(pair.algorithm, "RSA-3072");
    assert.match(pair.publicKey, /^ssh-rsa [A-Za-z0-9+/=]+ container-gui-generated$/);
    assert.match(pair.privateKey, /^-----BEGIN PRIVATE KEY-----\n/);

    const privateKeyPath = join(temporaryDirectory, "id_container_gui");
    writeFileSync(privateKeyPath, pair.privateKey, { mode: 0o600 });
    const derivedPublicKey = execFileSync(
      "/usr/bin/ssh-keygen",
      ["-y", "-f", privateKeyPath],
      { encoding: "utf8" }
    ).trim();
    const expectedPublicKey = pair.publicKey.split(" ").slice(0, 2).join(" ");

    assert.equal(derivedPublicKey, expectedPublicKey);
  });
});
