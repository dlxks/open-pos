import { defineConfig } from '@playwright/test';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const registerDirectory = process.cwd();
const repositoryDirectory = resolve(registerDirectory, '../..');
const localFlutterBin = resolve(repositoryDirectory, '../.tooling/flutter/bin');
const hubPort = process.env.POS_E2E_HUB_PORT ?? '8789';
const webPort = process.env.POS_E2E_WEB_PORT ?? '8788';
const commandPath = (name: 'dart' | 'flutter') => {
  const extension = process.platform === 'win32' ? '.bat' : '';
  const bundled = resolve(localFlutterBin, `${name}${extension}`);
  const configured = process.env[`${name.toUpperCase()}_BIN`];
  const executable = configured ?? (existsSync(bundled) ? bundled : name);
  return process.platform === 'win32' && executable.endsWith('.bat')
    ? `call "${executable}"`
    : `"${executable}"`;
};

const dart = commandPath('dart');
const flutter = commandPath('flutter');

export default defineConfig({
  testDir: './e2e',
  timeout: 180_000,
  fullyParallel: false,
  reporter: 'list',
  use: {
    baseURL: `http://127.0.0.1:${webPort}`,
    headless: true,
    viewport: { width: 1440, height: 1000 },
    trace: 'retain-on-failure',
  },
  webServer: [
    {
      command: `${dart} run bin/server.dart`,
      cwd: resolve(repositoryDirectory, 'apps/hub'),
      url: `http://127.0.0.1:${hubPort}/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
      env: {
        PORT: hubPort,
        POS_HUB_DATABASE: ':memory:',
        POS_ALLOWED_ORIGINS: `http://127.0.0.1:${webPort}`,
      },
    },
    {
      command: `${flutter} run -d web-server --web-hostname 127.0.0.1 --web-port ${webPort} --dart-define=POS_HUB_URL=http://127.0.0.1:${hubPort}`,
      cwd: registerDirectory,
      url: `http://127.0.0.1:${webPort}`,
      reuseExistingServer: !process.env.CI,
      timeout: 180_000,
    },
  ],
});
