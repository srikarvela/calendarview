// Bundles the React UI into macapp/Resources/web/ so CalendarView.app can
// load it straight off disk — no server, no network.
import { execFileSync } from "node:child_process";
import { mkdirSync, copyFileSync, rmSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as esbuild from "esbuild";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const out = resolve(root, "macapp/Resources/web");

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

await esbuild.build({
  entryPoints: [resolve(root, "src/native/main.tsx")],
  bundle: true,
  format: "iife",
  target: ["safari15"],
  jsx: "automatic",
  minify: true,
  outfile: resolve(out, "app.js"),
  alias: { "@": resolve(root, "src") },
  loader: { ".css": "empty" }, // Tailwind is built separately, below.
  define: { "process.env.NODE_ENV": '"production"' },
  logLevel: "warning",
});

execFileSync(
  "npx",
  [
    "@tailwindcss/cli",
    "-i", resolve(root, "src/app/globals.css"),
    "-o", resolve(out, "app.css"),
    "--minify",
  ],
  { cwd: root, stdio: "inherit" },
);

copyFileSync(resolve(root, "src/native/index.html"), resolve(out, "index.html"));

console.log("web bundle -> macapp/Resources/web/");
