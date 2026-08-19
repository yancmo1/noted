import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["apps/**/*.test.ts"],
    setupFiles: ["apps/api/test/setup.ts"],
    passWithNoTests: false,
  },
});
