import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/**/*.ts'],
  format: ['esm'],
  platform: 'node',
  target: 'node22',
  outDir: 'dist',
  dts: true,
  clean: true,
  sourcemap: true,
  bundle: false,
  splitting: false,
  outExtension: () => ({ js: '.js' }),
});
