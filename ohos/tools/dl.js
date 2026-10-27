// 通用下载器：绕过 Windows schannel 问题，使用 Node 原生 TLS（OpenSSL）
// 用法: node tools\dl.js <url> <destPath> [expectedSize]
const fs = require('fs');
const path = require('path');
const { pipeline } = require('stream/promises');

async function main() {
  const [url, dest, expected] = process.argv.slice(2);
  if (!url || !dest) {
    console.error('usage: node dl.js <url> <destPath> [expectedSize]');
    process.exit(2);
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const tmp = dest + '.part';
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      const res = await fetch(url, { redirect: 'follow' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const total = Number(res.headers.get('content-length') || 0);
      let done = 0;
      const out = fs.createWriteStream(tmp);
      const reader = res.body.getReader();
      while (true) {
        const { done: end, value } = await reader.read();
        if (end) break;
        done += value.length;
        if (!out.write(Buffer.from(value))) {
          await new Promise((r) => out.once('drain', r));
        }
      }
      await new Promise((r) => out.end(r));
      if (total && done !== total) throw new Error(`size mismatch ${done}/${total}`);
      if (expected && Number(expected) !== done) throw new Error(`size mismatch ${done}/${expected}`);
      fs.renameSync(tmp, dest);
      console.log(`OK ${done} bytes -> ${dest}`);
      return;
    } catch (e) {
      console.error(`attempt ${attempt} failed: ${e.message}`);
      try { fs.unlinkSync(tmp); } catch {}
      if (attempt === 5) process.exit(1);
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
}
main();
