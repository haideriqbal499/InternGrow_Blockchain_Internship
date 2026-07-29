import { defineConfig } from "vite";
import { resolve } from "node:path";

export default defineConfig({
  optimizeDeps: {
    exclude: ["ethers"]
  },
  build: {
    rollupOptions: {
      input: {
        main: resolve(import.meta.dirname, "index.html"),
        daoVoting: resolve(import.meta.dirname, "dao-voting.html")
      }
    }
  }
});
