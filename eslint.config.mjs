import tseslint from "@typescript-eslint/eslint-plugin";
import parser from "@typescript-eslint/parser";
export default [{ ignores: ["dist/**", "node_modules/**"] }, { files: ["**/*.{ts,tsx}"], languageOptions: { parser }, plugins: { "@typescript-eslint": tseslint }, rules: { "@typescript-eslint/no-explicit-any": "off", "@typescript-eslint/no-unused-vars": ["warn", { argsIgnorePattern: "^_" }] } }];
