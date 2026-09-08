import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const SHIP = process.env.SHIP_URL || 'http://localhost:8081'  // ~wex

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      '/~': { target: SHIP, changeOrigin: true },
      '/spider': { target: SHIP, changeOrigin: true },
    },
  },
})
