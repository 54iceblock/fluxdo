// Node 预加载补丁：Windows 未开启开发者模式时 symlink 创建会 EPERM。
// 将目录符号链接降级为 junction（mklink /J，无需管理员），文件链接降级为复制。
// 通过 NODE_OPTIONS=--require <本文件> 注入到 hvigor / pnpm / npm 等全部 node 进程。
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function fallback(target, linkPath) {
  try {
    fs.mkdirSync(path.dirname(linkPath), { recursive: true });
  } catch {}
  let isDir = true;
  try {
    isDir = fs.statSync(target).isDirectory();
  } catch {}
  try {
    fs.rmSync(linkPath, { recursive: true, force: true });
  } catch {}
  if (isDir) {
    const cmd = process.env.ComSpec || 'cmd.exe';
    try {
      execFileSync(cmd, ['/d', '/c', 'mklink', '/J', linkPath, target], {
        stdio: 'ignore',
        windowsHide: true,
      });
    } catch (e) {
      // 跨盘符 junction 理论可用；若仍失败则退回复制
      fs.cpSync(target, linkPath, { recursive: true, dereference: true });
    }
  } else {
    fs.copyFileSync(target, linkPath);
  }
}

const origSymlinkSync = fs.symlinkSync.bind(fs);
fs.symlinkSync = function (target, linkPath, type) {
  try {
    return origSymlinkSync(target, linkPath, type);
  } catch (e) {
    return fallback(target, linkPath);
  }
};

const origSymlink = fs.symlink.bind(fs);
fs.symlink = function (target, linkPath, type, cb) {
  if (typeof type === 'function') {
    cb = type;
    type = undefined;
  }
  try {
    return origSymlink(target, linkPath, type, cb);
  } catch (e) {
    try {
      fallback(target, linkPath);
      if (cb) cb(null);
    } catch (e2) {
      if (cb) cb(e2);
      else throw e2;
    }
  }
};

try {
  const origP = fs.promises.symlink.bind(fs.promises);
  fs.promises.symlink = async function (target, linkPath, type) {
    try {
      return await origP(target, linkPath, type);
    } catch (e) {
      return fallback(target, linkPath);
    }
  };
} catch {}
